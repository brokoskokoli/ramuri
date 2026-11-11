package io.github.brokoskokoli.ramuri

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordingServiceControllerTest {
    private class Fx(var startThrows: Boolean = false) : ServiceEffects<String> {
        val log = mutableListOf<String>()
        var lastMode: RecordingMode? = null
        override fun startService(mode: RecordingMode) {
            lastMode = mode
            if (startThrows) throw IllegalStateException("nein")
            log.add("startService")
        }
        override fun stopService() { log.add("stopService") }
        override fun scheduleTimeout() { log.add("schedule") }
        override fun cancelTimeout() { log.add("cancel") }
        override fun success(result: String) { log.add("ok:$result") }
        override fun error(result: String, code: String, detail: String?) { log.add("err:$result:$code:$detail") }
    }

    private fun make(fx: Fx = Fx()) = fx to RecordingServiceController(fx)

    @Test fun withoutLocationPermissionNoServiceIsStartedAndCallerGetsError() {
        val (fx, c) = make()
        c.start("a", false)
        assertEquals(listOf("err:a:start_failed:SecurityException"), fx.log)
        assertFalse(c.hasPending)
    }

    @Test fun treadmillWithoutActivityRecognitionGivesOwnReasonAndStartsNothing() {
        val (fx, c) = make()
        // Standortrecht allein genügt im Laufbandmodus nicht.
        c.start("a", true, RecordingMode.TREADMILL, false)
        assertEquals(listOf("err:a:start_denied:activity_recognition"), fx.log)
        assertFalse(c.hasPending)
        assertEquals(null, fx.lastMode)
    }

    @Test fun treadmillWithActivityRecognitionStartsWithoutLocation() {
        val (fx, c) = make()
        c.start("a", false, RecordingMode.TREADMILL, true)
        assertEquals(listOf("startService", "schedule"), fx.log)
        assertEquals(RecordingMode.TREADMILL, fx.lastMode)
    }

    @Test fun gpsStartPassesGpsMode() {
        val (fx, c) = make()
        c.start("a", true)
        assertEquals(RecordingMode.GPS, fx.lastMode)
    }

    @Test fun startWithPermissionStartsServiceOnceAndAnswersAllWaitersOnStarted() {
        val (fx, c) = make()
        c.start("a", true)
        c.start("b", true)
        assertEquals(listOf("startService", "schedule"), fx.log)
        c.started()
        assertTrue(c.running)
        assertEquals(listOf("startService", "schedule", "cancel", "ok:a", "ok:b"), fx.log)
    }

    @Test fun startWhileRunningSucceedsWithoutSecondStart() {
        val (fx, c) = make()
        c.start("a", true)
        c.started()
        fx.log.clear()
        c.start("b", true)
        assertEquals(listOf("ok:b"), fx.log)
    }

    @Test fun startServiceThrowingFailsWaitersWithoutTimeout() {
        val (fx, c) = make(Fx(startThrows = true))
        c.start("a", true)
        assertEquals(listOf("cancel", "err:a:start_failed:IllegalStateException"), fx.log)
        assertFalse(c.running)
    }

    @Test fun timeoutFailsWaitersAndRemembersStopForLateService() {
        val (fx, c) = make()
        c.start("a", true)
        c.onTimeout()
        assertEquals("err:a:start_failed:IllegalStateException", fx.log.last())
        assertFalse(c.hasPending)
        assertTrue(c.takeStopRequest()) // später gestarteter Dienst beendet sich selbst
        assertFalse(c.takeStopRequest()) // gelöscht
        assertFalse(fx.log.contains("stopService")) // nie von außen beenden
    }

    @Test fun stopWhileStartingIsRememberedNotExecuted() {
        val (fx, c) = make()
        c.start("a", true)
        c.stop()
        assertFalse(fx.log.contains("stopService"))
        assertEquals("err:a:start_failed:IllegalStateException", fx.log.last())
        assertTrue(c.takeStopRequest())
    }

    @Test fun newStartClearsEarlierStopRequest() {
        val (_, c) = make()
        c.start("a", true)
        c.stop()
        c.start("b", true) // neuer Versuch: alter Wunsch gilt nicht mehr
        assertFalse(c.takeStopRequest())
    }

    @Test fun takeStopRequestClearsFlag() {
        val (_, c) = make()
        c.start("a", true)
        c.stop()
        assertTrue(c.takeStopRequest())
        assertFalse(c.takeStopRequest())
    }

    @Test fun stopWhenRunningStopsServiceAndMarksNotRunningBeforeDestroy() {
        val (fx, c) = make()
        c.start("a", true)
        c.started()
        fx.log.clear()
        c.stop()
        assertEquals(listOf("stopService"), fx.log)
        assertFalse(c.running) // schon vor onDestroy
        c.start("b", true) // Start im Fenster meldet keinen Erfolg ohne Dienst
        assertEquals(listOf("stopService", "startService", "schedule"), fx.log)
        assertTrue(c.hasPending)
    }

    @Test fun stopWithoutServiceDoesNothing() {
        val (fx, c) = make()
        c.stop()
        assertTrue(fx.log.isEmpty())
        assertFalse(c.takeStopRequest())
    }

    @Test fun stoppedAndFailedClearRunning() {
        val (_, c) = make()
        c.start("a", true)
        c.started()
        c.stopped()
        assertFalse(c.running)
        c.start("b", true)
        c.started()
        c.failed(RuntimeException())
        assertFalse(c.running)
    }
}
