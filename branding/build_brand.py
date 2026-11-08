"""Erzeugt die ramuri-Logodateien (SVG, Android-Vektoren) aus einer Quelle.

Aufruf (Einzelheiten in README.md):
    python -I branding/build_brand.py <Sora[wght].ttf> branding
"""
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen

NACHT, TIEFGRUEN, MINZE, GLUT, GLUT_DUNKEL, PAPIER = (
    "#0E1A1A", "#0F5E5A", "#7FD6C6", "#FF7A45", "#E0561F", "#F3F6F5")

# Zeichen im Raster 100 x 100, optische Mitte (50|50)
PTS = [("M", [(13, 61)]), ("L", [(29, 61)]), ("L", [(37, 43)]), ("L", [(47, 73)]),
       ("L", [(55, 53)]), ("C", [(60, 42), (66, 36), (71, 35)])]
DOT = (85, 30, 6.5)
LINE = "M13 61 H29 L37 43 L47 73 L55 53 C60 42 66 36 71 35"


def fmt(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def mark_svg(line, dot, stroke=8, dot_r=6.5):
    cx, cy, _ = DOT
    return (f'<path d="{LINE}" fill="none" stroke="{line}" stroke-width="{fmt(stroke)}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{fmt(dot_r)}" fill="{dot}"/>')


def doc(w, h, body, label):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{fmt(w)}" height="{fmt(h)}" '
            f'viewBox="0 0 {fmt(w)} {fmt(h)}" role="img" aria-label="{label}">'
            f'<title>{label}</title>{body}</svg>\n')


def wordmark(font_path):
    font = TTFont(font_path)
    font = instantiateVariableFont(font, {"wght": 600})
    upm = font["head"].unitsPerEm
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    hmtx = font["hmtx"]
    tracking = -0.03 * upm
    x, parts = 0.0, []
    bp = BoundsPen(gs)
    for ch in "ramuri":
        name = cmap[ord(ch)]
        pen = SVGPathPen(gs, ntos=fmt)
        # y nach unten, Grundlinie bei 0
        gs[name].draw(TransformPen(pen, (1, 0, 0, -1, x, 0)))
        gs[name].draw(TransformPen(bp, (1, 0, 0, -1, x, 0)))
        parts.append(pen.getCommands())
        x += hmtx[name][0] + tracking
    xh = font["OS/2"].sxHeight
    return " ".join(parts), bp.bounds, xh, upm


def lockups(font_path):
    d, (x0, y0, x1, y1), xh, upm = wordmark(font_path)
    out = {}

    # Wortmarke allein, Schriftgröße 100
    s = 100 / upm
    pad = 0
    w, h = (x1 - x0) * s, (y1 - y0) * s
    body = f'<path transform="scale({fmt(s)}) translate({fmt(-x0)} {fmt(-y0)})" d="{d}" fill="{{c}}"/>'
    out["wordmark"] = (w, h, body)

    # Horizontal: Zeichen 88 x 58 (Ausschnitt 8 22 85 56), Abstand 20, Schrift 60
    ms = 58 / 56
    fs = 60 / upm
    tx = 88 + 20
    baseline = 29 + xh * fs / 2
    top = min(0, baseline + y0 * fs)
    bottom = max(58, baseline + y1 * fs)
    W = tx + (x1 - x0) * fs
    H = bottom - top
    def horiz(line, dot, text):
        return (f'<g transform="translate(0 {fmt(-top)})">'
                f'<g transform="scale({fmt(ms)}) translate(-8 -22)">{mark_svg(line, dot)}</g>'
                f'<path transform="translate({fmt(tx)} {fmt(baseline)}) scale({fmt(fs)}) translate({fmt(-x0)} 0)" d="{d}" fill="{text}"/></g>')
    out["horizontal"] = (W, H, horiz)

    # Gestapelt: Zeichen 120 breit, Abstand 14, Schrift 44, zentriert
    fs2 = 44 / upm
    tw = (x1 - x0) * fs2
    mw, mh = 120, 120 * 56 / 85
    W2 = max(mw, tw)
    base2 = mh + 14 - y0 * fs2
    H2 = base2 + y1 * fs2
    def stacked(line, dot, text):
        return (f'<g transform="translate({fmt((W2 - mw) / 2)} 0) scale({fmt(mw / 85)}) translate(-8 -22)">{mark_svg(line, dot)}</g>'
                f'<path transform="translate({fmt((W2 - tw) / 2)} {fmt(base2)}) scale({fmt(fs2)}) translate({fmt(-x0)} 0)" d="{d}" fill="{text}"/>')
    out["stacked"] = (W2, H2, stacked)
    return out


def tpath(cx, cy, s, c=50):
    """Zeichen ohne Transformation, für Android-Vektoren."""
    out = []
    for cmd, pts in PTS:
        out.append(cmd + " ".join(f"{fmt(cx + s * (x - c))},{fmt(cy + s * (y - c))}" for x, y in pts))
    return " ".join(out)


def tdot(cx, cy, s, r, c=50):
    x, y = cx + s * (DOT[0] - c), cy + s * (DOT[1] - c)
    rr = s * r
    return (f"M{fmt(x - rr)},{fmt(y)} a{fmt(rr)},{fmt(rr)} 0 1,0 {fmt(2 * rr)},0 "
            f"a{fmt(rr)},{fmt(rr)} 0 1,0 {fmt(-2 * rr)},0")


def vector(size, line_path, dot_path, stroke, line_color, dot_color, tint=None):
    tint_attr = f'\n    android:tint="{tint}"' if tint else ""
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!-- ramuri: generiert von branding/build_brand.py, nicht von Hand ändern -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{size}dp"
    android:height="{size}dp"
    android:viewportWidth="{size}"
    android:viewportHeight="{size}"{tint_attr}>
    <path
        android:pathData="{line_path}"
        android:strokeColor="{line_color}"
        android:strokeWidth="{fmt(stroke)}"
        android:strokeLineCap="round"
        android:strokeLineJoin="round" />
    <path
        android:pathData="{dot_path}"
        android:fillColor="{dot_color}" />
</vector>
'''


def main(font_path, target):
    t = Path(target)
    svg = t / "svg"
    svg.mkdir(parents=True, exist_ok=True)
    files = {}

    # Icons
    tile = lambda rx, label: doc(100, 100, f'<rect width="100" height="100" rx="{rx}" fill="{NACHT}"/>'
                                 f'<g transform="translate(50 50) scale(0.78) translate(-50 -50)">'
                                 f'{mark_svg(MINZE, GLUT, 9)}</g>', label)
    files["svg/ramuri-icon.svg"] = tile(23, "ramuri")
    files["svg/ramuri-icon-square.svg"] = tile(0, "ramuri")
    files["svg/ramuri-mark-on-dark.svg"] = doc(85, 56, f'<g transform="translate(-8 -22)">{mark_svg(MINZE, GLUT)}</g>', "ramuri")
    files["svg/ramuri-mark-on-light.svg"] = doc(85, 56, f'<g transform="translate(-8 -22)">{mark_svg(TIEFGRUEN, GLUT_DUNKEL)}</g>', "ramuri")
    files["svg/ramuri-mark-mono.svg"] = doc(85, 56, f'<g transform="translate(-8 -22)">{mark_svg(NACHT, NACHT)}</g>', "ramuri")

    lk = lockups(font_path)
    w, h, body = lk["wordmark"]
    files["svg/ramuri-wordmark-on-light.svg"] = doc(w, h, body.replace("{c}", NACHT), "ramuri")
    files["svg/ramuri-wordmark-on-dark.svg"] = doc(w, h, body.replace("{c}", PAPIER), "ramuri")
    W, H, horiz = lk["horizontal"]
    files["svg/ramuri-logo-horizontal-on-light.svg"] = doc(W, H, horiz(TIEFGRUEN, GLUT_DUNKEL, NACHT), "ramuri")
    files["svg/ramuri-logo-horizontal-on-dark.svg"] = doc(W, H, horiz(MINZE, GLUT, PAPIER), "ramuri")
    W2, H2, stacked = lk["stacked"]
    files["svg/ramuri-logo-stacked-on-light.svg"] = doc(W2, H2, stacked(TIEFGRUEN, GLUT_DUNKEL, NACHT), "ramuri")
    files["svg/ramuri-logo-stacked-on-dark.svg"] = doc(W2, H2, stacked(MINZE, GLUT, PAPIER), "ramuri")

    # Android: Adaptive Icon 108 dp, Zeichen im Schutzkreis Ø 66 dp
    fg_line, fg_dot = tpath(54, 54, 0.66), tdot(54, 54, 0.66, 6.5)
    res = "android/res"
    files[f"{res}/drawable/ic_launcher_foreground.xml"] = vector(108, fg_line, fg_dot, 9 * 0.66, MINZE, GLUT)
    files[f"{res}/drawable/ic_launcher_monochrome.xml"] = vector(108, fg_line, fg_dot, 9 * 0.66, "#000000", "#000000")
    files[f"{res}/drawable/ic_stat_ramuri.xml"] = vector(24, tpath(12, 12, 0.22), tdot(12, 12, 0.22, 8), 10 * 0.22, "#FFFFFF", "#FFFFFF")
    files[f"{res}/values/ic_launcher_background.xml"] = (
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{NACHT}</color>\n</resources>\n')
    files[f"{res}/mipmap-anydpi-v26/ic_launcher.xml"] = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n')

    for rel, text in files.items():
        p = t / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
        print(rel)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
