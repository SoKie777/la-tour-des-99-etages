# Pipeline de production

Le même pipeline que **Coup d'État** (dépôt `SoKie777/coup-detat`), déjà validé sur ce PC.

```
 MPFB2 dans Blender ──▶ assets/models/<id>.fbx ─┐
 (corps, peau, cheveux,  (squelette Mixamo,      │   Godot 4.7 : à l'import, BoneMap humanoïde
  vêtements peints)       textures embarquées)   ├─▶ (mixamo_bonemap.tres) sur tous les FBX
                                                 │   → CharacterModel joue les anims sur le modèle
 Mixamo (web) ─────────▶ assets/mixamo/anims/ ───┘
 (animations, X/Y Bot,   *.fbx
  Without Skin)
```

## Les outils et leur rôle

| Outil | Rôle | Qui |
|---|---|---|
| **MPFB2** (MakeHuman dans Blender) | Fabrique chaque personnage : morphologie, peau, cheveux, vêtements, plus un **squelette Mixamo**. Exporte un FBX prêt pour Godot. | Claude : `tools/mpfb/make_characters.py` |
| **Mixamo** | Banque d'**animations** (Adobe, gratuit, connexion obligatoire, pas d'API). | Toi : téléchargements seulement |
| **Godot 4.7** | Moteur du jeu. À l'import, il **recible** les animations Mixamo sur chaque personnage grâce à la BoneMap. | Claude (MCP Godot ou code) |
| **GitHub Actions** | Construit l'APK et le publie dans les Releases. | Automatique |

## Déjà en place

- `assets/mixamo/ybot_idle.fbx` : le mannequin Y Bot, utilisé tant qu'un personnage n'a pas son modèle.
- `assets/models/<id>.fbx` : les 9 personnages du roster (MPFB), avec leurs textures extraites par Godot
  (`<id>_N.png`, limitées à 1024 px et compressées par `set_retarget.py`).
- `assets/mixamo/anims/` : 24 animations. Celles de Coup d'État (coups de poing et de pied, provocation,
  blocage, coups reçus, KO, victoire) et 7 téléchargées de Mixamo pour ce projet :

  | Fichier | Animation Mixamo |
  |---|---|
  | `cast_attack` | Standing 1H Magic Attack 01 |
  | `cast_area` | Standing 2H Magic Area Attack 01 |
  | `cast_buff` | Standing 2H Cast Spell 01 |
  | `heal` | Magic Heal (soin à une main) |
  | `idle_caster` | Standing Idle (attente des lanceurs de sorts) |
  | `roar` | Yelling Out (cri des tanks) |
  | `jump_attack` | Mutant Jump Attack |

  Correspondance action → animation : `MAP` (par défaut) et `CHAR_MAP` (par personnage, selon son kit)
  dans `scripts/ui/character_model.gd`.
- `assets/mixamo/mixamo_bonemap.tres` : la correspondance entre les os Mixamo et le profil humanoïde de Godot, générée par `tools/make_bonemap.gd`.

## Créer un personnage

1. Régler sa fiche dans `tools/mpfb/characters.json` : macros, `race`, `skin`, `hair`, `eyebrows`, `clothes` et les couleurs de `paint` (vêtements en aplats).
2. Lancer :
   ```
   blender --background --python tools/mpfb/make_characters.py -- eirikr
   ```
   Sans id, le script fabrique tout le roster. Sortie : `assets/models/eirikr.fbx`.
3. Lancer `python tools/set_retarget.py`. Ce script active la BoneMap dans les `.import` des nouveaux FBX. Le chemin du squelette d'un modèle est `<id>_body_rig/Skeleton3D`.
4. Ouvrir Godot pour l'import. La scène de combat prend le modèle automatiquement.

⚠️ Noms d'assets MPFB : seuls ceux déjà utilisés par Coup d'État sont sûrs :
- peau `Young african male` ;
- cheveux `Short01`, `Short02`, `Short04`, `Afro01` ;
- vêtements `Male casualsuit01` et `Male casualsuit04`, chaussures `Shoes01` à `Shoes06`.

Les autres (peaux caucasienne et asiatique, `Female casualsuit01`, `Long01`, `Ponytail01`) sont à vérifier. En cas d'erreur, le script affiche la liste des noms disponibles.

## Ajouter une animation

1. Mixamo, avec le personnage X Bot ou Y Bot → *FBX Binary, Without Skin*.
2. Mettre le fichier dans `assets/mixamo/anims/<nom>.fbx`, puis lancer `python tools/set_retarget.py` et ouvrir Godot.
3. L'associer à une action dans `MAP` (`scripts/ui/character_model.gd`).

Tu peux aussi copier n'importe quelle animation de `coup-detat/assets/mixamo/anims/`, avec son `.import` : 32 sont disponibles (coups de pied, chopes, provocation…).

## Outils de contrôle

| Commande (`godot --path . --script res://tools/…`) | Rôle |
|---|---|
| `lineup.gd -- sortie.png [action] [secondes]` | Photo de groupe des 9 personnages, dans une action donnée |
| `shot.gd -- res://scenes/x.tscn sortie.png` | Capture d'un écran du jeu |
| `playtest.gd -- --save=user://profil_test.json <dossier>` | Parcours complet sur un profil de test, avec captures |
| `tune_tower.gd` (headless) | Taux de victoire par étage selon la puissance des ennemis |

## Tests

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd -- --sims=400
godot --headless --path . res://scenes/battle.tscn -- --smoke
```

## APK

Changer `VERSION`, puis committer et pousser sur `main`. On obtient :
- une Release `vX.Y.Z` ;
- la Release fixe **`apk-latest`**, qui contient toujours la dernière version (le lien ne change pas).
