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

    /** Helligkeitssprung nach der Sperre: Rot-Sekundenmittel weicht um mehr als 20 % vom Bezug ab (PAR-245). */
    const val JUMP_RELATIVE = 0.20

    /** Ruhe nach dem Sprung: zwei aufeinanderfolgende Rot-Sekundenmittel weichen um höchstens 5 % ab (PAR-246). */
    const val CALM_RELATIVE = 0.05

    /** Bezug nach jeder Sperre: Mittel von Rot der Bilder 0,5 bis 1,5 s nach der Sperre (PAR-245). */
    const val REFERENCE_FROM_SECONDS = 0.5
    const val REFERENCE_TO_SECONDS = 1.5

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

    private fun entry(id: String, physical: String?, p: PpgCameraProps?, torch: Boolean, isDefault: Boolean): PpgCameraEntry {
        // Genau die Rate, mit der die Aufnahme auf dieser Kamera liefe (PpgCamera.kt startet mit ihr).
        val fps = p?.let { chooseFps(it.fpsRanges) }
        return PpgCameraEntry(
            cameraId = id,
            physicalCameraId = physical,
            focalLength = p?.focalLengths?.filter { it > 0f }?.minOrNull(),
            isDefault = isDefault,
            frameRate = fps,
            reason = when {
                p == null -> "error"
                !torch -> "no_flash"
                fps == null -> "frame_rate"
                chooseSize(p.yuvSizes) == null -> "error"
                else -> null
            },
        )
    }

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
 * sonst "no_flash", "frame_rate" oder "error" (wie die Abbruchgründe beim Start). [frameRate] ist die
 * Bildrate, mit der die Aufnahme auf ihr liefe ([PpgCameraLogic.chooseFps]), `null` ohne feste Rate
 * 30–60 oder ohne lesbare Eigenschaften (FR-0220). Nie ins Log.
 */
data class PpgCameraEntry(
    val cameraId: String,
    val physicalCameraId: String?,
    val focalLength: Float?,
    val isDefault: Boolean,
    val reason: String?,
    val frameRate: Int? = null,
) {
    val usable: Boolean get() = reason == null

    /** Für den MethodChannel; ohne Bildrate fehlt der Schlüssel "frameRate". */
    fun toMap(): Map<String, Any?> = buildMap {
        put("cameraId", cameraId)
        put("physicalCameraId", physicalCameraId)
        put("focalLength", focalLength?.toDouble())
        put("isDefault", isDefault)
        put("usable", usable)
        put("reason", reason)
        frameRate?.let { put("frameRate", it) }
    }
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

    /** Zurück auf die Automatik der ersten Phase (AE an, ohne Sperre), für die Neusperre (PAR-246). */
    fun unlockExposure()
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

/**
 * Wann die Belichtung gesperrt und wann sie neu eingeschwungen wird (PAR-245, PAR-246), nur aus Sensorzeit
 * [frame] `t` (Sekunden seit dem ersten Bild) und Rot-Mittel `r` je Bild:
 * - Einschwingen: [PpgCameraLogic.AE_LOCK_AT_SECONDS] nach Beginn (bzw. nach dem Beginn des
 *   Neu-Einschwingens) wird gesperrt ([Step.LOCK]).
 * - Bezug: Mittel von Rot der Bilder 0,5 bis 1,5 s nach der Sperre.
 * - Danach je volle Sekunde Sensorzeit (`[k, k + 1)`, erste volle Sekunde nach dem Bezug) das Rot-Mittel;
 *   weicht es um mehr als [PpgCameraLogic.JUMP_RELATIVE] vom Bezug ab, ist das ein Sprung ([Step.JUMP],
 *   mit dem Bild, das diese Sekunde abschließt).
 * - Nach dem Sprung ruhig, sobald zwei aufeinanderfolgende Sekundenmittel um höchstens
 *   [PpgCameraLogic.CALM_RELATIVE] voneinander abweichen: dann Neu-Einschwingen ([Step.RELOCK]) mit dem Bild,
 *   das die zweite ruhige Sekunde abschließt. Keine Höchstzahl.
 * Keine Werte ins Log (ADR-0011 Entscheidung 7).
 */
class PpgExposureWatch {
    /** [JUMP] meldet nur den erkannten Sprung (Test, Ablauf); gehandelt wird bei [LOCK] und [RELOCK]. */
    enum class Step { NONE, LOCK, JUMP, RELOCK }

    private enum class Phase { SETTLING, REFERENCE, WATCHING, JUMPED }

    private var phase = Phase.SETTLING
    private var settleFrom = 0.0
    private var lockAt = 0.0
    private var refSum = 0.0
    private var refCount = 0
    private var reference = 0.0
    private var firstSecond = 0L
    private var second = Long.MIN_VALUE
    private var secondSum = 0.0
    private var secondCount = 0
    private var previousSecond = Long.MIN_VALUE
    private var previousMean = 0.0

    fun frame(t: Double, r: Double): Step = when (phase) {
        Phase.SETTLING -> if (t - settleFrom >= PpgCameraLogic.AE_LOCK_AT_SECONDS) {
            phase = Phase.REFERENCE
            lockAt = t
            refSum = 0.0
            refCount = 0
            Step.LOCK
        } else {
            Step.NONE
        }
        Phase.REFERENCE -> {
            val d = t - lockAt
            if (d > PpgCameraLogic.REFERENCE_TO_SECONDS) {
                // Ohne Bild im Bezugsfenster (Bildlücke) gilt das erste Bild danach.
                reference = if (refCount > 0) refSum / refCount else r
                phase = Phase.WATCHING
                firstSecond = Math.ceil(lockAt + PpgCameraLogic.REFERENCE_TO_SECONDS).toLong()
                second = Long.MIN_VALUE
                previousSecond = Long.MIN_VALUE
                watch(t, r)
            } else {
                if (d >= PpgCameraLogic.REFERENCE_FROM_SECONDS) {
                    refSum += r
                    refCount++
                }
                Step.NONE
            }
        }
        Phase.WATCHING, Phase.JUMPED -> watch(t, r)
    }

    private fun watch(t: Double, r: Double): Step {
        val k = Math.floor(t).toLong()
        if (k < firstSecond) return Step.NONE
        var step = Step.NONE
        if (k != second) {
            if (secondCount > 0) step = closeSecond(second, secondSum / secondCount)
            if (step == Step.RELOCK) {
                phase = Phase.SETTLING
                settleFrom = t
                secondCount = 0
                return step
            }
            second = k
            secondSum = 0.0
            secondCount = 0
        }
        secondSum += r
        secondCount++
        return step
    }

    /** Wertet ein abgeschlossenes Sekundenmittel aus: [Step.JUMP], [Step.RELOCK] (ruhig nach dem Sprung) oder nichts. */
    private fun closeSecond(k: Long, mean: Double): Step {
        if (phase == Phase.WATCHING) {
            if (Math.abs(mean - reference) <= PpgCameraLogic.JUMP_RELATIVE * reference) return Step.NONE
            phase = Phase.JUMPED
            previousSecond = k
            previousMean = mean
            return Step.JUMP
        }
        val calm = previousSecond == k - 1 &&
            Math.abs(mean - previousMean) <= PpgCameraLogic.CALM_RELATIVE * previousMean
        previousSecond = k
        previousMean = mean
        return if (calm) Step.RELOCK else Step.NONE
    }
}

/** Wohin der Controller meldet (Android: EventChannel auf dem Hauptthread; Test: Liste). */
interface PpgSink {
    fun event(map: Map<String, Any>)
    fun end()
}

/**
 * Ablauf einer Aufnahme: Zeit seit dem ersten Bild, Sperre nach 2,5 s, Neusperre nach einem
 * Helligkeitssprung ([PpgExposureWatch]) und das Beenden. Beenden
 * (Abbruch mit Grund, Hintergrund, Abbestellen) schaltet immer zuerst den Torch aus, schließt dann
 * Sitzung und Gerät und beendet den Strom genau einmal. Danach wird nichts mehr gemeldet.
 */
class PpgController(
    private val hw: PpgHardware,
    private val sink: PpgSink,
    /** ISP-Werte je Bild mitsenden (nur auf Anforderung: Morgenmessung im Entwicklermodus). */
    private val ispFrames: Boolean = false,
) {
    private var firstNs = -1L
    private var locked = false
    private val watch = PpgExposureWatch()
    private var finished = false
    private var frames = 0L
    private var saturatedSum = 0.0
    private var sinceLock = 0

    /**
     * Kamera läuft; meldet Bildrate, die tatsächlich geöffnete Kamera und die tatsächlich gesetzten
     * Diagnose-Schalter ([diagnostics], Schlüssel "diagnostics" nur, wenn welche gesetzt sind; dazu
     * "awbVariant" bei festem Weißabgleich).
     */
    @Synchronized
    fun started(
        fps: Int,
        cameraId: String,
        physicalCameraId: String? = null,
        diagnostics: PpgDiagnosticSettings = PpgDiagnosticSettings.NONE,
    ) {
        if (finished) return
        val m = mutableMapOf<String, Any>("type" to "started", "fps" to fps, "cameraId" to cameraId)
        physicalCameraId?.let { m["physicalCameraId"] = it }
        val applied = diagnostics.applied
        if (applied.isNotEmpty()) m["diagnostics"] = applied.map { it.wire }
        diagnostics.awb?.let { m["awbVariant"] = it.wire }
        sink.event(m)
    }

    @Synchronized
    fun frame(timestampNs: Long, stats: PpgStats, capture: PpgCaptureInfo? = null, isp: DoubleArray? = null) {
        if (finished) return
        if (firstNs < 0) firstNs = timestampNs
        val t = (timestampNs - firstNs) / 1e9
        val m = mutableMapOf<String, Any>(
            "type" to "frame",
            "t" to t,
            "r" to stats.r,
            "g" to stats.g,
            "r16" to stats.r16.toList(),
            "g16" to stats.g16.toList(),
        )
        // 19 Werte als DoubleArray (Dart: Float64List), NaN = nicht gemeldet; nur auf Anforderung.
        if (ispFrames) m["isp"] = isp?.takeIf { it.size == PpgDiagnostics.ISP_VALUES } ?: PpgDiagnostics.notReported()
        sink.event(m)
        frames++
        saturatedSum += stats.saturated
        val step = watch.frame(t, stats.r)
        if (step == PpgExposureWatch.Step.RELOCK) {
            // Neu einschwingen nach einem Helligkeitssprung (PAR-246); die Sperre folgt 2,5 s später.
            attempt { hw.unlockExposure() }
            sink.event(mapOf("type" to "relocking", "t" to t))
        }
        if (step == PpgExposureWatch.Step.LOCK) {
            locked = true
            // Bei jeder Sperre mit ihrer Sensorzeit.
            if (attempt { hw.lockExposure() }) sink.event(mapOf("type" to "locked", "t" to t))
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

/**
 * Diagnose-Schalter der Bildverarbeitung (FR-0217, ADR-0011, Nachtrag 2026-11-21: Diagnose der
 * Bildverarbeitung). [wire] ist der Name im Kanal (Argument "diagnostics", Meldung in "started").
 */
enum class PpgDiagnostic(val wire: String) {
    NOISE_REDUCTION_OFF("noise_reduction_off"),
    EDGE_OFF("edge_off"),
    AWB_FIXED("awb_fixed"),
    TONEMAP_LINEAR("tonemap_linear"),
    SHADING_OFF("shading_off"),
    ;

    companion object {
        /** Liest die Liste aus dem Start-Argument; Unbekanntes entfällt. */
        fun fromWire(list: Any?): Set<PpgDiagnostic> {
            val names = (list as? List<*>)?.filterIsInstance<String>().orEmpty().toSet()
            return entries.filter { it.wire in names }.toSet()
        }
    }
}

/** Variante „Weißabgleich fest ab Start“: (a) [MATRIX] AWB aus mit fester Matrix, (b) [LOCK] AWB-Sperre ab dem ersten Bild. */
enum class PpgAwbVariant(val wire: String) { MATRIX("matrix"), LOCK("lock") }

/**
 * Characteristics der Kamera, an die die Anfrage geht, für [PpgCameraLogic.diagnosticSettings]
 * (ohne Android-Objekte); `null` = fehlt.
 */
data class PpgIspProps(
    /** NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES. */
    val noiseReductionModes: List<Int>? = null,
    /** EDGE_AVAILABLE_EDGE_MODES. */
    val edgeModes: List<Int>? = null,
    /** CONTROL_AWB_AVAILABLE_MODES. */
    val awbModes: List<Int>? = null,
    /** CONTROL_AWB_LOCK_AVAILABLE. */
    val awbLockAvailable: Boolean? = null,
    /** Fähigkeit MANUAL_POST_PROCESSING (REQUEST_AVAILABLE_CAPABILITIES). */
    val manualPostProcessing: Boolean = false,
    /** TONEMAP_AVAILABLE_TONE_MAP_MODES. */
    val tonemapModes: List<Int>? = null,
    /** SHADING_AVAILABLE_MODES. */
    val shadingModes: List<Int>? = null,
)

/**
 * Zusätzliche Werte der Anfrage aus den Diagnose-Schaltern, `null` = nicht setzen:
 * NOISE_REDUCTION_MODE, EDGE_MODE, TONEMAP_MODE (mit [tonemapCurve] für alle Kanäle), SHADING_MODE
 * und die Variante des festen Weißabgleichs. [applied] sind die tatsächlich gesetzten Schalter.
 */
data class PpgDiagnosticSettings(
    val noiseReductionMode: Int? = null,
    val edgeMode: Int? = null,
    val tonemapMode: Int? = null,
    val tonemapCurve: FloatArray? = null,
    val shadingMode: Int? = null,
    val awb: PpgAwbVariant? = null,
) {
    val applied: List<PpgDiagnostic>
        get() = buildList {
            if (noiseReductionMode != null) add(PpgDiagnostic.NOISE_REDUCTION_OFF)
            if (edgeMode != null) add(PpgDiagnostic.EDGE_OFF)
            if (awb != null) add(PpgDiagnostic.AWB_FIXED)
            if (tonemapMode != null) add(PpgDiagnostic.TONEMAP_LINEAR)
            if (shadingMode != null) add(PpgDiagnostic.SHADING_OFF)
        }

    override fun equals(other: Any?): Boolean =
        other is PpgDiagnosticSettings && noiseReductionMode == other.noiseReductionMode &&
            edgeMode == other.edgeMode && tonemapMode == other.tonemapMode &&
            (tonemapCurve?.toList() == other.tonemapCurve?.toList()) &&
            shadingMode == other.shadingMode && awb == other.awb

    override fun hashCode(): Int =
        listOf(noiseReductionMode, edgeMode, tonemapMode, tonemapCurve?.toList(), shadingMode, awb).hashCode()

    companion object {
        /** Alle Schalter aus: die Anfrage bleibt wie in der Vorgabe des Verfahrens. */
        val NONE = PpgDiagnosticSettings()
    }
}

/** Diagnose der Bildverarbeitung (ADR-0011, Nachtrag 2026-11-21), reine Funktionen und kleine Zustände. */
object PpgDiagnostics {
    /** Lineare Tonwertkurve (0,0)–(1,1) als (Eingang, Ausgang)-Paare je Kanal. */
    val LINEAR_CURVE = floatArrayOf(0f, 0f, 1f, 1f)

    /** Spätestens nach dieser Zeit ab dem ersten Ergebnis gilt das Ergebnis für den festen Weißabgleich (a). */
    const val AWB_FIX_LATEST_NS = 500_000_000L

    /** Anzahl der ISP-Werte je Bild (Reihenfolge siehe [PpgIspValues]). */
    const val ISP_VALUES = 19

    /** Größe des Puffers für die Zuordnung Ergebnis ↔ Bild über den Sensor-Zeitstempel. */
    const val MATCH_CAPACITY = 8

    /**
     * Schalter + Characteristics → Schlüssel und Werte. Gesetzt wird nur, was die Kamera laut
     * Characteristics anbietet; `null` oder leer gilt als „nicht angeboten“, dann wirkt der Schalter
     * nicht. Weißabgleich: (a) AWB OFF mit Transformationsmatrix, wenn die Kamera MANUAL_POST_PROCESSING
     * meldet und AWB OFF führt; sonst (b) AWB-Sperre ab dem ersten Bild, wenn CONTROL_AWB_LOCK_AVAILABLE.
     */
    fun diagnosticSettings(requested: Set<PpgDiagnostic>, props: PpgIspProps): PpgDiagnosticSettings {
        fun offered(on: PpgDiagnostic, mode: Int, modes: List<Int>?): Int? =
            mode.takeIf { on in requested && it in modes.orEmpty() }
        val tonemap = offered(
            PpgDiagnostic.TONEMAP_LINEAR, CameraMetadata.TONEMAP_MODE_CONTRAST_CURVE, props.tonemapModes,
        )
        val awb = when {
            PpgDiagnostic.AWB_FIXED !in requested -> null
            props.manualPostProcessing && CameraMetadata.CONTROL_AWB_MODE_OFF in props.awbModes.orEmpty() ->
                PpgAwbVariant.MATRIX
            props.awbLockAvailable == true -> PpgAwbVariant.LOCK
            else -> null
        }
        return PpgDiagnosticSettings(
            noiseReductionMode = offered(
                PpgDiagnostic.NOISE_REDUCTION_OFF, CameraMetadata.NOISE_REDUCTION_MODE_OFF, props.noiseReductionModes,
            ),
            edgeMode = offered(PpgDiagnostic.EDGE_OFF, CameraMetadata.EDGE_MODE_OFF, props.edgeModes),
            tonemapMode = tonemap,
            tonemapCurve = if (tonemap != null) LINEAR_CURVE.copyOf() else null,
            shadingMode = offered(PpgDiagnostic.SHADING_OFF, CameraMetadata.SHADING_MODE_OFF, props.shadingModes),
            awb = awb,
        )
    }

    /** Packt die 19 Werte eines Ergebnisses; was fehlt (`null`), ist NaN („nicht gemeldet“). */
    fun pack(values: List<Number?>): DoubleArray {
        require(values.size == ISP_VALUES)
        return DoubleArray(ISP_VALUES) { values[it]?.toDouble() ?: Double.NaN }
    }

    /** Alle 19 Werte „nicht gemeldet“. */
    fun notReported(): DoubleArray = DoubleArray(ISP_VALUES) { Double.NaN }
}

/**
 * Wählt für den festen Weißabgleich (a) das Ergebnis, dessen Farbverstärkungen [G] und Matrix [M]
 * gelten: das erste mit AWB-Zustand CONVERGED, spätestens das erste ab [PpgDiagnostics.AWB_FIX_LATEST_NS]
 * nach dem ersten Ergebnis. Ein Ergebnis ohne Verstärkungen oder Matrix zählt nicht. Liefert genau
 * einmal einen Wert, danach immer `null`.
 */
class PpgAwbFixer<G, M> {
    private var firstNs: Long? = null
    private var done = false

    fun offer(timestampNs: Long, awbState: Int?, gains: G?, matrix: M?): Pair<G, M>? {
        if (done) return null
        val first = firstNs ?: timestampNs.also { firstNs = it }
        if (gains == null || matrix == null) return null
        val due = awbState == CameraMetadata.CONTROL_AWB_STATE_CONVERGED ||
            timestampNs - first >= PpgDiagnostics.AWB_FIX_LATEST_NS
        if (!due) return null
        done = true
        return gains to matrix
    }
}

/**
 * Ordnet jedem Bild die ISP-Werte des Ergebnisses mit demselben Sensor-Zeitstempel zu
 * (CaptureResult.SENSOR_TIMESTAMP = Image.getTimestamp()). Ergebnisse und Bilder kommen je in
 * zeitlicher Reihenfolge, aber nicht zwingend im Wechsel: ein Bild ohne passendes Ergebnis wartet, bis
 * es kommt (verspätetes Ergebnis), bis ein Ergebnis eines späteren Bildes kommt oder bis mehr als
 * [capacity] Bilder warten; dann ist es „nicht gemeldet“ (`null`), nie der Wert eines anderen Bildes.
 * Bilder gehen in ihrer Reihenfolge an [emit]. Gemerkt werden höchstens [capacity] Ergebnisse.
 */
class PpgIspMatcher<F>(
    private val capacity: Int = PpgDiagnostics.MATCH_CAPACITY,
    private val emit: (timestampNs: Long, frame: F, isp: DoubleArray?) -> Unit,
) {
    private val results = LinkedHashMap<Long, DoubleArray>()
    private val pending = ArrayDeque<Pair<Long, F>>()
    private var latestResultNs = Long.MIN_VALUE

    fun onResult(timestampNs: Long, values: DoubleArray) {
        results[timestampNs] = values
        while (results.size > capacity) results.remove(results.keys.first())
        if (timestampNs > latestResultNs) latestResultNs = timestampNs
        drain()
    }

    fun onFrame(timestampNs: Long, frame: F) {
        pending.addLast(timestampNs to frame)
        drain()
        while (pending.size > capacity) {
            val (ts, f) = pending.removeFirst()
            emit(ts, f, results.remove(ts))
        }
    }

    private fun drain() {
        while (pending.isNotEmpty()) {
            val (ts, f) = pending.first()
            val r = results.remove(ts)
            when {
                r != null -> emit(ts, f, r)
                latestResultNs > ts -> emit(ts, f, null)
                else -> return
            }
            pending.removeFirst()
        }
    }
}

/** Kamera der Kamerasuche (Dart: PpgCameraRef). */
data class PpgPreviewRef(val cameraId: String, val physicalCameraId: String?)

/**
 * Plan der Kamerasuche (FR-0220): [live] sind die angefragten Kameras, die nutzbar sind (Reihenfolge
 * wie angefragt), [failed] die übrigen mit Grund ("no_camera", "no_flash", "frame_rate", "error").
 */
data class PpgPreviewPlan(val live: List<PpgPreviewRef>, val failed: List<Pair<PpgPreviewRef, String>>)

/**
 * Reine Regeln der Kamerasuche (FR-0220, PAR-227; ADR-0011, Nachtrag 2026-11-24): welche Kameras,
 * gleichzeitig oder im Wechsel, Reihenfolge und Takt des Wechsels, Größe und Nachrichten an Dart.
 * Vorschaubilder gehen nur in die Texture der Anzeige, nie nach Dart, in Logs oder auf Platte.
 */
object PpgPreviewLogic {
    /** PAR-227: Dauer einer Kamera im Wechsel und Fenster des gleitenden Mittels (1,5 s). */
    const val PREVIEW_TURN_NS = 1_500_000_000L

    /** Vorschaubild je Kamera (klein, eine Ausgabe je Kamera). */
    const val PREVIEW_WIDTH = 160
    const val PREVIEW_HEIGHT = 120

    /** Argument von Dart (`{cameras: [{cameraId, physicalCameraId}]}`); Unpassendes entfällt, doppelte auch. */
    fun parseRefs(arguments: Any?): List<PpgPreviewRef> {
        val list = (arguments as? Map<*, *>)?.get("cameras") as? List<*> ?: return emptyList()
        val out = LinkedHashSet<PpgPreviewRef>()
        for (m in list) {
            if (m !is Map<*, *>) continue
            val id = m["cameraId"] as? String ?: continue
            if (id.isEmpty()) continue
            val physical = m["physicalCameraId"]
            if (physical != null && (physical !is String || physical.isEmpty())) continue
            out.add(PpgPreviewRef(id, physical as String?))
        }
        return out.toList()
    }

    /** Ordnet die angefragten Kameras der Kameraliste zu ([PpgCameraLogic.pick]): nutzbar oder mit Grund. */
    fun plan(refs: List<PpgPreviewRef>, entries: List<PpgCameraEntry>): PpgPreviewPlan {
        val live = ArrayList<PpgPreviewRef>()
        val failed = ArrayList<Pair<PpgPreviewRef, String>>()
        for (r in refs) {
            val pick = PpgCameraLogic.pick(entries, r.cameraId, r.physicalCameraId)
            val reason = pick.reason ?: if (pick.entry == null) "error" else null
            if (reason == null) live.add(r) else failed.add(r to reason)
        }
        return PpgPreviewPlan(live, failed)
    }

    /**
     * Gleichzeitiger Betrieb kommt nur in Frage, wenn alle Kameras zu derselben logischen Kamera
     * gehören (gleiche cameraId): eine Sitzung, die logische Kamera selbst mit einem Ausgang ohne,
     * ihre physischen Kameras je mit einem Ausgang mit setPhysicalCameraId. Ob das Gerät die
     * Kombination trägt, entscheidet isSessionConfigurationSupported ([previewMode]). Getrennte
     * Kamera-IDs werden nie gleichzeitig geöffnet. Eine einzelne Kamera braucht keinen Wechsel.
     */
    fun canShareSession(live: List<PpgPreviewRef>): Boolean = when {
        live.size <= 1 -> true
        else -> live.all { it.cameraId == live[0].cameraId } && live.toSet().size == live.size
    }

    /**
     * PAR-227: gleichzeitig ("simultaneous"), wenn die Kameras eine Sitzung teilen können und das Gerät
     * die Kombination bestätigt ([sessionSupported], CameraDevice.isSessionConfigurationSupported), sonst
     * im Wechsel ("alternating"). Eine einzelne Kamera läuft immer allein in ihrer Sitzung.
     */
    fun previewMode(live: List<PpgPreviewRef>, sessionSupported: Boolean): String = when {
        live.size <= 1 -> "simultaneous"
        canShareSession(live) && sessionSupported -> "simultaneous"
        else -> "alternating"
    }

    /**
     * Nächste Kamera im Wechsel nach [current] (Reihenfolge der Anfrage, Standardkamera zuerst, endlos),
     * ausgelassen werden die mit Fehler ([failed]); `null`, wenn keine mehr übrig ist. [current] -1 = Beginn.
     */
    fun nextTurn(current: Int, count: Int, failed: Set<Int>): Int? {
        if (count <= 0) return null
        for (step in 1..count) {
            val k = Math.floorMod(current + step, count)
            if (k !in failed) return k
        }
        return null
    }

    /** Größe des Vorschauausgangs: die kleinste ab [PREVIEW_WIDTH]×[PREVIEW_HEIGHT], sonst die größte. */
    fun chooseSize(sizes: List<Pair<Int, Int>>): Pair<Int, Int>? =
        sizes.filter { it.first >= PREVIEW_WIDTH && it.second >= PREVIEW_HEIGHT }.minByOrNull { it.first * it.second }
            ?: sizes.maxByOrNull { it.first * it.second }

    /**
     * Verkleinertes Farbbild (ARGB, BT.601 Vollbereich) aus YUV_420_888 für die Anzeige, [outW]×[outH]
     * Pixel durch Abtasten. Nur für die Texture; nie gespeichert, nie nach Dart.
     */
    fun argb(w: Int, h: Int, y: PpgPlane, u: PpgPlane, v: PpgPlane, outW: Int, outH: Int, out: IntArray) {
        for (oy in 0 until outH) {
            val sy = oy * h / outH
            for (ox in 0 until outW) {
                val sx = ox * w / outW
                val yy = (y.buffer.get(sy * y.rowStride + sx * y.pixelStride).toInt() and 0xff).toDouble()
                val ci = (sy / 2) * u.rowStride + (sx / 2) * u.pixelStride
                val cv = (sy / 2) * v.rowStride + (sx / 2) * v.pixelStride
                val uu = (u.buffer.get(ci).toInt() and 0xff) - 128.0
                val vv = (v.buffer.get(cv).toInt() and 0xff) - 128.0
                val r = clamp(yy + 1.402 * vv)
                val g = clamp(yy - 0.344136 * uu - 0.714136 * vv)
                val b = clamp(yy + 1.772 * uu)
                out[oy * outW + ox] = (0xff shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
    }

    private fun clamp(x: Double): Int = x.toInt().coerceIn(0, 255)

    private fun refMap(r: PpgPreviewRef): Map<String, Any?> =
        mapOf("cameraId" to r.cameraId, "physicalCameraId" to r.physicalCameraId)

    fun startedMap(mode: String, textures: Map<PpgPreviewRef, Long>): Map<String, Any?> = mapOf(
        "type" to "started",
        "mode" to mode,
        "textures" to textures.map { (r, id) -> refMap(r) + ("textureId" to id) },
    )

    /** Ein Bild: R, G der Bildmitte, Belichtungszeit und ISO, [t] Sensorzeit in s seit dem ersten Bild der Suche. */
    fun frameMap(r: PpgPreviewRef, t: Double, red: Double, green: Double, exposureNs: Long?, iso: Int?): Map<String, Any?> =
        refMap(r) + mapOf("type" to "frame", "t" to t, "r" to red, "g" to green, "exposureNs" to exposureNs, "iso" to iso)

    fun turnMap(r: PpgPreviewRef): Map<String, Any?> = refMap(r) + ("type" to "turn")

    fun failedMap(r: PpgPreviewRef, reason: String): Map<String, Any?> =
        refMap(r) + mapOf("type" to "failed", "reason" to reason)

    fun stoppedMap(reason: String): Map<String, Any?> = mapOf("type" to "stopped", "reason" to reason)
}
