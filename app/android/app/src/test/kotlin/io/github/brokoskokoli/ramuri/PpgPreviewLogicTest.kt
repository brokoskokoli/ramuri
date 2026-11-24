package io.github.brokoskokoli.ramuri

import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Kamerasuche (FR-0220, PAR-227): reine Regeln ohne Android. Erfundene Kamera-IDs. */
class PpgPreviewLogicTest {
    private val std = PpgPreviewRef("0", null)
    private val p2 = PpgPreviewRef("0", "2")
    private val p3 = PpgPreviewRef("0", "3")
    private val other = PpgPreviewRef("1", null)

    @Test fun turnIsOneAndAHalfSeconds() {
        // PAR-227: 1,5 s je Kamera im Wechsel.
        assertEquals(1_500_000_000L, PpgPreviewLogic.PREVIEW_TURN_NS)
    }

    @Test fun parsesCamerasInOrderAndDropsInvalidAndDuplicates() {
        val args = mapOf(
            "cameras" to listOf(
                mapOf("cameraId" to "0", "physicalCameraId" to null),
                mapOf("cameraId" to "0", "physicalCameraId" to "2"),
                mapOf("cameraId" to "", "physicalCameraId" to null),
                mapOf("cameraId" to "0", "physicalCameraId" to ""),
                mapOf("cameraId" to 3),
                "x",
                mapOf("cameraId" to "0", "physicalCameraId" to "2"),
            ),
        )
        assertEquals(listOf(std, p2), PpgPreviewLogic.parseRefs(args))
        assertTrue(PpgPreviewLogic.parseRefs(null).isEmpty())
        assertTrue(PpgPreviewLogic.parseRefs(mapOf("cameras" to "x")).isEmpty())
    }

    @Test fun planKeepsUsableAndReportsReasons() {
        val entries = listOf(
            PpgCameraEntry("0", null, 5f, true, null, 60),
            PpgCameraEntry("0", "2", 2f, false, null, 30),
            PpgCameraEntry("1", null, 6f, false, "no_flash"),
        )
        val plan = PpgPreviewLogic.plan(listOf(std, p2, other, PpgPreviewRef("9", null)), entries)
        assertEquals(listOf(std, p2), plan.live)
        assertEquals(listOf(other to "no_flash", PpgPreviewRef("9", null) to "no_camera"), plan.failed)
    }

    @Test fun sharedSessionOnlyForPhysicalCamerasOfOneLogicalCamera() {
        assertTrue(PpgPreviewLogic.canShareSession(listOf(p2, p3)))
        assertTrue(PpgPreviewLogic.canShareSession(listOf(std)))
        assertTrue(PpgPreviewLogic.canShareSession(emptyList()))
        // Logische Kamera selbst neben ihrer physischen: kein gemeinsamer Ausgang je Kamera.
        assertFalse(PpgPreviewLogic.canShareSession(listOf(std, p2)))
        // Getrennte Kamera-IDs nie gleichzeitig.
        assertFalse(PpgPreviewLogic.canShareSession(listOf(p2, PpgPreviewRef("1", "4"))))
        assertFalse(PpgPreviewLogic.canShareSession(listOf(std, other)))
        assertFalse(PpgPreviewLogic.canShareSession(listOf(p2, p2)))
    }

    @Test fun modeSimultaneousOnlyWhenSharedAndConfirmed() {
        assertEquals("simultaneous", PpgPreviewLogic.previewMode(listOf(p2, p3), sessionSupported = true))
        assertEquals("alternating", PpgPreviewLogic.previewMode(listOf(p2, p3), sessionSupported = false))
        assertEquals("alternating", PpgPreviewLogic.previewMode(listOf(std, p2), sessionSupported = true))
        assertEquals("alternating", PpgPreviewLogic.previewMode(listOf(std, other), sessionSupported = true))
        assertEquals("simultaneous", PpgPreviewLogic.previewMode(listOf(std), sessionSupported = false))
    }

    @Test fun turnsFollowRequestOrderEndlesslyAndSkipFailed() {
        // Beginn bei der ersten (Standardkamera), dann der Reihe nach, wieder von vorn.
        assertEquals(0, PpgPreviewLogic.nextTurn(-1, 3, emptySet()))
        assertEquals(1, PpgPreviewLogic.nextTurn(0, 3, emptySet()))
        assertEquals(2, PpgPreviewLogic.nextTurn(1, 3, emptySet()))
        assertEquals(0, PpgPreviewLogic.nextTurn(2, 3, emptySet()))
        // Kamera mit Fehler fällt aus dem Wechsel.
        assertEquals(2, PpgPreviewLogic.nextTurn(0, 3, setOf(1)))
        assertEquals(1, PpgPreviewLogic.nextTurn(1, 3, setOf(0, 2)))
        assertNull(PpgPreviewLogic.nextTurn(0, 3, setOf(0, 1, 2)))
        assertNull(PpgPreviewLogic.nextTurn(-1, 0, emptySet()))
    }

    @Test fun previewSizeSmallestAtLeast160x120() {
        assertEquals(176 to 144, PpgPreviewLogic.chooseSize(listOf(640 to 480, 176 to 144, 320 to 240, 160 to 90)))
        assertEquals(160 to 120, PpgPreviewLogic.chooseSize(listOf(160 to 120, 320 to 240)))
        assertEquals(160 to 90, PpgPreviewLogic.chooseSize(listOf(160 to 90, 96 to 96)))
        assertNull(PpgPreviewLogic.chooseSize(emptyList()))
    }

    @Test fun argbDownscalesBt601() {
        // 4×4 Bild, Y 100, U 128, V 200 → R = 100 + 1,402·72 ≈ 200, G ≈ 48, B 100.
        val y = ByteBuffer.wrap(ByteArray(16) { 100 })
        val u = ByteBuffer.wrap(ByteArray(8) { 128.toByte() })
        val v = ByteBuffer.wrap(ByteArray(8) { 200.toByte() })
        val out = IntArray(4)
        PpgPreviewLogic.argb(4, 4, PpgPlane(y, 4, 1), PpgPlane(u, 4, 2), PpgPlane(v, 4, 2), 2, 2, out)
        for (px in out) {
            assertEquals(0xff, px ushr 24)
            assertEquals(200, (px shr 16) and 0xff)
            assertEquals(48, (px shr 8) and 0xff)
            assertEquals(100, px and 0xff)
        }
    }

    @Test fun messagesMatchDartWire() {
        assertEquals(
            mapOf(
                "type" to "started",
                "mode" to "alternating",
                "textures" to listOf(mapOf("cameraId" to "0", "physicalCameraId" to "2", "textureId" to 7L)),
            ),
            PpgPreviewLogic.startedMap("alternating", mapOf(p2 to 7L)),
        )
        assertEquals(
            mapOf(
                "cameraId" to "0", "physicalCameraId" to null, "type" to "frame", "t" to 1.5,
                "r" to 200.0, "g" to 40.0, "exposureNs" to 8_333_333L, "iso" to 100,
            ),
            PpgPreviewLogic.frameMap(std, 1.5, 200.0, 40.0, 8_333_333L, 100),
        )
        assertEquals(mapOf("cameraId" to "0", "physicalCameraId" to "2", "type" to "turn"), PpgPreviewLogic.turnMap(p2))
        assertEquals(
            mapOf("cameraId" to "1", "physicalCameraId" to null, "type" to "failed", "reason" to "busy"),
            PpgPreviewLogic.failedMap(other, "busy"),
        )
        assertEquals(mapOf("type" to "stopped", "reason" to "background"), PpgPreviewLogic.stoppedMap("background"))
    }
}
