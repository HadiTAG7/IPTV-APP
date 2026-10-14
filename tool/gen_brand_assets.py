#!/usr/bin/env python3
"""Generates the Android launcher icons and TV banners from one glyph.

Run from the repo root: python3 tool/gen_brand_assets.py
Needs Pillow with raqm (for the Arabic banner) and the bundled Tajawal font.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'android/app/src/main/res'
FONT = ROOT / 'assets/fonts/Tajawal-Bold.ttf'

SS = 4  # supersampling factor
BG_TOP = (11, 16, 32)  # #0B1020, also @color/ic_launcher_background
BG_BOTTOM = (30, 27, 75)  # #1E1B4B
ACCENT_A = (34, 211, 238)  # #22D3EE
ACCENT_B = (139, 92, 246)  # #8B5CF6
SCREEN = (15, 23, 42)  # #0F172A
WHITE = (248, 250, 252)


def gradient(size, start, end, horizontal=False):
    w, h = size
    grad = Image.new('RGBA', size)
    px = grad.load()
    span = max((w if horizontal else h) - 1, 1)
    for y in range(h):
        for x in range(w):
            t = (x if horizontal else y) / span
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(start, end)) + (255,)
    return grad


def diagonal_gradient(size, start, end):
    w, h = size
    grad = Image.new('RGBA', size)
    px = grad.load()
    span = max(w + h - 2, 1)
    for y in range(h):
        for x in range(w):
            t = (x + y) / span
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(start, end)) + (255,)
    return grad


def glyph(size):
    """TV set with a play triangle, on a transparent square of [size] px."""
    s = size * SS
    mask = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(mask)
    u = s / 100.0
    # Antennas.
    d.line([(50 * u, 22 * u), (34 * u, 6 * u)], fill=255, width=round(5 * u))
    d.line([(50 * u, 22 * u), (66 * u, 6 * u)], fill=255, width=round(5 * u))
    d.ellipse([30 * u, 2 * u, 38 * u, 10 * u], fill=255)
    d.ellipse([62 * u, 2 * u, 70 * u, 10 * u], fill=255)
    # Body and stand.
    d.rounded_rectangle([4 * u, 20 * u, 96 * u, 86 * u], radius=12 * u, fill=255)
    d.rounded_rectangle([30 * u, 90 * u, 70 * u, 96 * u], radius=3 * u, fill=255)
    body = diagonal_gradient((s, s), ACCENT_A, ACCENT_B)
    layer = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    layer.paste(body, (0, 0), mask)

    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([11 * u, 27 * u, 89 * u, 79 * u], radius=7 * u, fill=SCREEN + (255,))
    d.polygon([(42 * u, 39 * u), (42 * u, 67 * u), (66 * u, 53 * u)], fill=WHITE + (255,))
    return layer.resize((size, size), Image.LANCZOS)


def rounded_background(size, radius_ratio):
    s = size * SS
    bg = gradient((s, s), BG_TOP, BG_BOTTOM)
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=s * radius_ratio, fill=255)
    out = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def legacy_icon(size):
    icon = rounded_background(size, 0.22)
    g = glyph(round(size * 0.66))
    off = (size - g.width) // 2
    icon.alpha_composite(g, (off, off))
    return icon


def adaptive_foreground(size):
    # 108dp canvas; keep the glyph inside the 66dp safe zone.
    fg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    g = glyph(round(size * 56 / 108))
    off = (size - g.width) // 2
    fg.alpha_composite(g, (off, off))
    return fg


def banner(lines, rtl):
    w, h = 320, 180
    s_w, s_h = w * SS, h * SS
    img = gradient((s_w, s_h), BG_TOP, BG_BOTTOM, horizontal=True)
    d = ImageDraw.Draw(img)
    g = glyph(104 * SS)
    gx = (s_w - 24 * SS - g.width) if rtl else 24 * SS
    img.alpha_composite(g, (gx, (s_h - g.height) // 2))

    text_left = 24 * SS if rtl else gx + g.width + 14 * SS
    text_right = gx - 14 * SS if rtl else s_w - 18 * SS
    max_w = text_right - text_left
    fonts = []
    for text, px, _ in lines:
        size = px * SS
        while True:
            font = ImageFont.truetype(str(FONT), size, layout_engine=ImageFont.Layout.RAQM)
            box = d.textbbox((0, 0), text, font=font)
            if box[2] - box[0] <= max_w or size <= 12 * SS:
                break
            size -= SS
        fonts.append((font, box))

    gap = 4 * SS
    total = sum(b[3] - b[1] for _, b in fonts) + gap * (len(lines) - 1)
    y = (s_h - total) // 2
    for (text, _, color), (font, box) in zip(lines, fonts):
        tw = box[2] - box[0]
        x = text_right - tw if rtl else text_left
        d.text((x - box[0], y - box[1]), text, font=font, fill=color + (255,))
        y += box[3] - box[1] + gap
    return img.resize((w, h), Image.LANCZOS).convert('RGB')


def save(img, rel):
    path = RES / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f'{rel} {img.size[0]}x{img.size[1]}')


def main():
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, scale in densities.items():
        save(legacy_icon(round(48 * scale)), f'mipmap-{name}/ic_launcher.png')
        save(adaptive_foreground(round(108 * scale)), f'drawable-{name}/ic_launcher_foreground.png')
    save(banner([('IPTV', 50, ACCENT_A), ('Player', 38, WHITE)], rtl=False), 'drawable-xhdpi/banner.png')
    save(banner([('مشغّل', 46, WHITE), ('IPTV', 44, ACCENT_A)], rtl=True), 'drawable-ar-xhdpi/banner.png')


if __name__ == '__main__':
    main()
