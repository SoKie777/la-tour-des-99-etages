# La Tour des 99 Étages

Gacha RPG mobile au tour par tour (3 contre 3, barre d'action), inspiré de Dislyte.
Moteur : **Godot 4.5.1**. APK de test : onglet **Releases** du dépôt.

## Le pipeline en une image

```
 ┌────────────────────┐   ┌────────────────────┐   ┌────────────────────┐   ┌──────────────┐
 │ 1. MPFB2 (Blender) │   │ 2. Mixamo (web)    │   │ 3. Blender         │   │ 4. Godot     │
 │ fabrique le CORPS  │──▶│ fournit les        │──▶│ colle les anims    │──▶│ le JEU       │
 │ du perso + son     │   │ ANIMATIONS         │   │ sur chaque perso   │   │ (combat, UI, │
 │ squelette          │   │ (idle, attaque…)   │   │ et exporte un .glb │   │ gacha, APK)  │
 └────────────────────┘   └────────────────────┘   └────────────────────┘   └──────────────┘
   make_character.py        téléchargement manuel    apply_mixamo_anims.py    assets/characters/
```

| Outil | À quoi il sert | Qui s'en occupe |
|---|---|---|
| **Blender** | Le logiciel 3D dans lequel tout le travail sur les modèles se fait. | Claude, via le MCP Blender ou les scripts `tools/blender/` |
| **MPFB2** | C'est **MakeHuman dans Blender** : il génère un humain en 3D (morphologie, peau, cheveux, vêtements) et lui pose un **squelette compatible Mixamo**. C'est lui qui crée les personnages. | Claude (`tools/blender/make_character.py`, réglages par perso dans `tools/blender/characters.json`) |
| **Mixamo** | Site gratuit d'Adobe, une bibliothèque d'**animations** (repos, coup, sort, coup reçu, mort). Pas d'API : connexion obligatoire. | **Toi** : te connecter et télécharger 6 fichiers FBX, **une seule fois** pour tout le roster |
| **Godot** | Le **moteur du jeu** : combat, interface, gacha, sauvegarde, export Android. | Claude, via le MCP Godot (éditeur) ou directement dans le code |
| **GitHub Actions** | Construit l'**APK** à chaque nouvelle version et le publie dans les Releases. | Automatique |

Pourquoi Mixamo une seule fois : le squelette posé par MPFB2 porte exactement les mêmes noms d'os que
Mixamo. Les mêmes 6 animations s'appliquent donc à tous les personnages, sans envoyer chaque modèle
sur Mixamo.

## Étapes pour un personnage

1. `blender --background --python tools/blender/make_character.py -- --id eirikr`
   → `art/characters/eirikr/eirikr.blend`
2. (une seule fois) Mixamo → personnage X Bot → chaque animation : *FBX Binary, Without Skin, 30 ips*
   → `art/animations/mixamo/` : `idle.fbx` `attack.fbx` `skill.fbx` `ultimate.fbx` `hit.fbx` `death.fbx`
3. `blender --background art/characters/eirikr/eirikr.blend --python tools/blender/apply_mixamo_anims.py -- --id eirikr`
   → `assets/characters/eirikr/eirikr.glb`
4. Rien à faire dans Godot : la scène de combat prend le `.glb` automatiquement (sinon, capsule de couleur).

⚠️ Les scripts Blender n'ont pas encore été exécutés : premier essai à faire avec un seul personnage.

## Sortir un APK de test

Changer le numéro dans `VERSION` (ex. `0.2.0`), committer, pousser sur `main`.
GitHub Actions lance les tests, construit l'APK et crée la Release `v0.2.0`.
Lancement manuel possible : onglet Actions → *APK Android de test* → *Run workflow*.

## Installation sur PC

Voir `docs/PIPELINE.md` : Godot 4.5.1, Blender 4.5 LTS, MPFB2 et son pack d'assets, Node.js, uv,
Claude Code et les deux MCP (Godot et Blender).

## Contenu du dépôt

| Dossier | Contenu |
|---|---|
| `docs/GDD.md` | Game design : lore, combat, triangle, roster, reliques, gacha, simulations, feuille de route |
| `docs/PIPELINE.md` | Installation et pipeline détaillés |
| `data/` | Tout l'équilibrage en JSON (personnages, règles, gacha, reliques) |
| `scripts/core/` | Moteur de combat, gacha, reliques (sans affichage, testable) |
| `scripts/ui/`, `scenes/` | Menu et combat jouable |
| `tests/` | Tests des règles et simulation d'équilibrage (headless) |
| `tools/blender/` | Création des persos (MPFB2) et application des animations (Mixamo) |
| `art/` | Sources 3D (.blend, FBX Mixamo) : hors du jeu exporté |
| `assets/` | Ce que le jeu charge (.glb) |

## Tests

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd -- --sims=400
godot --headless --path . res://scenes/battle.tscn -- --smoke
```
