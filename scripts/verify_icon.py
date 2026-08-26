#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Verifica el contenido visual del ícono generado (colores del diseño)."""
import os
from collections import Counter

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def analyze(rel, step=4):
    path = os.path.join(ROOT, rel)
    img = Image.open(path).convert("RGB")
    W, H = img.size
    px = img.load()
    gold = white = indigo = teal = dark = 0
    cnt = Counter()
    n = 0
    for y in range(0, H, step):
        for x in range(0, W, step):
            r, g, b = px[x, y]
            cnt[(r // 32 * 32, g // 32 * 32, b // 32 * 32)] += 1
            n += 1
            if r > 200 and g > 150 and b < 130:
                gold += 1
            if r > 240 and g > 240 and b > 240:
                white += 1
            if b > 100 and b > r and b > g and r < 130:
                indigo += 1
            if g > 110 and b > 70 and r < 130 and g > r and g >= b:
                teal += 1
            if r < 60 and g < 80 and b < 110:
                dark += 1
    print(f"== {rel} ({W}x{H}) ==")
    print(f"  muestras={n}  gold={gold}  white={white}  indigo={indigo}  teal={teal}  dark={dark}")
    print(f"  top5 colores: {cnt.most_common(5)}")
    return n, gold, white, indigo, teal, dark


def main():
    files = [
        "assets/icons/app_icon_1024.png",
        "assets/icons/feature_graphic_1024x500.png",
        "web/icons/Icon-512.png",
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png",
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png",
    ]
    for f in files:
        analyze(f)
    print("\nVerificación completada.")


if __name__ == "__main__":
    main()
