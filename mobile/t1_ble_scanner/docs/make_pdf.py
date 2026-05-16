"""
Generate a PDF product-page for T1 BLE Scanner.
Layout: A4 portrait, 3 screenshots per row × 2 rows, dark-branded header + captions.
Run:  python docs/make_pdf.py
Output: docs/T1_BLE_Scanner_Product.pdf
"""

from PIL import Image, ImageDraw, ImageFont
import os, sys, textwrap

# ── paths ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SS_DIR = os.path.join(SCRIPT_DIR, "screenshots")
OUT_PDF = os.path.join(SCRIPT_DIR, "T1_BLE_Scanner_Product.pdf")

# ── page geometry (A4 portrait @ 150 dpi) ─────────────────────────────────────
DPI = 150
PAGE_W = int(210 * DPI / 25.4)   # 1240 px
PAGE_H = int(297 * DPI / 25.4)   # 1754 px

MARGIN     = 44
COL_GAP    = 18
ROW_GAP    = 32
HEADER_H   = 170
CAPTION_H  = 72
COLS       = 3

# screenshot crop: keep top 1700 px of 2400 (hide bottom nav bar area)
CROP_H = 1700

AVAIL_W = PAGE_W - 2 * MARGIN
THUMB_W = (AVAIL_W - (COLS - 1) * COL_GAP) // COLS
THUMB_H = int(THUMB_W * CROP_H / 1080)

# ── colours ───────────────────────────────────────────────────────────────────
BG          = (7, 22, 40)          # #071628
CARD_BG     = (15, 23, 42)        # #0F172A
ACCENT      = (0, 196, 255)        # #00C4FF  (light blue)
GREEN       = (0, 255, 135)        # #00FF87
WHITE       = (255, 255, 255)
WHITE54     = (138, 148, 163)
DIVIDER     = (27, 58, 92)        # #1B3A5C

# ── fonts (Windows system fonts, Cyrillic-capable) ───────────────────────────
FONT_DIR = "C:\\Windows\\Fonts"

def load(name, size):
    for n in (name, "arialuni", "arial", "calibri", "segoeui"):
        try:
            return ImageFont.truetype(os.path.join(FONT_DIR, n + ".ttf"), size)
        except Exception:
            pass
    return ImageFont.load_default()

F_TITLE    = load("arialbd",  40)
F_TAGLINE  = load("arial",    18)
F_LABEL    = load("arialbd",  15)
F_CAPTION  = load("arial",    13)
F_FOOTER   = load("arial",    11)

# ── screenshot metadata ───────────────────────────────────────────────────────
SCREENS = [
    ("01_radar.png",
     "Радар",
     "Живой BLE-радар. Метки T1 расшифровываются локально "
     "по AES-128 и показываются зелёным. Другие операторы — своим цветом."),

    ("02_list.png",
     "Список устройств",
     "Детальная карточка каждого бикона: UUID, major/minor, "
     "расшифрованный слот, derived MAC и название остановки."),

    ("03_stops.png",
     "Справочник остановок",
     "Редактируемый справочник TagID → название. "
     "Поиск по ID или тексту. Данные сохраняются между сессиями."),

    ("04_operators.png",
     "Операторы UUID",
     "Реестр UUID-операторов с цветовой маркировкой. "
     "Каждый оператор получает уникальный цвет на радаре."),

    ("05_settings.png",
     "Настройки сканирования",
     "AES-128 ключ, режим Prototype / Production, "
     "диапазон TagID и параметры временного слота."),

    ("06_operator_edit.png",
     "Выбор цвета",
     "Интерактивный выбор цвета для оператора: "
     "12 вариантов, отображаемых на тёмном радарном поле."),
]

# ── helpers ───────────────────────────────────────────────────────────────────

def multiline(draw, text, xy, font, fill, max_width, line_height=None):
    """Wrap text to max_width pixels and draw it."""
    if line_height is None:
        line_height = font.size + 4
    words = text.split()
    lines, current = [], []
    for w in words:
        test = ' '.join(current + [w])
        bbox = draw.textbbox((0, 0), test, font=font)
        if bbox[2] - bbox[0] > max_width and current:
            lines.append(' '.join(current))
            current = [w]
        else:
            current.append(w)
    if current:
        lines.append(' '.join(current))
    x, y = xy
    for line in lines:
        draw.text((x, y), line, font=font, fill=fill)
        y += line_height
    return y

# ── build page ────────────────────────────────────────────────────────────────

page = Image.new("RGB", (PAGE_W, PAGE_H), BG)
draw = ImageDraw.Draw(page)

# header background strip
draw.rectangle([0, 0, PAGE_W, HEADER_H], fill=CARD_BG)
draw.rectangle([0, HEADER_H, PAGE_W, HEADER_H + 2], fill=ACCENT)

# logo dot + title
dot_r = 14
dot_cx = MARGIN + dot_r
dot_cy = HEADER_H // 2
draw.ellipse([dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r], fill=GREEN)

title = "T1 BLE Scanner"
draw.text((MARGIN + dot_r * 2 + 10, dot_cy - 26), title, font=F_TITLE, fill=WHITE)

tagline = (
    "Мобильное приложение для сканирования BLE-меток транспортной системы T1. "
    "Локальное AES-128 дешифрование, радар-вид, справочники остановок и операторов."
)
multiline(draw, tagline,
          (MARGIN + dot_r * 2 + 10, dot_cy + 20),
          F_TAGLINE, WHITE54, PAGE_W - MARGIN * 2 - dot_r * 2 - 10)

# screenshots grid
y_start = HEADER_H + 28
for row in range(2):
    for col in range(COLS):
        idx = row * COLS + col
        if idx >= len(SCREENS):
            break
        fname, label, caption = SCREENS[idx]

        x = MARGIN + col * (THUMB_W + COL_GAP)
        y = y_start + row * (THUMB_H + CAPTION_H + ROW_GAP)

        # load + crop + resize screenshot
        path = os.path.join(SS_DIR, fname)
        try:
            img = Image.open(path).convert("RGB")
            w, h = img.size
            # crop to CROP_H from top
            crop_h = min(CROP_H, h)
            img = img.crop((0, 0, w, crop_h))
            img = img.resize((THUMB_W, THUMB_H), Image.LANCZOS)
        except Exception as e:
            print(f"  Warning: could not open {fname}: {e}")
            img = Image.new("RGB", (THUMB_W, THUMB_H), CARD_BG)

        # phone frame: rounded rect border
        draw.rounded_rectangle(
            [x - 3, y - 3, x + THUMB_W + 3, y + THUMB_H + 3],
            radius=14, outline=DIVIDER, width=2
        )
        page.paste(img, (x, y))

        # label (bold)
        draw.text((x, y + THUMB_H + 8), label, font=F_LABEL, fill=ACCENT)

        # caption
        multiline(draw, caption,
                  (x, y + THUMB_H + 8 + F_LABEL.size + 4),
                  F_CAPTION, WHITE54, THUMB_W, line_height=16)

# footer
footer_y = PAGE_H - 28
draw.rectangle([0, footer_y - 12, PAGE_W, PAGE_H], fill=CARD_BG)
draw.text((MARGIN, footer_y - 6),
          "T1 BLE Scanner  ·  Android  ·  AES-128 локальная дешифровка  ·  Flutter",
          font=F_FOOTER, fill=WHITE54)

# ── save as PDF ───────────────────────────────────────────────────────────────
page.save(OUT_PDF, "PDF", resolution=DPI)
print(f"Saved: {OUT_PDF}")
print(f"  Page size: {PAGE_W} x {PAGE_H} px  ({DPI} dpi)")
