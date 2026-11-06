package io.github.brokoskokoli.running_app

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
}
