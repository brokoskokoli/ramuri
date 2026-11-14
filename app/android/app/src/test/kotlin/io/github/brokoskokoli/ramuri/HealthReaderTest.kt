package io.github.brokoskokoli.ramuri

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class HealthReaderTest {
    private class Source(var granted: Set<String>) : HealthSource {
        val reads = mutableListOf<HealthKind>()
        var checks = 0
        override fun sdkStatus() = "available"
        override fun grantedPermissions(): Set<String> { checks++; return granted }
        override fun readPage(kind: HealthKind, fromMs: Long, toMs: Long, pageToken: String?, pageSize: Int): HealthPage {
            reads.add(kind)
            return HealthPage(listOf(mapOf("id" to "x")), null)
        }
    }

    private fun code(block: () -> Unit): String {
        try { block() } catch (e: HealthReadException) { return e.code }
        fail("keine HealthReadException")
        return ""
    }

    private fun reader(s: Source, clock: () -> Long = { 0L }, sleeps: MutableList<Long> = mutableListOf()) =
        HealthReader(s, nowMs = clock, sleep = { sleeps.add(it) })

    @Test fun withoutThePermissionOfThisKindNothingIsRead() {
        val s = Source(emptySet())
        for (k in HealthKind.values()) {
            assertEquals("permission_missing", code { reader(s).read(k.key, 0, 1000, null, null) })
        }
        assertEquals(emptyList<HealthKind>(), s.reads)
    }

    @Test fun grantingOneKindDoesNotOpenTheOthers() {
        val s = Source(setOf(HealthKind.SLEEP.permission))
        val r = reader(s)
        assertEquals(1, r.read("sleep", 0, 1000, null, null).records.size)
        for (k in HealthKind.values().filter { it != HealthKind.SLEEP }) {
            assertEquals("permission_missing", code { r.read(k.key, 0, 1000, null, null) })
        }
        assertEquals(listOf(HealthKind.SLEEP), s.reads)
    }

    @Test fun permissionIsAskedFreshBeforeEveryRead() {
        val s = Source(setOf(HealthKind.VO2_MAX.permission))
        val r = reader(s)
        r.read("vo2_max", 0, 1000, null, null)
        s.granted = emptySet() // im System entzogen
        assertEquals("permission_missing", code { r.read("vo2_max", 0, 1000, "next", null) })
        assertEquals(1, s.reads.size)
        assertEquals(2, s.checks)
    }

    @Test fun unknownKindAndBadWindowAreRejectedBeforeAnyAccess() {
        val s = Source(HealthKind.values().map { it.permission }.toSet())
        val r = reader(s)
        assertEquals("bad_arguments", code { r.read("steps", 0, 1000, null, null) })
        assertEquals("bad_arguments", code { r.read(null, 0, 1000, null, null) })
        assertEquals("bad_arguments", code { r.read("sleep", 1000, 1000, null, null) })
        assertEquals("bad_arguments", code { r.read("sleep", null, 1000, null, null) })
        assertEquals(0, s.reads.size)
        assertEquals(0, s.checks)
    }

    @Test fun heartRateOnlyInTheWindowOfOneSession() {
        val s = Source(setOf(HealthKind.HEART_RATE.permission))
        val r = reader(s)
        val day = 24L * 60 * 60 * 1000
        assertEquals(1, r.read("heart_rate", 0, day, null, null).records.size)
        assertEquals("bad_arguments", code { r.read("heart_rate", 0, day + 1, null, null) })
    }

    @Test fun grantedKeysListOnlyTheSixKinds() {
        val s = Source(setOf(HealthKind.SLEEP.permission, "android.permission.health.WRITE_SLEEP",
            "android.permission.health.READ_STEPS"))
        assertEquals(listOf("sleep"), reader(s).grantedKeys())
    }

    @Test fun readsKeepAMinimumGap() {
        val s = Source(setOf(HealthKind.SLEEP.permission))
        var now = 1000L
        val sleeps = mutableListOf<Long>()
        val r = HealthReader(s, nowMs = { now }, sleep = { sleeps.add(it); now += it }, minGapMs = 300)
        r.read("sleep", 0, 10, null, null)
        assertTrue(sleeps.isEmpty())
        now += 100
        r.read("sleep", 0, 10, null, null)
        assertEquals(listOf(200L), sleeps)
        now += 500
        r.read("sleep", 0, 10, null, null)
        assertEquals(listOf(200L), sleeps)
    }

    @Test fun permissionStringsAreExactlyTheSixReadRights() {
        val all = HealthKind.values().map { it.permission }
        assertEquals(6, all.toSet().size)
        assertTrue(all.all { it.startsWith("android.permission.health.READ_") })
        assertFalse(all.any { it.endsWith("HISTORY") || it.endsWith("BACKGROUND") })
    }
}
