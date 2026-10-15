"""Active le retargeting humanoïde (BoneMap Mixamo) dans les .import de tous les FBX du jeu.
À relancer après l'ajout de nouveaux FBX (persos MPFB ou animations Mixamo)."""
import glob, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BONEMAP = 'Resource("res://assets/mixamo/mixamo_bonemap.tres")'


def skeleton_path(fbx):
    if "/models/" in fbx.replace("\\", "/"):
        return os.path.splitext(os.path.basename(fbx))[0] + "_body_rig/Skeleton3D"
    return "Skeleton3D"


def patch(imp):
    fbx = imp[:-len(".import")]
    sub = ('_subresources={\n"nodes": {\n"PATH:%s": {\n"retarget/bone_map": %s,\n'
           '"retarget/bone_renamer/rename_bones": true,\n"retarget/bone_renamer/unique_node/make_unique": false,\n'
           '"retarget/rest_fixer/apply_node_transforms": true,\n"retarget/rest_fixer/normalize_position_tracks": true,\n'
           '"retarget/rest_fixer/overwrite_axis": true,\n"retarget/rest_fixer/fix_silhouette/enable": true\n}\n}\n}') % (
               skeleton_path(fbx), BONEMAP)
    s = open(imp, encoding="utf-8").read()
    s2 = re.sub(r"_subresources=\{.*?\n\}(?=\n[a-z_/]+=|\s*$)|_subresources=\{\}", sub, s, count=1, flags=re.S)
    if s2 != s:
        open(imp, "w", encoding="utf-8", newline="\n").write(s2)
        print("ok", os.path.relpath(fbx, ROOT))


for imp in glob.glob(os.path.join(ROOT, "assets", "**", "*.fbx.import"), recursive=True):
    patch(imp)
