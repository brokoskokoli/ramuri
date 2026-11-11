package io.github.brokoskokoli.ramuri

import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Test

class PpgFrameStatsTest {
    private val w = 320
    private val h = 240

    /** Y mit Zeilenpuffer (rowStride > w), U/V verschachtelt wie NV21 (pixelStride 2) auf getrennten Puffern. */
    private fun image(y: (Int, Int) -> Int, u: Int, v: Int): Triple<PpgPlane, PpgPlane, PpgPlane> {
        val yRow = w + 16
        val yb = ByteBuffer.allocate(yRow * h)
        for (yy in 0 until h) for (xx in 0 until w) yb.put(yy * yRow + xx, y(xx, yy).toByte())
        val cRow = w + 8
        val ub = ByteBuffer.allocate(cRow * (h / 2))
        val vb = ByteBuffer.allocate(cRow * (h / 2))
        for (cy in 0 until h / 2) for (cx in 0 until w / 2) {
            ub.put(cy * cRow + cx * 2, u.toByte())
            vb.put(cy * cRow + cx * 2, v.toByte())
        }
        return Triple(PpgPlane(yb, yRow, 1), PpgPlane(ub, cRow, 2), PpgPlane(vb, cRow, 2))
    }

    @Test fun uniformGrayHasEqualRedAndGreenEverywhere() {
        val (y, u, v) = image({ _, _ -> 100 }, 128, 128)
        val s = PpgFrameStats.compute(w, h, y, u, v)
        assertEquals(100.0, s.r, 1e-9)
        assertEquals(100.0, s.g, 1e-9)
        for (i in 0 until 16) {
            assertEquals(100.0, s.r16[i], 1e-9)
            assertEquals(100.0, s.g16[i], 1e-9)
        }
    }

    @Test fun colourFollowsBt601() {
        val (y, u, v) = image({ _, _ -> 120 }, 100, 200)
        val s = PpgFrameStats.compute(w, h, y, u, v)
        assertEquals(120 + 1.402 * 72, s.r, 1e-9)
        assertEquals(120 - 0.344136 * -28 - 0.714136 * 72, s.g, 1e-9)
    }

    @Test fun blocksAreRowMajorOverTheWholeImage() {
        // Linke Bildhälfte 200, rechte 50: Spalten 0 und 1 des Rasters hell, 2 und 3 dunkel.
        val (y, u, v) = image({ x, _ -> if (x < w / 2) 200 else 50 }, 128, 128)
        val s = PpgFrameStats.compute(w, h, y, u, v)
        for (i in 0 until 16) assertEquals("Block $i", if (i % 4 < 2) 200.0 else 50.0, s.r16[i], 1e-9)
        // Die Mitte (mittlere 50 %) liegt je zur Hälfte in beiden: Mittel 125.
        assertEquals(125.0, s.r, 1e-9)
        // Zeilen: oben hell, unten dunkel.
        val (y2, u2, v2) = image({ _, yy -> if (yy < h / 2) 200 else 50 }, 128, 128)
        val t = PpgFrameStats.compute(w, h, y2, u2, v2)
        for (i in 0 until 16) assertEquals("Block $i", if (i / 4 < 2) 200.0 else 50.0, t.r16[i], 1e-9)
    }

    @Test fun centreIgnoresTheBorder() {
        // Rand 0, Mitte 200: nur die mittleren 50 % gehen in r/g ein.
        val (y, u, v) = image({ x, yy -> if (x in w / 4 until 3 * w / 4 && yy in h / 4 until 3 * h / 4) 200 else 0 }, 128, 128)
        val s = PpgFrameStats.compute(w, h, y, u, v)
        assertEquals(200.0, s.r, 1e-9)
    }
}
