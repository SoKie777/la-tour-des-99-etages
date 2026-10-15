"""Icônes des effets (buffs / debuffs) : carré bleu à symbole blanc pour les bonus, rouge pour les malus.

Usage : python tools/status_icons.py   →  assets/status_icons/<id>.png (64 px)
Les effets viennent de data/rules.json (effects) et data/statuses.json (statuts signature).
Symboles : police Segoe UI Symbol (Windows) ; légende courte (ATK, DEF…) en Lilita One.
"""
import json, os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "status_icons")
SYM = "C:/Windows/Fonts/seguisym.ttf"
CAP = os.path.join(ROOT, "assets", "fonts", "LilitaOne-Regular.ttf")
BLUE = (38, 92, 170)
RED = (178, 34, 34)
GOOD = {"buff", "aura", "stance"}
S = 64

# id : (symbole, légende)
ICONS = {
    "atk_up": ("▲", "ATK"), "def_up": ("▲", "DEF"), "spd_up": ("▲", "VIT"), "cr_up": ("▲", "TC"),
    "cd_up": ("▲", "DC"), "acc_up": ("▲", "PRÉ"),
    "atk_down": ("▼", "ATK"), "def_down": ("▼", "DEF"), "spd_down": ("▼", "VIT"), "slow": ("▼", "VIT"),
    "res_down": ("▼", "RÉS"), "def_break": ("✖", "DEF"),
    "burn": ("♨", ""), "poison": ("☣", ""), "curse": ("☠", ""), "disorient": ("✺", ""),
    "silence": ("⊘", "SIL"), "sleep": ("Z", ""), "stun": ("✦", ""), "freeze": ("❄", ""),
    "taunt": ("!", ""), "immunity": ("✚", "IMM"), "shield": ("⛨", ""), "vulnerable": ("⇱", ""),
    "aging": ("⌛", ""), "dmg_reduce": ("⛨", ""), "aura_spd": ("»", ""), "aura_dmg_reduce": ("⛨", "AURA"),
    "aura_chill": ("❄", "AURA"), "guarded": ("⛉", ""), "bastion": ("⚖", ""), "invincible": ("★", ""),
    "block": ("⊘", "BUFF"), "no_heal": ("✚", "✕"), "regen": ("♥", ""), "entrave": ("⛓", ""),
    # statuts signature
    "room": ("▣", ""), "vieillissement": ("⌛", ""), "givre": ("❄", ""), "clone": ("⧉", ""), "inertie": ("◉", ""),
    "garde_de_fer": ("⛨", "FER"), "visage": ("☺", ""), "rage": ("✹", ""), "dette": ("¤", ""),
    "benediction": ("✧", ""), "espera": ("∞", ""), "gravite": ("⤓", ""), "vide": ("○", ""), "revele": ("◎", ""),
    "lien": ("⛓", ""), "scellement": ("⊕", ""), "clef": ("⚿", ""), "venin_solaire": ("☀", ""),
}


def kinds():
    out = {}
    for k, v in json.load(open(os.path.join(ROOT, "data", "rules.json"), encoding="utf-8"))["effects"].items():
        out[k] = v.get("kind", "debuff")
    for k, v in json.load(open(os.path.join(ROOT, "data", "statuses.json"), encoding="utf-8")).items():
        if not k.startswith("_"):
            out[k] = v.get("kind", "debuff")
    return out


def icon(sym, cap, good):
    big = S * 4
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = BLUE if good else RED
    d.rounded_rectangle([6, 6, big - 7, big - 7], radius=28, fill=base, outline=(255, 255, 255), width=12)
    d.rounded_rectangle([26, 26, big - 27, big * 0.42], radius=18, fill=tuple(min(255, c + 30) for c in base))  # reflet
    cy = big * (0.42 if cap else 0.5)
    size = 150 if cap else 175
    font = ImageFont.truetype(CAP if sym.isalpha() else SYM, size)
    d.text((big / 2, cy), sym, font=font, fill="white", anchor="mm")
    if cap:
        f2 = ImageFont.truetype(CAP if cap != "✕" else SYM, 76 if len(cap) <= 3 else 60)
        d.text((big / 2, big * 0.8), cap, font=f2, fill="white", anchor="mm", stroke_width=4, stroke_fill=base)
    return img.resize((S, S), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    k = kinds()
    for eid, kind in k.items():
        sym, cap = ICONS.get(eid, ("?", ""))
        icon(sym, cap, kind in GOOD).save(os.path.join(OUT, eid + ".png"))
    print("ICONES", len(k))


main()
