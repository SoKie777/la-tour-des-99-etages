"""Génère les personnages avec MPFB (MakeHuman dans Blender) et les exporte en FBX (squelette Mixamo).

Usage : blender --background --python tools/mpfb/make_characters.py -- [id ...]
Les specs sont dans tools/mpfb/characters.json. Les FBX vont dans assets/models/<id>.fbx
"""
import bpy, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")

from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.assetservice import AssetService


def asset(kind, name, ext):
    lst = AssetService.get_asset_list(kind)
    if name not in lst:
        raise RuntimeError("asset %s/%s introuvable (dispo : %s)" % (kind, name, sorted(lst.keys())))
    item = lst[name]
    for k in ("full_path", "fragment", "path"):
        if isinstance(item, dict) and k in item:
            p = item[k]
            break
    else:
        p = item
    if not os.path.isabs(p):
        p = AssetService.find_asset_absolute_path(p)
    return p


def simplify_materials():
    """MPFB utilise des groupes de nœuds que le FBX ne transmet pas : on refait
    des matériaux simples (texture diffuse -> Base Color, alpha pour cheveux/sourcils)."""
    done = {}
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        for slot in ob.material_slots:
            mat = slot.material
            if mat is None or not mat.use_nodes:
                continue
            if mat.name in done:
                slot.material = done[mat.name]
                continue
            imgs = []
            def collect(tree):
                for n in tree.nodes:
                    if n.type == "TEX_IMAGE" and n.image:
                        imgs.append(n)
                    elif n.type == "GROUP" and n.node_tree:
                        collect(n.node_tree)
            collect(mat.node_tree)
            diffuse = None
            for n in imgs:
                key = (n.name + n.label + n.image.name).lower()
                if "diffuse" in key or "albedo" in key or "color" in key:
                    diffuse = n
                    break
            if diffuse is None:
                for n in imgs:
                    key = (n.name + n.label + n.image.name).lower()
                    if "normal" not in key and "bump" not in key and "rough" not in key and "spec" not in key:
                        diffuse = n
                        break
            new = bpy.data.materials.new(mat.name + "_fbx")
            new.use_nodes = True
            nt = new.node_tree
            bsdf = nt.nodes.get("Principled BSDF")
            if diffuse is not None:
                tex = nt.nodes.new("ShaderNodeTexImage")
                tex.image = diffuse.image
                nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
                lname = (ob.name + mat.name).lower()
                if any(k in lname for k in ("hair", "brow", "short", "afro", "braid", "long", "lash")):
                    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
                    new.blend_method = "HASHED" if hasattr(new, "blend_method") else new.blend_method
            print("MAT", ob.name, mat.name, "->", diffuse.image.name if diffuse else "AUCUNE TEXTURE")
            done[mat.name] = new
            slot.material = new


def bone_head(rig, name):
    b = rig.data.bones.get("mixamorig:" + name) or rig.data.bones.get(name)
    return rig.matrix_world @ b.head_local if b else None


def paint(spec, rig):
    """Peint les vêtements / cheveux en couleurs de sommets selon des zones du corps.
    Godot utilise ces couleurs comme couleur de base (rendu aplat façon DBFZ)."""
    import random
    rules = spec.get("paint", {})
    hips = bone_head(rig, "Hips")
    larm = bone_head(rig, "LeftArm")
    lfore = bone_head(rig, "LeftForeArm")
    lhand = bone_head(rig, "LeftHand")
    neck = bone_head(rig, "Neck")
    waist_z = hips.z + 0.06
    shoulder_x = abs(larm.x) * 0.92
    wrist_x = abs(lhand.x)
    rnd = random.Random(98)
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        n = ob.name.lower()
        kind = "hair" if spec.get("hair") and spec["hair"].lower() in n else                "shoes" if "shoes" in n else "clothes" if any(c.lower().replace(" ", "_") in n for c in spec.get("clothes", [])) else None
        if kind is None:
            continue
        me = ob.data
        attr = me.color_attributes.get("Col") or me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
        mw = ob.matrix_world
        def col(key, default):
            c = rules.get(key, default)
            return (c[0], c[1], c[2], 1.0)
        top = col("top", [0.5, 0.5, 0.5])
        bottom = col("bottom", [0.1, 0.1, 0.12])
        for i, v in enumerate(me.vertices):
            w = mw @ v.co
            ax = abs(w.x)
            if kind == "hair":
                c = col("hair", [0.05, 0.04, 0.035])
            elif kind == "shoes":
                c = col("shoes", [0.08, 0.08, 0.08])
            elif w.z < waist_z:
                c = bottom
                if "sparkle" in rules and rnd.random() < 0.022:
                    c = col("sparkle", [1, 1, 1])
                if "stripe_bottom" in rules and abs(ax - 0.1) < 0.015:
                    c = col("stripe_bottom", [1, 1, 1])
            else:
                c = top
                sleeve = ax > shoulder_x
                if sleeve and "sleeve" in rules:
                    c = col("sleeve", top)
                if sleeve and "cuff" in rules and ax > wrist_x - 0.07:
                    c = col("cuff", top)
                if not sleeve and "inner" in rules and ax < rules.get("inner_w", 0.07) and w.y < hips.y                         and w.z < neck.z - 0.02:
                    c = col("inner", top)
                if not sleeve and "stripes" in rules and ((w.x + 1.0) * 9.0) % 1.0 < 0.14:
                    c = col("stripes", top)
                if not sleeve and "collar" in rules and w.z > neck.z - 0.06:
                    c = col("collar", top)
                if not sleeve and "graphic" in rules and w.y < hips.y and abs(w.z - (waist_z + neck.z) / 2) < 0.07                         and ax < 0.13 and rnd.random() < 0.5:
                    c = col("graphic", top)
            attr.data[i].color = c
        me.color_attributes.active_color = attr
        print("PAINT", ob.name, kind, len(me.vertices))


def build(fid, spec):
    # scène vide (sans recharger les préférences, sinon MPFB est désactivé)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    AssetService.update_all_asset_lists()
    macros = dict(spec["macros"])
    macros["race"] = spec.get("race", {"african": 1.0, "asian": 0.0, "caucasian": 0.0})
    basemesh = HumanService.create_human(macro_detail_dict=macros, scale=0.1)
    basemesh.name = fid + "_body"
    # squelette AVANT les vêtements : ils sont alors attachés (et déformés) par le rig
    HumanService.add_builtin_rig(basemesh, "mixamo")
    HumanService.set_character_skin(asset("skins", spec.get("skin", "Young african male"), "mhmat"), basemesh,
                                    skin_type="MAKESKIN")
    HumanService.add_mhclo_asset(asset("eyes", "Low-poly", "mhclo"), basemesh, asset_type="Eyes", subdiv_levels=0)
    HumanService.add_mhclo_asset(asset("eyebrows", spec.get("eyebrows", "Eyebrow001"), "mhclo"), basemesh,
                                 asset_type="Eyebrows", subdiv_levels=0)
    if spec.get("hair"):
        HumanService.add_mhclo_asset(asset("hair", spec["hair"], "mhclo"), basemesh, asset_type="Hair", subdiv_levels=0)
    for c in spec.get("clothes", []):
        HumanService.add_mhclo_asset(asset("clothes", c, "mhclo"), basemesh, asset_type="Clothes", subdiv_levels=0)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    paint(spec, rig)
    simplify_materials()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, fid + ".fbx")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(filepath=path, use_selection=False, object_types={"ARMATURE", "MESH"},
                             use_mesh_modifiers=True, add_leaf_bones=False, bake_anim=False,
                             path_mode="COPY", embed_textures=True, axis_forward="-Z", axis_up="Y", colors_type="LINEAR",
                             apply_scale_options="FBX_SCALE_ALL", bake_space_transform=True)
    print("EXPORTED", fid, path, os.path.getsize(path))


def main():
    specs = json.load(open(os.path.join(HERE, "characters.json"), encoding="utf-8"))
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for fid in (args or specs.keys()):
        try:
            build(fid, specs[fid])
        except Exception as e:
            import traceback
            traceback.print_exc()
            print("FAILED", fid, e)


main()
