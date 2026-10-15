# Pipeline de production : qui fait quoi

Objectif : tu ne fais que te connecter ou télécharger. Le reste passe par Claude et ses MCP.

## Ce qui est possible depuis où

| Tâche | Session cloud (claude.ai/code) | Claude Code ou Claude Desktop **sur ton PC** |
|---|---|---|
| Code GDScript, données, tests headless, simulations | Oui (fait ici avec Godot 4.5.1 headless) | Oui |
| Piloter l'éditeur Godot (scènes, lancer le jeu, captures) | Non | Oui, via **godot-mcp** |
| Piloter Blender (MakeHuman, rig, export) | Non (Blender bloqué par le réseau de cette session) | Oui, via **Blender MCP** ou les scripts `tools/blender` |
| Mixamo (site Adobe, connexion obligatoire, pas d'API) | Non | Toi : connexion et téléchargements. Ou Claude in Chrome si tu l'utilises |
| Export Android ou iOS | Non | Oui (modèles d'export Godot à télécharger) |

En pratique : le gameplay, l'équilibrage et l'interface peuvent avancer ici. La 3D et l'éditeur
Godot demandent une session **sur ta machine**.

## Installation sur ton PC (une seule fois)

Ce que tu dois télécharger ou installer :
1. **Godot 4.5.1** : https://godotengine.org/download (version standard, pas .NET).
2. **Blender 4.5 LTS** : https://www.blender.org/download/
3. **MPFB2** (MakeHuman pour Blender) : dans Blender, Edit → Preferences → Get Extensions →
   chercher « MPFB », puis installer le pack d'assets **makehuman_system_assets**
   (https://static.makehumancommunity.org/asset_packs/makehuman_system_assets.html). Dans les préférences de MPFB,
   indiquer le dossier des assets.
4. **Node.js LTS** (pour godot-mcp) et **uv** (pour Blender MCP) :
   https://nodejs.org et https://docs.astral.sh/uv/getting-started/installation/
5. **Claude Code** sur ton PC, puis dans un terminal :
   ```
   claude mcp add godot -e GODOT_PATH=<chemin vers Godot> -- npx @coding-solo/godot-mcp
   claude mcp add blender uvx mcp-for-blender
   uvx mcp-for-blender install-addon
   ```
   Dans Blender : activer l'add-on « Blender MCP », puis dans la vue 3D, touche N → onglet
   BlenderMCP → *Start MCP Server*.
6. Cloner ce dépôt et ouvrir `tour-des-99-etages/project.godot` dans Godot une fois.

## Personnages : MakeHuman → Mixamo → Godot

L'astuce : MPFB2 sait poser un squelette **« mixamo »** sur un humain MakeHuman, avec les mêmes noms
d'os que Mixamo. Les animations téléchargées **une seule fois** sur Mixamo servent donc à **tous** les
personnages. Pas besoin d'envoyer chaque modèle sur Mixamo.

1. **Créer le personnage** (Claude, via Blender MCP ou en ligne de commande) :
   ```
   blender --background --python tools/blender/make_character.py -- --id eirikr
   ```
   Les morphologies, peaux, cheveux et vêtements sont dans `tools/blender/characters.json`.
   Sortie : `art/characters/eirikr/eirikr.blend`.
2. **Animations Mixamo** (toi, une fois pour tout le roster) : sur https://www.mixamo.com, connexion
   Adobe, personnage par défaut (X Bot). Pour chaque animation : Download → FBX Binary,
   **Without Skin**, 30 ips. Les ranger dans `art/animations/mixamo/` sous ces noms :
   `idle.fbx`, `attack.fbx`, `skill.fbx`, `ultimate.fbx`, `hit.fbx`, `death.fbx`.
   Suggestions : *Fighting Idle*, *Punching* ou *Sword Slash*, *Standing Magic Attack*,
   *Great Sword Slash* ou *Spell Casting*, *Hit Reaction*, *Dying*.
3. **Appliquer et exporter** (Claude) :
   ```
   blender --background art/characters/eirikr/eirikr.blend --python tools/blender/apply_mixamo_anims.py -- --id eirikr
   ```
   Sortie : `assets/characters/eirikr/eirikr.glb`.
4. **Dans Godot, rien à faire** : la scène de combat utilise automatiquement le `.glb` s'il existe,
   sinon elle affiche une capsule.

> Les deux scripts Blender suivent l'API réelle de MPFB2 (exemples officiels `script_samples`), mais
> ils **n'ont pas encore été exécutés** : Blender n'a pas pu être téléchargé dans la session cloud.
> Premier test à faire sur ton PC avec un seul personnage.

## Tests (n'importe où)

```
godot --headless --path tour-des-99-etages --import
godot --headless --path tour-des-99-etages --script res://tests/run_tests.gd -- --sims=400
godot --headless --path tour-des-99-etages res://scenes/battle.tscn -- --smoke
```
