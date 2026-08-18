"""Genera l'icona dell'app / della mod (icon.png, 1024x1024 + varianti).

Design: quadrato scuro arrotondato con la palette della dashboard e tre
barre ascendenti color oro (il leaderboard), con una scheggia "crit" sopra
la barra piu' alta. Disegnata a 4x e ridotta, per bordi puliti.

Uso:
    python tools/make_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

BASE = Path(__file__).resolve().parent.parent
OUT = BASE / "icon.png"

S = 4  # supersampling
SIZE = 1024 * S

BG = (18, 19, 26, 255)          # --bg
PANEL_EDGE = (44, 48, 64, 255)  # --line
GOLD_DIM = (122, 92, 40, 255)   # --accent-soft
GOLD_MID = (183, 138, 66, 255)
GOLD = (212, 160, 74, 255)      # --accent
SPARK = (240, 200, 120, 255)


def rounded(draw: ImageDraw.ImageDraw, box, radius, fill, outline=None, width=0):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def main() -> None:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Sfondo: quadrato arrotondato scuro con bordo appena percettibile.
    m = 40 * S
    rounded(d, (m, m, SIZE - m, SIZE - m), radius=190 * S,
            fill=BG, outline=PANEL_EDGE, width=10 * S)

    # Tre barre ascendenti (leaderboard), arrotondate.
    bar_w = 150 * S
    gap = 60 * S
    total = bar_w * 3 + gap * 2
    x0 = (SIZE - total) // 2
    base_y = SIZE - 240 * S
    heights = (260 * S, 400 * S, 560 * S)
    colors = (GOLD_DIM, GOLD_MID, GOLD)
    for i, (h, c) in enumerate(zip(heights, colors)):
        x = x0 + i * (bar_w + gap)
        rounded(d, (x, base_y - h, x + bar_w, base_y), radius=42 * S, fill=c)

    # Linea di base sotto le barre.
    ly = base_y + 46 * S
    rounded(d, (x0 - 20 * S, ly, x0 + total + 20 * S, ly + 22 * S),
            radius=11 * S, fill=PANEL_EDGE)

    # Scheggia "crit": rombo sopra la barra piu' alta.
    cx = x0 + 2 * (bar_w + gap) + bar_w // 2
    cy = base_y - heights[2] - 110 * S
    r1, r2 = 62 * S, 40 * S
    d.polygon([(cx, cy - r1), (cx + r2, cy), (cx, cy + r1), (cx - r2, cy)], fill=SPARK)

    final = img.resize((1024, 1024), Image.LANCZOS)
    final.save(OUT)
    for size in (512, 256, 64):
        final.resize((size, size), Image.LANCZOS).save(BASE / f"icon_{size}.png")
    print(f"scritte: {OUT.name}, icon_512.png, icon_256.png, icon_64.png")


if __name__ == "__main__":
    main()
