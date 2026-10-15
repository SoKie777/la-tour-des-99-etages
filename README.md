# La Tour des 99 Étages

Gacha RPG au tour par tour (3 contre 3, barre d'action), inspiré de Dislyte, en Godot 4.5.

- `docs/GDD.md` : game design (lore, combat, triangle, reliques, gacha, simulations, feuille de route)
- `docs/PIPELINE.md` : outils, installation des MCP, pipeline MakeHuman → Mixamo → Godot
- `data/` : tout l'équilibrage (personnages, règles, gacha, reliques) en JSON
- `scripts/core/` : moteur de combat, gacha et reliques, sans lien avec l'affichage
- `scripts/ui/`, `scenes/` : menu et combat jouable (capsules en attendant les modèles 3D)
- `tests/run_tests.gd` : tests des règles et simulation d'équilibrage en headless
- `tools/blender/` : création des personnages (MPFB2) et application des animations Mixamo

Lancer : ouvrir `project.godot` dans Godot 4.5.1, puis F5.
