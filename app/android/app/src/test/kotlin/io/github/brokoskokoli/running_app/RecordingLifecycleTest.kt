package io.github.brokoskokoli.running_app

import android.content.pm.ServiceInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordingLifecycleTest {
    private class FakeLock(var releaseThrows: Boolean = false) : WakeLockHandle {
        override var isHeld = false
        var acquired = 0
        var released = 0
        override fun acquire() { isHeld = true; acquired++ }
        override fun release() {
            released++
            isHeld = false
            if (releaseThrows) throw RuntimeException("schon frei")
        }
    }

    @Test fun withoutFineLocationServiceMayNotStart() {
        val denied = RecordingLifecycle.mayStart(false)
        assertTrue(denied.isFailure)
        assertTrue(denied.exceptionOrNull() is SecurityException)
        assertTrue(RecordingLifecycle.mayStart(true).isSuccess)
    }

    @Test fun startTypeWithoutBluetoothConnectIsLocationOnly() {
        val type = RecordingLifecycle.startType(false)
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION, type)
        assertFalse(RecordingLifecycle.hasConnectedDevice(type))
    }

    @Test fun startTypeWithBluetoothConnectAddsConnectedDevice() {
        val type = RecordingLifecycle.startType(true)
        assertEquals(
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            type,
        )
        assertTrue(RecordingLifecycle.hasConnectedDevice(type))
    }

    @Test fun serviceEntersForegroundWithTypeFromPermissionAtStart() {
        for (granted in listOf(false, true)) {
            val types = mutableListOf<Int>()
            val lc = RecordingLifecycle(FakeLock(), { granted }, {}, { types.add(it) })
            assertTrue(lc.start().isSuccess)
            assertEquals(listOf(RecordingLifecycle.startType(granted)), types)
            assertEquals(RecordingLifecycle.startType(granted), lc.currentType)
        }
    }

    @Test fun retypeAddsConnectedDeviceWhenPermissionArrivesLater() {
        var granted = false
        val types = mutableListOf<Int>()
        val lc = RecordingLifecycle(FakeLock(), { granted }, {}, { types.add(it) })
        lc.start()
        assertFalse(lc.retype()) // Recht fehlt weiter: kein zweiter startForeground
        assertEquals(1, types.size)
        granted = true
        assertTrue(lc.retype())
        assertEquals(2, types.size)
        assertTrue(RecordingLifecycle.hasConnectedDevice(types.last()))
        assertTrue(lc.retype()) // schon gesetzt: nichts mehr zu tun
        assertEquals(2, types.size)
    }

    @Test fun retypeFailureKeepsOldTypeAndService() {
        var granted = false
        var calls = 0
        val lc = RecordingLifecycle(FakeLock(), { granted }, {}, { calls++; if (calls > 1) throw SecurityException("x") })
        lc.start()
        granted = true
        assertFalse(lc.retype())
        assertTrue(lc.running)
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION, lc.currentType)
    }

    @Test fun retypeWithoutForegroundDoesNothing() {
        var calls = 0
        val lc = RecordingLifecycle(FakeLock(), { true }, {}, { calls++ })
        assertFalse(lc.retype())
        assertEquals(0, calls)
        lc.start()
        lc.stop()
        assertFalse(lc.retype())
        assertEquals(1, calls)
    }

    @Test fun startHoldsLockAndEntersForegroundWithLocation() {
        val lock = FakeLock()
        val types = mutableListOf<Int>()
        val lc = RecordingLifecycle(lock) { types.add(it) }
        assertTrue(lc.start().isSuccess)
        assertTrue(lc.running)
        assertTrue(lock.isHeld)
        assertEquals(listOf(ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION), types)
    }

    @Test fun failedStartDoesNotKeepLock() {
        val lock = FakeLock()
        val lc = RecordingLifecycle(lock) { throw SecurityException("kein Standort") }
        val r = lc.start()
        assertTrue(r.isFailure)
        assertTrue(r.exceptionOrNull() is SecurityException)
        assertFalse(lc.running)
        assertFalse(lock.isHeld)
    }

    @Test fun lockAcquireFailureLeavesNothingRunning() {
        val lock = object : WakeLockHandle {
            override val isHeld = false
            override fun acquire() = throw RuntimeException("kein Lock")
            override fun release() {}
        }
        var entered = false
        val lc = RecordingLifecycle(lock) { entered = true }
        assertTrue(lc.start().isFailure)
        assertFalse(entered)
        assertFalse(lc.running)
    }

    @Test fun stopReleasesLockAndIsIdempotent() {
        val lock = FakeLock()
        val lc = RecordingLifecycle(lock) {}
        lc.start()
        lc.stop()
        lc.stop()
        assertFalse(lc.running)
        assertFalse(lock.isHeld)
        assertEquals(1, lock.released)
    }

    @Test fun stopSurvivesReleaseFailure() {
        val lock = FakeLock(releaseThrows = true)
        val lc = RecordingLifecycle(lock) {}
        lc.start()
        lc.stop()
        assertFalse(lc.running)
    }

    @Test fun secondStartDoesNotAcquireTwice() {
        val lock = FakeLock()
        val lc = RecordingLifecycle(lock) {}
        lc.start()
        lc.start()
        assertEquals(1, lock.acquired)
    }

    @Test fun neverRestartsAfterKill() {
        assertEquals(android.app.Service.START_NOT_STICKY, RecordingLifecycle.START_MODE)
    }

    @Test fun onDestroyReleasesLock() {
        val lock = FakeLock()
        val lc = RecordingLifecycle(lock) {}
        lc.start()
        lc.onDestroy()
        assertFalse(lock.isHeld)
        assertFalse(lc.running)
    }

    private fun events(lock: FakeLock, log: MutableList<String>, fgThrows: Boolean = false) =
        RecordingLifecycle(
            lock,
            stopSelf = { log.add("stopSelf:held=${lock.isHeld}") },
            enterForeground = { if (fgThrows) throw SecurityException("x"); log.add("foreground") },
        )

    @Test fun normalStartKeepsServiceAndLock() {
        val log = mutableListOf<String>()
        val lock = FakeLock()
        val r = events(lock, log).onStartCommand(stopRequested = false)
        assertTrue(r.isSuccess)
        assertEquals(listOf("foreground"), log)
        assertTrue(lock.isHeld)
    }

    @Test fun stopRequestedDuringStartEntersForegroundBeforeStopSelf() {
        val log = mutableListOf<String>()
        val lock = FakeLock()
        val r = events(lock, log).onStartCommand(stopRequested = true)
        assertEquals("start_cancelled", r.exceptionOrNull()?.message)
        assertEquals(listOf("foreground", "stopSelf:held=false"), log)
        assertFalse(lock.isHeld)
    }

    @Test fun foregroundFailureStopsSelfWithoutLock() {
        val log = mutableListOf<String>()
        val lock = FakeLock()
        val lc = events(lock, log, fgThrows = true)
        val r = lc.onStartCommand(stopRequested = false)
        assertTrue(r.exceptionOrNull() is SecurityException)
        assertEquals(listOf("stopSelf:held=false"), log)
        assertFalse(lc.running)
    }
}
