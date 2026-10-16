"""Convertit un personnage VRoid (.vrm) en FBX au format du jeu (squelette Mixamo, matériaux simples).

    blender --background --python tools/vroid/vrm_to_fbx.py -- <id> <fichier.vrm> [--locs] [--gold] [--preview <dossier>]

- os du squelette renommés en « mixamorig:* » (même BoneMap que les modèles MPFB) ;
- un objet par matériau, nommé d'après son rôle (body, face, eye_*, brow, hair…) pour character_model.gd ;
- --locs : remplace les cheveux VRoid par des locks torsadées noires (vanilla twists), générées ici ;
- --gold : repeint en or (#D1AD62) le rouge des textures de vêtements ;
- --amethyst : repeint en violet le bleu des vêtements ;
- --preview : rendus de contrôle au lieu de l'export.
Il faut l'extension « VRM Add-on for Blender » (blender --command extension install vrm --enable).
Réservé aux Légendaires (style gacha).
"""
import bpy, bmesh, math, os, random, re, sys, tempfile
from mathutils import Vector, Matrix
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "assets", "models")

# os humanoïdes VRM -> noms Mixamo
MIXAMO = {
    "hips": "Hips", "spine": "Spine", "chest": "Spine1", "upperChest": "Spine2", "neck": "Neck", "head": "Head",
    "leftUpperLeg": "LeftUpLeg", "leftLowerLeg": "LeftLeg", "leftFoot": "LeftFoot", "leftToes": "LeftToeBase",
    "rightUpperLeg": "RightUpLeg", "rightLowerLeg": "RightLeg", "rightFoot": "RightFoot", "rightToes": "RightToeBase",
    "leftShoulder": "LeftShoulder", "leftUpperArm": "LeftArm", "leftLowerArm": "LeftForeArm", "leftHand": "LeftHand",
    "rightShoulder": "RightShoulder", "rightUpperArm": "RightArm", "rightLowerArm": "RightForeArm", "rightHand": "RightHand",
}
for side, S in (("left", "Left"), ("right", "Right")):
    for vf, mf in (("Thumb", "Thumb"), ("Index", "Index"), ("Middle", "Middle"), ("Ring", "Ring"), ("Little", "Pinky")):
        for k, (vp, n) in enumerate((("Proximal", 1), ("Intermediate", 2), ("Distal", 3))):
            MIXAMO[side + vf + vp] = "%sHand%s%d" % (S, mf, n)

# rôle d'un matériau VRoid -> nom d'objet (les mots-clés sont lus par character_model.gd)
ROLES = [("EyeIris", "eye_iris"), ("EyeHighlight", "eye_highlight"), ("EyeWhite", "eye_white"),
         ("FaceEyeline", "eye_line"), ("FaceEyelash", "eye_lash"), ("FaceBrow", "brow"), ("FaceMouth", "mouth"),
         ("Face_", "face"), ("HairBack", "hair_back"), ("Hair", "hair"), ("Body", "body"), ("Tops", "jacket"),
         ("Bottoms", "pants"), ("Shoes", "shoes"), ("Accessory", "accessory")]
SIDE = {"eye": 256, "brow": 256, "mouth": 256, "face": 1024, "body": 1024}  # taille max des textures
GOLD = (0.819, 0.678, 0.384)


def role(mat_name):
    for key, r in ROLES:
        if key in mat_name:
            return r
    return "part"


def import_vrm(path):
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.vrm(filepath=path)
    for ob in list(bpy.data.objects):  # colliders des spring bones : inutiles en jeu
        if ob.type == "EMPTY":
            bpy.data.objects.remove(ob, do_unlink=True)
    return next(o for o in bpy.data.objects if o.type == "ARMATURE")


def rename_bones(arm, fid):
    hb = arm.data.vrm_addon_extension.vrm0.humanoid.human_bones
    pairs = [(b.node.bone_name, MIXAMO[b.bone]) for b in hb if b.bone in MIXAMO and b.node.bone_name]
    for old, new in pairs:
        bone = arm.data.bones.get(old)
        if bone:
            bone.name = "mixamorig:" + new  # renomme aussi les groupes de sommets
    arm.name = fid + "_body_rig"
    arm.data.name = fid + "_body_rig"


def mesh_objects():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def split_by_material(fid):
    for ob in mesh_objects():
        if ob.data.shape_keys:
            ob.shape_key_clear()
        for a in list(ob.data.color_attributes):  # pas de couleurs de sommets : on garde les textures
            ob.data.color_attributes.remove(a)
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.separate(type="MATERIAL")
        bpy.ops.object.mode_set(mode="OBJECT")
    for ob in mesh_objects():
        used = {p.material_index for p in ob.data.polygons}
        mats = [ob.material_slots[i].material for i in used if ob.material_slots[i].material]
        r = role(mats[0].name) if mats else "part"
        ob.name = "%s_%s" % (fid, r)


def main_texture(mat):
    """Texture de couleur principale (MToon : Lit Color Texture), sinon la première image utile."""
    try:
        src = mat.vrm_addon_extension.mtoon1.pbr_metallic_roughness.base_color_texture.index.source
        if src:
            return src
    except AttributeError:
        pass
    imgs = []
    def collect(tree):
        for n in tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and "NoneBlack" not in n.image.name:
                imgs.append(n.image)
            elif n.type == "GROUP" and n.node_tree:
                collect(n.node_tree)
    if mat.node_tree:
        collect(mat.node_tree)
    return imgs[0] if imgs else None


def gold_recolor(img):
    """Rouge saturé -> or ancien, en gardant la luminosité (revers, foulard, doublure)."""
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / np.maximum(mx, 1e-5)
    red = (r == mx) & (sat > 0.35) & (g < r * 0.7) & (b < r * 0.75)
    lum = mx[red] / 0.75
    for c in range(3):
        px[red, c] = np.clip(GOLD[c] * lum, 0, 1)
    img.pixels[:] = px.ravel()
    print("OR", img.name, int(red.sum()), "pixels")


def amethyst_recolor(img):
    """Bleu -> violet améthyste (robe de Géode), en gardant la luminosité."""
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    blue = (b > r * 1.25) & (b > g * 1.15)
    px[blue, 0] = np.clip(b[blue] * 0.78, 0, 1)
    px[blue, 1] = np.clip(g[blue] * 0.6, 0, 1)
    img.pixels[:] = px.ravel()
    print("AMETHYSTE", img.name, int(blue.sum()), "pixels")


def simplify_materials(gold, amethyst=False):
    done = {}
    tmp = os.path.join(tempfile.gettempdir(), "t99_vroid_textures")
    os.makedirs(tmp, exist_ok=True)
    for ob in mesh_objects():
        r = ob.name.split("_", 1)[1]
        for slot in ob.material_slots:
            mat = slot.material
            if mat is None:
                continue
            if mat.name in done:
                slot.material = done[mat.name]
                continue
            img = main_texture(mat)
            if img is not None:
                side = next((v for k, v in SIDE.items() if r.startswith(k)), 1024)
                if gold and r.split(".")[0] in ("jacket", "pants", "shoes"):
                    gold_recolor(img)
                if amethyst and r.split(".")[0] in ("jacket", "pants", "shoes", "part", "accessory"):
                    amethyst_recolor(img)
                if img.size[0] > side:
                    img.scale(side, side)
                path = os.path.join(tmp, re.sub(r"[^A-Za-z0-9_.-]", "_", ob.name) + ".png")
                img.filepath_raw = path
                img.file_format = "PNG"
                img.save()
                img = bpy.data.images.load(path)  # image du disque : l'export n'embarque plus l'original empaqueté
            new = bpy.data.materials.new(ob.name + "_mat")
            new.use_nodes = True
            nt = new.node_tree
            bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            if img is not None:
                tex = nt.nodes.new("ShaderNodeTexImage")
                tex.image = img
                nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
                if r.split(".")[0] not in ("body", "face", "jacket", "pants", "shoes"):
                    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            print("MAT", ob.name, mat.name, "->", img.name if img else "AUCUNE TEXTURE")
            done[mat.name] = new
            slot.material = new


# ---------------------------------------------------------------- locks

def head_mesh():
    return next(o for o in mesh_objects() if o.name.endswith("_face"))


def head_bmesh():
    """Peau de toute la tête en repère monde : visage + haut du corps (VRoid met le crâne dans le corps)."""
    face = head_mesh()
    body = next(o for o in mesh_objects() if o.name.endswith("_body"))
    fz = [(face.matrix_world @ v.co).z for v in face.data.vertices]
    chin = min(fz)
    bm = bmesh.new()
    for ob in (face, body):
        part = bmesh.new()
        part.from_mesh(ob.data)
        part.transform(ob.matrix_world)
        bmesh.ops.delete(part, geom=[v for v in part.verts if v.co.z < chin], context="VERTS")
        tmp = bpy.data.meshes.new("tmp_head")
        part.to_mesh(tmp)
        part.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    bm.normal_update()
    return bm


def make_scalp(fid):
    """Calotte : copie du crâne au-dessus de la ligne des cheveux, décollée de quelques millimètres."""
    bm = head_bmesh()
    zs = sorted(v.co.z for v in bm.verts)
    ys = sorted(v.co.y for v in bm.verts)
    top, chin = zs[-1], zs[0]
    h = top - chin
    front_y = ys[0]
    cy = (ys[0] + ys[-1]) / 2
    kill = []
    for v in bm.verts:
        fr = (cy - v.co.y) / max(cy - front_y, 1e-4)  # 1 au front, <0 derrière
        line = chin + h * (0.80 if fr > 0.3 else 0.62 + 0.18 * max(fr, 0) / 0.3 if fr > 0 else 0.30 + 0.32 * (fr + 1))
        if v.co.z < line:
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    for v in bm.verts:
        v.co += v.normal * 0.004
    me = bpy.data.meshes.new(fid + "_twists_scalp")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(fid + "_twists_scalp", me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob, (top, chin, front_y, cy)


def loc_path(root, normal, bvh, dims, length, rng):
    """Trajet d'une lock : part du cuir chevelu, retombe sous la gravité en glissant sur la tête."""
    top, chin, front_y, cy = dims
    h = top - chin
    pts = [root.copy()]
    down = Vector((0, 0, -1))
    fr = (cy - root.y) / max(cy - front_y, 1e-4)
    flat = Vector((normal.x, normal.y, 0))
    if flat.length < 0.25:  # sommet du crâne : la lock part sur le côté ou vers l'arrière, jamais vers le ciel
        flat = Vector((rng.uniform(-1, 1), rng.uniform(0.3, 1), 0))
    flat.normalize()
    if fr > 0.3:  # front : coiffées vers l'arrière
        flat = Vector((flat.x * 0.6, 1, 0)).normalized()
    d = (flat * 0.7 + down * 0.5).normalized()
    steps = 36
    step = length / steps
    gap = 0.012
    for i in range(steps):
        d = (d * 0.8 + down * 0.2 + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * 0.015).normalized()
        p = pts[-1] + d * step
        loc, nrm, _, dist = bvh.find_nearest(p)
        if loc is not None and (p - loc).dot(nrm) < gap:
            p = loc + nrm * gap
        # jamais devant le visage : écarté vers la joue
        if p.y < cy - (cy - front_y) * 0.35 and abs(p.x) < h * 0.36 and p.z < chin + h * 0.82:
            p.x = math.copysign(h * 0.36, p.x if abs(p.x) > 1e-4 else rng.uniform(-1, 1))
        pts.append(p)
    return pts


def tube(bm, pts, radius, rng):
    """Torsade à deux brins : section à deux lobes qui tourne le long de la lock."""
    ring_n = 8
    phase = rng.uniform(0, math.tau)
    rings = []
    n = len(pts)
    for i, p in enumerate(pts):
        t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        t.normalize()
        a = t.orthogonal().normalized()
        b = t.cross(a).normalized()
        taper = 1.0 if i < n - 4 else 0.6 + 0.1 * (n - 1 - i)
        ring = []
        for k in range(ring_n):
            th = math.tau * k / ring_n
            twist = phase + i * 0.9
            rr = radius * taper * (1.0 + 0.22 * math.cos(2 * (th - twist)))
            ring.append(bm.verts.new(p + (a * math.cos(th) + b * math.sin(th)) * rr))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(ring_n):
            k2 = (k + 1) % ring_n
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def make_locs(arm, fid, count=78, seed=7):
    from mathutils.bvhtree import BVHTree
    for ob in mesh_objects():  # cheveux VRoid retirés
        if "_hair" in ob.name:
            bpy.data.objects.remove(ob, do_unlink=True)
    rng = random.Random(seed)
    scalp, dims = make_scalp(fid)
    top, chin, front_y, cy = dims
    h = top - chin
    hb = head_bmesh()
    bvh = BVHTree.FromBMesh(hb)
    # racines : sommets de la calotte, espacés régulièrement
    cand = [(scalp.matrix_world @ v.co, v.normal.copy()) for v in scalp.data.vertices]
    rng.shuffle(cand)
    roots = []
    for co, nrm in cand:
        if all((co - r[0]).length > h * 0.085 for r in roots):
            roots.append((co, nrm))
        if len(roots) >= count:
            break
    bm = bmesh.new()
    for co, nrm in roots:
        tube(bm, loc_path(co, nrm, bvh, dims, h * rng.uniform(1.05, 1.35), rng), h * rng.uniform(0.032, 0.04), rng)
    me = bpy.data.meshes.new(fid + "_twists")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(fid + "_twists", me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    mat = bpy.data.materials.new(fid + "_twists_mat")
    mat.use_nodes = True
    bsdf = next(nn for nn in mat.node_tree.nodes if nn.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.03, 0.022, 0.018, 1)
    bsdf.inputs["Roughness"].default_value = 0.55
    for o in (ob, scalp):
        o.data.materials.append(mat)
        vg = o.vertex_groups.new(name="mixamorig:Head")  # les locks suivent la tête
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        o.parent = arm
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    print("LOCKS", len(roots))


# ---------------------------------------------------------------- sortie

def preview(fid, out_dir):
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.55, 0.55, 0.6, 1)
    bg.inputs["Strength"].default_value = 1.2
    sc.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    sc.render.resolution_x, sc.render.resolution_y = 600, 700
    face = next(o for o in mesh_objects() if o.name.endswith("_face"))
    vs = [face.matrix_world @ v.co for v in face.data.vertices]
    head = sum(vs, Vector()) / len(vs)
    os.makedirs(out_dir, exist_ok=True)
    shots = [("face", Vector((0, -1, 0)), 0.55), ("trois_quarts", Vector((0.75, -0.75, 0.05)), 0.55),
             ("dos", Vector((0, 1, 0.05)), 0.6), ("corps", Vector((0.4, -1, 0)), 2.1)]
    for name, d, scale in shots:
        target = head if name != "corps" else Vector((head.x, head.y, head.z * 0.52))
        cam.location = target + d.normalized() * 4.0
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.ortho_scale = scale
        sc.render.filepath = os.path.join(out_dir, "%s_%s.png" % (fid, name))
        bpy.ops.render.render(write_still=True)
    print("PREVIEW", out_dir)


def export(fid):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, fid + ".fbx")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(filepath=path, use_selection=False, object_types={"ARMATURE", "MESH"},
                             use_mesh_modifiers=True, add_leaf_bones=False, bake_anim=False,
                             path_mode="COPY", embed_textures=True, axis_forward="-Z", axis_up="Y", colors_type="LINEAR",
                             apply_scale_options="FBX_SCALE_ALL", bake_space_transform=True)
    print("EXPORTED", fid, path, os.path.getsize(path))


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    preview_dir = None
    if "--preview" in args:
        i = args.index("--preview")
        preview_dir = args[i + 1]
        del args[i:i + 2]
    locs = "--locs" in args
    gold = "--gold" in args
    amethyst = "--amethyst" in args
    args = [a for a in args if not a.startswith("--")]
    fid, vrm = args[0], args[1]
    arm = import_vrm(vrm)
    rename_bones(arm, fid)
    split_by_material(fid)
    simplify_materials(gold, amethyst)
    if locs:
        make_locs(arm, fid)
    if preview_dir:
        preview(fid, preview_dir)
    else:
        export(fid)


main()
