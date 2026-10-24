"""Icônes de la refonte Dragon Traveler (style de tools/ui_icons.py : glyphe ivoire 64 × 64).
Usage : python tools/refonte_icons.py
  → assets/icons/f_<faction>.svg   les 6 factions (pièces d'échecs)
  → assets/icons/<monnaie>.svg     encre, essence, gelee, sceau, sceau_destin, poupee, patrouille, campagne, star_*
"""
import os, math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "assets", "icons")
IV = "#E8DEC5"


def svg(inner):
    return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">%s</svg>' % inner


def path(d, c=IV, rule="nonzero"):
    return '<path d="%s" fill="%s" fill-rule="%s"/>' % (d, c, rule)


def line(d, c=IV, w=5):
    return '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % (d, c, w)


def circle(x, y, r, c=IV):
    return '<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % (x, y, r, c)


def star_d(n, ro, ri, cx=32, cy=32, rot=-90):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot + 180.0 * i / n)
        r = ro if i % 2 == 0 else ri
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return "M" + " L".join("%.1f %.1f" % p for p in pts) + " Z"


BASE = "M14 58 H50 V52 H46 L43 46 H21 L18 52 H14 Z"
ICONS_DEF = {
    # pièces d'échecs (factions)
    "f_roi": path(BASE) + path("M24 44 L22 28 H42 L40 44 Z") + path("M20 28 H44 V23 H20 Z") + path("M29 6 H35 V11 H40 V17 H35 V22 H29 V17 H24 V11 H29 Z"),
    "f_dame": path(BASE) + path("M23 44 L19 22 L26 30 L32 16 L38 30 L45 22 L41 44 Z") + circle(19, 19, 3.5) + circle(32, 12, 3.5) + circle(45, 19, 3.5),
    "f_fou": path(BASE) + path("M24 44 C20 34 24 22 32 12 C40 22 44 34 40 44 Z") + line("M28 30 L37 21", "#21172F", 3.5) + circle(32, 9, 3.5),
    "f_cavalier": path(BASE) + path("M20 44 C20 34 24 30 28 28 L18 26 L22 18 C26 12 34 8 40 10 C46 14 47 26 44 44 Z") + circle(31, 17, 2.2, "#21172F"),
    "f_tour": path(BASE) + path("M22 44 L23 22 H41 L42 44 Z") + path("M18 22 H46 V10 H40 V15 H35 V10 H29 V15 H24 V10 H18 Z"),
    "f_pion": path(BASE) + path("M24 44 C24 36 27 32 29 30 H35 C37 32 40 36 40 44 Z") + circle(32, 22, 9),
    # monnaies et ressources
    "encre": path("M32 6 C24 20 16 30 16 40 A16 16 0 0 0 48 40 C48 30 40 20 32 6 Z") + circle(26, 40, 3.5, "#21172F"),
    "essence": path(star_d(4, 26, 9)) + circle(32, 32, 4, "#21172F"),
    "gelee": path("M12 50 C10 34 20 22 32 22 C44 22 54 34 52 50 Z") + circle(25, 38, 3.2, "#21172F") + circle(39, 38, 3.2, "#21172F"),
    "sceau": path("M16 10 H48 V44 L32 56 L16 44 Z") + path(star_d(5, 11, 4.5, 32, 27), "#21172F"),
    "sceau_destin": path("M16 10 H48 V44 L32 56 L16 44 Z") + path("M32 15 L38 27 L32 39 L26 27 Z", "#21172F") + circle(32, 27, 2.5),
    "poupee": circle(32, 16, 9) + path("M20 58 L24 30 H40 L44 58 Z") + line("M18 36 L46 36", IV, 5),
    "patrouille": line("M10 50 C20 30 28 44 36 26 C42 14 50 18 54 12", IV, 5) + circle(54, 12, 5) + circle(10, 50, 5),
    "campagne": path("M10 54 L24 18 L34 38 L40 28 L54 54 Z") + path("M24 18 L24 8 L34 12 L24 16 Z"),
    "star_or": path(star_d(5, 26, 11)),
    "star_violet": path(star_d(5, 26, 11)) + circle(32, 34, 5, "#21172F"),
    "star_rouge": path(star_d(5, 26, 11)) + path(star_d(5, 10, 4.2, 32, 34), "#21172F"),
    "star_arc": path(star_d(8, 28, 13)),
    "overdrive": path("M36 4 L14 36 H30 L26 60 L50 26 H34 Z"),
    "grid": "".join(path("M%d %d h14 v14 h-14 Z" % (8 + 18 * (i % 3), 8 + 18 * (i // 3))) for i in range(9)),
}

for name, inner in ICONS_DEF.items():
    with open(os.path.join(ICONS, name + ".svg"), "w", encoding="utf-8") as f:
        f.write(svg(inner))
print(len(ICONS_DEF), "icônes écrites dans", ICONS)
