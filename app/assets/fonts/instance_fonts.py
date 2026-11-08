"""Schneidet aus den Variable Fonts von google/fonts statische Schnitte.

Aufruf (Python mit fonttools, isoliert):
  python -I instance_fonts.py <Ordner mit den Variable Fonts> <Zielordner>
Erwartet in <Ordner>: Sora[wght].ttf und Manrope[wght].ttf.
"""
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

SLICES = {
    "Sora": [(500, "Medium"), (600, "SemiBold"), (700, "Bold")],
    "Manrope": [(400, "Regular"), (500, "Medium"), (600, "SemiBold"),
                (700, "Bold"), (800, "ExtraBold")],
}


def main(src: Path, dst: Path) -> None:
    dst.mkdir(parents=True, exist_ok=True)
    for family, slices in SLICES.items():
        for weight, style in slices:
            font = TTFont(src / f"{family}[wght].ttf")
            inst = instancer.instantiateVariableFont(font, {"wght": weight})
            full = f"{family} {style}"
            ribbi = style in ("Regular", "Bold")
            names = {1: family if ribbi else full,
                     2: style if ribbi else "Regular",
                     4: full, 6: f"{family}-{style}"}
            for nid in (16, 17, 25):
                inst["name"].removeNames(nameID=nid)
            for nid, text in names.items():
                inst["name"].setName(text, nid, 3, 1, 0x409)
                inst["name"].setName(text, nid, 1, 0, 0)
            inst["OS/2"].usWeightClass = weight
            inst.save(dst / f"{family}-{style}.ttf")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
