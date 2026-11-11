package io.github.brokoskokoli.ramuri

import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraDevice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PpgCameraLogicTest {
    // --- Verfügbarkeit ---

    @Test fun availabilityPrefersCameraThenFlashThenPermission() {
        assertEquals("no_camera", PpgCameraLogic.decide(false, true, true))
        assertEquals("no_camera", PpgCameraLogic.decide(false, false, false))
        assertEquals("no_flash", PpgCameraLogic.decide(true, false, true))
        assertEquals("permission_denied", PpgCameraLogic.decide(true, true, false))
        assertEquals("available", PpgCameraLogic.decide(true, true, true))
    }

    // --- Bildrate und Größe ---

    @Test fun fpsPrefersSixtyOverThirty() {
        assertEquals(60, PpgCameraLogic.chooseFps(listOf(30 to 30, 60 to 60, 15 to 60)))
    }

    @Test fun fpsFallsBackToThirty() {
        assertEquals(30, PpgCameraLogic.chooseFps(listOf(24 to 24, 30 to 30, 15 to 60)))
    }

    @Test fun fpsBelowThirtyOrOnlyVariableIsAnError() {
        assertNull(PpgCameraLogic.chooseFps(listOf(24 to 24, 15 to 30)))
        assertNull(PpgCameraLogic.chooseFps(listOf(30 to 60, 15 to 60)))
        assertNull(PpgCameraLogic.chooseFps(emptyList()))
    }

    @Test fun fpsAboveSixtyIsNotChosen() {
        // Die Auswertung ist für 30 und 60 fps festgelegt.
        assertEquals(60, PpgCameraLogic.chooseFps(listOf(120 to 120, 60 to 60)))
        assertEquals(30, PpgCameraLogic.chooseFps(listOf(120 to 120, 30 to 30)))
        assertNull(PpgCameraLogic.chooseFps(listOf(120 to 120)))
    }

    @Test fun sizePrefersExactThenSmallestLargerThenLargestSmaller() {
        assertEquals(320 to 240, PpgCameraLogic.chooseSize(listOf(640 to 480, 320 to 240, 176 to 144)))
        assertEquals(352 to 288, PpgCameraLogic.chooseSize(listOf(640 to 480, 352 to 288, 176 to 144)))
        assertEquals(176 to 144, PpgCameraLogic.chooseSize(listOf(160 to 120, 176 to 144)))
        assertNull(PpgCameraLogic.chooseSize(emptyList()))
    }

    // --- Fehlerzuordnung ---

    @Test fun deviceErrorsMapToReasons() {
        assertEquals("busy", PpgCameraLogic.fromDeviceError(CameraDevice.StateCallback.ERROR_CAMERA_IN_USE))
        assertEquals("busy", PpgCameraLogic.fromDeviceError(CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE))
        assertEquals("permission_denied", PpgCameraLogic.fromDeviceError(CameraDevice.StateCallback.ERROR_CAMERA_DISABLED))
        assertEquals("error", PpgCameraLogic.fromDeviceError(CameraDevice.StateCallback.ERROR_CAMERA_DEVICE))
        assertEquals("error", PpgCameraLogic.fromDeviceError(CameraDevice.StateCallback.ERROR_CAMERA_SERVICE))
        assertEquals("error", PpgCameraLogic.fromDeviceError(999))
    }

    @Test fun accessReasonsMapToReasons() {
        assertEquals("busy", PpgCameraLogic.fromAccessReason(CameraAccessException.CAMERA_IN_USE))
        assertEquals("busy", PpgCameraLogic.fromAccessReason(CameraAccessException.MAX_CAMERAS_IN_USE))
        assertEquals("disconnected", PpgCameraLogic.fromAccessReason(CameraAccessException.CAMERA_DISCONNECTED))
        assertEquals("permission_denied", PpgCameraLogic.fromAccessReason(CameraAccessException.CAMERA_DISABLED))
        assertEquals("error", PpgCameraLogic.fromAccessReason(CameraAccessException.CAMERA_ERROR))
    }

    @Test fun securityExceptionIsPermissionDenied() {
        assertEquals("permission_denied", PpgCameraLogic.fromException(SecurityException("x")))
        assertEquals("error", PpgCameraLogic.fromException(IllegalStateException("x")))
    }

    // --- Ablauf und Lebenszyklus ---

    private class Hw(val log: MutableList<String>, val failTorch: Boolean = false) : PpgHardware {
        override fun lockExposure() { log += "lock" }
        override fun torchOff() { log += "torchOff"; if (failTorch) throw IllegalStateException("zu") }
        override fun closeSession() { log += "closeSession" }
        override fun closeDevice() { log += "closeDevice" }
    }

    private class Sink(val log: MutableList<String>) : PpgSink {
        val events = mutableListOf<Map<String, Any>>()
        var ended = 0
        override fun event(map: Map<String, Any>) { events += map; log += "event:" + map["type"] }
        override fun end() { ended++; log += "end" }
    }

    private val stats = PpgStats(200.0, 40.0, DoubleArray(16) { 200.0 }, DoubleArray(16) { 40.0 })
    private fun ns(s: Double) = (s * 1e9).toLong()

    @Test fun frameTimeIsSecondsSinceFirstFrameOnSensorClock() {
        val log = mutableListOf<String>()
        val sink = Sink(log)
        val c = PpgController(Hw(log), sink)
        c.frame(ns(1000.0), stats)
        c.frame(ns(1000.5), stats)
        assertEquals(0.0, sink.events[0]["t"] as Double, 0.0)
        assertEquals(0.5, sink.events[1]["t"] as Double, 1e-9)
        assertEquals(16, (sink.events[1]["r16"] as List<*>).size)
    }

    @Test fun exposureIsLockedOnceAtTwoAndAHalfSeconds() {
        val log = mutableListOf<String>()
        val c = PpgController(Hw(log), Sink(log))
        for (t in listOf(0.0, 1.0, 2.4)) c.frame(ns(t), stats)
        assertFalse(log.contains("lock"))
        c.frame(ns(2.5), stats)
        assertEquals("Sperre mit dem Bild bei 2,5 s", 1, log.count { it == "lock" })
        for (t in listOf(3.0, 4.0)) c.frame(ns(t), stats)
        assertEquals(1, log.count { it == "lock" })
        assertEquals(1, log.count { it == "event:locked" })
    }

    @Test fun abortTurnsTorchOffThenClosesSessionAndDeviceThenEndsStream() {
        val log = mutableListOf<String>()
        val sink = Sink(log)
        val c = PpgController(Hw(log), sink)
        c.started(60)
        c.abort("background")
        assertEquals(
            listOf("event:started", "event:stopped", "torchOff", "closeSession", "closeDevice", "end"),
            log,
        )
        assertEquals("background", sink.events.last()["reason"])
        assertTrue(c.isFinished)
    }

    @Test fun nothingIsReportedAfterTheEnd() {
        val log = mutableListOf<String>()
        val sink = Sink(log)
        val c = PpgController(Hw(log), sink)
        c.abort("busy")
        val n = log.size
        c.frame(ns(5.0), stats)
        c.started(30)
        c.abort("error")
        c.stop()
        assertEquals(n, log.size)
        assertEquals(1, sink.ended)
    }

    @Test fun regularStopReleasesWithoutEventAndIsIdempotent() {
        val log = mutableListOf<String>()
        val sink = Sink(log)
        val c = PpgController(Hw(log), sink)
        c.stop()
        c.stop()
        assertEquals(listOf("torchOff", "closeSession", "closeDevice", "end"), log)
        assertTrue(sink.events.isEmpty())
    }

    @Test fun failingStepDoesNotPreventTheOthers() {
        val log = mutableListOf<String>()
        val sink = Sink(log)
        PpgController(Hw(log, failTorch = true), sink).abort("error")
        assertEquals(listOf("event:stopped", "torchOff", "closeSession", "closeDevice", "end"), log)
        assertEquals(1, sink.ended)
    }

    // --- Kamerathread ---

    @Test fun stepsFromOtherThreadsArePostedInOrderAndNotRunInline() {
        val queue = mutableListOf<Runnable>()
        val log = mutableListOf<String>()
        val t = PpgCameraThread(onThread = { false }, post = { queue += it })
        t.run { log += "a" }
        t.run { log += "b" }
        assertTrue("noch nichts ausgeführt", log.isEmpty())
        queue.forEach { it.run() }
        assertEquals(listOf("a", "b"), log)
    }

    @Test fun stepsOnTheCameraThreadRunInlineAndKeepTheirErrors() {
        val queue = mutableListOf<Runnable>()
        val log = mutableListOf<String>()
        val t = PpgCameraThread(onThread = { true }, post = { queue += it })
        t.run { log += "a" }
        assertEquals(listOf("a"), log)
        assertTrue(queue.isEmpty())
        var caught = false
        try {
            t.run { throw IllegalStateException("zu") }
        } catch (_: IllegalStateException) {
            caught = true
        }
        assertTrue("Fehler geht an den Aufrufer (der Controller fängt ihn je Schritt)", caught)
    }

    @Test fun aFailingPostedStepDoesNotStopTheNextOne() {
        val queue = mutableListOf<Runnable>()
        val log = mutableListOf<String>()
        val t = PpgCameraThread(onThread = { false }, post = { queue += it })
        t.run { throw IllegalStateException("zu") }
        t.run { log += "next" }
        queue.forEach { it.run() }
        assertEquals(listOf("next"), log)
    }
}
