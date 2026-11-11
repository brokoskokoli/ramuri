package io.github.brokoskokoli.ramuri

import android.app.NotificationManager.INTERRUPTION_FILTER_ALL as ALL
import android.app.NotificationManager.INTERRUPTION_FILTER_NONE as NONE
import android.app.NotificationManager.INTERRUPTION_FILTER_PRIORITY as PRIORITY
import android.app.NotificationManager.INTERRUPTION_FILTER_UNKNOWN as UNKNOWN
import android.media.AudioManager.RINGER_MODE_NORMAL as NORMAL
import android.media.AudioManager.RINGER_MODE_SILENT as SILENT
import android.media.AudioManager.RINGER_MODE_VIBRATE as VIBRATE
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RestingSignalTest {
    private class Recorder : RestingSignalOutput {
        val calls = mutableListOf<String>()
        override fun tone() { calls.add("tone") }
        override fun vibrate() { calls.add("vibrate") }
    }

    @Test fun toneAndVibrateGoToTheirOutputOnly() {
        val r = Recorder()
        assertTrue(RestingSignal.dispatch("tone", r))
        assertEquals(listOf("tone"), r.calls)
        assertTrue(RestingSignal.dispatch("vibrate", r))
        assertEquals(listOf("tone", "vibrate"), r.calls)
    }

    @Test fun unknownMethodIsNotHandled() {
        val r = Recorder()
        assertFalse(RestingSignal.dispatch("alert", r))
        assertEquals(emptyList<String>(), r.calls)
    }

    @Test fun toneAloneInNormalModeWithoutDnd() {
        assertFalse(RestingSignal.vibrateWithTone(NORMAL, ALL))
        assertFalse(RestingSignal.vibrateWithTone(NORMAL, UNKNOWN))
    }

    @Test fun silentOrVibrateRingerAddsVibration() {
        assertTrue(RestingSignal.vibrateWithTone(SILENT, ALL))
        assertTrue(RestingSignal.vibrateWithTone(VIBRATE, ALL))
    }

    @Test fun doNotDisturbAddsVibration() {
        assertTrue(RestingSignal.vibrateWithTone(NORMAL, PRIORITY))
        assertTrue(RestingSignal.vibrateWithTone(NORMAL, NONE))
    }
}
