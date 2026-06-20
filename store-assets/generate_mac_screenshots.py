#!/usr/bin/env python3
"""
Generate macOS App Store screenshots (2560×1600) from existing drone footage images.
Composites each image onto a simulated macOS desktop with a menu bar.
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, math

# ── constants ──────────────────────────────────────────────────────────────
W, H          = 2560, 1600
MENUBAR_H     = 48          # px at 2x (24pt)
FONT_REGULAR  = "/Library/Fonts/SF-Pro-Display-Regular.otf"
FONT_MEDIUM   = "/Library/Fonts/SF-Pro-Display-Medium.otf"
FONT_SEMIBOLD = "/Library/Fonts/SF-Pro-Display-Semibold.otf"

SCREENSHOTS_DIR = os.path.dirname(__file__) + "/screenshots"
OUT_DIR         = os.path.dirname(__file__) + "/mac-screenshots"
os.makedirs(OUT_DIR, exist_ok=True)

# ── each screenshot: source image, video caption, output name ──────────────
SHOTS = [
    ("01-valencia.png",       "Old Valencia, Spain",          "01-valencia"),
    ("02-patagonia.png",      "Patagonia, Argentina",         "02-patagonia"),
    ("03-redrocks.png",       "Red Rocks Amphitheatre, CO",   "03-redrocks"),
    ("04-goldengate.png",     "Golden Gate Bridge, SF",       "04-goldengate"),
    ("05-neuschwanstein.png", "Neuschwanstein Castle, DE",    "05-neuschwanstein"),
    ("06-yosemite.png",       "Yosemite Valley, CA",          "06-yosemite"),
]

# ── helpers ─────────────────────────────────────────────────────────────────

def load_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size)


CAPTION_CROP_PX = 80  # pixels to trim from bottom of source to remove burned-in caption

def scale_fill(img: Image.Image, w: int, h: int) -> Image.Image:
    """Scale image to fill w×h, center-crop. Trims bottom first to remove burned-in caption."""
    img = img.crop((0, 0, img.width, img.height - CAPTION_CROP_PX))
    ratio = max(w / img.width, h / img.height)
    new_w = round(img.width * ratio)
    new_h = round(img.height * ratio)
    img = img.resize((new_w, new_h), Image.LANCZOS)
    left = (new_w - w) // 2
    top  = (new_h - h) // 2
    return img.crop((left, top, left + w, top + h))


def rounded_rect(draw, xy, radius, fill, outline=None, outline_width=1):
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill,
                           outline=outline, width=outline_width)


def draw_menubar(canvas: Image.Image, caption: str):
    """Draw a macOS-style menu bar with the app's status menu icon."""
    draw = ImageDraw.Draw(canvas, "RGBA")

    # Dark translucent bar
    bar = Image.new("RGBA", (W, MENUBAR_H), (20, 20, 20, 210))
    canvas.paste(bar, (0, 0), bar)

    # ── fonts ──
    f_reg  = load_font(FONT_REGULAR,  26)
    f_med  = load_font(FONT_MEDIUM,   26)
    f_semi = load_font(FONT_SEMIBOLD, 28)

    draw = ImageDraw.Draw(canvas)
    y_mid = MENUBAR_H // 2

    # Apple  logo (unicode approximation)
    draw.text((20, y_mid), "", font=load_font(FONT_SEMIBOLD, 28),
              fill=(255, 255, 255, 255), anchor="lm")

    # Left menu items
    menu_items = ["Finder", "File", "Edit", "View", "Go", "Window", "Help"]
    x = 60
    for item in menu_items:
        draw.text((x, y_mid), item, font=f_reg,
                  fill=(255, 255, 255, 220), anchor="lm")
        bbox = draw.textbbox((0, 0), item, font=f_reg)
        x += (bbox[2] - bbox[0]) + 28

    # Right side: time + wifi + battery glyphs (unicode)
    right_items = ["⌨", "Wi-Fi", "11:42 AM"]
    x_r = W - 20
    for item in reversed(right_items):
        bbox = draw.textbbox((0, 0), item, font=f_reg)
        iw = bbox[2] - bbox[0]
        draw.text((x_r - iw, y_mid), item, font=f_reg,
                  fill=(255, 255, 255, 200), anchor="lm")
        x_r -= iw + 24

    # App status icon — play.rectangle glyph area (simple filled rect icon)
    icon_size = 28
    ix = x_r - icon_size - 8
    iy = (MENUBAR_H - icon_size) // 2
    # Draw a small "▶▭" style icon
    draw.rounded_rectangle(
        [ix, iy, ix + icon_size, iy + icon_size],
        radius=4, fill=(255, 255, 255, 220)
    )
    # Play triangle inside
    tri = [(ix + 8, iy + 7), (ix + icon_size - 6, iy + icon_size // 2),
           (ix + 8, iy + icon_size - 7)]
    draw.polygon(tri, fill=(20, 20, 20, 240))

    return ix + icon_size // 2   # return icon center x


def draw_dropdown(canvas: Image.Image, anchor_x: int, caption: str):
    """Draw the status-menu dropdown showing video name + controls."""
    draw = ImageDraw.Draw(canvas, "RGBA")

    f_caption = load_font(FONT_MEDIUM,   28)
    f_item    = load_font(FONT_REGULAR,  26)
    f_hint    = load_font(FONT_REGULAR,  22)

    PAD_X, PAD_Y = 28, 16
    ITEM_H = 44
    SEP_H  = 12
    menu_w = 420

    rows = [
        ("caption", caption),
        ("sep",     None),
        ("item",    ("Previous", "⌃⌥←")),
        ("item",    ("Next",     "⌃⌥→")),
        ("item",    ("Pause",    "⌃⌥Space")),
        ("sep",     None),
        ("item",    ("Quit",     "⌘Q")),
    ]

    # Measure height
    menu_h = PAD_Y * 2
    for kind, _ in rows:
        menu_h += SEP_H if kind == "sep" else ITEM_H

    # Position: below menu bar, aligned to icon
    mx = min(max(anchor_x - menu_w + 40, 8), W - menu_w - 8)
    my = MENUBAR_H + 6

    # Shadow
    shadow = Image.new("RGBA", (menu_w + 40, menu_h + 40), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([20, 20, menu_w + 20, menu_h + 20],
                         radius=14, fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    canvas.paste(shadow, (mx - 20, my - 20), shadow)

    # Menu background
    menu_img = Image.new("RGBA", (menu_w, menu_h), (0, 0, 0, 0))
    md = ImageDraw.Draw(menu_img)
    md.rounded_rectangle([0, 0, menu_w, menu_h], radius=14,
                         fill=(36, 36, 36, 245))
    canvas.paste(menu_img, (mx, my), menu_img)

    # Draw rows
    draw = ImageDraw.Draw(canvas)
    cy = my + PAD_Y
    for kind, data in rows:
        if kind == "sep":
            draw.line([(mx + 8, cy + SEP_H // 2),
                       (mx + menu_w - 8, cy + SEP_H // 2)],
                      fill=(80, 80, 80, 160), width=1)
            cy += SEP_H
        elif kind == "caption":
            draw.text((mx + PAD_X, cy + ITEM_H // 2), data,
                      font=f_caption, fill=(160, 160, 160, 255), anchor="lm")
            cy += ITEM_H
        else:
            label, hint = data
            draw.text((mx + PAD_X, cy + ITEM_H // 2), label,
                      font=f_item, fill=(240, 240, 240, 255), anchor="lm")
            hint_bbox = draw.textbbox((0, 0), hint, font=f_hint)
            hw = hint_bbox[2] - hint_bbox[0]
            draw.text((mx + menu_w - PAD_X - hw, cy + ITEM_H // 2), hint,
                      font=f_hint, fill=(140, 140, 140, 255), anchor="lm")
            cy += ITEM_H


# ── main ────────────────────────────────────────────────────────────────────

def make_screenshot(src_name: str, caption: str, out_stem: str,
                    show_menu: bool = False):
    src_path = os.path.join(SCREENSHOTS_DIR, src_name)
    img = Image.open(src_path).convert("RGBA")
    canvas = scale_fill(img, W, H)

    icon_x = draw_menubar(canvas, caption)
    if show_menu:
        draw_dropdown(canvas, icon_x, caption)

    out_name = f"{out_stem}{'_menu' if show_menu else ''}.png"
    out_path = os.path.join(OUT_DIR, out_name)
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"  saved {out_name}")


if __name__ == "__main__":
    print(f"Generating macOS App Store screenshots → {OUT_DIR}/")

    for src, caption, stem in SHOTS:
        make_screenshot(src, caption, stem, show_menu=False)

    # Also generate a menu-open variant for the first two
    for src, caption, stem in SHOTS[:2]:
        make_screenshot(src, caption, stem, show_menu=True)

    print("Done.")
