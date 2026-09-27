#!/usr/bin/env python3
"""Print a PNG as ASCII art so its layout can be inspected without eyeballing it.

Uses ImageMagick for decoding, which is what is installed here; there is no
pip, so Pillow is not an option.
"""
import subprocess
import sys

RAMP = " .:-=+*#%@"  # darkest to lightest


def gray_map(path, cols=100):
    """Downsamples to a greyscale byte grid, one byte per character cell."""
    # Read the image size first so the aspect ratio can be preserved.
    out = subprocess.run(
        ["identify", "-format", "%w %h", path], capture_output=True, text=True
    ).stdout.split()
    w, h = int(out[0]), int(out[1])
    rows = max(1, round(cols * h / w * 0.42))  # chars are taller than wide

    raw = subprocess.run(
        ["convert", path, "-resize", f"{cols}x{rows}!", "-colorspace", "Gray",
         "-depth", "8", "gray:-"],
        capture_output=True,
    ).stdout
    return rows, cols, raw


def main():
    path = sys.argv[1]
    cols = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    rows, cols, raw = gray_map(path, cols)
    print(f"{path}  ({rows} rows x {cols} cols)")
    for y in range(rows):
        line = raw[y * cols:(y + 1) * cols]
        print("".join(RAMP[min(len(RAMP) - 1, b * len(RAMP) // 256)] for b in line))


if __name__ == "__main__":
    main()
