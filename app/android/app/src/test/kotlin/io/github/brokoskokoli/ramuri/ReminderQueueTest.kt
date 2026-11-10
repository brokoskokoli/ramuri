package io.github.brokoskokoli.ramuri

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class ReminderQueueTest {
    private fun item(at: Long) = ReminderQueue.Item(at, "easy")

    @Test fun showsDueKeepsFutureAndDropsStale() {
        val now = 10 * ReminderQueue.STALE_MS
        val stale = item(now - ReminderQueue.STALE_MS)
        val due = item(now - 1000)
        val exact = item(now)
        val later = item(now + 5000)
        val soon = item(now + 1000)
        val s = ReminderQueue.split(listOf(later, stale, exact, due, soon), now)
        assertEquals(listOf(due, exact), s.show)
        assertEquals(listOf(soon, later), s.keep)
        assertEquals(now + 1000, s.next)
    }

    @Test fun nothingLeftMeansNoAlarm() {
        val s = ReminderQueue.split(listOf(item(5)), 10)
        assertEquals(listOf(item(5)), s.show)
        assertNull(s.next)
    }

    @Test fun storesOnlyTimeAndKind() {
        val items = listOf(ReminderQueue.Item(1731256200000L, "long"), ReminderQueue.Item(1731342600000L, "easy"))
        val raw = ReminderQueue.encode(items)
        assertEquals("1731256200000 long\n1731342600000 easy", raw)
        assertEquals(items, ReminderQueue.decode(raw))
    }

    @Test fun decodeSkipsMalformedAndRejectsTextAsKind() {
        assertEquals(emptyList<ReminderQueue.Item>(), ReminderQueue.decode(null))
        assertEquals(
            listOf(ReminderQueue.Item(5, "easy")),
            ReminderQueue.decode("5 easy\n[{\"at\":1}]\n6 Langer Lauf um 18:00\nx tempo"),
        )
        assertThrows(IllegalArgumentException::class.java) {
            ReminderQueue.encode(listOf(ReminderQueue.Item(1, "Langer Lauf um 18:00")))
        }
    }
}
