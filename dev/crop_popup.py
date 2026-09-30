#!/usr/bin/env python3
"""Crop an Omarchy popup card out of a screenshot.

  crop_popup.py closed.png open.png out.png

The card is located by what changed between the two shots. The
horizontal extent comes from the card's own border: the right edge of the
changed area is the card's right border, and scanning left from there, the
first column painted in that border color is the card's left border. Other
windows repainting underneath (focus borders, dimming) can't widen the crop.
"""
import sys

from PIL import Image, ImageChops


def close(a, b, tol=40):
    return all(abs(x - y) <= tol for x, y in zip(a[:3], b[:3]))


def main():
    closed = Image.open(sys.argv[1]).convert("RGB")
    opened = Image.open(sys.argv[2]).convert("RGB")
    diff = ImageChops.difference(closed, opened).convert("L").point(lambda v: 255 if v > 12 else 0)
    box = diff.getbbox()
    if not box:
        sys.exit("no popup found")
    left, top, right, bottom = box
    px = opened.load()

    # The right border column: scan inward from the diff's right edge.
    mid = (top + bottom) // 2
    border_x = right - 1
    border = px[border_x, mid]

    # Follow the right border up and down to the card's real top and bottom;
    # a small allowance covers rounded corners.
    y = mid
    while y > top and close(px[border_x, y - 1], border):
        y -= 1
    top = max(top, y - 12)
    y = mid
    while y < bottom - 1 and close(px[border_x, y + 1], border):
        y += 1
    bottom = min(bottom, y + 13)

    rows = range(top + (bottom - top) // 5, bottom - (bottom - top) // 5)
    card_left = left
    for x in range(border_x - 60, left - 1, -1):
        hits = sum(1 for y in rows if close(px[x, y], border))
        if hits >= 0.95 * len(rows):
            card_left = x
            break

    opened.crop((card_left, top, right, bottom)).save(sys.argv[3])


if __name__ == "__main__":
    main()
