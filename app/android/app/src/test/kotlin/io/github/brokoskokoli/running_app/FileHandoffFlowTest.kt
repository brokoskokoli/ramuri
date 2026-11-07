package io.github.brokoskokoli.running_app

import java.io.IOException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FileHandoffFlowTest {
    private val log = mutableListOf<String>()

    /** Hintergrund und Hauptthread als Warteschlangen: Der Test bestimmt, wann was läuft. */
    private val backgroundQueue = ArrayDeque<() -> Unit>()
    private val mainQueue = ArrayDeque<() -> Unit>()
    private var onBackground = false
    private val flow = FileHandoffFlow(object : HandoffAnswers<String> {
        override fun success(result: String, value: String) { log.add("$result:$value") }
        override fun error(result: String, code: String, detail: String?) { log.add("$result!$code${detail?.let { "($it)" } ?: ""}") }
    }, object : HandoffThreads {
        override fun background(work: () -> Unit) { backgroundQueue.addLast(work) }
        override fun main(work: () -> Unit) { mainQueue.addLast(work) }
    })

    /** Erst alle Hintergrundarbeit, dann alle Rückmeldungen auf dem Hauptthread. */
    private fun drain() {
        while (backgroundQueue.isNotEmpty()) {
            onBackground = true
            backgroundQueue.removeFirst()()
            onBackground = false
        }
        while (mainQueue.isNotEmpty()) mainQueue.removeFirst()()
    }

    private val launches = mutableListOf<String>()

    /** Teilen mit Schreiben ohne Fehler; das Menü gilt nach [drain] als gestartet. */
    private fun beginShare(result: String): Boolean =
        flow.share(result, write = { "datei" }) { launches.add(it) }

    @Test fun shareTargetChosenCompletes() {
        assertTrue(beginShare("a"))
        drain()
        flow.paused()
        flow.chosen()
        flow.resumed()
        assertEquals(listOf("a:completed"), log)
        assertFalse(flow.busy)
    }

    @Test fun shareMenuClosedWithoutChoiceIsCancelled() {
        beginShare("a")
        drain()
        flow.paused()
        flow.resumed()
        assertEquals(listOf("a:cancelled"), log)
    }

    @Test fun resumeBeforeTheMenuCoveredTheActivityDoesNotCancel() {
        beginShare("a")
        drain()
        flow.resumed()
        assertEquals(emptyList<String>(), log)
        flow.paused()
        flow.chosen()
        assertEquals(listOf("a:completed"), log)
    }

    @Test fun secondHandoffWhileOneIsOpenIsBusy() {
        beginShare("a")
        drain()
        assertFalse(flow.beginSave("b", byteArrayOf(1)))
        assertFalse(beginShare("c"))
        assertEquals(listOf("b!busy", "c!busy"), log)
        flow.paused()
        flow.resumed()
        assertEquals("a:cancelled", log.last())
    }

    @Test fun saveWritesTheBytesIntoTheChosenTarget() {
        flow.beginSave("s", byteArrayOf(4, 5))
        var written: Pair<String, ByteArray>? = null
        flow.saveAnswered("content://doc") { uri, bytes ->
            assertTrue("Schreiben im Hintergrund", onBackground)
            written = uri to bytes
        }
        assertEquals(null, written)
        assertEquals(emptyList<String>(), log)
        drain()
        assertEquals("content://doc", written!!.first)
        assertArrayEquals(byteArrayOf(4, 5), written!!.second)
        assertEquals(listOf("s:completed"), log)
    }

    @Test fun saveWithoutTargetIsCancelledAndWritesNothing() {
        flow.beginSave("s", byteArrayOf(1))
        flow.saveAnswered<String>(null) { _, _ -> throw AssertionError("nicht schreiben") }
        assertEquals(listOf("s:cancelled"), log)
    }

    @Test fun saveWriteErrorIsFailedWithClassNameOnly() {
        flow.beginSave("s", byteArrayOf(1))
        flow.saveAnswered("content://doc") { _, _ -> throw IOException("/geheimer/pfad") }
        drain()
        assertEquals(listOf("s!write_failed(IOException)"), log)
        assertFalse(flow.busy)
    }

    @Test fun pauseAndResumeDoNotTouchASave() {
        flow.beginSave("s", byteArrayOf(1))
        flow.paused()
        flow.resumed()
        flow.chosen()
        assertEquals(emptyList<String>(), log)
        assertTrue(flow.busy)
    }

    @Test fun detachEndsTheOpenHandoff() {
        beginShare("a")
        drain()
        flow.detached()
        assertEquals(listOf("a!detached"), log)
        flow.detached()
        flow.paused()
        flow.resumed()
        assertEquals(1, log.size)
        assertTrue(flow.beginSave("b", byteArrayOf(1)))
    }

    @Test fun startFailureEndsTheHandoff() {
        beginShare("a")
        drain()
        flow.fail("share_failed", "ActivityNotFoundException")
        assertEquals(listOf("a!share_failed(ActivityNotFoundException)"), log)
        assertFalse(flow.busy)
    }

    @Test fun lateAnswersAfterTheEndAreIgnored() {
        beginShare("a")
        drain()
        flow.chosen()
        flow.chosen()
        flow.paused()
        flow.resumed()
        flow.saveAnswered("x") { _, _ -> throw AssertionError() }
        assertEquals(listOf("a:completed"), log)
    }

    @Test fun shareWritesInTheBackgroundAndLaunchesOnMain() {
        var wroteOnBackground = false
        var launchedOnBackground: Boolean? = null
        assertTrue(flow.share("a", write = { wroteOnBackground = onBackground; "datei" }) {
            launchedOnBackground = onBackground
            launches.add(it)
        })
        assertEquals(emptyList<String>(), launches)
        drain()
        assertTrue(wroteOnBackground)
        assertEquals(false, launchedOnBackground)
        assertEquals(listOf("datei"), launches)
        assertEquals(emptyList<String>(), log)
    }

    @Test fun shareWriteErrorFailsWithClassNameOnlyAndLaunchesNothing() {
        flow.share("a", write = { throw IOException("/geheimer/pfad") }) { _: String -> launches.add("x") }
        drain()
        assertEquals(listOf("a!share_failed(IOException)"), log)
        assertEquals(emptyList<String>(), launches)
        assertFalse(flow.busy)
    }

    @Test fun pauseWhileWritingIsNotTheShareMenu() {
        beginShare("a")
        flow.paused()
        flow.resumed()
        assertEquals(emptyList<String>(), log)
        drain()
        assertEquals(listOf("datei"), launches)
        flow.paused()
        flow.resumed()
        assertEquals(listOf("a:cancelled"), log)
    }

    @Test fun lateWriteResultAfterDetachIsIgnored() {
        beginShare("a")
        flow.detached()
        assertTrue(flow.beginSave("b", byteArrayOf(1)))
        drain()
        assertEquals(emptyList<String>(), launches)
        assertEquals(listOf("a!detached"), log)
        assertTrue(flow.busy)
    }

    @Test fun lateSaveResultAfterDetachIsIgnored() {
        flow.beginSave("s", byteArrayOf(1))
        flow.saveAnswered("content://doc") { _, _ -> }
        flow.detached()
        assertTrue(flow.beginSave("t", byteArrayOf(2)))
        drain()
        assertEquals(listOf("s!detached"), log)
        assertTrue(flow.busy)
    }
}
