#!/usr/bin/env python3
"""Generate the Stash app-icon glyph.

Draws the Stash bookmark-ribbon mark — the same vertical ribbon with a V-notch
at the bottom that the browser extension uses (Extension/icons/) — as a white
glyph on a transparent square canvas, sized for the Icon Composer glass layer.
The indigo background gradient and the Liquid Glass treatment are supplied by
AppIcon.icon/icon.json; this script only produces the foreground shape.

No external dependencies beyond Pillow. Run from the StashApp/icon/ folder:

    python3 generate-app-icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

WHITE = (255, 255, 255, 255)
SIZE = 1024
SUPERSAMPLE = 4

OUTPUT = Path(__file__).resolve().parent.parent / "Stash" / "AppIcon.icon" / "Assets" / "Ribbon.png"


def ribbon_points(size):
    """The ribbon polygon, as (x, y) tuples in pixel space for a square canvas."""
    left, right = 0.30 * size, 0.70 * size
    top = 0.18 * size
    bottom = 0.82 * size
    notch = 0.65 * size
    return [
        (left, top),
        (right, top),
        (right, bottom),
        (0.5 * size, notch),
        (left, bottom),
    ]


def render(size):
    canvas = size * SUPERSAMPLE
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    radius = 0.05 * canvas
    draw.polygon(ribbon_points(canvas), fill=WHITE)
    draw.rounded_rectangle(
        [0.30 * canvas, 0.18 * canvas, 0.70 * canvas, 0.30 * canvas],
        radius=radius,
        fill=WHITE,
    )
    return image.resize((size, size), Image.LANCZOS)


def main():
    render(SIZE).save(OUTPUT)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
