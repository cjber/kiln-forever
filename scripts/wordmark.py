#!/usr/bin/env python3
"""Regenerate the README wordmark: "kiln" in Liberation Sans Bold with kiln's ember for the dot of the i,
then "forever" in the regular weight and the ember colour.

The ember is not a second drawing of the letter: the i is outlined as dotless, and the ember fills the box
the font gives the missing dot. Shapes and colours match cjber/kiln's scripts/wordmark.py.
"""

from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONTS = Path("/usr/share/fonts/liberation")
INK = "#101214"
PAPER = "#f4f1ec"
EMBER, FLAME = "#df8b63", "#ffc477"
SIZE = 74
BASELINE = 77
TRACKING = -2
SPACE = 18
MARGIN = 10
TOP = 8
HEIGHT = 80
OUT = Path(__file__).resolve().parent.parent / "assets"


class Face:
    def __init__(self, file: str) -> None:
        self.font = TTFont(FONTS / file)
        self.glyphs = self.font.getGlyphSet()
        self.cmap = self.font.getBestCmap()
        self.scale = SIZE / self.font["head"].unitsPerEm

    def outline(self, char: str, x: float) -> tuple[str, float]:
        glyph = self.cmap[ord(char)]
        pen = SVGPathPen(self.glyphs)
        self.glyphs[glyph].draw(TransformPen(pen, (self.scale, 0, 0, -self.scale, x, BASELINE)))
        return pen.getCommands(), self.glyphs[glyph].width * self.scale

    def dot_box(self, x: float) -> tuple[float, float, float, float]:
        """The box the i glyph gives its dot, in SVG coordinates."""
        glyph = self.font["glyf"][self.cmap[ord("i")]]
        coords, ends, _ = glyph.getCoordinates(self.font["glyf"])
        start, boxes = 0, []
        for end in ends:
            points = coords[start : end + 1]
            xs, ys = [p[0] for p in points], [p[1] for p in points]
            boxes.append((min(xs), min(ys), max(xs), max(ys)))
            start = end + 1
        dx0, dy0, dx1, dy1 = max(boxes, key=lambda box: box[3])
        s = self.scale
        return x + dx0 * s, BASELINE - dy1 * s, (dx1 - dx0) * s, (dy1 - dy0) * s


BOLD = Face("LiberationSans-Bold.ttf")
REGULAR = Face("LiberationSans-Regular.ttf")


def ember(x: float) -> str:
    """A flame standing where the i's dot would be, in kiln's ember and flame colours."""
    left, top, width, height = BOLD.dot_box(x)
    bx, bw = left - width * 0.12, width * 1.24
    bh = height * 1.75
    by = top + height - bh

    def point(px: float, py: float) -> str:
        return f"{bx + px * bw:.2f} {by + py * bh:.2f}"

    def curve(points: list[tuple[float, float]]) -> str:
        return "C" + " ".join(point(px, py) for px, py in points)

    outer = "M" + point(0.5, 0)
    outer += curve([(0.58, 0.14), (0.82, 0.3), (0.82, 0.6)])
    outer += curve([(0.82, 0.83), (0.68, 1), (0.5, 1)])
    outer += curve([(0.32, 1), (0.18, 0.83), (0.18, 0.6)])
    outer += curve([(0.18, 0.42), (0.28, 0.32), (0.35, 0.18)])
    outer += curve([(0.38, 0.28), (0.44, 0.36), (0.5, 0.4)])
    outer += curve([(0.47, 0.28), (0.47, 0.12), (0.5, 0)]) + "Z"

    inner = "M" + point(0.5, 0.42)
    inner += curve([(0.58, 0.52), (0.66, 0.62), (0.66, 0.74)])
    inner += curve([(0.66, 0.86), (0.59, 0.93), (0.5, 0.93)])
    inner += curve([(0.41, 0.93), (0.34, 0.86), (0.34, 0.74)])
    inner += curve([(0.34, 0.66), (0.4, 0.58), (0.5, 0.42)]) + "Z"

    return f'<path d="{outer}" fill="{EMBER}"/><path d="{inner}" fill="{FLAME}"/>'


def wordmark(ink: str) -> str:
    x, parts = float(MARGIN), []
    for char in "kiln":
        path, advance = BOLD.outline("ı" if char == "i" else char, x)
        parts.append(f'<path d="{path}" fill="{ink}"/>')
        if char == "i":
            parts.append(ember(x))
        x += advance + TRACKING
    x += SPACE
    for char in "forever":
        path, advance = REGULAR.outline(char, x)
        parts.append(f'<path d="{path}" fill="{EMBER}"/>')
        x += advance + TRACKING

    width = x - TRACKING + MARGIN
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 {TOP} {width:.2f} {HEIGHT}" role="img" '
        f'aria-label="Kiln Forever"><title>Kiln Forever</title>{"".join(parts)}</svg>\n'
    )


OUT.mkdir(exist_ok=True)
(OUT / "wordmark.svg").write_text(wordmark(INK))
(OUT / "wordmark-dark.svg").write_text(wordmark(PAPER))
