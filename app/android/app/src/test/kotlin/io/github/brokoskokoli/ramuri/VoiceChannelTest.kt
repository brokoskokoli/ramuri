package io.github.brokoskokoli.ramuri

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

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

    private class FakePlayer : FilePlayer {
        val played = mutableListOf<String>()
        var stops = 0
        val ends = mutableListOf<(Boolean) -> Unit>()
        override fun play(file: File, onEnd: (ok: Boolean) -> Unit) { played.add(file.name); ends.add(onEnd) }
        override fun stop() { stops++ }
    }

    private class Playback {
        val player = FakePlayer()
        val deleted = mutableListOf<String>()
        val finished = mutableListOf<String>()
        val pb = SynthesisPlayback(player, { deleted.add(it.name) }) { finished.add(it) }
        fun begin(vararg ids: String) = ids.forEach { pb.begin(it, File("$it.wav")) }
    }

    @Test fun playsInOrderOfBeginEvenIfSynthesisFinishesOutOfOrder() {
        val p = Playback()
        p.begin("a", "b")
        p.pb.synthesized("b", true)
        assertEquals(emptyList<String>(), p.player.played)
        p.pb.synthesized("a", true)
        assertEquals(listOf("a.wav"), p.player.played)
        p.player.ends[0](true)
        assertEquals(listOf("a.wav", "b.wav"), p.player.played)
        assertEquals(listOf("a"), p.finished)
    }

    @Test fun nextIsOnlyStartedAfterTheCurrentEnded() {
        val p = Playback()
        p.begin("a", "b")
        p.pb.synthesized("a", true)
        p.pb.synthesized("b", true)
        assertEquals(listOf("a.wav"), p.player.played)
    }

    @Test fun fileIsDeletedAfterPlaybackAndFinishedReportedOnce() {
        val p = Playback()
        p.begin("a")
        p.pb.synthesized("a", true)
        assertEquals(emptyList<String>(), p.deleted)
        p.player.ends[0](true)
        p.player.ends[0](true)
        assertEquals(listOf("a.wav"), p.deleted)
        assertEquals(listOf("a"), p.finished)
        assertEquals(0, p.pb.count)
    }

    @Test fun playbackErrorStillDeletesAndContinues() {
        val p = Playback()
        p.begin("a", "b")
        p.pb.synthesized("a", true)
        p.pb.synthesized("b", true)
        p.player.ends[0](false)
        assertEquals(listOf("a.wav"), p.deleted)
        assertEquals(listOf("a.wav", "b.wav"), p.player.played)
    }

    @Test fun failedSynthesisIsDeletedReportedAndSkipped() {
        val p = Playback()
        p.begin("a", "b")
        p.pb.synthesized("b", true)
        p.pb.synthesized("a", false)
        assertEquals(listOf("a.wav"), p.deleted)
        assertEquals(listOf("a"), p.finished)
        assertEquals(listOf("b.wav"), p.player.played)
    }

    @Test fun abortDeletesWithoutFinished() {
        val p = Playback()
        p.begin("a")
        p.pb.abort("a")
        assertEquals(listOf("a.wav"), p.deleted)
        assertEquals(emptyList<String>(), p.finished)
        assertEquals(0, p.pb.count)
    }

    @Test fun clearStopsPlayerDeletesAllAndIgnoresLateEvents() {
        val p = Playback()
        p.begin("a", "b", "c")
        p.pb.synthesized("a", true)
        p.pb.clear()
        assertEquals(1, p.player.stops)
        assertEquals(listOf("a.wav", "b.wav", "c.wav"), p.deleted)
        p.player.ends[0](true)
        p.pb.synthesized("b", true)
        assertEquals(emptyList<String>(), p.finished)
        assertEquals(listOf("a.wav"), p.player.played)
    }

    @Test fun staleFilesAreRemovedOnlyWithOurPrefix() {
        val dir = kotlin.io.path.createTempDirectory("voice").toFile()
        try {
            File(dir, "ramuri-voice-1.wav").writeText("x")
            File(dir, "ramuri-voice-ramuri-voice-2.wav").writeText("x")
            File(dir, "other.bin").writeText("x")
            assertEquals(2, deleteStaleVoiceFiles(dir))
            assertEquals(listOf("other.bin"), dir.list()!!.toList())
        } finally { dir.deleteRecursively() }
    }
}
