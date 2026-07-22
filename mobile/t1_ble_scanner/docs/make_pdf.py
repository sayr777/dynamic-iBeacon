"""
Generate PDF product page for T1 BLE Scanner using ReportLab.
Run:  python docs/make_pdf.py
Out:  docs/T1_BLE_Scanner_Product.pdf
"""
import os
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from PIL import Image as PILImage

# ── paths ──────────────────────────────────────────────────────────────────────
DOCS = os.path.dirname(os.path.abspath(__file__))
SS   = os.path.join(DOCS, "screenshots")
OUT  = os.path.join(DOCS, "T1_BLE_Scanner_Product.pdf")

# ── register Cyrillic-capable fonts ───────────────────────────────────────────
FD = "C:\\Windows\\Fonts"
for alias, fname in [
    ("Arial",   "arial.ttf"),
    ("ArialBd", "arialbd.ttf"),
]:
    try:
        pdfmetrics.registerFont(TTFont(alias, os.path.join(FD, fname)))
    except Exception:
        pass   # fall back to Helvetica below

def font(bold=False):
    name = "ArialBd" if bold else "Arial"
    try:
        pdfmetrics.getFont(name)
        return name
    except Exception:
        return "Helvetica-Bold" if bold else "Helvetica"

# ── page geometry (A4 portrait, points) ───────────────────────────────────────
PW, PH = A4          # 595.27 × 841.89 pt
M       = 22         # margin pt
GAP_H   = 10         # horizontal gap between columns
GAP_V   = 14         # vertical gap between rows
COLS    = 3
HDR_H   = 72         # header strip height
CAP_H   = 38         # caption zone height
CROP_H  = 1700       # crop phone screenshots to this height (px)
CROP_W  = 1080

col_w   = (PW - 2*M - (COLS-1)*GAP_H) / COLS
thumb_h = col_w * CROP_H / CROP_W

# ── palette ───────────────────────────────────────────────────────────────────
BG      = colors.Color(7/255,  22/255,  40/255)
CARD    = colors.Color(15/255, 23/255,  42/255)
DIVIDER = colors.Color(27/255, 58/255,  92/255)
ACCENT  = colors.Color(0,      196/255, 1)
GREEN   = colors.Color(0,      1,       135/255)
WHITE   = colors.white
DIM     = colors.Color(138/255, 148/255, 163/255)

# ── screen metadata ────────────────────────────────────────────────────────────
SCREENS = [
    ("01_radar.png",
     "Радар",
     "Живой BLE-радар. T1-метки расшифровываются локально (AES-128) "
     "и отображаются зелёным. Другие операторы — своим цветом."),
    ("02_list.png",
     "Список устройств",
     "Детальные карточки: UUID, major/minor, derived MAC, "
     "слот, стартовое время и название остановки."),
    ("03_stops.png",
     "Справочник остановок",
     "Редактируемый справочник TagID → название. "
     "Поиск, сохранение между сессиями."),
    ("04_operators.png",
     "Операторы UUID",
     "Реестр UUID-операторов. Каждый оператор "
     "получает свой цвет точки на радаре."),
    ("05_settings.png",
     "Настройки",
     "AES-128 ключ, режим Prototype / Production, "
     "диапазон TagID и размер окна слота."),
    ("06_operator_edit.png",
     "Выбор цвета",
     "12 цветов на выбор для отображения "
     "меток оператора на радаре."),
]

# ── build PDF ─────────────────────────────────────────────────────────────────
c = canvas.Canvas(OUT, pagesize=A4)
c.setTitle("T1 BLE Scanner — Product Overview")
c.setAuthor("T1")
c.setSubject("BLE Scanner for T1 Transport System")

# background
c.setFillColor(BG)
c.rect(0, 0, PW, PH, fill=1, stroke=0)

# ── header ────────────────────────────────────────────────────────────────────
c.setFillColor(CARD)
c.rect(0, PH - HDR_H, PW, HDR_H, fill=1, stroke=0)

# accent line under header
c.setFillColor(ACCENT)
c.rect(0, PH - HDR_H - 1.5, PW, 1.5, fill=1, stroke=0)

# green dot
dot_r = 7
dot_x = M + dot_r
dot_y = PH - HDR_H/2
c.setFillColor(GREEN)
c.circle(dot_x, dot_y, dot_r, fill=1, stroke=0)

# title
c.setFillColor(WHITE)
c.setFont(font(bold=True), 22)
c.drawString(M + dot_r*2 + 6, dot_y + 4, "T1 BLE Scanner")

# tagline
c.setFillColor(DIM)
c.setFont(font(), 9)
tagline = ("Мобильное приложение для сканирования BLE-меток транспортной системы T1.  "
           "AES-128 локальное дешифрование · радар-вид · справочник остановок · реестр операторов  "
           "Flutter 3.41.8 · Android 6+")
c.drawString(M + dot_r*2 + 6, dot_y - 10, tagline)

# ── screenshots grid ──────────────────────────────────────────────────────────
y_top = PH - HDR_H - 10   # top of first row

for row in range(2):
    for col in range(COLS):
        idx = row * COLS + col
        if idx >= len(SCREENS):
            break
        fname, label, caption = SCREENS[idx]

        x = M + col * (col_w + GAP_H)
        y = y_top - row * (thumb_h + CAP_H + GAP_V) - thumb_h

        # phone-frame border
        c.setStrokeColor(DIVIDER)
        c.setLineWidth(1)
        c.roundRect(x - 1, y - 1, col_w + 2, thumb_h + 2,
                    radius=5, fill=0, stroke=1)

        # screenshot image
        path = os.path.join(SS, fname)
        try:
            img = PILImage.open(path).convert("RGB")
            iw, ih = img.size
            img = img.crop((0, 0, iw, min(CROP_H, ih)))
            tmp = path + "_tmp.jpg"
            img.save(tmp, "JPEG", quality=88)
            c.drawImage(tmp, x, y, width=col_w, height=thumb_h,
                        preserveAspectRatio=False)
            os.remove(tmp)
        except Exception as e:
            c.setFillColor(CARD)
            c.rect(x, y, col_w, thumb_h, fill=1, stroke=0)
            c.setFillColor(DIM)
            c.setFont(font(), 8)
            c.drawString(x + 4, y + thumb_h/2, str(e)[:40])

        # label
        label_y = y - 13
        c.setFillColor(ACCENT)
        c.setFont(font(bold=True), 9)
        c.drawString(x, label_y, label)

        # caption (wrap manually to col_w)
        c.setFillColor(DIM)
        c.setFont(font(), 7.5)
        words = caption.split()
        lines, cur = [], []
        for w in words:
            test = ' '.join(cur + [w])
            if c.stringWidth(test, font(), 7.5) > col_w and cur:
                lines.append(' '.join(cur)); cur = [w]
            else:
                cur.append(w)
        if cur:
            lines.append(' '.join(cur))
        cy = label_y - 10
        for ln in lines[:3]:
            c.drawString(x, cy, ln)
            cy -= 9

# ── footer ────────────────────────────────────────────────────────────────────
c.setFillColor(CARD)
c.rect(0, 0, PW, 16, fill=1, stroke=0)
c.setFillColor(DIM)
c.setFont(font(), 7)
c.drawString(M, 5, "T1 BLE Scanner  ·  Android  ·  AES-128 локальная дешифровка  ·  Flutter 3.41.8")
c.drawRightString(PW - M, 5, "github.com/sayr777/dynamic-iBeacon")

c.save()
print(f"Saved: {OUT}  ({os.path.getsize(OUT)//1024} KB)")
