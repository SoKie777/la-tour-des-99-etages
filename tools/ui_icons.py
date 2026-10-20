"""Icônes vectorielles minimalistes de l'interface (règle UI T99 : zéro texte superflu).

Usage : python tools/ui_icons.py
  → assets/icons/<id>.svg         glyphe ivoire sur fond transparent (ressources, stats, classes, boutons…)
  → assets/icons/fx_<effet>.svg   glyphe ivoire de chaque effet (symboles des compétences)
  → assets/status_icons/<id>.svg  effet de combat : carré à symbole ivoire (Bible D.A., §3.1)
       bleu minéral = bonus non dissipable (aura, posture…), or ancien = bonus dissipable,
       rouge sceau = malus. Les effets viennent de data/rules.json et data/statuses.json.
Tout est dessiné en 64 × 64 ; Godot importe les SVG en textures.
"""
import json, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "assets", "icons")
STATUS = os.path.join(ROOT, "assets", "status_icons")
IVORY = "#E8DEC5"
GOLD = "#D1AD62"
MINERAL = "#263C4A"
SEAL = "#B83A35"
GOOD = {"buff", "aura", "stance"}


# --- Primitives (chaîne SVG, couleur c) ----------------------------------------------

def poly(pts, c):
    return '<polygon points="%s" fill="%s"/>' % (" ".join("%.1f,%.1f" % p for p in pts), c)


def path(d, c, rule="nonzero"):
    return '<path d="%s" fill="%s" fill-rule="%s"/>' % (d, c, rule)


def line(d, c, w=5):
    return '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % (d, c, w)


def circle(x, y, r, c):
    return '<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % (x, y, r, c)


def ring(x, y, r, c, w=5):
    return '<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" stroke-width="%s"/>' % (x, y, r, c, w)


def star_pts(n, ro, ri, cx=32, cy=32, rot=-90):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot + 180.0 * i / n)
        r = ro if i % 2 == 0 else ri
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def ngon(n, r, cx=32, cy=32, rot=-90):
    return [(cx + r * math.cos(math.radians(rot + 360.0 * i / n)), cy + r * math.sin(math.radians(rot + 360.0 * i / n))) for i in range(n)]


def d_of(pts):
    return "M" + " L".join("%.1f %.1f" % p for p in pts) + " Z"


def g(inner, tf):
    return '<g transform="%s">%s</g>' % (tf, inner)


# --- Glyphes ----------------------------------------------------------------------

def heart(c):
    return path("M32 56 L9 33 C1 24 6 9 19 9 C25 9 29 13 32 18 C35 13 39 9 45 9 C58 9 63 24 55 33 Z", c)


def sword(c):
    return g(poly([(32, 3), (37, 10), (37, 40), (27, 40), (27, 10)], c) + poly([(18, 40), (46, 40), (46, 45), (18, 45)], c)
             + poly([(29.5, 45), (34.5, 45), (34.5, 55), (29.5, 55)], c) + circle(32, 58.5, 3.5, c), "rotate(45 32 32)")


def shield(c):
    return path("M32 5 L55 13 V30 C55 45 45 55 32 59 C19 55 9 45 9 30 V13 Z", c)


def chevrons(c):
    return poly([(8, 12), (22, 12), (40, 32), (22, 52), (8, 52), (26, 32)], c) + poly([(28, 12), (40, 12), (58, 32), (40, 52), (28, 52), (46, 32)], c)


def crosshair(c):
    return ring(32, 32, 19, c, 5) + line("M32 4 V16 M32 48 V60 M4 32 H16 M48 32 H60", c, 5) + circle(32, 32, 5, c)


def burst(c):
    return poly(star_pts(8, 29, 13), c)


def eye(c):
    return path("M3 32 C15 12 49 12 61 32 C49 52 15 52 3 32 Z M32 21 A11 11 0 1 0 32.01 21 Z", c, "evenodd") + circle(32, 32, 6, c)


def ward(c):
    return path(d_of(ngon(6, 28)) + " " + d_of(ngon(6, 19)), c, "evenodd") + circle(32, 32, 8, c)


def crystal(c):
    return poly(star_pts(4, 28, 8, 30, 34), c) + poly(star_pts(4, 11, 3, 51, 12), c)


def coin(c):
    return path("M32 6 A26 26 0 1 0 32.01 6 Z M24 24 H40 V40 H24 Z", c, "evenodd")


def shards(c):
    return poly([(16, 6), (40, 10), (30, 30), (10, 40), (6, 20)], c) + poly([(45, 15), (58, 38), (36, 58), (24, 52), (34, 33)], c)


def bolt(c):
    return poly([(38, 3), (12, 36), (29, 36), (22, 61), (52, 24), (35, 24), (44, 3)], c)


def gem(c):
    return path("M20 9 H44 L57 24 L32 57 L7 24 Z M20 24 H44 L32 47 Z", c, "evenodd")


def hourglass(c):
    return poly([(12, 5), (52, 5), (52, 10), (36, 30), (36, 34), (52, 54), (52, 59), (12, 59), (12, 54), (28, 34), (28, 30), (12, 10)], c)


def flame(c):
    return path("M32 3 C36 16 52 22 50 40 C49 52 41 60 32 60 C22 60 14 52 14 41 C14 32 20 27 23 20 C25 27 28 30 31 30 C28 21 28 11 32 3 Z", c)


def drop(c):
    return path("M32 4 C40 18 52 30 52 42 C52 53 43 60 32 60 C21 60 12 53 12 42 C12 30 24 18 32 4 Z", c)


def skull(c):
    return path("M32 5 C17 5 8 15 8 28 C8 37 13 42 18 44 V54 H46 V44 C51 42 56 37 56 28 C56 15 47 5 32 5 Z "
                "M24 24 A6 6 0 1 0 24.01 24 Z M40 24 A6 6 0 1 0 40.01 24 Z", c, "evenodd")


def spiral(c):
    pts = []
    for i in range(60):
        t = i / 59 * 3.2 * math.pi
        r = 3 + 8.2 * t / math.pi
        pts.append((32 + r * math.cos(t), 32 + r * math.sin(t)))
    return line("M" + " L".join("%.1f %.1f" % p for p in pts), c, 5)


def mute(c):
    return path("M10 14 H54 V42 H30 L18 54 V42 H10 Z", c) + line("M6 58 L58 6", c, 5)



def zz(c):
    return poly([(10, 10), (34, 10), (34, 15), (18, 30), (34, 30), (34, 35), (10, 35), (10, 30), (26, 15), (10, 15)], c) + \
        poly([(36, 34), (54, 34), (54, 38), (42, 50), (54, 50), (54, 54), (36, 54), (36, 50), (48, 38), (36, 38)], c)


def stars_stun(c):
    return poly(star_pts(5, 18, 7, 22, 26), c) + poly(star_pts(5, 12, 5, 46, 44), c)


def snowflake(c):
    d = ""
    for k in range(3):
        a = math.radians(90 + 60 * k)
        dx, dy = 27 * math.cos(a), 27 * math.sin(a)
        d += "M%.1f %.1f L%.1f %.1f " % (32 - dx, 32 - dy, 32 + dx, 32 + dy)
        for s in (1, -1):
            bx, by = 32 + s * dx * 0.55, 32 + s * dy * 0.55
            for t in (-1, 1):
                b = a + t * math.radians(45) + (0 if s > 0 else math.pi)
                d += "M%.1f %.1f L%.1f %.1f " % (bx, by, bx + 9 * math.cos(b), by + 9 * math.sin(b))
    return line(d, c, 4.5)


def exclaim(c):
    return poly([(26, 6), (38, 6), (35, 42), (29, 42)], c) + circle(32, 52, 6, c)


def plus(c, s=1.0, cx=32, cy=32):
    w, l = 7 * s, 22 * s
    return poly([(cx - w, cy - l), (cx + w, cy - l), (cx + w, cy - w), (cx + l, cy - w), (cx + l, cy + w), (cx + w, cy + w),
                 (cx + w, cy + l), (cx - w, cy + l), (cx - w, cy + w), (cx - l, cy + w), (cx - l, cy - w), (cx - w, cy - w)], c)


def shield_plus(c):
    return path("M32 5 L55 13 V30 C55 45 45 55 32 59 C19 55 9 45 9 30 V13 Z "
                "M28 18 H36 V28 H46 V36 H36 V46 H28 V36 H18 V28 H28 Z", c, "evenodd")


def shield_minus(c):
    return path("M32 5 L55 13 V30 C55 45 45 55 32 59 C19 55 9 45 9 30 V13 Z M18 28 H46 V36 H18 Z", c, "evenodd")


def cracked(c):
    return path("M32 5 L55 13 V30 C55 45 45 55 32 59 C19 55 9 45 9 30 V13 Z M30 8 L24 26 L34 32 L26 56 L30 56 L39 31 L29 25 L34 8 Z", c, "evenodd")


def tower(c):
    return poly([(10, 58), (10, 14), (18, 14), (18, 22), (26, 22), (26, 14), (38, 14), (38, 22), (46, 22), (46, 14), (54, 14), (54, 58),
                 (38, 58), (38, 44), (26, 44), (26, 58)], c)


def star5(c):
    return poly(star_pts(5, 29, 12, 32, 34), c)


def no_up(c):
    return poly([(32, 10), (50, 34), (38, 34), (38, 54), (26, 54), (26, 34), (14, 34)], c) + line("M10 54 L54 10", c, 5)


def heart_slash(c):
    return heart(c) + line("M8 56 L56 8", c, 5)


def heart_plus(c):
    return path("M32 56 L9 33 C1 24 6 9 19 9 C25 9 29 13 32 18 C35 13 39 9 45 9 C58 9 63 24 55 33 Z "
                "M28 20 H36 V28 H44 V36 H36 V44 H28 V36 H20 V28 H28 Z", c, "evenodd")


def chain(c):
    return g(path("M8 22 A10 10 0 0 1 18 12 H32 A10 10 0 0 1 32 32 H18 A10 10 0 0 1 8 22 Z M16 18 A4 4 0 0 0 16 26 H32 A4 4 0 0 0 32 18 Z", c, "evenodd")
             + path("M24 42 A10 10 0 0 1 34 32 H48 A10 10 0 0 1 48 52 H34 A10 10 0 0 1 24 42 Z M32 38 A4 4 0 0 0 32 46 H48 A4 4 0 0 0 48 38 Z", c, "evenodd"),
             "rotate(-30 32 32)")


def frame(c):
    return path("M6 6 H58 V58 H6 Z M14 14 V50 H50 V14 Z", c, "evenodd") + poly([(24, 24), (40, 24), (40, 40), (24, 40)], c)


def two_squares(c):
    return path("M6 6 H40 V40 H6 Z M12 12 V34 H34 V12 Z", c, "evenodd") + poly([(24, 24), (58, 24), (58, 58), (24, 58)], c)


def rings(c):
    return ring(32, 32, 24, c, 5) + ring(32, 32, 13, c, 5) + circle(32, 32, 4, c)


def mask(c):
    return path("M10 10 H54 V30 C54 46 44 58 32 58 C20 58 10 46 10 30 Z M17 24 C20 20 26 20 29 24 C26 28 20 28 17 24 Z "
                "M35 24 C38 20 44 20 47 24 C44 28 38 28 35 24 Z M24 42 H40 V45 H24 Z", c, "evenodd")


def debt(c):
    return path("M32 6 A26 26 0 1 0 32.01 6 Z M18 29 H46 V35 H18 Z", c, "evenodd")


def sparkle(c):
    return poly(star_pts(4, 28, 6), c) + poly(star_pts(4, 10, 2.5, 50, 12), c) + poly(star_pts(4, 8, 2, 13, 50), c)


def infinity(c):
    return line("M32 32 C24 18 8 20 8 32 C8 44 24 46 32 32 C40 18 56 20 56 32 C56 44 40 46 32 32 Z", c, 6)


def gravity(c):
    return poly([(26, 4), (38, 4), (38, 26), (48, 26), (32, 44), (16, 26), (26, 26)], c) + poly([(8, 50), (56, 50), (56, 58), (8, 58)], c)


def void(c):
    return ring(32, 32, 24, c, 7)


def target(c):
    return ring(32, 32, 25, c, 5) + ring(32, 32, 14, c, 5) + circle(32, 32, 5, c)


def seal(c):
    return ring(32, 32, 25, c, 5) + line("M32 10 V54 M10 32 H54", c, 5)


def key(c):
    return path("M20 8 A14 14 0 1 0 20.01 8 Z M20 16 A6 6 0 1 0 20.01 16 Z", c, "evenodd") + \
        poly([(30, 28), (58, 28), (58, 35), (52, 35), (52, 44), (45, 44), (45, 35), (30, 35)], c)


def sun_drop(c):
    return path(d_of(star_pts(12, 28, 19)) + " M32 16 A16 16 0 1 0 32.01 16 Z", c, "evenodd") +         path("M32 21 C36 27 40 32 40 37 C40 42 36 45 32 45 C28 45 24 42 24 37 C24 32 28 27 32 21 Z", c)


def spark(c):
    return poly(star_pts(4, 26, 7), c) + poly(star_pts(4, 10, 3, 48, 48), c)


def fang(c):
    return path("M8 10 H56 V20 C50 20 46 24 44 32 L38 58 L32 34 L26 58 L20 32 C18 24 14 20 8 20 Z", c)


def leaf_life(c):
    return heart(c)


def info(c):
    return circle(32, 13, 7, c) + poly([(24, 24), (38, 24), (38, 50), (44, 50), (44, 58), (20, 58), (20, 50), (26, 50), (26, 32), (24, 32)], c)


def scroll(c):
    return path("M14 8 H48 C53 8 56 11 56 16 H48 V52 C48 56 45 59 41 59 H12 C8 59 6 56 6 52 H14 Z", c) + \
        line("M20 22 H40 M20 32 H40 M20 42 H34", MINERAL, 3.5)


def loop(c):
    return line("M50 24 A20 20 0 0 0 14 22 M14 40 A20 20 0 0 0 50 42", c, 6) + poly([(46, 12), (58, 26), (42, 28)], c) + poly([(18, 52), (6, 38), (22, 36)], c)


def door(c):
    return path("M12 6 H44 V18 H38 V12 H18 V52 H38 V46 H44 V58 H12 Z", c) + poly([(30, 29), (46, 29), (46, 21), (60, 32), (46, 43), (46, 35), (30, 35)], c)


def back(c):
    return poly([(6, 32), (28, 10), (28, 24), (58, 24), (58, 40), (28, 40), (28, 54)], c)


def play(c):
    return poly([(16, 8), (54, 32), (16, 56)], c)


def close(c):
    return line("M14 14 L50 50 M50 14 L14 50", c, 8)


def lock(c):
    return path("M12 28 H52 V58 H12 Z M28 38 H36 V50 H28 Z", c, "evenodd") + line("M20 28 V20 A12 12 0 0 1 44 20 V28", c, 6)


def tower_floor(c):
    return poly([(32, 2), (36, 10), (48, 14), (40, 18), (42, 28), (54, 32), (44, 36), (46, 48), (60, 54), (60, 60), (4, 60), (4, 54),
                 (18, 48), (20, 36), (10, 32), (22, 28), (24, 18), (16, 14), (28, 10)], c)


def crown(c):
    return poly([(6, 50), (6, 16), (20, 30), (32, 10), (44, 30), (58, 16), (58, 50)], c) + poly([(6, 54), (58, 54), (58, 60), (6, 60)], c)


def twin_swords(c):
    return g(sword(c), "translate(-9 0) scale(0.85) translate(6 6)") + g(g(sword(c), "scale(-1 1) translate(-64 0)"), "translate(9 0) scale(0.85) translate(6 6)")


def shield_sword(c):
    return g(shield(c), "translate(4 8) scale(0.78)") + g(sword(c), "translate(22 -2) scale(0.6)")


def bars(c):
    return poly([(6, 56), (58, 56), (58, 61), (6, 61)], c) + poly([(9, 36), (21, 36), (21, 52), (9, 52)], c) +         poly([(26, 14), (38, 14), (38, 52), (26, 52)], c) + poly([(43, 26), (55, 26), (55, 52), (43, 52)], c)


def stars_lines(pts, links, c):
    d = " ".join("M%.1f %.1f L%.1f %.1f" % (pts[a][0], pts[a][1], pts[b][0], pts[b][1]) for a, b in links)
    return line(d, c, 2.5) + "".join(circle(x, y, r, c) for x, y, r in pts)


def orion(c):
    pts = [(16, 8, 5), (48, 11, 4.5), (25, 31, 3.5), (32, 33, 3.5), (39, 35, 3.5), (18, 56, 4.5), (47, 54, 5)]
    return stars_lines([(x, y, r) for x, y, r in pts], [(0, 2), (1, 4), (2, 3), (3, 4), (2, 5), (4, 6), (0, 1)], c)


def grande_ourse(c):
    pts = [(4, 22, 3.5), (15, 26, 3.5), (25, 30, 3.5), (35, 32, 4), (37, 48, 4), (58, 48, 4.5), (57, 30, 4.5)]
    return stars_lines(pts, [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 3)], c)


def sirius(c):
    return poly(star_pts(4, 28, 6), c) + poly(star_pts(4, 15, 4, 32, 32, -45), c) + circle(52, 52, 4, c)


def seal_gem(c):
    return path(d_of([(32, 3), (61, 32), (32, 61), (3, 32)]) + " " + d_of([(32, 17), (47, 32), (32, 47), (17, 32)]), c, "evenodd") +         poly([(32, 24), (40, 32), (32, 40), (24, 32)], c)


def summon(c):
    return ring(32, 32, 26, c, 4) + poly(star_pts(6, 20, 9), c)


ARROW_UP = [(49, 1), (63, 17), (55, 17), (55, 26), (43, 26), (43, 17), (35, 17)]
ARROW_DOWN = [(49, 26), (63, 10), (55, 10), (55, 1), (43, 1), (43, 10), (35, 10)]


def with_arrow(fn, up):
    def f(c):
        return g(fn(c), "translate(0 22) scale(0.66)") + poly(ARROW_UP if up else ARROW_DOWN, c)
    return f


def with_ring(fn):
    def f(c):
        return ring(32, 32, 29, c, 3) + g(fn(c), "translate(13 13) scale(0.6)")
    return f


# --- Catalogue -------------------------------------------------------------------------

UI = {
    # ressources
    "eclat_de_voeu": crystal, "pieces": coin, "fragments_etage": shards, "energie": bolt, "relique": gem,
    # stats
    "hp": heart, "atk": sword, "def": shield, "spd": chevrons, "cr": crosshair, "cd": burst, "acc": eye, "res": ward,
    "shield": shield, "cooldown": hourglass, "passive": infinity, "turn": play, "floor": tower_floor,
    # classes
    "dps_single": sword, "dps_aoe": twin_swords, "tank_def": shield, "tank_off": shield_sword, "neutralizer": chain,
    "support": heart_plus, "titan": crown, "boss": skull,
    # ensembles de reliques
    "set_attaque": sword, "set_vitesse": chevrons, "set_taux_critique": crosshair, "set_defense": shield,
    "set_immunite": shield_plus, "set_vampirisme": fang, "set_vie": heart, "set_precision": eye, "set_gel": snowflake,
    "set_ocean": drop, "set_astralis": sparkle, "set_calamite": skull, "set_egide": tower,
    "resonance": star5,
    # cumuls signature
    "stack_spark": spark, "stack_fury": flame, "stack_rage": burst, "stack_visage": mask, "stack_dette": debt,
    "stack_clone": two_squares, "stack_inertia": rings,
    # boutons
    "info": info, "journal": scroll, "auto": loop, "quit": door, "back": back, "close": close, "lock": lock,
    "summon": summon, "speed": chevrons, "stats": bars, "dmg_taken": cracked,
    # mode tactique de la Tour
    "orion": orion, "grande_ourse": grande_ourse, "sirius": sirius, "sceau": seal_gem, "charge": exclaim,
}

STATUS_GLYPHS = {
    "atk_up": with_arrow(sword, True), "def_up": with_arrow(shield, True), "spd_up": with_arrow(chevrons, True),
    "cr_up": with_arrow(crosshair, True), "cd_up": with_arrow(burst, True), "acc_up": with_arrow(eye, True),
    "atk_down": with_arrow(sword, False), "def_down": with_arrow(shield, False), "spd_down": with_arrow(chevrons, False),
    "slow": with_arrow(chevrons, False), "res_down": with_arrow(ward, False), "def_break": cracked,
    "burn": flame, "poison": drop, "curse": skull, "disorient": spiral, "silence": mute, "sleep": zz, "stun": stars_stun,
    "freeze": snowflake, "taunt": exclaim, "immunity": shield_plus, "shield": shield, "vulnerable": target,
    "aging": hourglass, "dmg_reduce": shield_minus, "aura_spd": with_ring(chevrons), "aura_dmg_reduce": with_ring(shield_minus),
    "aura_chill": with_ring(snowflake), "guarded": shield, "bastion": tower, "invincible": star5, "block": no_up,
    "no_heal": heart_slash, "regen": heart_plus, "entrave": chain,
    "room": frame, "vieillissement": hourglass, "givre": snowflake, "clone": two_squares, "inertie": rings,
    "garde_de_fer": tower, "visage": mask, "rage": burst, "dette": debt, "benediction": sparkle, "espera": infinity,
    "gravite": gravity, "vide": void, "revele": eye, "lien": chain, "scellement": seal, "clef": key, "venin_solaire": sun_drop,
}


def svg(inner):
    return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">%s</svg>\n' % inner


def effects():
    out = {}
    for k, v in json.load(open(os.path.join(ROOT, "data", "rules.json"), encoding="utf-8"))["effects"].items():
        out[k] = v
    for k, v in json.load(open(os.path.join(ROOT, "data", "statuses.json"), encoding="utf-8")).items():
        if not k.startswith("_"):
            out[k] = v
    return out


def status_color(d):
    kind = d.get("kind", "debuff")
    if kind not in GOOD:
        return SEAL
    return GOLD if kind == "buff" and d.get("dispellable", True) else MINERAL


def main():
    os.makedirs(ICONS, exist_ok=True)
    os.makedirs(STATUS, exist_ok=True)
    for name, fn in UI.items():
        open(os.path.join(ICONS, name + ".svg"), "w", encoding="utf-8").write(svg(fn(IVORY)))
    for name, fn in STATUS_GLYPHS.items():  # symboles des compétences (UiKit.skill_icon_id)
        open(os.path.join(ICONS, "fx_" + name + ".svg"), "w", encoding="utf-8").write(svg(fn(IVORY)))
    n = 0
    for eid, d in effects().items():
        fn = STATUS_GLYPHS.get(eid, star5)
        bg = status_color(d)
        inner = '<rect x="2" y="2" width="60" height="60" rx="9" fill="%s" stroke="%s" stroke-width="3"/>' % (bg, IVORY)
        inner += g(fn(IVORY), "translate(12 12) scale(0.625)")
        open(os.path.join(STATUS, eid + ".svg"), "w", encoding="utf-8").write(svg(inner))
        old = os.path.join(STATUS, eid + ".png")
        for f in (old, old + ".import"):
            if os.path.exists(f):
                os.remove(f)
        n += 1
    print("ICONES UI", len(UI), "· EFFETS", n)


main()
