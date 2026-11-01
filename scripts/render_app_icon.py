"""Render the studio's geometric waveform mark. Requires Pillow; no fonts or remote assets."""
from math import cos, pi, sqrt
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE, SCALE = 1024, 3
MINT = (146, 248, 186)
image = Image.new("RGB", (SIZE, SIZE))
pixels = image.load()
for y in range(SIZE):
    for x in range(SIZE):
        glow = max(0, 1 - sqrt(((x - 340) / 900) ** 2 + ((y - 320) / 900) ** 2))
        pixels[x, y] = (int(9 + 8 * glow), int(15 + 20 * glow), int(20 + 17 * glow))
image = image.resize((SIZE * SCALE, SIZE * SCALE), Image.Resampling.BICUBIC)
draw = ImageDraw.Draw(image)


def line(points, fill, width):
    points = [(round(x * SCALE), round(y * SCALE)) for x, y in points]
    draw.line(points, fill=fill, width=round(width * SCALE), joint="curve")
    r = width * SCALE / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


# Subtle staff lines anchor the curve without becoming small-size visual noise.
for y in (352, 512, 672):
    line([(176, y), (848, y)], (31, 51, 51), 3)

# A single generous cycle reads clearly at Home Screen sizes.
points = [(180 + 664 * i / 600, 512 - 178 * cos(2 * pi * i / 600)) for i in range(601)]
halo = Image.new("RGB", image.size, (0, 0, 0))
halo_draw = ImageDraw.Draw(halo)
halo_draw.line([(int(x * SCALE), int(y * SCALE)) for x, y in points], fill=(35, 72, 53), width=64 * SCALE)
halo = halo.filter(ImageFilter.GaussianBlur(18 * SCALE))
from PIL import ImageChops
image = ImageChops.add(image, halo)
draw = ImageDraw.Draw(image)
line(points, MINT, 36)

# The tracking dot sits precisely on the same curve at 3/4 progress.
cx, cy = 180 + 664 * 0.75, 512 - 178 * cos(2 * pi * 0.75)
for radius, color in [(52, (16, 31, 31)), (36, MINT), (13, (230, 255, 239))]:
    draw.ellipse(((cx - radius) * SCALE, (cy - radius) * SCALE,
                  (cx + radius) * SCALE, (cy + radius) * SCALE), fill=color)
image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
destination = Path(__file__).resolve().parents[1] / "MathBeatStudio/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
image.save(destination)
assert image.mode == "RGB"  # App Store icons must be opaque.
print(destination)
