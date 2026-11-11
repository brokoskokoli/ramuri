package io.github.brokoskokoli.ramuri

import java.nio.ByteBuffer

/** Bildstatistik eines Kamerabilds: R und G der Mitte, je 16 Teilbereiche. Keine Pixel (ADR-0011 Punkt 1). */
class PpgStats(val r: Double, val g: Double, val r16: DoubleArray, val g16: DoubleArray)

/** Eine Ebene eines YUV-420-Bilds (Android: Image.Plane). */
class PpgPlane(val buffer: ByteBuffer, val rowStride: Int, val pixelStride: Int)

/**
 * Statistik je Bild wie in der Referenz (`MainActivity.onFrame`, Stand algo-v0.4-frozen): Mittelwerte
 * von Y/U/V einmal für die Bildmitte (mittlere 50 %) und je Teilbereich eines 4×4-Rasters über das
 * ganze Bild, jedes zweite Pixel in x und y, danach R und G nach BT.601 (ALGORITHMUS.md Abschn. 2).
 * Reines Kotlin ohne Android-Bezug, daher einzeln testbar.
 */
object PpgFrameStats {
    const val GRID = 4
    const val BLOCKS = GRID * GRID

    fun compute(w: Int, h: Int, yP: PpgPlane, uP: PpgPlane, vP: PpgPlane): PpgStats {
        val yb = yP.buffer
        val ub = uP.buffer
        val vb = vP.buffer
        var sy = 0.0
        var su = 0.0
        var sv = 0.0
        var cnt = 0
        val by = DoubleArray(BLOCKS)
        val bu = DoubleArray(BLOCKS)
        val bv = DoubleArray(BLOCKS)
        val bc = IntArray(BLOCKS)
        val cx0 = w / 4
        val cx1 = 3 * w / 4
        val cy0 = h / 4
        val cy1 = 3 * h / 4
        var yy = 0
        while (yy < h) {
            val rowY = yy * yP.rowStride
            val uy = yy / 2
            val rowU = uy * uP.rowStride
            val rowV = uy * vP.rowStride
            val bRow = (yy * GRID / h) * GRID
            var xx = 0
            while (xx < w) {
                val y = (yb.get(rowY + xx * yP.pixelStride).toInt() and 0xFF).toDouble()
                val ux = xx / 2
                val u = (ub.get(rowU + ux * uP.pixelStride).toInt() and 0xFF).toDouble()
                val v = (vb.get(rowV + ux * vP.pixelStride).toInt() and 0xFF).toDouble()
                val b = bRow + xx * GRID / w
                by[b] += y; bu[b] += u; bv[b] += v; bc[b]++
                if (xx in cx0 until cx1 && yy in cy0 until cy1) {
                    sy += y; su += u; sv += v; cnt++
                }
                xx += 2
            }
            yy += 2
        }
        val (r, g) = rg(sy / cnt, su / cnt, sv / cnt)
        val r16 = DoubleArray(BLOCKS)
        val g16 = DoubleArray(BLOCKS)
        for (b in 0 until BLOCKS) {
            val (rr, gg) = rg(by[b] / bc[b], bu[b] / bc[b], bv[b] / bc[b])
            r16[b] = rr
            g16[b] = gg
        }
        return PpgStats(r, g, r16, g16)
    }

    /** BT.601, Vollbereich. */
    fun rg(y: Double, u: Double, v: Double): Pair<Double, Double> =
        (y + 1.402 * (v - 128)) to (y - 0.344136 * (u - 128) - 0.714136 * (v - 128))
}
