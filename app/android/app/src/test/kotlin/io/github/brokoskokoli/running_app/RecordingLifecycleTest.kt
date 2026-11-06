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

    @Test fun startTypeIsLocationOnly() {
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION, RecordingLifecycle.startType())
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
}
