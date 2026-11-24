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
        override fun unlockExposure() { log += "unlock" }
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

    // --- Neusperre nach Helligkeitssprung (PAR-245, PAR-246) ---

    /** Bilder mit 30 fps von 0 bis [until] s; liefert (Schritt, Sensorzeit) aller Schritte außer NONE. */
    private fun watchRun(until: Double, red: (Double) -> Double): List<Pair<PpgExposureWatch.Step, Double>> {
        val w = PpgExposureWatch()
        val out = mutableListOf<Pair<PpgExposureWatch.Step, Double>>()
        var i = 0
        while (true) {
            val t = i / 30.0
            if (t > until) break
            val s = w.frame(t, red(t))
            if (s != PpgExposureWatch.Step.NONE) out += s to t
            i++
        }
        return out
    }

    private fun steps(run: List<Pair<PpgExposureWatch.Step, Double>>, s: PpgExposureWatch.Step) =
        run.filter { it.first == s }.map { it.second }

    /** Sekunde, die das Bild bei [t] abschließt (Sprung bzw. Ruhe werden mit dem ersten Bild danach erkannt). */
    private fun closedSecond(t: Double) = Math.floor(t + 1e-9).toLong() - 1

    @Test fun steadyRedWithThreePercentNoiseNeverJumps() {
        // ±3 % je Bild und langsam ±3 % über die Sekunden.
        val run = watchRun(120.0) { t ->
            val frame = if (Math.round(t * 30) % 2 == 0L) 1.03 else 0.97
            140.0 * frame * (1 + 0.03 * Math.sin(t / 7))
        }
        assertEquals(listOf(PpgExposureWatch.Step.LOCK), run.map { it.first })
        assertEquals(2.5, run.single().second, 1e-9)
    }

    @Test fun jumpAtTwentyCalmAtTwentyFourThenRelockAndLockTwoAndAHalfSecondsLater() {
        val run = watchRun(60.0) { t ->
            when {
                t < 20 -> 140.0
                t < 21 -> 250.0
                t < 22 -> 180.0
                t < 23 -> 230.0
                else -> 250.0
            }
        }
        val jumps = steps(run, PpgExposureWatch.Step.JUMP)
        assertEquals("ein Sprung", 1, jumps.size)
        assertEquals("Sprung in Sekunde 20", 20L, closedSecond(jumps.single()))
        val relock = steps(run, PpgExposureWatch.Step.RELOCK)
        assertEquals("eine Neusperre", 1, relock.size)
        assertEquals("ruhig mit Sekunde 24 (23 und 24 gleich)", 24L, closedSecond(relock.single()))
        assertEquals(25.0, relock.single(), 1e-9)
        val locks = steps(run, PpgExposureWatch.Step.LOCK)
        assertEquals(2, locks.size)
        assertEquals(2.5, locks[0], 1e-9)
        assertEquals("Sperre 2,5 s nach dem Neu-Einschwingen", 27.5, locks[1], 1e-9)
        // Neuer Bezug 250: danach kein Sprung mehr.
        assertTrue(run.none { it.first != PpgExposureWatch.Step.LOCK && it.second > 27.5 })
    }

    @Test fun darkerByTwentyFivePercentIsAJump() {
        val run = watchRun(40.0) { t -> if (t < 20) 140.0 else 105.0 }
        assertEquals(listOf(20L), steps(run, PpgExposureWatch.Step.JUMP).map(::closedSecond))
        // Danach gleich bleibend: ruhig mit Sekunde 21, neu eingeschwungen.
        assertEquals(listOf(21L), steps(run, PpgExposureWatch.Step.RELOCK).map(::closedSecond))
    }

    @Test fun brighterByFourteenPercentIsNoJump() {
        val run = watchRun(60.0) { t -> if (t < 20) 140.0 else 160.0 }
        assertEquals(listOf(PpgExposureWatch.Step.LOCK), run.map { it.first })
    }

    @Test fun continuouslyJumpingRedNeverRelocks() {
        // Ab 20 s wechselt das Sekundenmittel jede Sekunde um mehr als 5 %.
        val run = watchRun(120.0) { t -> if (t < 20) 140.0 else if (Math.floor(t).toLong() % 2 == 0L) 250.0 else 200.0 }
        assertEquals(1, steps(run, PpgExposureWatch.Step.JUMP).size)
        assertTrue("keine Neusperre", steps(run, PpgExposureWatch.Step.RELOCK).isEmpty())
        assertEquals(1, steps(run, PpgExposureWatch.Step.LOCK).size)
    }

    @Test fun fiveJumpsWithCalmBetweenGiveFiveRelocks() {
        // Alle 15 s ab 10 s ein Wechsel zwischen 140 und 250, dazwischen ruhig: keine Höchstzahl.
        val run = watchRun(84.0) { t -> if (t < 10 || Math.floor((t - 10) / 15).toLong() % 2 == 1L) 140.0 else 250.0 }
        val relocks = steps(run, PpgExposureWatch.Step.RELOCK)
        assertEquals(listOf(11L, 26L, 41L, 56L, 71L), relocks.map { closedSecond(it) })
        assertEquals(6, steps(run, PpgExposureWatch.Step.LOCK).size)
        assertEquals(5, steps(run, PpgExposureWatch.Step.JUMP).size)
    }

    @Test fun referenceIsTheMeanHalfASecondToOneAndAHalfAfterTheLock() {
        // Bis 3,0 s dunkel (zählt nicht), 3,0 bis 4,0 s 140, danach 160: +14 % zum Bezug, kein Sprung.
        val run = watchRun(30.0) { t -> if (t < 3.0) 60.0 else if (t <= 4.0) 140.0 else 160.0 }
        assertEquals(listOf(PpgExposureWatch.Step.LOCK), run.map { it.first })
        // Gleicher Verlauf mit 105 danach: −25 %, Sprung in der ersten vollen Sekunde nach dem Bezug.
        val dark = watchRun(30.0) { t -> if (t < 3.0) 60.0 else if (t <= 4.0) 140.0 else 105.0 }
        assertEquals(listOf(4L), steps(dark, PpgExposureWatch.Step.JUMP).map(::closedSecond))
    }

    @Test fun controllerRelocksUnlocksAndReportsSensorTimes() {
        val log = mutableListOf<String>()
        val sink = Sink(log)
        val c = PpgController(Hw(log), sink)
        fun red(r: Double) = PpgStats(r, 40.0, DoubleArray(16) { r }, DoubleArray(16) { 40.0 })
        // 25 Bilder je Sekunde in ganzen 40 ms, damit die Sekundengrenzen genau getroffen werden.
        for (i in 0..1000) {
            val t = i * 0.04
            c.frame(1_000_000_000_000L + i * 40_000_000L, red(if (t < 20) 140.0 else 250.0))
        }
        val control = sink.events.filter { it["type"] == "locked" || it["type"] == "relocking" }
        assertEquals(listOf("locked", "relocking", "locked"), control.map { it["type"] })
        // Erstes Bild ab 2,5 s ist das bei 2,52 s; ruhig mit Sekunde 21, Bild bei 22,0 s; Sperre ab 24,5 s.
        assertEquals(2.52, control[0]["t"] as Double, 1e-6)
        assertEquals(22.0, control[1]["t"] as Double, 1e-6)
        assertEquals(24.52, control[2]["t"] as Double, 1e-6)
        assertEquals(listOf("lock", "unlock", "lock"), log.filter { it == "lock" || it == "unlock" })
        // Neu einschwingen vor der Meldung; Sperre vor ihrer Meldung.
        assertTrue(log.indexOf("unlock") < log.indexOf("event:relocking"))
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

    // --- Diagnose der Bildverarbeitung (ADR-0011, Nachtrag 2026-11-21) ---

    private fun isp(v: Double) = DoubleArray(PpgDiagnostics.ISP_VALUES) { v }

    private fun matched(): Pair<PpgIspMatcher<String>, MutableList<Pair<String, DoubleArray?>>> {
        val out = mutableListOf<Pair<String, DoubleArray?>>()
        return PpgIspMatcher<String>(capacity = 4) { _, f, v -> out += f to v } to out
    }

    @Test fun eachFrameGetsTheResultWithItsOwnTimestamp() {
        val (m, out) = matched()
        m.onResult(1, isp(1.0))
        m.onResult(2, isp(2.0))
        m.onResult(3, isp(3.0))
        m.onFrame(2, "b2")
        m.onFrame(3, "b3")
        m.onFrame(4, "b4")
        // Ein Ergebnis eines späteren Bildes: Bild 4 hat keines bekommen.
        m.onResult(5, isp(5.0))
        assertEquals(listOf("b2", "b3", "b4"), out.map { it.first })
        assertEquals(2.0, out[0].second!![0], 0.0)
        assertEquals(3.0, out[1].second!![0], 0.0)
        assertNull("Bild 4 nicht gemeldet, nie der Wert eines anderen Bildes", out[2].second)
    }

    @Test fun aLateResultIsMatchedToItsFrameWhileInTheBuffer() {
        val (m, out) = matched()
        m.onFrame(10, "b10")
        m.onFrame(11, "b11")
        assertTrue("wartet auf das Ergebnis", out.isEmpty())
        m.onResult(10, isp(10.0))
        m.onResult(11, isp(11.0))
        assertEquals(listOf("b10", "b11"), out.map { it.first })
        assertEquals(10.0, out[0].second!![0], 0.0)
        assertEquals(11.0, out[1].second!![0], 0.0)
    }

    @Test fun aFrameWhoseResultNeverComesIsNotReportedOnceTheBufferIsFull() {
        val (m, out) = matched()
        for (ts in 1L..5L) m.onFrame(ts, "b$ts")
        assertEquals("ältestes Bild geht ohne Werte weiter", listOf("b1"), out.map { it.first })
        assertNull(out[0].second)
        m.onResult(2, isp(2.0))
        assertEquals(2.0, out[1].second!![0], 0.0)
    }

    @Test fun packTurnsMissingValuesIntoNaN() {
        val values = MutableList<Number?>(19) { it }
        values[16] = 3.5f
        values[18] = null
        val p = PpgDiagnostics.pack(values)
        assertEquals(19, p.size)
        assertEquals(15.0, p[15], 0.0)
        assertEquals(3.5, p[16], 0.0)
        assertTrue(p[18].isNaN())
    }

    private val allOffered = PpgIspProps(
        noiseReductionModes = listOf(0, 1, 2),
        edgeModes = listOf(0, 1),
        awbModes = listOf(0, 1),
        awbLockAvailable = true,
        manualPostProcessing = true,
        tonemapModes = listOf(0, 1, 2),
        shadingModes = listOf(0, 1),
    )
    private val all = PpgDiagnostic.entries.toSet()

    @Test fun everyOfferedSwitchSetsItsKey() {
        val nr = PpgDiagnostics.diagnosticSettings(setOf(PpgDiagnostic.NOISE_REDUCTION_OFF), allOffered)
        assertEquals(PpgDiagnosticSettings(noiseReductionMode = CameraMetadata.NOISE_REDUCTION_MODE_OFF), nr)
        val edge = PpgDiagnostics.diagnosticSettings(setOf(PpgDiagnostic.EDGE_OFF), allOffered)
        assertEquals(PpgDiagnosticSettings(edgeMode = CameraMetadata.EDGE_MODE_OFF), edge)
        val tone = PpgDiagnostics.diagnosticSettings(setOf(PpgDiagnostic.TONEMAP_LINEAR), allOffered)
        assertEquals(CameraMetadata.TONEMAP_MODE_CONTRAST_CURVE, tone.tonemapMode)
        assertEquals(listOf(0f, 0f, 1f, 1f), tone.tonemapCurve!!.toList())
        val shading = PpgDiagnostics.diagnosticSettings(setOf(PpgDiagnostic.SHADING_OFF), allOffered)
        assertEquals(PpgDiagnosticSettings(shadingMode = CameraMetadata.SHADING_MODE_OFF), shading)
        val awb = PpgDiagnostics.diagnosticSettings(setOf(PpgDiagnostic.AWB_FIXED), allOffered)
        assertEquals(PpgDiagnosticSettings(awb = PpgAwbVariant.MATRIX), awb)
        assertEquals(PpgDiagnostic.entries, PpgDiagnostics.diagnosticSettings(all, allOffered).applied)
    }

    @Test fun aSwitchTheCameraDoesNotOfferSetsNothing() {
        val without = PpgIspProps(
            noiseReductionModes = listOf(1, 2),
            edgeModes = listOf(1),
            awbModes = listOf(1),
            awbLockAvailable = false,
            manualPostProcessing = true,
            tonemapModes = listOf(1, 2),
            shadingModes = listOf(1, 2),
        )
        assertEquals(PpgDiagnosticSettings.NONE, PpgDiagnostics.diagnosticSettings(all, without))
        assertTrue(PpgDiagnostics.diagnosticSettings(all, without).applied.isEmpty())
    }

    @Test fun missingCharacteristicsSetNothing() {
        assertEquals(PpgDiagnosticSettings.NONE, PpgDiagnostics.diagnosticSettings(all, PpgIspProps()))
    }

    @Test fun allSwitchesOffAddNoKeys() {
        assertEquals(PpgDiagnosticSettings.NONE, PpgDiagnostics.diagnosticSettings(emptySet(), allOffered))
        assertTrue(PpgDiagnosticSettings.NONE.applied.isEmpty())
        assertNull(PpgDiagnosticSettings.NONE.tonemapCurve)
    }

    @Test fun whiteBalanceFallsBackToTheLockWithoutManualPostProcessingOrAwbOff() {
        val req = setOf(PpgDiagnostic.AWB_FIXED)
        val noMpp = allOffered.copy(manualPostProcessing = false)
        assertEquals(PpgAwbVariant.LOCK, PpgDiagnostics.diagnosticSettings(req, noMpp).awb)
        val noOff = allOffered.copy(awbModes = listOf(1, 2))
        assertEquals(PpgAwbVariant.LOCK, PpgDiagnostics.diagnosticSettings(req, noOff).awb)
        val nothing = noOff.copy(awbLockAvailable = null)
        assertNull("weder (a) noch (b) angeboten", PpgDiagnostics.diagnosticSettings(req, nothing).awb)
    }

    @Test fun fixedWhiteBalanceTakesTheFirstConvergedResult() {
        val f = PpgAwbFixer<String, String>()
        val searching = CameraMetadata.CONTROL_AWB_STATE_SEARCHING
        val converged = CameraMetadata.CONTROL_AWB_STATE_CONVERGED
        assertNull(f.offer(ns(10.0), searching, "g0", "m0"))
        assertNull("ohne Verstärkungen zählt es nicht", f.offer(ns(10.1), converged, null, "m1"))
        assertEquals("g2" to "m2", f.offer(ns(10.2), converged, "g2", "m2"))
        assertNull("nur einmal", f.offer(ns(10.3), converged, "g3", "m3"))
    }

    @Test fun fixedWhiteBalanceTakesTheResultAtHalfASecondAtTheLatest() {
        val f = PpgAwbFixer<String, String>()
        val searching = CameraMetadata.CONTROL_AWB_STATE_SEARCHING
        assertNull(f.offer(ns(10.0), searching, "g0", "m0"))
        assertNull(f.offer(ns(10.49), searching, "g1", "m1"))
        assertEquals("g2" to "m2", f.offer(ns(10.5), searching, "g2", "m2"))
    }

    @Test fun startedReportsExactlyTheAppliedSwitches() {
        val sink = Sink(mutableListOf())
        val c = PpgController(Hw(mutableListOf()), sink, ispFrames = true)
        val applied = PpgDiagnostics.diagnosticSettings(
            setOf(PpgDiagnostic.EDGE_OFF, PpgDiagnostic.AWB_FIXED, PpgDiagnostic.SHADING_OFF),
            allOffered.copy(shadingModes = listOf(1)),
        )
        c.started(60, "0", null, applied)
        assertEquals(listOf("edge_off", "awb_fixed"), sink.events[0]["diagnostics"])
        assertEquals("matrix", sink.events[0]["awbVariant"])
    }

    @Test fun withoutSwitchesStartedHasNoDiagnostics() {
        val sink = Sink(mutableListOf())
        PpgController(Hw(mutableListOf()), sink).started(30, "0")
        assertFalse(sink.events[0].containsKey("diagnostics"))
        assertFalse(sink.events[0].containsKey("awbVariant"))
    }

    @Test fun frameCarriesIspValuesOnlyOnRequest() {
        val sink = Sink(mutableListOf())
        val c = PpgController(Hw(mutableListOf()), sink, ispFrames = true)
        c.frame(ns(1.0), stats, null, isp(7.0))
        c.frame(ns(1.1), stats, null, null)
        assertEquals(7.0, (sink.events[0]["isp"] as DoubleArray)[3], 0.0)
        assertTrue((sink.events[1]["isp"] as DoubleArray).all { it.isNaN() })
        val plain = Sink(mutableListOf())
        val r = PpgController(Hw(mutableListOf()), plain)
        r.frame(ns(1.0), stats, null, isp(7.0))
        assertFalse("ohne Anforderung (Ruhepuls) keine ISP-Werte", plain.events[0].containsKey("isp"))
    }

    @Test fun diagnosticsFromTheStartArgument() {
        assertEquals(
            setOf(PpgDiagnostic.NOISE_REDUCTION_OFF, PpgDiagnostic.TONEMAP_LINEAR),
            PpgDiagnostic.fromWire(listOf("noise_reduction_off", "tonemap_linear", "unbekannt", 3)),
        )
        assertTrue(PpgDiagnostic.fromWire(null).isEmpty())
    }
}
