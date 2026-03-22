#!/usr/bin/env python3
"""Generate the Stash toolbar icons.

Draws the Stash bookmark-ribbon mark — a vertical ribbon with a V-notch at the
bottom — in deep indigo (#231468) on a transparent background, and exports it at
the four sizes the WebExtension manifest references (16, 32, 48, 128).

No external dependencies beyond Pillow. Run from the Extension/icons/ folder:

    python3 generate-icons.py
"""

from PIL import Image, ImageDraw

INDIGO = (35, 20, 104, 255)  # #231468
SIZES = (16, 32, 48, 128)
SUPERSAMPLE = 8


def ribbon_points(size):
    """The ribbon polygon, as (x, y) tuples in pixel space for a square canvas."""
    left, right = 0.30 * size, 0.70 * size
    top = 0.12 * size
    bottom = 0.88 * size
    notch = 0.70 * size
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
    radius = 0.06 * canvas
    draw.polygon(ribbon_points(canvas), fill=INDIGO)
    draw.rounded_rectangle(
        [0.30 * canvas, 0.12 * canvas, 0.70 * canvas, 0.30 * canvas],
        radius=radius,
        fill=INDIGO,
    )
    return image.resize((size, size), Image.LANCZOS)


def main():
    for size in SIZES:
        render(size).save(f"icon-{size}.png")
        print(f"wrote icon-{size}.png")


if __name__ == "__main__":
    main()
