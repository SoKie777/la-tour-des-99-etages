"""Transforme les photos de buste (tools/portraits.gd) en icônes façon estampe ukiyo-e.

Usage : python tools/ukiyoe_portraits.py <dossier_des_photos> [taille]
Écrit assets/portraits/<id>.png : aplats de couleurs (bois gravé), contour à l'encre, fond de papier
washi, disque de soleil à la couleur de la constellation, sceau rouge (hanko) avec la rareté.
"""
import json, os, random, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "portraits")
SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 256
# palette d'estampe (mêmes teintes que UiKit.CONST_COLORS) : bleu de Prusse, vermillon, glycine ; papier washi
SUN = {"orion": (43, 79, 140), "grande_ourse": (196, 62, 40), "sirius": (130, 98, 172), "neutre": (40, 36, 44)}
PAPER = (236, 224, 198)
INK = (28, 22, 26)
SEAL = (196, 40, 32)
RANK = {3: "三", 4: "四", 5: "五", 0: "鬼"}  # rareté en chiffre japonais ; 鬼 (oni) pour les boss
FONT = "C:/Windows/Fonts/YuGothB.ttc"


def roster():
    info = {}
    data = json.load(open(os.path.join(ROOT, "data", "characters.json"), encoding="utf-8"))
    nation = json.load(open(os.path.join(ROOT, "data", "rules.json"), encoding="utf-8"))["triangle"]["nation_constellation"]
    for c in data["characters"]:
        info[c["id"]] = (nation[c["nation"]], int(c["rarity"]))
    for f in ("bosses.json", "loot_bosses.json"):
        for b in json.load(open(os.path.join(ROOT, "data", f), encoding="utf-8"))["bosses"].values():
            info[b["id"]] = (b.get("constellation", "neutre"), 0)
    return info


def washi(size, seed):
    rnd = random.Random(seed)
    img = Image.new("RGB", (size, size), PAPER)
    d = ImageDraw.Draw(img)
    for _ in range(size * 3):  # fibres du papier
        x, y = rnd.randrange(size), rnd.randrange(size)
        l = rnd.randint(3, 14)
        t = rnd.randint(-12, 6)
        d.line([(x, y), (x + l, y + rnd.randint(-2, 2))], fill=(PAPER[0] + t, PAPER[1] + t, PAPER[2] + t - 4))
    return img.filter(ImageFilter.GaussianBlur(0.6))


def woodblock(rgba, colors=7):
    """Aplats : peu de couleurs, comme une gravure sur bois imprimée planche par planche."""
    rgb = rgba.convert("RGB").filter(ImageFilter.MedianFilter(9)).filter(ImageFilter.GaussianBlur(1.5))
    # palette calculée sur les seuls pixels du personnage (le fond transparent la fausserait)
    alpha = rgba.split()[3]
    pixels = [p for p, a in zip(rgb.get_flattened_data(), alpha.get_flattened_data()) if a > 128]
    sample = Image.new("RGB", (len(pixels), 1))
    sample.putdata(pixels)
    pal = sample.quantize(colors, method=Image.Quantize.MEDIANCUT)
    flat = rgb.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
    return flat.filter(ImageFilter.ModeFilter(9))


def ink_lines(flat, alpha):
    """Contours à l'encre : silhouette épaisse + traits intérieurs entre les aplats."""
    edges = flat.convert("L").filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 55 else 0)
    edges = edges.filter(ImageFilter.MaxFilter(3))
    outer = ImageChops.subtract(alpha.filter(ImageFilter.MaxFilter(7)), alpha.filter(ImageFilter.MinFilter(3)))
    return ImageChops.lighter(ImageChops.multiply(edges, alpha.point(lambda v: 255 if v > 128 else 0)), outer)


def portrait(src, cid, constellation, rarity):
    big = 512
    rgba = Image.open(src).convert("RGBA").resize((big, big), Image.LANCZOS)
    alpha = rgba.split()[3].point(lambda v: 255 if v > 100 else 0)
    flat = woodblock(rgba)
    lines = ink_lines(flat, alpha)
    canvas = washi(big, hash(cid) & 0xFFFF)
    d = ImageDraw.Draw(canvas)
    sun = SUN.get(constellation, SUN["neutre"])
    d.ellipse([big * 0.16, big * 0.04, big * 0.84, big * 0.72], fill=sun)  # soleil derrière la tête
    for k in range(5):  # vagues seigaiha en bas
        y = big * 0.8 + k * 22
        for x in range(-40, big + 40, 56):
            d.arc([x - 28 + (k % 2) * 28, y - 28, x + 28 + (k % 2) * 28, y + 28], 180, 360, fill=(70, 90, 120), width=3)
    canvas.paste(flat, (0, 0), alpha)
    canvas.paste(Image.new("RGB", (big, big), INK), (0, 0), lines)
    # cadre et sceau
    d = ImageDraw.Draw(canvas)
    d.rectangle([4, 4, big - 5, big - 5], outline=INK, width=8)
    d.rectangle([16, 16, big - 17, big - 17], outline=INK, width=2)
    s0 = big - 128
    d.rounded_rectangle([s0, s0, s0 + 98, s0 + 98], radius=14, fill=SEAL)
    d.rounded_rectangle([s0 + 7, s0 + 7, s0 + 91, s0 + 91], radius=10, outline=PAPER, width=3)
    try:
        font = ImageFont.truetype(FONT, 66)
        d.text((s0 + 49, s0 + 47), RANK.get(rarity, "三"), font=font, fill=PAPER, anchor="mm")
    except OSError:
        d.text((s0 + 40, s0 + 40), str(rarity), fill=PAPER)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    src_dir = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    info = roster()
    for f in sorted(os.listdir(src_dir)):
        cid, ext = os.path.splitext(f)
        if ext != ".png" or cid not in info:
            continue
        cons, rar = info[cid]
        portrait(os.path.join(src_dir, f), cid, cons, rar).save(os.path.join(OUT, cid + ".png"))
        print("ICONE", cid)


main()
