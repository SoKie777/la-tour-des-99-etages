"""Applique les animations Mixamo à un personnage MPFB et exporte le .glb pour Godot.

Usage :
    blender --background art/characters/eirikr/eirikr.blend \
        --python tools/blender/apply_mixamo_anims.py -- --id eirikr

Animations attendues dans art/animations/mixamo/ (téléchargées une seule fois sur
Mixamo, format FBX, "Without Skin", 30 ips) :
    idle.fbx  attack.fbx  skill.fbx  ultimate.fbx  hit.fbx  death.fbx
Un fichier manquant est simplement ignoré.

Sortie : assets/characters/<id>/<id>.glb, que la scène de combat charge automatiquement.
"""
import argparse
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
ANIMS = ["idle", "attack", "skill", "ultimate", "hit", "death"]


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--id", required=True)
    p.add_argument("--anims", default=os.path.join(PROJECT, "art", "animations", "mixamo"))
    p.add_argument("--out", default=os.path.join(PROJECT, "assets", "characters"))
    p.add_argument("--in-place", action="store_true", help="ne pas copier le déplacement des hanches")
    return p.parse_args(argv)


def strip_prefix(bone_name):
    return bone_name.split(":", 1)[1] if ":" in bone_name else bone_name


def bake_one(dst, fbx_path, anim_name, in_place):
    before = set(bpy.data.objects)
    actions_before = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=fbx_path, ignore_leaf_bones=True, automatic_bone_orientation=False)
    imported = [o for o in bpy.data.objects if o not in before]
    src = next((o for o in imported if o.type == "ARMATURE"), None)
    if src is None or src.animation_data is None or src.animation_data.action is None:
        print(f"[anims] {fbx_path} : pas d'armature animée, ignoré")
        return
    start, end = (int(v) for v in src.animation_data.action.frame_range)

    # Même principe que l'opérateur "Snap to mixamo" de MPFB : contraintes de copie, puis bake.
    src_bones = {strip_prefix(b.name): b.name for b in src.data.bones}
    for pb in dst.pose.bones:
        key = strip_prefix(pb.name)
        if key not in src_bones:
            continue
        c = pb.constraints.new("COPY_ROTATION")
        c.target, c.subtarget = src, src_bones[key]
        if key == "Hips" and not in_place:
            c2 = pb.constraints.new("COPY_LOCATION")
            c2.target, c2.subtarget = src, src_bones[key]

    bpy.ops.object.select_all(action="DESELECT")
    dst.select_set(True)
    bpy.context.view_layer.objects.active = dst
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(frame_start=start, frame_end=end, only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=False, bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")

    action = dst.animation_data.action
    action.name = anim_name
    action.use_fake_user = True
    track = dst.animation_data.nla_tracks.new()
    track.name = anim_name
    track.strips.new(anim_name, start, action)
    dst.animation_data.action = None

    for o in imported:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in set(bpy.data.actions) - actions_before - {action}:
        bpy.data.actions.remove(a)
    print(f"[anims] {anim_name} : {end - start + 1} images")


def main():
    args = parse_args()
    rigs = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if len(rigs) != 1:
        raise RuntimeError(f"Le .blend doit contenir exactement une armature (trouvé {len(rigs)})")
    dst = rigs[0]
    if dst.animation_data is None:
        dst.animation_data_create()
    for name in ANIMS:
        path = os.path.join(args.anims, f"{name}.fbx")
        if os.path.exists(path):
            bake_one(dst, path, name, args.in_place)
        else:
            print(f"[anims] absent, ignoré : {path}")

    out_dir = os.path.join(args.out, args.id)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{args.id}.glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True,
                              export_animation_mode="ACTIONS", export_apply=True, export_yup=True)
    print(f"[anims] OK : {out}")


if __name__ == "__main__":
    main()
