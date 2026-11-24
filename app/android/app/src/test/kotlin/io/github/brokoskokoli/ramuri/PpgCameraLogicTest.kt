package io.github.brokoskokoli.ramuri

import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraMetadata
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

    // --- Kameraliste (FR-0220) ---

    private val good = listOf(30 to 30, 60 to 60)
    private val yuv = listOf(320 to 240, 640 to 480)

    private fun cam(
        id: String,
        back: Boolean = true,
        flash: Boolean = true,
        physical: List<String> = emptyList(),
        focal: List<Float> = listOf(4.2f),
        fps: List<Pair<Int, Int>> = good,
        sizes: List<Pair<Int, Int>> = yuv,
    ) = PpgCameraProps(id, back, flash, physical.isNotEmpty(), physical, focal, fps, sizes)

    private fun list(vararg cams: PpgCameraProps, extra: Map<String, PpgCameraProps> = emptyMap()): List<PpgCameraEntry> {
        val all = cams.associateBy { it.id } + extra
        return PpgCameraLogic.listCameras(cams.map { it.id }, { all[it] })
    }

    private fun keys(l: List<PpgCameraEntry>) = l.map { e -> e.physicalCameraId?.let { "${e.cameraId}/$it" } ?: e.cameraId }

    @Test fun logicalMultiCameraListsItsThreePhysicalCameras() {
        val phys = mapOf(
            "4" to cam("4", flash = false, focal = listOf(6.0f, 5.5f)),
            "3" to cam("3", flash = false, focal = listOf(2.2f)),
            "5" to cam("5", flash = false, fps = listOf(15 to 30)),
        )
        val l = list(cam("0", physical = listOf("4", "3", "5"), focal = listOf(4.7f)), cam("1", back = false), extra = phys)
        assertEquals(listOf("0", "0/3", "0/4", "0/5"), keys(l))
        assertTrue(l[0].isDefault)
        assertFalse(l.drop(1).any { it.isDefault })
        // Physische Kameras: eigene Eigenschaften, Taschenlampe über die logische Kamera.
        assertEquals(2.2f, l[1].focalLength)
        assertEquals(5.5f, l[2].focalLength)
        assertNull(l[1].reason)
        assertNull(l[2].reason)
        assertEquals("frame_rate", l[3].reason)
        assertFalse(l[3].usable)
    }

    @Test fun physicalCamerasOfALogicalCameraWithoutFlashAreNotUsable() {
        val l = list(
            cam("0"),
            cam("2", flash = false, physical = listOf("6")),
            extra = mapOf("6" to cam("6", flash = true)),
        )
        assertEquals(listOf("0", "2", "2/6"), keys(l))
        assertEquals("no_flash", l[1].reason)
        assertEquals("no_flash", l[2].reason)
    }

    @Test fun cameraWithoutFlashIsListedButNotUsable() {
        val l = list(cam("0", flash = false), cam("1"))
        // Standard ist die erste Rückkamera mit Blitz (wie bisher), sie steht zuerst.
        assertEquals(listOf("1", "0"), keys(l))
        assertTrue(l[0].isDefault)
        assertTrue(l[0].usable)
        assertEquals("no_flash", l[1].reason)
        assertFalse(l[1].isDefault)
    }

    @Test fun cameraWithoutFixedFrameRateIsNotUsable() {
        val l = list(cam("0"), cam("1", fps = listOf(15 to 30, 30 to 60)))
        assertEquals("frame_rate", l[1].reason)
        assertNull(l[0].reason)
    }

    @Test fun cameraWithoutYuvSizeOrUnreadablePropertiesIsAnError() {
        val l = list(cam("0"), cam("1", sizes = emptyList()), cam("2", physical = listOf("9")))
        assertEquals(listOf("0", "1", "2", "2/9"), keys(l))
        assertEquals("error", l[1].reason)
        assertNull(l[2].reason)
        // Physische Kamera ohne lesbare Eigenschaften.
        assertEquals("error", l[3].reason)
        assertNull(l[3].focalLength)
    }

    @Test fun noBackCameraGivesAnEmptyList() {
        assertTrue(list(cam("0", back = false), cam("1", back = false)).isEmpty())
        assertTrue(PpgCameraLogic.listCameras(emptyList(), { null }).isEmpty())
        // Nicht lesbare Kamera-ID zählt nicht als Rückkamera.
        assertTrue(PpgCameraLogic.listCameras(listOf("0"), { null }).isEmpty())
    }

    @Test fun sortingDefaultFirstThenNumericIdsThenPhysical() {
        val l = list(cam("10"), cam("2", physical = listOf("11", "3")), cam("1", flash = false), cam("x"),
            extra = mapOf("11" to cam("11"), "3" to cam("3")))
        assertEquals(listOf("10", "1", "2", "2/3", "2/11", "x"), keys(l))
        assertTrue(l[0].isDefault)
        assertEquals(-1, Integer.signum(PpgCameraLogic.compareIds("2", "10")))
        assertEquals(1, Integer.signum(PpgCameraLogic.compareIds("a", "10")))
    }

    @Test fun focalLengthUnknownIsNull() {
        val l = list(cam("0", focal = emptyList()))
        assertNull(l[0].focalLength)
        assertNull(l[0].toMap()["focalLength"])
        assertEquals(true, l[0].toMap()["usable"])
    }

    @Test fun frameRateIsTheRateTheMeasurementWouldUse() {
        val l = list(
            cam("0", fps = listOf(30 to 30, 60 to 60)),
            cam("1", fps = listOf(30 to 30, 15 to 30)),
            cam("2", fps = listOf(15 to 30)),
        )
        assertEquals(listOf("0", "1", "2"), keys(l))
        assertEquals(60, l[0].frameRate)
        assertEquals(30, l[1].frameRate)
        assertNull(l[1].reason)
        assertNull(l[2].frameRate)
        assertEquals("frame_rate", l[2].reason)
    }

    @Test fun physicalCameraHasItsOwnFrameRate() {
        // Logische Kamera kann 60, ihre physische nur 30 (FR-0220, ADR-0011).
        val l = list(
            cam("0", physical = listOf("3", "4"), fps = listOf(30 to 30, 60 to 60)),
            extra = mapOf(
                "3" to cam("3", flash = false, fps = listOf(30 to 30)),
                "4" to cam("4", flash = false, fps = listOf(60 to 60, 30 to 30)),
            ),
        )
        assertEquals(listOf("0", "0/3", "0/4"), keys(l))
        assertEquals(60, l[0].frameRate)
        assertEquals(30, l[1].frameRate)
        assertEquals(60, l[2].frameRate)
    }

    @Test fun frameRateIsNullWithoutReadablePropertiesAndOnlyInTheMapWhenKnown() {
        val l = list(cam("0", physical = listOf("9")))
        assertEquals("error", l[1].reason)
        assertNull(l[1].frameRate)
        assertFalse(l[1].toMap().containsKey("frameRate"))
        assertEquals(60, l[0].toMap()["frameRate"])
    }

    // --- Kamera für den Start ---

    @Test fun pickWithoutArgumentIsTheDefaultCamera() {
        val l = list(cam("0", flash = false), cam("1"))
        val p = PpgCameraLogic.pick(l, null, null)
        assertEquals("1", p.entry?.cameraId)
        assertNull(p.reason)
        // Keine Rückkamera mit Blitz: wie bisher "no_flash".
        assertEquals("no_flash", PpgCameraLogic.pick(list(cam("0", flash = false)), null, null).reason)
        // Standardkamera ohne Bildrate: wie bisher "frame_rate".
        assertEquals("frame_rate", PpgCameraLogic.pick(list(cam("0", fps = listOf(15 to 30))), null, null).reason)
    }

    @Test fun pickOpensExactlyTheGivenCameraOrNone() {
        val l = list(cam("0", physical = listOf("3")), cam("1", flash = false), extra = mapOf("3" to cam("3", flash = false)))
        assertEquals(PpgCameraPick(l[1], null), PpgCameraLogic.pick(l, "0", "3"))
        assertEquals("0", PpgCameraLogic.pick(l, "0", null).entry?.cameraId)
        assertNull(PpgCameraLogic.pick(l, "0", null).entry?.physicalCameraId)
        // Unbekannt: kein Wechsel auf eine andere Kamera.
        assertEquals(PpgCameraPick(null, "no_camera"), PpgCameraLogic.pick(l, "9", null))
        assertEquals(PpgCameraPick(null, "no_camera"), PpgCameraLogic.pick(l, "0", "9"))
        assertEquals(PpgCameraPick(null, "no_camera"), PpgCameraLogic.pick(l, "3", null))
        // Nicht nutzbar: ihr Grund.
        assertEquals("no_flash", PpgCameraLogic.pick(l, "1", null).reason)
    }

    @Test fun startedReportsTheOpenedCamera() {
        val log = mutableListOf<String>()
        val sink = Sink(log)
        val c = PpgController(Hw(log), sink)
        c.started(30, "0", "3")
        assertEquals(mapOf("type" to "started", "fps" to 30, "cameraId" to "0", "physicalCameraId" to "3"), sink.events.single())
        val sink2 = Sink(log)
        PpgController(Hw(log), sink2).started(60, "1")
        assertEquals(mapOf("type" to "started", "fps" to 60, "cameraId" to "1"), sink2.events.single())
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

    @Test fun detailsComeOnlyAfterLockWithCaptureValuesAndMeanSaturation() {
        val log = mutableListOf<String>()
        val sink = Sink(log)
        val c = PpgController(Hw(log), sink)
        val info = PpgCaptureInfo(8_333_333L, 100, "realtime", 20_000_000L, null)
        val sat = PpgStats(200.0, 40.0, DoubleArray(16) { 200.0 }, DoubleArray(16) { 40.0 }, 0.25)
        for (i in 0 until 2) c.frame(ns(i * 0.5), sat, info)
        assertTrue("vor der Sperre keine Angaben", sink.events.none { it["type"] == "details" })
        c.frame(ns(2.5), sat, info)
        for (i in 1..29) c.frame(ns(2.5 + i / 30.0), stats, info)
        assertTrue("erst 30 Bilder nach der Sperre", sink.events.none { it["type"] == "details" })
        c.frame(ns(3.6), stats, info)
        val d = sink.events.single { it["type"] == "details" }
        assertEquals(8_333_333L, d["exposureNs"])
        assertEquals(100, d["iso"])
        assertEquals("realtime", d["timestampSource"])
        assertEquals(20_000_000L, d["skewNs"])
        assertFalse("Torch-Stärke fehlt, wenn die Kamera sie nicht liefert", d.containsKey("torch"))
        assertEquals("Mittel über alle 33 Bilder (3 mit 0,25)", 0.75 / 33, d["saturated"] as Double, 1e-9)
    }

    @Test fun sourceNameMapsTimestampSource() {
        assertEquals("realtime", PpgCaptureInfo.sourceName(1))
        assertEquals("unknown", PpgCaptureInfo.sourceName(0))
        assertEquals(null, PpgCaptureInfo.sourceName(null))
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
        c.started(60, "0")
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
        c.started(30, "0")
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

    // --- Kamerathread bei Abbruch vor onOpened ---

    @Test fun threadQuitsAtOnceWhenNoOpenIsPending() {
        var quits = 0
        val g = PpgThreadGuard { quits++ }
        g.quitWhenIdle()
        assertEquals(1, quits)
        g.quitWhenIdle()
        g.openSettled()
        assertEquals(1, quits)
    }

    @Test fun threadWaitsForPendingOpenThenQuitsOnce() {
        var quits = 0
        val g = PpgThreadGuard { quits++ }
        g.openRequested()
        g.quitWhenIdle()
        assertEquals(0, quits)
        g.openSettled()
        assertEquals(1, quits)
        g.openSettled()
        assertEquals(1, quits)
    }

    @Test fun settledOpenDoesNotQuitWithoutRequest() {
        var quits = 0
        val g = PpgThreadGuard { quits++ }
        g.openRequested()
        g.openSettled()
        assertEquals(0, quits)
        g.quitWhenIdle()
        assertEquals(1, quits)
    }

    // --- Fokus und Stabilisierung (ADR-0011, Nachtrag 2026-11-21) ---

    private val afOff = CameraMetadata.CONTROL_AF_MODE_OFF
    private val afAuto = CameraMetadata.CONTROL_AF_MODE_AUTO
    private val afPicture = CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE
    private val oisOff = CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_OFF
    private val oisOn = CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON
    private val vsOff = CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF
    private val vsOn = CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON

    @Test fun manualFocusIsOffAtTheShortestDistance() {
        val s = PpgCameraLogic.lensSettings(PpgLensProps(afModes = listOf(afOff, afAuto, afPicture), minFocusDistance = 10.0f))
        assertEquals(afOff, s.afMode)
        assertEquals(10.0f, s.focusDistance!!, 0f)
    }

    @Test fun fixedFocusSetsNoFocusKeys() {
        for (min in listOf(0f, null)) {
            for (modes in listOf(listOf(afOff), listOf(afOff, afAuto))) {
                val s = PpgCameraLogic.lensSettings(PpgLensProps(afModes = modes, minFocusDistance = min))
                assertNull("$min $modes", s.afMode)
                assertNull("$min $modes", s.focusDistance)
            }
        }
    }

    @Test fun withoutOffFocusIsAutoWithoutDistance() {
        val s = PpgCameraLogic.lensSettings(PpgLensProps(afModes = listOf(afAuto, afPicture), minFocusDistance = 10.0f))
        assertEquals(afAuto, s.afMode)
        assertNull(s.focusDistance)
    }

    @Test fun withoutOffAndAutoNothingIsSet() {
        for (modes in listOf(listOf(afPicture), emptyList(), null)) {
            val s = PpgCameraLogic.lensSettings(PpgLensProps(afModes = modes, minFocusDistance = 10.0f))
            assertNull("$modes", s.afMode)
            assertNull("$modes", s.focusDistance)
        }
    }

    @Test fun stabilizationIsOffOnlyWhenAvailable() {
        val on = PpgCameraLogic.lensSettings(PpgLensProps(oisModes = listOf(oisOff, oisOn), videoStabModes = listOf(vsOff, vsOn)))
        assertEquals(oisOff, on.oisMode)
        assertEquals(vsOff, on.videoStabMode)
        for (ois in listOf(listOf(oisOn), emptyList(), null)) {
            assertNull("$ois", PpgCameraLogic.lensSettings(PpgLensProps(oisModes = ois)).oisMode)
        }
        for (vs in listOf(listOf(vsOn), listOf(vsOn, CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_PREVIEW_STABILIZATION), emptyList(), null)) {
            assertNull("$vs", PpgCameraLogic.lensSettings(PpgLensProps(videoStabModes = vs)).videoStabMode)
        }
    }

    @Test fun nothingKnownSetsNothing() {
        assertEquals(PpgLensSettings(null, null, null, null), PpgCameraLogic.lensSettings(PpgLensProps()))
    }

    @Test fun physicalCameraDeterminesTheFocusDistance() {
        // AF-Modi und Stabilisierung von der logischen Kamera (Anfrage), kürzeste Distanz von der physischen.
        val logical = PpgLensProps(listOf(afOff, afAuto), 10.0f, listOf(oisOff, oisOn), listOf(vsOff))
        val s = PpgCameraLogic.lensSettings(logical, PpgLensProps(afModes = null, minFocusDistance = 5.0f))
        assertEquals(afOff, s.afMode)
        assertEquals(5.0f, s.focusDistance!!, 0f)
        assertEquals(oisOff, s.oisMode)
        assertEquals(vsOff, s.videoStabMode)
        // Physische Kamera mit Fixfokus: keine Fokus-Schlüssel, auch wenn die logische fokussieren kann.
        val fixed = PpgCameraLogic.lensSettings(logical, PpgLensProps(minFocusDistance = 0f))
        assertNull(fixed.afMode)
        assertNull(fixed.focusDistance)
    }

    // --- Antibanding und Belichtung (ADR-0011, Nachtrag 2026-11-22) ---

    @Test fun antibandingIsOffOnlyWhenAvailable() {
        assertEquals(CameraMetadata.CONTROL_AE_ANTIBANDING_MODE_OFF, PpgCameraLogic.antibandingMode(listOf(0, 1, 2, 3)))
        for (modes in listOf(listOf(3), emptyList(), null)) {
            assertNull("$modes", PpgCameraLogic.antibandingMode(modes))
        }
    }

    private val ms = 1_000_000L
    private val exposure30s = 0L to 30_000 * ms
    private val iso = 50 to 6400

    private fun lock(
        fps: Int = 60,
        e0: Long? = 10_005_000L,
        s0: Int? = 2400,
        exposure: Pair<Long, Long>? = exposure30s,
        sensitivity: Pair<Int, Int>? = iso,
        manual: Boolean = true,
    ) = PpgCameraLogic.exposureLock(fps, e0, s0, exposure, sensitivity, manual)

    @Test fun manualAt60FpsUsesTheWholeFrameAndScalesTheSensitivity() {
        assertEquals(PpgExposureLock.Manual(16_666_667L, 1441, 16_666_667L), lock())
    }

    @Test fun manualAt30FpsUsesTheWholeFrame() {
        assertEquals(PpgExposureLock.Manual(33_333_333L, 1441, 33_333_333L), lock(fps = 30, e0 = 20_010_000L))
    }

    @Test fun sensitivityReportedAboveTheRangeIsCappedAtTheTop() {
        assertEquals(PpgExposureLock.Manual(16_666_667L, 6400, 16_666_667L), lock(e0 = 10 * ms, s0 = 12800))
    }

    @Test fun exposureIsLimitedByTheExposureRange() {
        // 2400 · 10 / 12 = 2000.
        assertEquals(PpgExposureLock.Manual(12 * ms, 2000, 16_666_667L), lock(e0 = 10 * ms, exposure = 0L to 12 * ms))
    }

    @Test fun neverShorterThanTheAutomatic() {
        // Automatik schon bei der vollen Bilddauer (30 Bilder/s).
        assertEquals(PpgExposureLock.Manual(33_333_333L, 2400, 33_333_333L), lock(fps = 30, e0 = 33_333_333L))
        // Bereich kürzer als die Belichtung der Automatik: deren Belichtung bleibt.
        assertEquals(
            PpgExposureLock.Manual(10_005_000L, 2400, 16_666_667L),
            lock(exposure = 0L to 8 * ms),
        )
    }

    @Test fun sensitivityBelowTheRangeIsRaisedToTheBottom() {
        // 60 · 10 / 16,67 = 36 < 50.
        assertEquals(PpgExposureLock.Manual(16_666_667L, 50, 16_666_667L), lock(e0 = 10 * ms, s0 = 60))
    }

    @Test fun withoutManualSensorValuesOrRangesTheAeLockStays() {
        val cases = mapOf(
            "ohne MANUAL_SENSOR" to lock(manual = false),
            "ohne e0" to lock(e0 = null),
            "ohne s0" to lock(s0 = null),
            "ohne Belichtungsbereich" to lock(exposure = null),
            "ohne Empfindlichkeitsbereich" to lock(sensitivity = null),
            "e0 = 0" to lock(e0 = 0L),
            "s0 = 0" to lock(s0 = 0),
        )
        for ((name, result) in cases) assertEquals(name, PpgExposureLock.AeLock, result)
    }
}
