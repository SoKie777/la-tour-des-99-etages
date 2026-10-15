"""Illustration de bannière d'un personnage (façon splash art) : rendu toon du jeu, contour à l'encre et
liseré d'or ; fond transparent pour être posée sur la bannière du jeu.

Usage : python tools/make_splash.py <photo.png> <id>   (photo : tools/splash_shot.gd)
Écrit assets/ui/splash_<id>.png (recadré sur le personnage, 900 px de haut au plus).
"""
import os, sys
from PIL import Image, ImageChops, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INK = (51, 44, 41)     # #332C29
GOLD = (209, 173, 98)  # #D1AD62


def stylize(src):
    rgba = Image.open(src).convert("RGBA")
    bbox = rgba.split()[3].point(lambda v: 255 if v > 20 else 0).getbbox()
    rgba = rgba.crop((max(0, bbox[0] - 30), max(0, bbox[1] - 30), min(rgba.width, bbox[2] + 30), min(rgba.height, bbox[3] + 10)))
    alpha = rgba.split()[3].point(lambda v: 255 if v > 100 else 0)
    flat = rgba.convert("RGB")  # le rendu toon du jeu est gardé tel quel (la postérisation l'abîmait)
    lines = ImageChops.subtract(alpha.filter(ImageFilter.MaxFilter(7)), alpha.filter(ImageFilter.MinFilter(3)))
    out = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    # liseré d'or autour de la silhouette, puis le personnage en aplats, puis l'encre
    glow = alpha.filter(ImageFilter.MaxFilter(11))
    out.paste(Image.new("RGBA", rgba.size, GOLD + (255,)), (0, 0), glow)
    out.paste(flat.convert("RGBA"), (0, 0), alpha)
    out.paste(Image.new("RGBA", rgba.size, INK + (255,)), (0, 0), lines)
    if out.height > 900:
        out = out.resize((round(out.width * 900 / out.height), 900), Image.LANCZOS)
    return out


def main():
    out = stylize(sys.argv[1])
    path = os.path.join(ROOT, "assets", "ui", "splash_%s.png" % sys.argv[2])
    out.save(path)
    print("SPLASH", path, out.size)


main()
