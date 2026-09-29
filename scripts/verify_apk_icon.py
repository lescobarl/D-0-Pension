#!/usr/bin/env python3
"""Verifica que el APK de release contenga el NUEVO logo (calculadora + $ dorado + destello IA).

Extrae los PNG compilados del APK (nombres ofuscados) y localiza los que tienen la
firma del icono: dimensiones cuadradas (48-432px) + paleta del logo
(indigo/teal/white/gold) SIN esquinas negras.
"""
import io
import os
import sys
import zipfile
from collections import Counter

from PIL import Image

APK = os.path.join("build", "app", "outputs", "flutter-apk", "app-release.apk")


def families(counter, total):
    """Cuenta familias de color con la misma definicion que verify_icon.py."""
    gold = sum(n for (r, g, b), n in counter.items() if r > 200 and g > 150 and b < 130)
    white = sum(n for (r, g, b), n in counter.items() if r > 240 and g > 240 and b > 240)
    indigo = sum(n for (r, g, b), n in counter.items() if b > 100 and b > r and b > g and r < 130)
    teal = sum(n for (r, g, b), n in counter.items() if g > 110 and g > r + 30 and g > b)
    black = sum(n for (r, g, b), n in counter.items() if r < 12 and g < 12 and b < 12)
    return {
        "gold": gold,
        "white": white,
        "indigo": indigo,
        "teal": teal,
        "black": black,
        "total_sampled": total,
    }


def analyze(png_bytes, name):
    img = Image.open(io.BytesIO(png_bytes))
    img = img.convert("RGB")
    w, h = img.size
    step = 4
    pix = img.load()
    total = 0
    c = Counter()
    for y in range(0, h, step):
        for x in range(0, w, step):
            c[pix[x, y]] += 1
            total += 1
    fam = families(c, total)
    top5 = c.most_common(5)
    return w, h, fam, top5


def main():
    if not os.path.exists(APK):
        print("No existe el APK:", APK)
        return 1
    z = zipfile.ZipFile(APK)
    hits = []
    for entry in z.infolist():
        if not entry.filename.startswith("res/") or not entry.filename.endswith(".png"):
            continue
        if ".9.png" in entry.filename:  # 9-patches no son iconos raster simples
            continue
        data = z.read(entry.filename)
        try:
            w, h, fam, top5 = analyze(data, entry.filename)
        except Exception as e:  # noqa: BLE001
            print(f"{entry.filename}: no es PNG valido ({e})")
            continue
        # Firma del logo: cuadrado + paleta con indigo y white significativos,
        # presencia de gold/teal y ausencia de esquinas negras dominantes.
        if w != h:
            continue
        if fam["indigo"] < 5 and fam["white"] < 5:
            continue
        black_ratio = fam["black"] / max(1, fam["total_sampled"])
        if black_ratio > 0.05:
            continue  # esquinas negras -> icono viejo con fondo redondeado
        hits.append((entry.filename, w, h, fam, top5))

    print(f"Total PNGs en APK (no 9-patch): {sum(1 for e in z.infolist() if e.filename.startswith('res/') and e.filename.endswith('.png') and '.9.png' not in e.filename)}")
    print(f"PNGs que coinciden con la firma del logo (cuadrado, indigo+white, sin esquinas negras): {len(hits)}")
    for name, w, h, fam, top5 in sorted(hits, key=lambda t: t[2]):
        pct = {k: round(100 * v / max(1, fam["total_sampled"]), 1) for k, v in fam.items()}
        print(f"  {name}  {w}x{h}  gold={pct['gold']}% white={pct['white']}% indigo={pct['indigo']}% teal={pct['teal']}% black={pct['black']}%  top: {[(tuple(t), n) for t, n in top5[:3]]}")
    z.close()
    return 0 if hits else 1


if __name__ == "__main__":
    sys.exit(main())
