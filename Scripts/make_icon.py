#!/usr/bin/env python3
import math
import os
import shutil
import subprocess
import sys
import tempfile
from PIL import Image, ImageDraw, ImageFilter


def lerp(a, b, t):
    return int(a + (b - a) * t)


def gradient(size):
    top = (26, 31, 63)
    mid = (12, 116, 132)
    bottom = (18, 125, 92)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        if t < 0.58:
            k = t / 0.58
            c = tuple(lerp(top[i], mid[i], k) for i in range(3))
        else:
            k = (t - 0.58) / 0.42
            c = tuple(lerp(mid[i], bottom[i], k) for i in range(3))
        for x in range(size):
            radial = math.hypot((x - size * 0.2) / size, (y - size * 0.15) / size)
            glow = max(0, 1 - radial * 2.4)
            cc = tuple(min(255, int(c[i] + glow * 44)) for i in range(3))
            px[x, y] = (*cc, 255)
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_icon(size=1024):
    scale = size / 1024
    base = gradient(size)
    mask = rounded_mask(size, int(220 * scale))
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(base, (0, 0), mask)
    d = ImageDraw.Draw(icon)

    for i in range(7):
        y = int((150 + i * 88) * scale)
        alpha = int(34 - i * 3)
        d.line((int(110 * scale), y, int(914 * scale), y), fill=(255, 255, 255, alpha), width=max(1, int(2 * scale)))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        (int(218 * scale), int(520 * scale), int(806 * scale), int(694 * scale)),
        radius=int(38 * scale),
        fill=(0, 0, 0, 120),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(30 * scale)))
    icon.alpha_composite(shadow)

    d = ImageDraw.Draw(icon)
    screen = (int(250 * scale), int(360 * scale), int(774 * scale), int(632 * scale))
    d.rounded_rectangle(screen, radius=int(42 * scale), fill=(235, 244, 246, 245))
    inset = int(28 * scale)
    d.rounded_rectangle(
        (screen[0] + inset, screen[1] + inset, screen[2] - inset, screen[3] - inset),
        radius=int(26 * scale),
        fill=(21, 35, 62, 255),
    )

    body = (int(196 * scale), int(634 * scale), int(828 * scale), int(710 * scale))
    d.rounded_rectangle(body, radius=int(34 * scale), fill=(226, 238, 241, 255))
    d.rounded_rectangle(
        (int(386 * scale), int(642 * scale), int(638 * scale), int(666 * scale)),
        radius=int(12 * scale),
        fill=(164, 182, 191, 255),
    )

    center = (int(512 * scale), int(555 * scale))
    arc_color = (85, 234, 209, 255)
    for radius, width, alpha in [(230, 36, 255), (158, 34, 235), (88, 32, 215)]:
        r = int(radius * scale)
        bbox = (center[0] - r, center[1] - r, center[0] + r, center[1] + r)
        d.arc(bbox, start=210, end=330, fill=(arc_color[0], arc_color[1], arc_color[2], alpha), width=int(width * scale))
    d.ellipse(
        (
            int(482 * scale),
            int(570 * scale),
            int(542 * scale),
            int(630 * scale),
        ),
        fill=(255, 211, 105, 255),
    )

    d.rounded_rectangle(
        (int(642 * scale), int(208 * scale), int(820 * scale), int(326 * scale)),
        radius=int(58 * scale),
        fill=(255, 255, 255, 46),
        outline=(255, 255, 255, 86),
        width=int(4 * scale),
    )
    d.ellipse((int(722 * scale), int(236 * scale), int(788 * scale), int(302 * scale)), fill=(255, 211, 105, 255))

    shine = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    sd.rounded_rectangle(
        (int(82 * scale), int(74 * scale), int(942 * scale), int(382 * scale)),
        radius=int(190 * scale),
        fill=(255, 255, 255, 26),
    )
    icon.alpha_composite(shine)
    return icon


def main():
    if len(sys.argv) != 2:
        print("usage: make_icon.py /path/AppIcon.icns", file=sys.stderr)
        return 64
    output = os.path.abspath(sys.argv[1])
    source_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Resources", "AppIconSource.png"))
    temp = tempfile.mkdtemp(prefix="keepgoing-icon.")
    iconset = os.path.join(temp, "AppIcon.iconset")
    os.makedirs(iconset)
    if os.path.exists(source_path):
        source = Image.open(source_path).convert("RGBA")
        source.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        canvas.alpha_composite(source, ((1024 - source.width) // 2, (1024 - source.height) // 2))
        source = canvas
    else:
        source = draw_icon(1024)
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, pixels in sizes:
        source.resize((pixels, pixels), Image.Resampling.LANCZOS).save(os.path.join(iconset, name))
    subprocess.run(["/usr/bin/iconutil", "-c", "icns", iconset, "-o", output], check=True)
    shutil.rmtree(temp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
