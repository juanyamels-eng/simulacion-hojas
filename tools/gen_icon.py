#!/usr/bin/env python3
"""Genera el icono original de la app (hoja otoñal sobre fondo de madera cálida)."""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 512
ROOT = os.path.join(os.path.dirname(__file__), "..")


def leaf_points(cx, cy, scale, angle):
    half = [(0, -1), (0.35, -0.55), (0.62, -0.62), (0.5, -0.2), (0.8, 0.05), (0.45, 0.2), (0.4, 0.55), (0.1, 0.45), (0, 0.7)]
    pts = half + [(-x, y) for (x, y) in reversed(half[1:-1])]
    ca, sa = math.cos(angle), math.sin(angle)
    return [(cx + (x * ca - y * sa) * scale, cy + (x * sa + y * ca) * scale) for (x, y) in pts]


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Fondo: degradado cálido redondeado.
    bg = Image.new("RGBA", (S, S))
    bd = ImageDraw.Draw(bg)
    for y in range(S):
        k = y / S
        col = (int(250 - 60 * k), int(170 - 70 * k), int(70 - 30 * k), 255)
        bd.line([(0, y), (S, y)], fill=col)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=110, fill=255)
    img.paste(bg, (0, 0), mask)
    # Hojas pequeñas de fondo.
    for (x, y, s, a, c) in [(110, 120, 70, 0.6, (200, 70, 30)), (410, 140, 60, -0.8, (240, 200, 60)), (120, 400, 55, 2.2, (150, 90, 40))]:
        d.polygon(leaf_points(x, y, s, a), fill=c + (255,))
    # Hoja principal con sombra.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(leaf_points(266, 276, 205, -0.5), fill=(60, 25, 5, 140))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)))
    pts = leaf_points(256, 262, 205, -0.5)
    d.polygon(pts, fill=(235, 110, 30, 255), outline=(120, 50, 15, 255))
    # Nervios.
    ca, sa = math.cos(-0.5), math.sin(-0.5)
    def rot(x, y):
        return (256 + (x * ca - y * sa) * 205, 262 + (x * sa + y * ca) * 205)
    d.line([rot(0, -0.85), rot(0, 0.95)], fill=(130, 50, 15, 255), width=12)
    for (y, x) in [(-0.4, 0.35), (-0.1, 0.5), (0.2, 0.38)]:
        d.line([rot(0, y + 0.15), rot(x, y)], fill=(150, 60, 20, 255), width=7)
        d.line([rot(0, y + 0.15), rot(-x, y)], fill=(150, 60, 20, 255), width=7)
    img.save(os.path.join(ROOT, "icon.png"))
    fg = img.resize((432, 432), Image.LANCZOS)
    canvas = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    canvas.paste(fg, (0, 0))
    os.makedirs(os.path.join(ROOT, "assets", "icon"), exist_ok=True)
    img.resize((192, 192), Image.LANCZOS).save(os.path.join(ROOT, "assets", "icon", "icon_192.png"))
    print("Icono generado")


if __name__ == "__main__":
    main()
