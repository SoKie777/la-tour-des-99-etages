# CLAUDE.md — La Tour des 99 Étages

Gacha RPG 3v3 à barre d'action inspiré de Dislyte (sans sa partie musique). Godot 4.5.1, GDScript typé.
L'utilisateur ne code pas : il se connecte ou télécharge quand c'est nécessaire (Mixamo, installations).
Il parle français ; écrire docs, commits et textes du jeu en français.

## Pipeline (à respecter)
MPFB2 dans Blender (corps + squelette « mixamo ») → animations Mixamo (6 FBX téléchargés une fois, X Bot,
Without Skin) → `tools/blender/apply_mixamo_anims.py` → `assets/characters/<id>/<id>.glb` → Godot.
- MCP Godot : `@coding-solo/godot-mcp`. MCP Blender : `mcp-for-blender`.
- Mixamo n'a pas d'API : demander à l'utilisateur de faire les téléchargements.
- Noms d'animations attendus par le jeu : idle, attack, skill, ultimate, hit, death.

## Règles du code
- `scripts/core/` ne dépend jamais de l'affichage. Toute règle de combat se teste dans `tests/run_tests.gd`.
- L'équilibrage est dans `data/*.json`, pas dans le code.
- Le doc de référence du design est `docs/GDD.md` ; en cas de conflit entre la Bible et le doc MVP, le doc MVP gagne.
- Avant chaque commit : `godot --headless --path . --script res://tests/run_tests.gd -- --sims=100`
  (0 échec) et le test de fumée `godot --headless --path . res://scenes/battle.tscn -- --smoke`.

## Livraison
Fin d'une grosse étape = incrémenter `VERSION` et pousser sur `main` : GitHub Actions publie l'APK dans les
Releases. Vérifier le run et donner le lien à l'utilisateur.
