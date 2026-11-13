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

    private class Engine(val accept: Boolean = true) {
        val said = mutableListOf<String>()
        var idle = 0
        val queue = VoiceQueue({ id, text, _ -> said.add("$id:$text"); accept }) { idle++ }
    }

    @Test fun waitingAnnouncementsAreAllKeptInOrder() {
        val e = Engine()
        e.queue.speak("A", "de")
        e.queue.speak("B", "de")
        assertEquals(2, e.queue.pendingCount)
        e.queue.markReady()
        assertEquals(listOf("ramuri-voice-1:A", "ramuri-voice-2:B"), e.said)
        assertEquals(0, e.queue.pendingCount)
    }

    @Test fun focusIsFreedOnlyAfterTheLastAnnouncement() {
        val e = Engine()
        e.queue.markReady()
        e.queue.speak("A", null)
        e.queue.speak("B", null)
        e.queue.finished("ramuri-voice-1")
        assertEquals(0, e.idle)
        e.queue.finished("ramuri-voice-2")
        assertEquals(1, e.idle)
    }

    @Test fun rejectedAnnouncementFreesTheFocusWhenNothingElseIsOutstanding() {
        val e = Engine(accept = false)
        e.queue.markReady()
        e.queue.speak("A", null)
        assertEquals(1, e.idle)
        assertEquals(0, e.queue.outstandingCount)
    }

    @Test fun clearDropsWaitingAndOutstanding() {
        val e = Engine()
        e.queue.speak("A", null)
        e.queue.clear()
        e.queue.markReady()
        assertEquals(emptyList<String>(), e.said)
        e.queue.speak("B", null)
        e.queue.clear()
        e.queue.finished("ramuri-voice-1")
        assertEquals(0, e.idle)
    }
}
