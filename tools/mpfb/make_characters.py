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
from bl_ext.blender_org.mpfb.services.targetservice import TargetService

# Style « gacha » des Légendaires (v0.10) : tête un peu plus grande, grands yeux, nez et bouche
# plus fins, mâchoire en V, jambes plus longues. Valeurs des cibles MPFB (0 à 1) ; une fiche peut les
# ajuster avec "targets" (une valeur à 0 retire la cible).
STYLE = {
    "head-scale-vert-incr": 0.6, "head-scale-horiz-incr": 0.45, "head-scale-depth-incr": 0.3, "head-age-decr": 1.0,
    "head-oval": 0.5, "l-eye-scale-incr": 1.0, "r-eye-scale-incr": 1.0, "l-eye-height2-incr": 0.25, "r-eye-height2-incr": 0.25,
    "l-eye-trans-down": 0.3, "r-eye-trans-down": 0.3, "l-eye-bag-decr": 0.8, "r-eye-bag-decr": 0.8,
    "nose-scale-horiz-decr": 0.6, "nose-scale-vert-decr": 0.4, "nose-volume-decr": 0.8, "nose-point-width-decr": 0.5,
    "mouth-scale-horiz-decr": 0.3, "chin-width-decr": 0.7, "chin-prominent-decr": 0.4, "chin-height-decr": 0.3,
    "l-cheek-bones-decr": 0.5, "r-cheek-bones-decr": 0.5,
    "neck-scale-horiz-decr": 0.35, "measure-upperleg-height-incr": 0.6, "lowerlegs-height-incr": 0.5,
}


def rarity(fid):
    data = json.load(open(os.path.join(ROOT, "data", "characters.json"), encoding="utf-8"))
    return next((int(c["rarity"]) for c in data["characters"] if c["id"] == fid), 0)


def apply_style(basemesh, spec):
    targets = dict(STYLE)
    targets.update(spec.get("targets", {}))
    for name, v in targets.items():
        if not v:
            continue
        path = TargetService.target_full_path(name)
        if not path:
            print("CIBLE INCONNUE", name)
            continue
        TargetService.load_target(basemesh, path, weight=float(v), name=name)


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
            if diffuse is not None:  # taille utile à l'écran d'un téléphone (APK et dépôt plus légers)
                oname = ob.name.lower()
                if any(k in oname for k in ("suit", "shoes", "fedora", "robe", "ninja", "tunic", "jacket", "pants", "boots", "dress", "uniform")):
                    side = 16  # vêtements peints en couleurs de sommets : la texture n'est pas affichée
                elif "eye" in oname or "brow" in oname or "lash" in oname:
                    side = 256
                elif ob.type == "MESH" and ob.name.endswith("_body"):
                    side = 1024
                else:
                    side = 512  # cheveux
                img = diffuse.image
                if img.size[0] > side:
                    import tempfile, re
                    img.scale(side, side)
                    # l'export FBX embarque le fichier : on enregistre la version réduite
                    tmp = os.path.join(tempfile.gettempdir(), "t99_textures")
                    os.makedirs(tmp, exist_ok=True)
                    img.filepath_raw = os.path.join(tmp, re.sub(r"[^A-Za-z0-9_.-]", "_", img.name) + "_%d.png" % side)
                    img.file_format = "PNG"
                    img.save()
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


def col_list(c):
    return (c[0], c[1], c[2], 1.0)


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
        kind = "hair" if (spec.get("hair") and spec["hair"].lower() in n) or n.endswith("_locs") else                "shoes" if "shoes" in n else "clothes" if any(c.lower().replace(" ", "_") in n for c in spec.get("clothes", [])) else None
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
            if kind == "clothes":
                pt = rules.get("patch")  # kente : carrés multicolores sur un pan et sa manche (le côté gauche = +X)
                if pt and (w.x > 0) == (pt.get("side", "left") == "left") and ax > 0.035 \
                        and w.z > waist_z - float(pt.get("down", 0.6)):
                    sz = float(pt.get("size", 0.05))
                    cell = (int((w.x + 5.0) / sz), int((w.z + 5.0) / sz))
                    pal = pt["colors"]
                    k = pal[(cell[0] * 7 + cell[1] * 3) % len(pal)]
                    c = (k[0], k[1], k[2], 1.0)
                fl = rules.get("hem_flames")  # flammes qui montent du bas du manteau
                if fl:
                    import math
                    limit = float(fl.get("height", 0.45)) + 0.07 * math.sin(w.x * 45.0) + 0.05 * math.sin(w.y * 33.0 + w.x * 12.0)
                    if w.z < limit - 0.1:
                        c = col_list(fl.get("core", fl["color"]))
                    elif w.z < limit:
                        c = col_list(fl["color"])
            attr.data[i].color = c
        me.color_attributes.active_color = attr
        print("PAINT", ob.name, kind, len(me.vertices))


def add_strands(fid, cfg, basemesh, rig):
    """Coiffures générées, absentes de MakeHuman. Les mèches partent du cuir chevelu, suivent le crâne
    (collision avec le corps) puis retombent. Attachées à 100 % à l'os de la tête.
    cfg["style"] :
      - "twists"  : two-strand twists (deux tubes enroulés en hélice), cfg : count, length, radius, front_length ;
      - "curtain" : raie au milieu, mèches plates épaisses qui tombent de part et d'autre du front, cfg : count,
                    front_length, side_length, back_length, width, thickness."""
    import bmesh, math, random
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    rnd = random.Random(7)
    style = cfg.get("style", "twists")
    head_bone = rig.data.bones.get("mixamorig:Head") or rig.data.bones.get("Head")
    dg = bpy.context.evaluated_depsgraph_get()
    ev = basemesh.evaluated_get(dg)
    me = ev.to_mesh()
    mw = basemesh.matrix_world
    gi = basemesh.vertex_groups[head_bone.name].index
    pts = []
    for v in me.vertices:
        if any(g.group == gi and g.weight > 0.5 for g in v.groups):
            pts.append((mw @ v.co, (mw.to_3x3() @ v.normal).normalized()))
    bvh = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(f.vertices) for f in me.polygons])
    ev.to_mesh_clear()
    xs = [q[0].x for q in pts]; ys = [q[0].y for q in pts]; zs = [q[0].z for q in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    zmin, zmax = min(zs), max(zs)
    h = zmax - zmin

    def zone(w):  # l'avant du personnage est vers -Y
        if w.y < cy - 0.03 and abs(w.x - cx) < 0.06:
            return "front"
        if w.y > cy + 0.015:
            return "back"
        return "side"

    def scalp(w):
        return w.z > zmin + h * {"front": 0.8, "side": 0.66, "back": 0.4}[zone(w)]

    cands = [q for q in pts if scalp(q[0])]
    rnd.shuffle(cands)
    spacing = float(cfg.get("spacing", 0.021 if style == "twists" else 0.011))
    roots = []
    for w, n in cands:
        if style == "curtain" and abs(w.x - cx) < 0.004:
            continue  # la raie
        if all((w - r[0]).length > spacing for r in roots):
            roots.append((w, n))
        if len(roots) >= int(cfg.get("count", 60)):
            break

    def surface(p, off):
        loc, nrm, _i, dist = bvh.find_nearest(p)
        if loc is None:
            return p, Vector((0, 0, 1))
        if (p - loc).dot(nrm) < off:  # dans le corps ou trop près : ramené à la surface
            p = loc + nrm * off
        return p, nrm

    bm = bmesh.new()

    def tube(line, normals, ring_fn, sides):
        prev = None
        for i, c in enumerate(line):
            tang = (line[min(i + 1, len(line) - 1)] - line[max(i - 1, 0)]).normalized()
            ax = tang.cross(normals[i])
            if ax.length < 1e-5:
                ax = tang.cross(Vector((0, 0, 1)))
            ax.normalize()
            ay = ax.cross(tang).normalized()
            verts = [bm.verts.new(c + off) for off in ring_fn(i / (len(line) - 1), ax, ay)]
            if prev:
                for k in range(sides):
                    bm.faces.new((prev[k], prev[(k + 1) % sides], verts[(k + 1) % sides], verts[k]))
            prev = verts

    for w, n in roots:
        z = zone(w)
        side = math.copysign(1.0, w.x - cx) if abs(w.x - cx) > 1e-4 else 1.0
        if style == "twists":
            rad = float(cfg.get("radius", 0.0042))
            off = rad * 1.3
            lo, hi = cfg.get("length", [0.13, 0.2])
            length = rnd.uniform(lo, hi) * (float(cfg.get("front_length", 0.5)) if z == "front" else 1.0)
            bias = Vector((side * (0.9 if z == "front" else 0.15), 0.35 if z != "back" else 0.25, -1.0))
        else:
            rad = 0.0
            off = float(cfg.get("thickness", 0.005)) * 0.9
            length = float(cfg.get(z + "_length", 0.09)) * rnd.uniform(0.85, 1.1)
            bias = Vector((side * (1.6 if z == "front" else 0.5), 0.1 if z == "front" else 0.6, -1.0))
        bias.normalize()
        g = Vector((0, 0, -1))
        d = (bias - n * bias.dot(n))
        d = d.normalized() if d.length > 1e-5 else bias
        p, nrm = surface(w + n * off, off)
        line, normals = [p], [nrm]
        steps = 14
        for i in range(steps):
            d = (d * 0.7 + (bias * 0.6 + g * 0.4).normalized() * 0.3).normalized()
            p, nrm = surface(line[-1] + d * (length / steps), off)
            d = (p - line[-1]).normalized()
            line.append(p)
            normals.append(nrm)
        if style == "twists":
            turns = length / 0.022
            for phase in (0.0, math.pi):
                def ring(t, ax, ay, phase=phase):
                    a = phase + t * turns * 2 * math.pi
                    r_tube = rad * 0.62 * (1.0 - 0.45 * t)
                    c = (ax * math.cos(a) + ay * math.sin(a)) * rad * 0.45
                    return [c + (ax * math.cos(k / 5 * 2 * math.pi) + ay * math.sin(k / 5 * 2 * math.pi)) * r_tube for k in range(5)]
                tube(line, normals, ring, 5)
        else:
            wid = float(cfg.get("width", 0.016)) * rnd.uniform(0.85, 1.15)
            th = float(cfg.get("thickness", 0.005))
            def ring(t, ax, ay):
                k = max(0.08, 1.0 - t ** 1.6)  # pointe effilée
                return [ax * math.cos(j / 6 * 2 * math.pi) * wid * 0.5 * k + ay * math.sin(j / 6 * 2 * math.pi) * th * 0.5 * (0.4 + 0.6 * k)
                        for j in range(6)]
            tube(line, normals, ring, 6)
    if cfg.get("cap", 0.0):  # calotte : le cuir chevelu recouvert, légèrement décollé du crâne
        ev = basemesh.evaluated_get(dg)
        me = ev.to_mesh()
        cap_off = float(cfg["cap"])
        idx = {}
        for v in me.vertices:
            w = mw @ v.co
            if any(g.group == gi and g.weight > 0.5 for g in v.groups) and scalp(w):
                idx[v.index] = bm.verts.new(w + (mw.to_3x3() @ v.normal).normalized() * cap_off)
        for f in me.polygons:
            if all(i in idx for i in f.vertices):
                bm.faces.new([idx[i] for i in f.vertices])
        ev.to_mesh_clear()
    mesh = bpy.data.meshes.new(fid + "_locs")
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    ob = bpy.data.objects.new(fid + "_locs", mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = rig
    vg = ob.vertex_groups.new(name=head_bone.name)
    vg.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    mesh.materials.append(bpy.data.materials.new(fid + "_locs_mat"))
    print("STRANDS", fid, style, len(roots), "mèches", len(mesh.vertices), "sommets")
    return ob


def preview(fid, path):
    """Rendu de contrôle (corps entier + gros plan de la tête) au lieu de l'export."""
    import math
    from mathutils import Vector
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for ob in bpy.data.objects:  # comme dans Godot : couleurs peintes (vêtements, cheveux) en couleur de base
        if ob.type == "MESH" and ob.data.color_attributes.get("Col"):
            for slot in ob.material_slots:
                nt = slot.material.node_tree
                bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
                vc = nt.nodes.new("ShaderNodeVertexColor")
                vc.layer_name = "Col"
                nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    hb = rig.data.bones.get("mixamorig:Head")
    head = rig.matrix_world @ hb.head_local + Vector((0, 0, 0.09))
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(55), 0, math.radians(25))
    sun.data.energy = 3.0
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    sc.render.resolution_x, sc.render.resolution_y = 520, 620
    shots = [("front", Vector((0, -1, 0)), 0.42), ("trois_quarts", Vector((0.75, -0.75, 0.05)), 0.42),
             ("dos", Vector((0, 1, 0.05)), 0.42), ("corps", Vector((0.3, -1, 0)), 2.0)]
    for name, d, scale in shots:
        target = head if name != "corps" else Vector((head.x, head.y, head.z * 0.52))
        cam.location = target + d.normalized() * 3.0
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = scale
        sc.render.filepath = path.replace(".png", "_%s.png" % name)
        bpy.ops.render.render(write_still=True)
    print("PREVIEW", fid, path)


def build(fid, spec, preview_path=None):
    # scène vide (sans recharger les préférences, sinon MPFB est désactivé)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    AssetService.update_all_asset_lists()
    macros = dict(spec["macros"])
    macros["race"] = spec.get("race", {"african": 1.0, "asian": 0.0, "caucasian": 0.0})
    basemesh = HumanService.create_human(macro_detail_dict=macros, scale=0.1)
    basemesh.name = fid + "_body"
    if not spec.get("realistic") and rarity(fid) == 5:  # style gacha : légendaires seulement
        apply_style(basemesh, spec)
    # squelette AVANT les vêtements : ils sont alors attachés (et déformés) par le rig
    HumanService.add_builtin_rig(basemesh, "mixamo")
    HumanService.set_character_skin(asset("skins", spec.get("skin", "Young african male"), "mhmat"), basemesh,
                                    skin_type="MAKESKIN")
    HumanService.add_mhclo_asset(asset("eyes", "Low-poly", "mhclo"), basemesh, asset_type="Eyes", subdiv_levels=0)
    HumanService.add_mhclo_asset(asset("eyebrows", spec.get("eyebrows", "Eyebrow001"), "mhclo"), basemesh,
                                 asset_type="Eyebrows", subdiv_levels=0)
    if spec.get("eyelashes", "Eyelashes01"):
        HumanService.add_mhclo_asset(asset("eyelashes", spec.get("eyelashes", "Eyelashes01"), "mhclo"), basemesh,
                                     asset_type="Eyelashes", subdiv_levels=0)
    if spec.get("hair"):
        HumanService.add_mhclo_asset(asset("hair", spec["hair"], "mhclo"), basemesh, asset_type="Hair", subdiv_levels=0)
    for c in spec.get("clothes", []):
        HumanService.add_mhclo_asset(asset("clothes", c, "mhclo"), basemesh, asset_type="Clothes", subdiv_levels=0)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    if spec.get("strands"):
        add_strands(fid, spec["strands"], basemesh, rig)
    paint(spec, rig)
    simplify_materials()
    if preview_path:
        preview(fid, preview_path)
        return
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
    preview_dir = None
    if "--preview" in args:  # -- --preview <dossier> id... : rendus de contrôle, pas d'export
        i = args.index("--preview")
        preview_dir = args[i + 1]
        args = args[:i] + args[i + 2:]
    if "--realistic" in args:  # comparaison : sans le style gacha
        args.remove("--realistic")
        for sp in specs.values():
            sp["realistic"] = True
    for fid in (args or specs.keys()):
        try:
            build(fid, specs[fid], os.path.join(preview_dir, fid + ".png") if preview_dir else None)
        except Exception as e:
            import traceback
            traceback.print_exc()
            print("FAILED", fid, e)


main()
