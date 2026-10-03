#!/usr/bin/env python3
"""Generates the detection UI texture atlases (needs ImageMagick's `magick` and rsvg-convert):

  textures/animated_eye_atlas_<size>.png  - the 21 crosshair frames of Stealth Overhaul 2 by Storm Atronach
                                        (https://www.nexusmods.com/morrowind/mods/57321, used with permission),
                                        8 columns x 3 rows, reordered from closed (0) to open (20). Its 128 px frames
                                        are scaled down here to each eye size (96 Big, 72 Medium, 48 Small), so the game
                                        draws them 1:1 instead of shrinking them itself, which looks jagged.
  textures/animated_eye_atlas_<size>_white.png - the same frames turned white, so the game can tint them.
  textures/marker_arrow_atlas.png    - 32 rotations of a triangle, 32x32 each, 8 columns x 4 rows.
                                        Rotation k points at k * 360/32 degrees, clockwise from screen right.

Usage: python3 tools/gen_detection_ui_textures.py [path to Stealth Overhaul 2's Textures/sa_so_ch_128]
Without the path only the arrow atlas is made.
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "scripts", "MaxYari", "SneakIsGoodNow", "textures")

COLUMNS = 8
EYE_FRAMES = 21
EYE_SIZES = (96, 72, 48)  # animated_eye.lua's SIZES
ARROW_DIRECTIONS = 32


def eye_atlas(so2_frames, cell, white):
    rows = -(-EYE_FRAMES // COLUMNS)
    command = ["magick", "-size", f"{cell * COLUMNS}x{cell * rows}", "xc:none"]
    recolor = ["-fill", "white", "-colorize", "100"] if white else []
    for i in range(EYE_FRAMES):
        # Stealth Overhaul's frame 1 is open and 21 closed
        frame = os.path.join(so2_frames, f"{EYE_FRAMES - i}.dds")
        x, y = (i % COLUMNS) * cell, (i // COLUMNS) * cell
        # Scaled in linear light, so the thin lines don't come out darker than they are
        resize = ["-colorspace", "RGB", "-filter", "Lanczos", "-resize", f"{cell}x{cell}", "-colorspace", "sRGB"]
        command += ["(", frame, "-alpha", "on", *recolor, *resize, ")", "-geometry", f"+{x}+{y}", "-composite"]
    path = os.path.join(OUT, f"animated_eye_atlas_{cell}{'_white' if white else ''}.png")
    # PNG32: plain RGBA, ImageMagick would otherwise save white frames as gray + alpha
    subprocess.run(command + ["PNG32:" + path], check=True)
    print("wrote", os.path.relpath(path, ROOT))


def arrow_atlas():
    cell = 32
    rows = ARROW_DIRECTIONS // COLUMNS
    c = cell / 2
    points = f"{c + 11},{c} {c - 7},{c - 9} {c - 7},{c + 9}"
    cells = []
    for k in range(ARROW_DIRECTIONS):
        x, y = (k % COLUMNS) * cell, (k // COLUMNS) * cell
        cells.append(
            f'<g transform="translate({x} {y}) rotate({k * 360 / ARROW_DIRECTIONS} {c} {c})">'
            f'<polygon points="{points}" fill="black" stroke="black" stroke-width="3" stroke-linejoin="round" '
            f'filter="url(#shadow)" opacity="0.6"/>'
            f'<polygon points="{points}" fill="white" stroke="white" stroke-width="1" stroke-linejoin="round"/>'
            f'</g>'
        )
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{cell * COLUMNS}" height="{cell * rows}">'
        f'<defs><filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">'
        f'<feGaussianBlur stdDeviation="1.2"/></filter></defs>'
        f'{"".join(cells)}</svg>'
    )
    path = os.path.join(OUT, "marker_arrow_atlas.png")
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg)
        tmp = f.name
    try:
        subprocess.run(["rsvg-convert", "-o", path, tmp], check=True)
    finally:
        os.remove(tmp)
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        for size in EYE_SIZES:
            eye_atlas(sys.argv[1], size, white=False)
            eye_atlas(sys.argv[1], size, white=True)
    arrow_atlas()
