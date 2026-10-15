# CLAUDE.md — T99

Jeu : **T99** (anciennement « La Tour des 99 Étages », qui reste le nom de la Tour dans l'univers).
Gacha RPG 3v3 à barre d'action inspiré de Dislyte (sans sa partie musique).
Ne pas changer l'identifiant Android `com.tour99.mvp` : un nouvel identifiant installerait une autre appli (sauvegarde perdue). **Godot 4.7**, GDScript typé.
L'utilisateur ne code pas : il se connecte ou télécharge quand c'est nécessaire (Mixamo, installations).
Il parle français : écrire docs, commits et textes du jeu en français.

## Le PC de l'utilisateur (Windows), déjà équipé
- Godot : `D:\Kleros\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe` (voir les `.bat` à la racine).
  Pour les tests en console, utiliser l'exécutable `_console.exe` du même dossier.
- Blender + MPFB2 + pack makehuman_system_assets, MCP Godot et MCP Blender : déjà utilisés pour **Coup d'État**
  (`SoKie777/coup-detat`, Godot 4.7). Ce projet en reprend le pipeline tel quel ; s'y référer en cas de doute.

## Pipeline (détails : docs/PIPELINE.md)
MPFB2 → `tools/mpfb/make_characters.py` → `assets/models/<id>.fbx` (squelette Mixamo)
Mixamo → `assets/mixamo/anims/*.fbx` (Without Skin)
→ `python tools/set_retarget.py` (BoneMap `assets/mixamo/mixamo_bonemap.tres` dans les .import)
→ Godot : `scripts/ui/character_model.gd` charge le modèle (ou le Y Bot) et joue les anims (`MAP`).
- MPFB s'importe par `from bl_ext.blender_org.mpfb.services...` ; les assets se désignent par leur nom affiché.
- Mixamo n'a pas d'API : demander à l'utilisateur de faire les téléchargements.
- `coup-detat/assets/mixamo/anims/` contient 32 animations réutilisables (copier aussi les `.import`).

## Règles du code
- `scripts/core/` ne dépend jamais de l'affichage. Toute règle de combat se teste dans `tests/run_tests.gd`.
- L'équilibrage est dans `data/*.json`, pas dans le code.
- Référence du design : `docs/GDD.md`. En cas de conflit entre la Bible et le doc MVP, le doc MVP gagne.
- Avant chaque commit : `godot --headless --path . --script res://tests/run_tests.gd -- --sims=100`
  (0 échec) et `godot --headless --path . res://scenes/battle.tscn -- --smoke`.

## Livraison
Fin d'une grosse étape = incrémenter `VERSION` et pousser sur `main`. GitHub Actions publie l'APK dans
la Release `vX.Y.Z` et dans `apk-latest`. Vérifier le run et donner le lien à l'utilisateur.
