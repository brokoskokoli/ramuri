package io.github.brokoskokoli.ramuri

import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.records.metadata.Metadata
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

/** Abbildung Record -> Kanal-Map mit gebauten Records (synthetische Werte, jedes Feld mit eigenem Wert). */
class HealthChannelMapTest {
    // Der Konstruktor von Metadata ist in connect-client 1.1.0 für Kotlin nicht sichtbar (die Factory-Methoden setzen
    // keine DataOrigin); im Bytecode ist er öffentlich. Der Test baut ihn deshalb per Reflexion.
    private fun meta(id: String): Metadata =
        Metadata::class.java.getConstructor(
            Int::class.javaPrimitiveType, String::class.java, DataOrigin::class.java, Instant::class.java,
            String::class.java, Long::class.javaPrimitiveType, androidx.health.connect.client.records.metadata.Device::class.java,
        ).newInstance(Metadata.RECORDING_METHOD_UNKNOWN, id, DataOrigin("com.example.source"), Instant.EPOCH, null, 0L, null)

    private val start = Instant.ofEpochMilli(1_700_000_000_000L)
    private val end = Instant.ofEpochMilli(1_700_000_600_000L)
    private val offset = ZoneOffset.ofHours(2)

    private fun common(m: Map<String, Any?>, id: String) {
        assertEquals(id, m["id"])
        assertEquals("com.example.source", m["origin"])
    }

    @Test fun exercise() {
        val m = toChannelMap(ExerciseSessionRecord(start, offset, end, offset, meta("e1"), ExerciseSessionRecord.EXERCISE_TYPE_RUNNING))
        common(m, "e1")
        assertEquals(1_700_000_000_000L, m["startMs"])
        assertEquals(1_700_000_600_000L, m["endMs"])
        assertEquals(7200L, m["offsetSeconds"])
        assertEquals(ExerciseSessionRecord.EXERCISE_TYPE_RUNNING.toLong(), m["exerciseType"])
    }

    @Test fun heartRateSamples() {
        val s1 = HeartRateRecord.Sample(start.plusSeconds(1), 61L)
        val s2 = HeartRateRecord.Sample(start.plusSeconds(2), 62L)
        val m = toChannelMap(HeartRateRecord(start, null, end, null, listOf(s1, s2), meta("h1")))
        common(m, "h1")
        assertEquals(1_700_000_000_000L, m["startMs"])
        assertEquals(1_700_000_600_000L, m["endMs"])
        assertEquals(null, m["offsetSeconds"])
        assertEquals("bpm", m["unit"])
        assertEquals(listOf(listOf(1_700_000_001_000L, 61L), listOf(1_700_000_002_000L, 62L)), m["samples"])
    }

    @Test fun restingHeartRate() {
        val m = toChannelMap(RestingHeartRateRecord(start, offset, 52L, meta("r1")))
        common(m, "r1")
        assertEquals(1_700_000_000_000L, m["startMs"])
        assertEquals(1_700_000_000_000L, m["endMs"])
        assertEquals(7200L, m["offsetSeconds"])
        assertEquals(52.0, m["value"])
        assertEquals("bpm", m["unit"])
    }

    @Test fun hrvRmssd() {
        val m = toChannelMap(HeartRateVariabilityRmssdRecord(start, offset, 43.5, meta("v1")))
        common(m, "v1")
        assertEquals(1_700_000_000_000L, m["startMs"])
        assertEquals(43.5, m["value"])
        assertEquals("ms", m["unit"])
    }

    @Test fun sleepWithStages() {
        val stages = listOf(
            SleepSessionRecord.Stage(start, start.plusSeconds(100), SleepSessionRecord.STAGE_TYPE_LIGHT),
            SleepSessionRecord.Stage(start.plusSeconds(100), end, SleepSessionRecord.STAGE_TYPE_DEEP),
        )
        val m = toChannelMap(SleepSessionRecord(start, offset, end, offset, meta("s1"), null, null, stages))
        common(m, "s1")
        assertEquals(1_700_000_000_000L, m["startMs"])
        assertEquals(1_700_000_600_000L, m["endMs"])
        assertEquals(7200L, m["offsetSeconds"])
        assertEquals(
            listOf(
                listOf(1_700_000_000_000L, 1_700_000_100_000L, SleepSessionRecord.STAGE_TYPE_LIGHT.toLong()),
                listOf(1_700_000_100_000L, 1_700_000_600_000L, SleepSessionRecord.STAGE_TYPE_DEEP.toLong()),
            ),
            m["stages"],
        )
    }

    @Test fun vo2Max() {
        val m = toChannelMap(Vo2MaxRecord(start, offset, meta("m1"), 47.25, Vo2MaxRecord.MEASUREMENT_METHOD_COOPER_TEST))
        common(m, "m1")
        assertEquals(1_700_000_000_000L, m["startMs"])
        assertEquals(47.25, m["value"])
        assertEquals("ml/min/kg", m["unit"])
        assertEquals(Vo2MaxRecord.MEASUREMENT_METHOD_COOPER_TEST.toLong(), m["method"])
    }

    @Test fun unsupportedRecordIsAProgrammingError() {
        val r = androidx.health.connect.client.records.StepsRecord(start, null, end, null, 5L, meta("x"))
        assertThrows(IllegalArgumentException::class.java) { toChannelMap(r) }
    }
}
