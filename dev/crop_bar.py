#!/usr/bin/env python3
"""Trim a bar screenshot to the widget at its right end.

  crop_bar.py in.png out.png

Scans the bar's inner rows from the left for the first column that differs
from the empty bar background, and keeps everything from there (plus padding)
to the right edge.
"""
import sys

from PIL import Image

PAD = 16


def main():
    im = Image.open(sys.argv[1]).convert("RGB")
    px = im.load()
    w, h = im.size
    mid = h // 2
    bg = px[4, mid]
    rows = range(mid - 8, mid + 9)
    start = 0
    for x in range(w):
        if any(sum(abs(a - b) for a, b in zip(px[x, y], bg)) > 60 for y in rows):
            start = x
            break
    im.crop((max(0, start - PAD), 0, w, h)).save(sys.argv[2])


if __name__ == "__main__":
    main()
