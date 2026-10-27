"""Draws the Tek mark and writes every app icon from it.

    python3 tool/brand/make_icons.py

The mark is an arch over a stem: a "T" that is also a tunnel. Shapes are
drawn at 4x and scaled down, so the edges stay smooth without an SVG
renderer.
"""
import io
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
APP = os.path.join(ROOT, "app")

GREEN_TOP = (34, 212, 134)
GREEN_BOTTOM = (14, 159, 99)
WHITE = (255, 255, 255, 255)

# Mark geometry on a 1024 grid: arch from (256, 400) through control
# (512, 170) to (768, 400), stem from the arch top (512, 285) to (512, 770).
ARCH = ((256, 400), (512, 170), (768, 400))
STEM = ((512, 285), (512, 770))
STROKE = 112


def _bezier(p0, p1, p2, steps=400):
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        yield x, y


def _stroke(draw, points, width, color, scale):
    r = width * scale / 2
    for x, y in points:
        draw.ellipse([x * scale - r, y * scale - r, x * scale + r, y * scale + r], fill=color)


def draw_mark(size, color=WHITE, mark_scale=1.0, offset=(0, 0)):
    """The mark alone on a transparent square of the given size."""
    ss = 4
    big = size * ss
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = big / 1024 * mark_scale
    cx = cy = 512

    def tr(p):
        return ((p[0] - cx) * mark_scale + cx + offset[0], (p[1] - cy) * mark_scale + cy + offset[1])

    arch = [tr(p) for p in _bezier(*ARCH)]
    stem_a, stem_b = tr(STEM[0]), tr(STEM[1])
    stem = [(stem_a[0], stem_a[1] + (stem_b[1] - stem_a[1]) * i / 300) for i in range(301)]
    s = big / 1024
    _stroke(d, arch, STROKE * mark_scale, color, s)
    _stroke(d, stem, STROKE * mark_scale, color, s)
    return img.resize((size, size), Image.LANCZOS)


def gradient(size):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1) or 1)
            px[x, y] = tuple(int(GREEN_TOP[i] + (GREEN_BOTTOM[i] - GREEN_TOP[i]) * t) for i in range(3)) + (255,)
    return img


def rounded_mask(size, radius_ratio=0.2266):
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size * ss - 1, size * ss - 1], radius=int(size * ss * radius_ratio), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def app_icon(size, rounded=True, padding=0.0):
    """Green tile with the white mark. padding shrinks the tile inside the canvas."""
    inner = max(1, round(size * (1 - 2 * padding)))
    tile = gradient(inner)
    if rounded:
        tile.putalpha(rounded_mask(inner))
    tile.alpha_composite(draw_mark(inner, mark_scale=0.86))
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    canvas.alpha_composite(tile, (off, off))
    return canvas


def save(img, *parts):
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path


def main():
    out = []
    # Android launcher icons (legacy) and adaptive layers.
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    res = os.path.join(APP, "android", "app", "src", "main", "res")
    for name, k in densities.items():
        legacy = round(48 * k)
        out.append(save(app_icon(legacy, padding=0.08), res, f"mipmap-{name}", "ic_launcher.png"))
        fg = round(108 * k)
        # The adaptive foreground keeps the mark in the inner 66% safe zone.
        out.append(save(draw_mark(fg, mark_scale=0.62), res, f"mipmap-{name}", "ic_launcher_foreground.png"))
        out.append(save(draw_mark(fg, color=(0, 0, 0, 255), mark_scale=0.62), res, f"mipmap-{name}", "ic_launcher_monochrome.png"))
        # Status bar icon: white on transparent.
        out.append(save(draw_mark(round(24 * k), mark_scale=1.15), res, f"drawable-{name}", "ic_stat_tek.png"))
    os.makedirs(os.path.join(res, "mipmap-anydpi-v26"), exist_ok=True)
    with open(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            '</adaptive-icon>\n')
    os.makedirs(os.path.join(res, "values"), exist_ok=True)
    with open(os.path.join(res, "values", "ic_launcher_background.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                '    <color name="ic_launcher_background">#16BB78</color>\n</resources>\n')

    # Windows: app icon and tray icon.
    ico_sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    big = app_icon(256, padding=0.0)
    ico_path = os.path.join(APP, "windows", "runner", "resources", "app_icon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    big.save(ico_path, sizes=[(s, s) for s in ico_sizes])
    out.append(ico_path)
    tray = os.path.join(APP, "assets", "tray", "tray.ico")
    os.makedirs(os.path.dirname(tray), exist_ok=True)
    app_icon(64).save(tray, sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (48, 48), (64, 64)])
    out.append(tray)

    # macOS: app icon set (Apple's grid leaves ~10% around the tile) and the
    # menu bar template image (black, the system recolours it).
    mac = os.path.join(APP, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for s in [16, 32, 64, 128, 256, 512, 1024]:
        out.append(save(app_icon(s, padding=0.1), mac, f"app_icon_{s}.png"))
    out.append(save(draw_mark(44, color=(0, 0, 0, 255), mark_scale=1.2), APP, "assets", "tray", "tray_template.png"))

    # Brand files for the site and stores.
    brand = os.path.join(ROOT, "docs", "brand")
    out.append(save(app_icon(1024, padding=0.0), brand, "tek-icon-1024.png"))
    out.append(save(app_icon(512, rounded=False), brand, "tek-icon-512-square.png"))
    print("\n".join(os.path.relpath(p, ROOT) for p in out))


if __name__ == "__main__":
    sys.exit(main())
