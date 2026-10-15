"""Image de bannière d'invocation façon estampe : photo des légendaires (tools/banner_shot.gd) posée sur
un soleil levant, des rayons, des nuages kumo et des vagues seigaiha, avec titre et sceau.

Usage : python tools/make_banner.py <photo.png> [titre] [sous-titre]
Écrit assets/ui/banner_legendaires.png (1600 x 900).
"""
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "banner_legendaires.png")
TITLE_FONT = os.path.join(ROOT, "assets", "fonts", "LilitaOne-Regular.ttf")
JP_FONT = "C:/Windows/Fonts/YuGothB.ttc"
PAPER = (236, 224, 198)
INK = (28, 22, 26)
VERMILION = (196, 40, 32)
PRUSSIAN = (32, 58, 104)
OCHRE = (214, 164, 70)
W, H = 1600, 900


def washi():
    rnd = random.Random(7)
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    for _ in range(9000):
        x, y = rnd.randrange(W), rnd.randrange(H)
        t = rnd.randint(-14, 6)
        d.line([(x, y), (x + rnd.randint(4, 18), y + rnd.randint(-2, 2))], fill=(PAPER[0] + t, PAPER[1] + t, PAPER[2] + t - 4))
    return img.filter(ImageFilter.GaussianBlur(0.7))


def rays(img, cx, cy):
    d = ImageDraw.Draw(img, "RGBA")
    n = 28
    for i in range(n):
        if i % 2:
            continue
        a0 = i * 2 * math.pi / n
        a1 = (i + 1) * 2 * math.pi / n
        r = 2000
        d.polygon([(cx, cy), (cx + r * math.cos(a0), cy + r * math.sin(a0)), (cx + r * math.cos(a1), cy + r * math.sin(a1))],
                  fill=OCHRE + (70,))


def clouds(img):
    d = ImageDraw.Draw(img, "RGBA")
    for (x, y, w) in [(120, 210, 340), (1180, 160, 380), (1260, 300, 260), (60, 360, 240)]:
        for k in range(4):  # nuage kumo : lobes empilés et liseré d'encre
            bx = x + k * w // 5
            d.ellipse([bx, y - 26 - (k % 2) * 14, bx + w // 2.4, y + 26], fill=(250, 244, 230, 235), outline=INK + (255,), width=4)
        d.rounded_rectangle([x - 20, y, x + w, y + 28], radius=14, fill=(250, 244, 230, 235), outline=INK + (255,), width=4)


def waves(img):
    d = ImageDraw.Draw(img)
    top = H - 150
    d.rectangle([0, top, W, H], fill=PRUSSIAN)
    for row in range(6):
        y = top + 10 + row * 26
        off = 0 if row % 2 == 0 else 35
        for x in range(-70, W + 70, 70):
            for r, col in ((34, (236, 224, 198)), (26, PRUSSIAN), (18, (236, 224, 198)), (10, PRUSSIAN)):
                d.ellipse([x + off - r, y - r, x + off + r, y + r], fill=col)


def outline(char):
    a = char.split()[3].point(lambda v: 255 if v > 90 else 0)
    ring = a.filter(ImageFilter.MaxFilter(9))
    out = Image.new("RGBA", char.size, INK + (0,))
    out.putalpha(ring)
    out.alpha_composite(char)
    return out


def main():
    title = sys.argv[2] if len(sys.argv) > 2 else "LÉGENDES"
    sub = sys.argv[3] if len(sys.argv) > 3 else "Vedette : Montana"
    img = washi()
    cx, cy = W // 2, 400
    rays(img, cx, cy)
    d = ImageDraw.Draw(img)
    d.ellipse([cx - 300, cy - 300, cx + 300, cy + 300], fill=VERMILION)
    clouds(img)
    waves(img)
    chars = outline(Image.open(sys.argv[1]).convert("RGBA"))
    canvas = img.convert("RGBA")
    canvas.alpha_composite(chars, (0, 0))
    d = ImageDraw.Draw(canvas)
    # titre en cartouche vertical à gauche (comme le titre d'une estampe)
    d.rectangle([40, 40, 200, 640], fill=PAPER, outline=INK, width=6)
    d.rectangle([52, 52, 188, 628], outline=INK, width=2)
    f = ImageFont.truetype(TITLE_FONT, 92)
    for i, ch in enumerate(title):
        d.text((120, 116 + i * 72), ch, font=f, fill=VERMILION if i == 0 else INK, anchor="mm")
    fs = ImageFont.truetype(TITLE_FONT, 56)
    d.text((W - 60, H - 205), sub, font=fs, fill=PAPER, anchor="rs", stroke_width=8, stroke_fill=INK)
    # sceau rouge
    s0x, s0y = W - 190, 40
    d.rounded_rectangle([s0x, s0y, s0x + 140, s0y + 140], radius=18, fill=VERMILION)
    d.rounded_rectangle([s0x + 10, s0y + 10, s0x + 130, s0y + 130], radius=12, outline=PAPER, width=4)
    d.text((s0x + 70, s0y + 70), "伝説", font=ImageFont.truetype(JP_FONT, 56), fill=PAPER, anchor="mm")
    d.rectangle([4, 4, W - 5, H - 5], outline=INK, width=10)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    canvas.convert("RGB").save(OUT)
    print("BANNIERE", OUT)


main()
