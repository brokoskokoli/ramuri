package io.github.brokoskokoli.ramuri

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceChannelTest {
    private class Recorder : VoiceOutput {
        val calls = mutableListOf<String>()
        override fun speak(text: String, languageTag: String?) { calls.add("speak:$text:$languageTag") }
        override fun stop() { calls.add("stop") }
    }

    @Test fun speakAndStopGoToTheirOutputOnly() {
        val r = Recorder()
        assertTrue(VoiceChannel.dispatch("speak", "Hallo", "de", r))
        assertEquals(listOf("speak:Hallo:de"), r.calls)
        assertTrue(VoiceChannel.dispatch("stop", null, null, r))
        assertEquals(listOf("speak:Hallo:de", "stop"), r.calls)
    }

    @Test fun emptyTextAndUnknownMethodAreNotHandled() {
        val r = Recorder()
        assertFalse(VoiceChannel.dispatch("speak", "", "de", r))
        assertFalse(VoiceChannel.dispatch("speak", null, "de", r))
        assertFalse(VoiceChannel.dispatch("play", "x", null, r))
        assertEquals(emptyList<String>(), r.calls)
    }

    @Test fun localeFollowsTheTagAndEmptyMeansSystem() {
        assertEquals("de", VoiceChannel.localeFor("de")?.language)
        assertEquals("en", VoiceChannel.localeFor("en_US")?.language)
        assertNull(VoiceChannel.localeFor(null))
        assertNull(VoiceChannel.localeFor(" "))
    }
}
