package io.github.brokoskokoli.ramuri

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
}
