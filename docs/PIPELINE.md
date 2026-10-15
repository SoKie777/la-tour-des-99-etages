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
- `assets/mixamo/anims/` : 7 animations reprises de Coup d'État :

  | Fichier | Utilisé pour |
  |---|---|
  | `idle` | Attente |
  | `cross` | Compétence 1 |
  | `punch_combo` | Compétence 2 |
  | `hurricane_kick` | Ultime |
  | `hit` | Coup reçu |
  | `ko` | Mort |
  | `victory` | Victoire |

  La correspondance est dans `MAP`, dans `scripts/ui/character_model.gd`.
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
