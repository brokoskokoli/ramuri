package io.github.brokoskokoli.ramuri

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReminderQueueTest {
    private fun item(at: Long) = ReminderQueue.Item(at, "t", "b$at")

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
}
