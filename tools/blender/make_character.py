"""Crée un personnage MakeHuman (MPFB2) avec le squelette Mixamo et l'enregistre en .blend.

Usage (Blender 4.2+ avec l'extension MPFB2 et le pack makehuman_system_assets installés) :
    blender --background --python tools/blender/make_character.py -- --id eirikr

Sortie : art/characters/<id>/<id>.blend
Le squelette "mixamo" de MPFB porte les mêmes noms d'os que Mixamo : les animations
téléchargées une seule fois sur Mixamo s'appliquent ensuite à tous les personnages
(voir apply_mixamo_anims.py).
"""
import argparse
import importlib
import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))


def dynamic_import(absolute_package_str, key):
    """MPFB est une extension Blender : son nom de paquet complet n'est pas connu à l'avance."""
    for amod in list(sys.modules):
        if amod.endswith(absolute_package_str):
            return getattr(importlib.import_module(amod), key)
    raise ValueError(f"MPFB introuvable ({absolute_package_str}). L'extension MPFB2 est-elle activée ?")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--id", required=True, help="id du personnage (voir characters.json)")
    p.add_argument("--out", default=os.path.join(PROJECT, "art", "characters"))
    return p.parse_args(argv)


def main():
    args = parse_args()
    with open(os.path.join(HERE, "characters.json"), encoding="utf-8") as f:
        spec = json.load(f)[args.id]

    HumanService = dynamic_import("mpfb.services.humanservice", "HumanService")
    AssetService = dynamic_import("mpfb.services.assetservice", "AssetService")
    TargetService = dynamic_import("mpfb.services.targetservice", "TargetService")
    ExportService = dynamic_import("mpfb.services.exportservice", "ExportService")
    HumanObjectProperties = dynamic_import("mpfb.entities.objectproperties", "HumanObjectProperties")

    # Scène vide
    bpy.ops.wm.read_factory_settings(use_empty=True)

    basemesh = HumanService.create_human()
    for key, value in spec.get("macros", {}).items():
        HumanObjectProperties.set_value(key, float(value), entity_reference=basemesh)
    TargetService.reapply_macro_details(basemesh)

    def find(name, subdir):
        path = AssetService.find_asset_absolute_path(name, asset_subdir=subdir)
        if path is None:
            print(f"[make_character] Asset introuvable, ignoré : {subdir}/{name}")
        return path

    skin = find(spec["skin"], "skins") if spec.get("skin") else None
    if skin:
        HumanService.set_character_skin(skin, basemesh, skin_type="GAMEENGINE")

    # Le squelette avant les vêtements, pour que ceux-ci reçoivent les poids.
    rig = HumanService.add_builtin_rig(basemesh, "mixamo")
    rig.name = f"{args.id}_rig"

    assets = [("eyes", "low-poly.mhclo", "Eyes"), ("eyebrows", "eyebrow001.mhclo", "Eyebrows"),
              ("eyelashes", "eyelashes01.mhclo", "Eyelashes")]
    if spec.get("hair"):
        assets.append(("hair", spec["hair"], "Hair"))
    for c in spec.get("clothes", []):
        assets.append(("clothes", c, "Clothes"))
    for subdir, name, atype in assets:
        path = find(name, subdir)
        if path:
            HumanService.add_mhclo_asset(path, basemesh, asset_type=atype, material_type="GAMEENGINE")

    # Nettoyage pour moteur de jeu : masques appliqués, géométrie d'aide supprimée.
    # Pas de subdivision : on reste léger pour le mobile.
    ExportService.bake_modifiers_remove_helpers(basemesh, bake_masks=True, bake_subdiv=False,
                                                remove_helpers=True, also_proxy=True)

    out_dir = os.path.join(args.out, args.id)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{args.id}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print(f"[make_character] OK : {out}")


if __name__ == "__main__":
    main()
