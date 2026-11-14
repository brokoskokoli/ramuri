package io.github.brokoskokoli.ramuri

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Weiche des Berechtigungsdialogs: ab API 34 Laufzeitrechte, darunter der Intent von Health Connect. */
class HealthPermissionRouteTest {
    @Test fun runtimePermissionsFromApi34() {
        assertFalse(HealthConnectChannel.usesRuntimePermissions(33))
        assertTrue(HealthConnectChannel.usesRuntimePermissions(34))
        assertTrue(HealthConnectChannel.usesRuntimePermissions(36))
    }
}
