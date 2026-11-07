package io.github.brokoskokoli.running_app

import java.io.IOException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FileHandoffFlowTest {
    private val log = mutableListOf<String>()
    private val flow = FileHandoffFlow(object : HandoffAnswers<String> {
        override fun success(result: String, value: String) { log.add("$result:$value") }
        override fun error(result: String, code: String, detail: String?) { log.add("$result!$code${detail?.let { "($it)" } ?: ""}") }
    })

    @Test fun shareTargetChosenCompletes() {
        assertTrue(flow.beginShare("a"))
        flow.paused()
        flow.chosen()
        flow.resumed()
        assertEquals(listOf("a:completed"), log)
        assertFalse(flow.busy)
    }

    @Test fun shareMenuClosedWithoutChoiceIsCancelled() {
        flow.beginShare("a")
        flow.paused()
        flow.resumed()
        assertEquals(listOf("a:cancelled"), log)
    }

    @Test fun resumeBeforeTheMenuCoveredTheActivityDoesNotCancel() {
        flow.beginShare("a")
        flow.resumed()
        assertEquals(emptyList<String>(), log)
        flow.paused()
        flow.chosen()
        assertEquals(listOf("a:completed"), log)
    }

    @Test fun secondHandoffWhileOneIsOpenIsBusy() {
        flow.beginShare("a")
        assertFalse(flow.beginSave("b", byteArrayOf(1)))
        assertFalse(flow.beginShare("c"))
        assertEquals(listOf("b!busy", "c!busy"), log)
        flow.paused()
        flow.resumed()
        assertEquals("a:cancelled", log.last())
    }

    @Test fun saveWritesTheBytesIntoTheChosenTarget() {
        flow.beginSave("s", byteArrayOf(4, 5))
        var written: Pair<String, ByteArray>? = null
        flow.saveAnswered("content://doc") { uri, bytes -> written = uri to bytes }
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
        flow.beginShare("a")
        flow.detached()
        assertEquals(listOf("a!detached"), log)
        flow.detached()
        flow.paused()
        flow.resumed()
        assertEquals(1, log.size)
        assertTrue(flow.beginSave("b", byteArrayOf(1)))
    }

    @Test fun startFailureEndsTheHandoff() {
        flow.beginShare("a")
        flow.fail("share_failed", "ActivityNotFoundException")
        assertEquals(listOf("a!share_failed(ActivityNotFoundException)"), log)
        assertFalse(flow.busy)
    }

    @Test fun lateAnswersAfterTheEndAreIgnored() {
        flow.beginShare("a")
        flow.chosen()
        flow.chosen()
        flow.paused()
        flow.resumed()
        flow.saveAnswered("x") { _, _ -> throw AssertionError() }
        assertEquals(listOf("a:completed"), log)
    }
}
