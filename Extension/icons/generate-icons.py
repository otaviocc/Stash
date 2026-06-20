#!/usr/bin/env python3
"""Generate the Stash extension icons.

Draws the Stash bookmark-ribbon mark — a vertical ribbon with a V-notch at the
bottom — at the four sizes the WebExtension manifest references (16, 32, 48, 128),
in two treatments matching where each size is shown:

- 16 and 32 back the manifest ``default_icon`` (the toolbar action button), so
  they render as a deep-indigo (#231468) ribbon on a transparent background —
  legible on both light and dark browser toolbars.
- 48 and 128 are the add-ons-manager / store display icons, so they render as the
  full app-icon look: a white ribbon on an indigo rounded square, matching the
  native app icon (StashApp/Stash/AppIcon.icon).

No external dependencies beyond Pillow. Run from the Extension/icons/ folder:

    python3 generate-icons.py
"""

from PIL import Image, ImageDraw

INDIGO = (35, 20, 104, 255)  # #231468
WHITE = (255, 255, 255, 255)
SIZES = (16, 32, 48, 128)
SUPERSAMPLE = 8

# Sizes at and above this get the squared app-icon treatment; smaller sizes stay
# a bare ribbon on transparent for the toolbar action.
SQUARE_MIN_SIZE = 48


def ribbon_points(size, top, bottom, notch):
    """The ribbon polygon, as (x, y) tuples in pixel space for a square canvas."""
    left, right = 0.30 * size, 0.70 * size
    return [
        (left, top * size),
        (right, top * size),
        (right, bottom * size),
        (0.5 * size, notch * size),
        (left, bottom * size),
    ]


def render(size):
    canvas = size * SUPERSAMPLE
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    if size >= SQUARE_MIN_SIZE:
        draw.rounded_rectangle(
            [0, 0, canvas - 1, canvas - 1],
            radius=0.22 * canvas,
            fill=INDIGO,
        )
        glyph, top, bottom, notch = WHITE, 0.18, 0.82, 0.65
    else:
        glyph, top, bottom, notch = INDIGO, 0.12, 0.88, 0.70

    draw.polygon(ribbon_points(canvas, top, bottom, notch), fill=glyph)
    draw.rounded_rectangle(
        [0.30 * canvas, top * canvas, 0.70 * canvas, (top + 0.12) * canvas],
        radius=0.06 * canvas,
        fill=glyph,
    )
    return image.resize((size, size), Image.LANCZOS)


def main():
    for size in SIZES:
        render(size).save(f"icon-{size}.png")
        print(f"wrote icon-{size}.png")


if __name__ == "__main__":
    main()
