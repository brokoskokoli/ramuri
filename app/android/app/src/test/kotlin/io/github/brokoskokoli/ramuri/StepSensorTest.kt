package io.github.brokoskokoli.ramuri

import org.junit.Assert.assertEquals
import org.junit.Test

class StepSensorTest {
    @Test fun noSensorWinsOverPermission() {
        assertEquals("no_sensor", StepSensor.decide(hasSensor = false, permissionGranted = true))
        assertEquals("no_sensor", StepSensor.decide(hasSensor = false, permissionGranted = false))
    }

    @Test fun sensorWithoutPermissionIsDenied() {
        assertEquals("permission_denied", StepSensor.decide(hasSensor = true, permissionGranted = false))
    }

    @Test fun sensorWithPermissionIsAvailable() {
        assertEquals("available", StepSensor.decide(hasSensor = true, permissionGranted = true))
    }

    @Test fun treadmillAsksWithoutSensorGpsDoesNot() {
        assertEquals(true, StepSensor.shouldAsk(hasSensor = false, permissionGranted = false, treadmill = true))
        assertEquals(false, StepSensor.shouldAsk(hasSensor = false, permissionGranted = false, treadmill = false))
        assertEquals(true, StepSensor.shouldAsk(hasSensor = true, permissionGranted = false, treadmill = false))
        assertEquals(false, StepSensor.shouldAsk(hasSensor = false, permissionGranted = true, treadmill = true))
    }

    @Test fun stepEventUsesSensorClockForElapsedAndAgeForWallTime() {
        // Ereignis vor 2 s (Sensorzeit 10_000 s), Wanduhr 1_000_000 ms.
        val e = StepSensor.stepEvent(wallMs = 1_000_000L, nowNs = 12_000_000_000_000L, eventNs = 10_000_000_000_000L)
        assertEquals(10_000_000L, e["elapsedMs"])
        assertEquals(1_000_000L - 2_000_000L, e["timeMs"])
    }

    @Test fun elapsedDoesNotDependOnWallClock() {
        val a = StepSensor.stepEvent(wallMs = 5L, nowNs = 3_000_000_000L, eventNs = 3_000_000_000L)
        val b = StepSensor.stepEvent(wallMs = 999_999L, nowNs = 3_000_000_000L, eventNs = 3_000_000_000L)
        assertEquals(a["elapsedMs"], b["elapsedMs"])
    }
}
