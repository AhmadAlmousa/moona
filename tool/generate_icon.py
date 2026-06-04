#!/usr/bin/env python3
"""Generate the Moona app icon set with Pillow (supersampled for crisp edges).

Design: the Moona green gradient, a bold "M" monogram, and a shopping cart
carrying a checklist (the "shopping list"). Outputs:
  assets/icon/moona_icon.png             1024 full-bleed square (iOS / legacy / web)
  assets/icon/moona_icon_foreground.png  1024 transparent emblem (Android adaptive)
"""
from PIL import Image, ImageDraw, ImageFilter

OUT = "assets/icon"
SS = 4                      # supersample factor
R = 1024 * SS              # render resolution

# Brand palette
GREEN_TOP = (46, 184, 124)     # #2EB87C
GREEN_BOT = (13, 116, 71)      # #0D7447
WHITE = (255, 255, 255)
MINT = (183, 242, 206)         # #B7F2CE
DEEP = (8, 80, 49)             # check glyph / shadow tint


def U(f):  # fraction (0..1) -> render pixels
    return f * R


def gradient_square(size, c1, c2):
    base = Image.new("RGB", (size, size), c1)
    top = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        top.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(c1, c2)))
    return top.resize((size, size))


def draw_emblem(scale=1.0, dy=0.0):
    """Return an RGBA layer (R x R) with the M + cart + checklist, white/mint."""
    layer = Image.new("RGBA", (R, R), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    cx = 0.5
    sw = 0.060 * scale          # primary stroke width
    def w(v):
        return max(1, round(v * R))

    def sx(f):  # scale a fraction around center x and apply dy
        return U(cx + (f - cx) * scale)
    def sy(f):
        return U((f + dy) * 1.0 if False else (0.5 + (f - 0.5) * scale + dy))

    # ---- M monogram (top) -------------------------------------------------
    mtop, mbot = 0.150, 0.380
    mxl, mxr = 0.330, 0.670
    mid_y = 0.300
    m_pts = [
        (sx(mxl), sy(mbot)),
        (sx(mxl), sy(mtop)),
        (sx(0.5), sy(mid_y)),
        (sx(mxr), sy(mtop)),
        (sx(mxr), sy(mbot)),
    ]
    d.line(m_pts, fill=WHITE, width=w(sw * 1.05), joint="curve")
    for (x, y) in [m_pts[0], m_pts[1], m_pts[3], m_pts[4]]:
        rr = w(sw * 1.05) / 2
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=WHITE)

    # ---- Shopping cart (lower) -------------------------------------------
    cs = w(sw)                                  # cart stroke
    # handle: up-left stub into the basket top-left
    hx0, hy0 = 0.150, 0.470
    btl_x, btl_y = 0.300, 0.470                 # basket top-left
    btr_x, btr_y = 0.760, 0.470                 # basket top-right
    bbl_x, bbl_y = 0.360, 0.660                 # basket bottom-left
    bbr_x, bbr_y = 0.700, 0.660                 # basket bottom-right
    d.line([(sx(hx0), sy(hy0)), (sx(btl_x), sy(btl_y))], fill=WHITE,
           width=cs, joint="curve")
    # basket outline (trapezoid)
    basket = [(sx(btl_x), sy(btl_y)), (sx(btr_x), sy(btr_y)),
              (sx(bbr_x), sy(bbr_y)), (sx(bbl_x), sy(bbl_y)), (sx(btl_x), sy(btl_y))]
    d.line(basket, fill=WHITE, width=cs, joint="curve")
    for (fx, fy) in [(btl_x, btl_y), (btr_x, btr_y), (bbr_x, bbr_y), (bbl_x, bbl_y)]:
        rr = cs / 2
        d.ellipse([sx(fx) - rr, sy(fy) - rr, sx(fx) + rr, sy(fy) + rr], fill=WHITE)
    # legs to wheels
    d.line([(sx(bbl_x), sy(bbl_y)), (sx(0.40), sy(0.720))], fill=WHITE, width=cs)
    d.line([(sx(bbr_x), sy(bbr_y)), (sx(0.66), sy(0.720))], fill=WHITE, width=cs)
    # wheels
    for wxf in (0.40, 0.66):
        rr = w(0.045 * scale)
        d.ellipse([sx(wxf) - rr, sy(0.770) - rr, sx(wxf) + rr, sy(0.770) + rr], fill=WHITE)

    # ---- Checklist inside the basket -------------------------------------
    rows = [(0.520, 0.300), (0.575, 0.260), (0.630, 0.300)]
    bar_x = 0.470
    bar_h = 0.026 * scale
    for i, (ry, rw) in enumerate(rows):
        # check tick (mint) at the row start
        tx, ty = sx(bar_x - 0.040), sy(ry)
        ts = w(0.018 * scale)
        d.line([(tx - ts, ty), (tx - ts * 0.2, ty + ts), (tx + ts, ty - ts)],
               fill=MINT, width=w(0.013 * scale), joint="curve")
        # the list line bar
        x0 = sx(bar_x)
        x1 = sx(bar_x + rw * 0.6)
        yy = sy(ry)
        hh = w(bar_h)
        d.rounded_rectangle([x0, yy - hh / 2, x1, yy + hh / 2], radius=hh / 2,
                            fill=(255, 255, 255, 235))
    return layer


def soft_shadow(emblem):
    a = emblem.split()[3]
    sh = Image.new("RGBA", emblem.size, (0, 0, 0, 0))
    tint = Image.new("RGBA", emblem.size, DEEP + (255,))
    sh.paste(tint, (0, 0), a)
    sh = sh.filter(ImageFilter.GaussianBlur(radius=R * 0.012))
    # reduce opacity
    r, g, b, al = sh.split()
    al = al.point(lambda v: int(v * 0.35))
    sh = Image.merge("RGBA", (r, g, b, al))
    off = round(R * 0.012)
    shifted = Image.new("RGBA", emblem.size, (0, 0, 0, 0))
    shifted.paste(sh, (0, off))
    return shifted


def main():
    # --- full-bleed icon (iOS / web / legacy) ---
    bg = gradient_square(R, GREEN_TOP, GREEN_BOT).convert("RGBA")
    # subtle top sheen
    sheen = Image.new("RGBA", (R, R), (0, 0, 0, 0))
    ds = ImageDraw.Draw(sheen)
    ds.ellipse([-R * 0.3, -R * 0.55, R * 1.3, R * 0.45], fill=(255, 255, 255, 26))
    bg = Image.alpha_composite(bg, sheen)

    emblem = draw_emblem(scale=1.0)
    bg = Image.alpha_composite(bg, soft_shadow(emblem))
    bg = Image.alpha_composite(bg, emblem)
    icon = bg.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    icon.save(f"{OUT}/moona_icon.png")

    # --- Android adaptive foreground ---
    # flutter_launcher_icons adds a 16% inset, so render the emblem larger here
    # (it lands inside the adaptive safe zone after that inset).
    fg = draw_emblem(scale=1.30).resize((1024, 1024), Image.LANCZOS)
    fg.save(f"{OUT}/moona_icon_foreground.png")

    print("wrote", f"{OUT}/moona_icon.png", "and moona_icon_foreground.png")


if __name__ == "__main__":
    main()
