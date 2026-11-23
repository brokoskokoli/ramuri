package io.github.brokoskokoli.ramuri

import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraMetadata

/**
 * Entscheidungen und Ablaufsteuerung der Kamera-Messung ohne Android-Objekte (ADR-0011 Punkte 2, 6),
 * damit sie als Kotlin-Unit-Test laufen. `PpgCamera.kt` bindet sie an Camera2.
 */
object PpgCameraLogic {
    /** Einschwingen: Belichtung und Weißabgleich werden 2,5 s nach Aufnahmebeginn gesperrt (ALGORITHMUS.md Abschn. 2). */
    const val AE_LOCK_AT_SECONDS = 2.5

    /** Zielgröße der Bildanalyse. */
    const val WIDTH = 320
    const val HEIGHT = 240

    /** Die Auswertung ist für 30 und 60 fps festgelegt; darunter taugt die Aufnahme nicht (ADR-0011 Punkt 6). */
    const val MIN_FPS = 30
    const val MAX_FPS = 60

    /** Dart: PpgCameraAvailability (available, noCamera, noFlash, permissionDenied). */
    fun decide(hasBackCamera: Boolean, hasFlash: Boolean, permissionGranted: Boolean): String = when {
        !hasBackCamera -> "no_camera"
        !hasFlash -> "no_flash"
        !permissionGranted -> "permission_denied"
        else -> "available"
    }

    /**
     * Höchste feste Bildrate zwischen 30 und 60 (60 vor 30); null, wenn es keine gibt
     * (Dart: Grund "frame_rate"). Bereiche als (untere, obere) Grenze.
     */
    fun chooseFps(ranges: List<Pair<Int, Int>>): Int? =
        ranges.filter { it.first == it.second && it.second in MIN_FPS..MAX_FPS }.maxOfOrNull { it.second }

    /** Größe nahe [WIDTH]×[HEIGHT]: genau, sonst die kleinste größere, sonst die größte kleinere. */
    fun chooseSize(sizes: List<Pair<Int, Int>>): Pair<Int, Int>? {
        val target = WIDTH * HEIGHT
        return sizes.filter { it.first * it.second >= target }.minByOrNull { it.first * it.second }
            ?: sizes.maxByOrNull { it.first * it.second }
    }

    /**
     * Rückkameras für die Kamerawahl (FR-0220) aus [ids] (Reihenfolge von `cameraIdList`) und den
     * Eigenschaften je ID ([props], `null` = nicht lesbar). Aufgeführt wird jede Rückkamera und, bei
     * einer logischen Mehrfachkamera, jede ihrer physischen Kameras mit deren eigenen Eigenschaften.
     * Standardkamera ist wie bisher die erste Rückkamera mit Blitz. Reihenfolge: Standardkamera zuerst,
     * dann nach Kamera-ID, dann physischer ID (die Kamera selbst vor ihren physischen); IDs aus Ziffern
     * nach Zahlenwert.
     */
    fun listCameras(ids: List<String>, props: (String) -> PpgCameraProps?): List<PpgCameraEntry> {
        val back = ids.mapNotNull { id -> props(id)?.takeIf { it.back } }
        val defaultId = back.firstOrNull { it.flash }?.id
        val out = mutableListOf<PpgCameraEntry>()
        for (c in back) {
            out += entry(c.id, null, c, torch = c.flash, isDefault = c.id == defaultId)
            if (!c.logicalMulti) continue
            for (p in c.physicalIds.distinct()) {
                // Die Taschenlampe schaltet die Anfrage der logischen Kamera: zählt deren Blitz.
                out += entry(c.id, p, props(p), torch = c.flash, isDefault = false)
            }
        }
        return out.sortedWith(
            compareByDescending<PpgCameraEntry> { it.isDefault }
                .thenComparator { a, b -> compareIds(a.cameraId, b.cameraId) }
                .thenComparator { a, b ->
                    when {
                        a.physicalCameraId == b.physicalCameraId -> 0
                        a.physicalCameraId == null -> -1
                        b.physicalCameraId == null -> 1
                        else -> compareIds(a.physicalCameraId, b.physicalCameraId)
                    }
                },
        )
    }

    private fun entry(id: String, physical: String?, p: PpgCameraProps?, torch: Boolean, isDefault: Boolean) =
        PpgCameraEntry(
            cameraId = id,
            physicalCameraId = physical,
            focalLength = p?.focalLengths?.filter { it > 0f }?.minOrNull(),
            isDefault = isDefault,
            reason = when {
                p == null -> "error"
                !torch -> "no_flash"
                chooseFps(p.fpsRanges) == null -> "frame_rate"
                chooseSize(p.yuvSizes) == null -> "error"
                else -> null
            },
        )

    /** IDs aus Ziffern nach Zahlenwert („2“ vor „10“), sonst als Text; Ziffern vor Text. */
    fun compareIds(a: String, b: String): Int {
        val x = a.toBigIntegerOrNull()
        val y = b.toBigIntegerOrNull()
        return when {
            x != null && y != null -> x.compareTo(y).takeIf { it != 0 } ?: a.compareTo(b)
            x != null -> -1
            y != null -> 1
            else -> a.compareTo(b)
        }
    }

    /**
     * Welche Kamera eine Aufnahme öffnet: ohne Angabe ([cameraId] `null`) die Standardkamera, sonst
     * genau die angegebene. Nie eine andere: unbekannt → Grund "no_camera" (ohne Angabe: "no_flash"
     * wie bisher, wenn keine Rückkamera Blitz hat), nicht nutzbar → ihr Grund.
     */
    fun pick(entries: List<PpgCameraEntry>, cameraId: String?, physicalCameraId: String?): PpgCameraPick {
        val e = if (cameraId == null) {
            entries.firstOrNull { it.isDefault } ?: return PpgCameraPick(null, "no_flash")
        } else {
            entries.firstOrNull { it.cameraId == cameraId && it.physicalCameraId == physicalCameraId }
                ?: return PpgCameraPick(null, "no_camera")
        }
        return PpgCameraPick(e, e.reason)
    }

    /**
     * Fokus und Stabilisierung der Aufnahme (ADR-0011, Nachtrag 2026-11-21): die Linse bewegt sich
     * während der Messung nicht. Nur was die Kamera laut Characteristics kann; `null` oder leer gilt
     * als „nicht unterstützt“, dann bleibt der Schlüssel ungesetzt.
     * - Fokus: kürzeste Distanz > 0 und AF-Modus OFF verfügbar → OFF mit Fokus auf die kürzeste
     *   Distanz; sonst AUTO ohne Auslöser, wenn verfügbar; Fixfokus (kürzeste Distanz fehlt oder 0) → nichts.
     * - OIS und Videostabilisierung: OFF, wenn verfügbar.
     * [request] ist die Kamera, an die die Anfrage geht (AF-Modi, OIS, Videostabilisierung);
     * [imageSource] die physische Kamera, die die Bilder liefert (FR-0220): von ihr kommt die
     * kürzeste Distanz. Ohne physische Kamera gilt die von [request].
     */
    fun lensSettings(request: PpgLensProps, imageSource: PpgLensProps? = null): PpgLensSettings {
        val minFocus = (imageSource ?: request).minFocusDistance
        val af = request.afModes.orEmpty()
        val manual = minFocus != null && minFocus > 0f && CameraMetadata.CONTROL_AF_MODE_OFF in af
        val afMode = when {
            minFocus == null || minFocus <= 0f -> null
            manual -> CameraMetadata.CONTROL_AF_MODE_OFF
            CameraMetadata.CONTROL_AF_MODE_AUTO in af -> CameraMetadata.CONTROL_AF_MODE_AUTO
            else -> null
        }
        return PpgLensSettings(
            afMode = afMode,
            focusDistance = if (manual) minFocus else null,
            oisMode = CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_OFF
                .takeIf { it in request.oisModes.orEmpty() },
            videoStabMode = CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF
                .takeIf { it in request.videoStabModes.orEmpty() },
        )
    }

    /**
     * Antibanding der Aufnahme (ADR-0011, Nachtrag 2026-11-22): OFF, wenn die Kamera, die die Bilder
     * liefert, es in CONTROL_AE_AVAILABLE_ANTIBANDING_MODES führt; sonst `null` (Standard bleibt).
     * Unter dem Finger leuchtet nur der Blitz, es gibt kein Netzflimmern.
     */
    fun antibandingMode(modes: List<Int>?): Int? =
        CameraMetadata.CONTROL_AE_ANTIBANDING_MODE_OFF.takeIf { it in modes.orEmpty() }

    /**
     * Sperre nach der Einschwingzeit (ADR-0011, Nachtrag 2026-11-22). Mit [manualSensor] (Fähigkeit
     * MANUAL_SENSOR der Kamera, die die Bilder liefert), Belichtung [e0] und Empfindlichkeit [s0] aus
     * dem letzten Ergebnis und beiden Bereichen: manuell mit Bilddauer T = 1 s / [fps], Belichtung
     * e = min(T, obere Grenze von [exposureRange]), nie kürzer als [e0], und Empfindlichkeit
     * s = round(s0 · e0 / e), begrenzt auf [sensitivityRange] – die Helligkeit bleibt wie bei der
     * Automatik. Sonst die AE-Sperre wie bisher. Bereiche als (untere, obere) Grenze; Zeiten in ns.
     */
    fun exposureLock(
        fps: Int,
        e0: Long?,
        s0: Int?,
        exposureRange: Pair<Long, Long>?,
        sensitivityRange: Pair<Int, Int>?,
        manualSensor: Boolean,
    ): PpgExposureLock {
        if (!manualSensor || e0 == null || s0 == null || exposureRange == null || sensitivityRange == null) {
            return PpgExposureLock.AeLock
        }
        // Ohne brauchbare Werte lässt sich nichts umrechnen.
        if (fps <= 0 || e0 <= 0 || s0 <= 0) return PpgExposureLock.AeLock
        val frame = Math.round(1e9 / fps)
        var e = minOf(frame, exposureRange.second)
        if (e <= e0) e = e0
        val s = Math.round(s0.toDouble() * e0 / e).toInt()
            .coerceIn(sensitivityRange.first, sensitivityRange.second)
        return PpgExposureLock.Manual(exposureNs = e, sensitivity = s, frameDurationNs = frame)
    }

    /** CameraDevice.StateCallback.onError. */
    fun fromDeviceError(code: Int): String = when (code) {
        CameraDevice.StateCallback.ERROR_CAMERA_IN_USE, CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE -> "busy"
        CameraDevice.StateCallback.ERROR_CAMERA_DISABLED -> "permission_denied"
        else -> "error"
    }

    /** CameraAccessException.getReason. */
    fun fromAccessReason(reason: Int): String = when (reason) {
        CameraAccessException.CAMERA_IN_USE, CameraAccessException.MAX_CAMERAS_IN_USE -> "busy"
        CameraAccessException.CAMERA_DISCONNECTED -> "disconnected"
        CameraAccessException.CAMERA_DISABLED -> "permission_denied"
        else -> "error"
    }

    fun fromException(e: Throwable): String = when (e) {
        is SecurityException -> "permission_denied"
        is CameraAccessException -> fromAccessReason(e.reason)
        else -> "error"
    }
}

/** Eigenschaften einer Camera2-ID, soweit die Kamerawahl sie braucht (ohne Android-Objekte). */
data class PpgCameraProps(
    val id: String,
    /** LENS_FACING_BACK. */
    val back: Boolean,
    /** FLASH_INFO_AVAILABLE. */
    val flash: Boolean,
    /** Fähigkeit LOGICAL_MULTI_CAMERA. */
    val logicalMulti: Boolean = false,
    /** getPhysicalCameraIds. */
    val physicalIds: List<String> = emptyList(),
    /** LENS_INFO_AVAILABLE_FOCAL_LENGTHS in mm. */
    val focalLengths: List<Float> = emptyList(),
    /** CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES als (untere, obere) Grenze. */
    val fpsRanges: List<Pair<Int, Int>> = emptyList(),
    /** Ausgabegrößen für YUV_420_888. */
    val yuvSizes: List<Pair<Int, Int>> = emptyList(),
)

/**
 * Eintrag der Kameraliste (Dart: PpgCameraInfo). [reason] ist `null`, wenn die Kamera nutzbar ist,
 * sonst "no_flash", "frame_rate" oder "error" (wie die Abbruchgründe beim Start).
 */
data class PpgCameraEntry(
    val cameraId: String,
    val physicalCameraId: String?,
    val focalLength: Float?,
    val isDefault: Boolean,
    val reason: String?,
) {
    val usable: Boolean get() = reason == null

    fun toMap(): Map<String, Any?> = mapOf(
        "cameraId" to cameraId,
        "physicalCameraId" to physicalCameraId,
        "focalLength" to focalLength?.toDouble(),
        "isDefault" to isDefault,
        "usable" to usable,
        "reason" to reason,
    )
}

/**
 * Characteristics einer Kamera für [PpgCameraLogic.lensSettings] (ohne Android-Objekte), `null` = fehlt.
 */
data class PpgLensProps(
    /** CONTROL_AF_AVAILABLE_MODES. */
    val afModes: List<Int>? = null,
    /** LENS_INFO_MINIMUM_FOCUS_DISTANCE in Dioptrien; 0 = Fixfokus. */
    val minFocusDistance: Float? = null,
    /** LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION. */
    val oisModes: List<Int>? = null,
    /** CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES. */
    val videoStabModes: List<Int>? = null,
)

/**
 * Zu setzende Werte der Anfrage, `null` = nicht setzen: CONTROL_AF_MODE, LENS_FOCUS_DISTANCE,
 * LENS_OPTICAL_STABILIZATION_MODE, CONTROL_VIDEO_STABILIZATION_MODE.
 */
data class PpgLensSettings(
    val afMode: Int?,
    val focusDistance: Float?,
    val oisMode: Int?,
    val videoStabMode: Int?,
)

/** Ergebnis von [PpgCameraLogic.exposureLock]. */
sealed class PpgExposureLock {
    /** CONTROL_AE_LOCK wie bisher (Automatik bleibt, gesperrt). */
    object AeLock : PpgExposureLock()

    /**
     * CONTROL_AE_MODE_OFF mit SENSOR_EXPOSURE_TIME = [exposureNs], SENSOR_SENSITIVITY = [sensitivity]
     * und SENSOR_FRAME_DURATION = [frameDurationNs].
     */
    data class Manual(val exposureNs: Long, val sensitivity: Int, val frameDurationNs: Long) : PpgExposureLock()
}

/** Ergebnis von [PpgCameraLogic.pick]: die zu öffnende Kamera oder der Grund des Abbruchs. */
data class PpgCameraPick(val entry: PpgCameraEntry?, val reason: String?)

/**
 * Kamera-Angaben aus dem letzten CaptureResult (Belichtung, ISO, Rolling-Shutter-Versatz,
 * Torch-Stärke) und der Zeitstempelquelle aus den Kameraeigenschaften ("realtime", "unknown").
 * Was das Gerät nicht liefert, ist null.
 */
class PpgCaptureInfo(
    val exposureNs: Long? = null,
    val iso: Int? = null,
    val timestampSource: String? = null,
    val skewNs: Long? = null,
    val torch: Int? = null,
) {
    /** Camera2 SENSOR_INFO_TIMESTAMP_SOURCE: 1 = REALTIME, 0 = UNKNOWN. */
    companion object {
        fun sourceName(code: Int?): String? = when (code) {
            1 -> "realtime"
            0 -> "unknown"
            else -> null
        }
    }
}

/** Was der Controller an der Kamera tut. Jeder Schritt darf scheitern, ohne die übrigen zu verhindern. */
interface PpgHardware {
    fun lockExposure()
    fun torchOff()
    fun closeSession()
    fun closeDevice()
}

/**
 * Führt Zugriffe auf Gerät, Sitzung, Anfrage und Reader auf dem Kamerathread aus. Camera2-Callbacks
 * und Bildabruf laufen dort; Freigabe und Stop kommen vom Hauptthread. Auf dem Kamerathread selbst läuft
 * der Schritt sofort (Fehler gehen an den Aufrufer), von anderen Threads wird er in die Warteschlange
 * gestellt, in der Reihenfolge der Aufrufe; ein Fehler dort wird verschluckt, weil niemand mehr
 * zuhört (Gerät schon weg) und ein Absturz des Threads die App beenden würde.
 */
class PpgCameraThread(private val onThread: () -> Boolean, private val post: (Runnable) -> Unit) {
    fun run(step: () -> Unit) {
        if (onThread()) {
            step()
        } else {
            post(Runnable {
                try {
                    step()
                } catch (_: Exception) {
                }
            })
        }
    }
}

/**
 * Beendet den Kamerathread erst, wenn kein openCamera mehr aussteht. Wird die Aufnahme beendet, bevor
 * onOpened kam, läge der Callback sonst auf einem toten Handler: das Gerät bliebe bis zum Prozessende offen.
 * [openRequested] vor openCamera; [openSettled] in onOpened, onError, onDisconnected und wenn openCamera
 * selbst scheitert; [quitWhenIdle] beim Freigeben. Der Thread wird genau einmal beendet, von wem zuletzt kommt.
 */
class PpgThreadGuard(private val quit: () -> Unit) {
    private var openPending = false
    private var quitRequested = false
    private var quitDone = false

    @Synchronized
    fun openRequested() {
        openPending = true
    }

    fun openSettled() {
        if (settle()) quit()
    }

    fun quitWhenIdle() {
        if (request()) quit()
    }

    @Synchronized
    private fun settle(): Boolean {
        openPending = false
        return mayQuit()
    }

    @Synchronized
    private fun request(): Boolean {
        quitRequested = true
        return mayQuit()
    }

    private fun mayQuit(): Boolean {
        if (!quitRequested || openPending || quitDone) return false
        quitDone = true
        return true
    }
}

/** Wohin der Controller meldet (Android: EventChannel auf dem Hauptthread; Test: Liste). */
interface PpgSink {
    fun event(map: Map<String, Any>)
    fun end()
}

/**
 * Ablauf einer Aufnahme: Zeit seit dem ersten Bild, Sperre nach 2,5 s und das Beenden. Beenden
 * (Abbruch mit Grund, Hintergrund, Abbestellen) schaltet immer zuerst den Torch aus, schließt dann
 * Sitzung und Gerät und beendet den Strom genau einmal. Danach wird nichts mehr gemeldet.
 */
class PpgController(private val hw: PpgHardware, private val sink: PpgSink) {
    private var firstNs = -1L
    private var locked = false
    private var finished = false
    private var frames = 0L
    private var saturatedSum = 0.0
    private var sinceLock = 0

    /** Kamera läuft; meldet Bildrate und die tatsächlich geöffnete Kamera. */
    @Synchronized
    fun started(fps: Int, cameraId: String, physicalCameraId: String? = null) {
        if (finished) return
        val m = mutableMapOf<String, Any>("type" to "started", "fps" to fps, "cameraId" to cameraId)
        physicalCameraId?.let { m["physicalCameraId"] = it }
        sink.event(m)
    }

    @Synchronized
    fun frame(timestampNs: Long, stats: PpgStats, capture: PpgCaptureInfo? = null) {
        if (finished) return
        if (firstNs < 0) firstNs = timestampNs
        val t = (timestampNs - firstNs) / 1e9
        sink.event(
            mapOf(
                "type" to "frame",
                "t" to t,
                "r" to stats.r,
                "g" to stats.g,
                "r16" to stats.r16.toList(),
                "g16" to stats.g16.toList(),
            ),
        )
        frames++
        saturatedSum += stats.saturated
        if (!locked && t >= PpgCameraLogic.AE_LOCK_AT_SECONDS) {
            locked = true
            if (attempt { hw.lockExposure() }) sink.event(mapOf("type" to "locked"))
        } else if (locked) {
            // Kamera-Angaben erst, wenn die Sperre gegriffen hat (30 Bilder nach dem Sperren), dann
            // gelegentlich erneuert, damit der Anteil gesättigter Pixel mitwächst; der letzte Stand gilt.
            sinceLock++
            if (sinceLock == DETAILS_FIRST_AFTER || sinceLock % DETAILS_EVERY == 0) {
                sink.event(details(capture))
            }
        }
    }

    private fun details(c: PpgCaptureInfo?): Map<String, Any> {
        val m = mutableMapOf<String, Any>("type" to "details")
        if (frames > 0) m["saturated"] = saturatedSum / frames
        c?.exposureNs?.let { m["exposureNs"] = it }
        c?.iso?.let { m["iso"] = it }
        c?.timestampSource?.let { m["timestampSource"] = it }
        c?.skewNs?.let { m["skewNs"] = it }
        c?.torch?.let { m["torch"] = it }
        return m
    }

    private companion object {
        const val DETAILS_FIRST_AFTER = 30
        const val DETAILS_EVERY = 120
    }

    /** Abbruch (Fehler, Hintergrund): Grund melden, Hardware freigeben, Strom beenden. */
    @Synchronized
    fun abort(reason: String) {
        if (finished) return
        finished = true
        sink.event(mapOf("type" to "stopped", "reason" to reason))
        release()
        sink.end()
    }

    /** Reguläres Ende (Dart hat abbestellt oder stop gerufen): ohne Ereignis. */
    @Synchronized
    fun stop() {
        if (finished) return
        finished = true
        release()
        sink.end()
    }

    val isFinished: Boolean @Synchronized get() = finished

    private fun release() {
        attempt { hw.torchOff() }
        attempt { hw.closeSession() }
        attempt { hw.closeDevice() }
    }

    private fun attempt(step: () -> Unit): Boolean = try {
        step()
        true
    } catch (_: Exception) {
        // Gerät schon weg oder Sitzung schon zu: die übrigen Schritte laufen trotzdem.
        false
    }
}
