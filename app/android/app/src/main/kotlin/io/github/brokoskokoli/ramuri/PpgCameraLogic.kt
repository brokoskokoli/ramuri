package io.github.brokoskokoli.ramuri

import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraDevice

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

/** Was der Controller an der Kamera tut. Jeder Schritt darf scheitern, ohne die übrigen zu verhindern. */
interface PpgHardware {
    fun lockExposure()
    fun torchOff()
    fun closeSession()
    fun closeDevice()
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

    @Synchronized
    fun started(fps: Int) {
        if (finished) return
        sink.event(mapOf("type" to "started", "fps" to fps))
    }

    @Synchronized
    fun frame(timestampNs: Long, stats: PpgStats) {
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
        if (!locked && t >= PpgCameraLogic.AE_LOCK_AT_SECONDS) {
            locked = true
            if (attempt { hw.lockExposure() }) sink.event(mapOf("type" to "locked"))
        }
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
