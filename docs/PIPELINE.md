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
- `assets/models/<id>.fbx` : les 24 personnages du roster (MPFB), avec leurs textures extraites par Godot
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
   Pour contrôler sans exporter : `-- --preview <dossier> eirikr` (rendus de face, de trois quarts, de dos
   et en pied).

   **Coiffures générées** (`"strands"` dans la fiche) quand MakeHuman n'a pas l'équivalent : les mèches
   suivent le crâne puis retombent, et sont attachées à l'os de la tête.
   - `"style": "twists"` : two-strand twists (Montana) ; `count`, `spacing`, `length`, `radius`, `front_length`.
   - `"style": "curtain"` : raie au milieu, mèches plates de part et d'autre (Don Selah) ; `count`, `spacing`,
     `front_length`, `side_length`, `back_length`, `width`, `thickness`, `cap` (calotte sous les mèches).
3. Lancer `python tools/set_retarget.py`. Ce script active la BoneMap dans les `.import` des nouveaux FBX. Le chemin du squelette d'un modèle est `<id>_body_rig/Skeleton3D`.
4. Ouvrir Godot pour l'import. La scène de combat prend le modèle automatiquement.

Vêtements supplémentaires : packs communautaires « suits02 » (CC0) et « suits03 » (CC-BY), à installer
dans les données utilisateur de MPFB (voir `CREDITS.md`). Motifs peints : `patch` (kente) et `hem_flames`
(flammes au bas d'un manteau), en plus de `sleeve`, `inner`, `stripes`, `sparkle`…

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

## Icônes des personnages (style estampe ukiyo-e)
1. `godot --path . --script res://tools/portraits.gd -- <dossier>` : photo de buste de chaque modèle 3D (fond transparent).
2. `python tools/ukiyoe_portraits.py <dossier>` : aplats façon gravure sur bois, contour à l'encre, papier washi,
   soleil à la couleur de la constellation, sceau rouge avec la rareté (三 四 五, 鬼 pour les boss) → `assets/portraits/<id>.png`.
À relancer après chaque remodelage d'un personnage. `UiKit.portrait(id, taille)` affiche l'icône.

## Icônes d'effets et image de bannière
- `python tools/ui_icons.py` : toutes les icônes vectorielles (SVG 64 × 64, importées par Godot).
  `assets/icons/<id>.svg` : glyphes ivoire des ressources, stats, classes, ensembles de reliques et boutons
  (règle UI : zéro texte superflu, voir `UiKit.icon`, `UiKit.amount`, `UiKit.bb` et `UiKit.iconize`).
  `assets/status_icons/<id>.svg` : un carré par effet de `data/rules.json` et `data/statuses.json`
  (bleu minéral = bonus non dissipable, or ancien = bonus dissipable, rouge sceau = malus).
  Planche de contrôle : `godot --path . --script res://tools/icon_sheet.gd -- planche.png`.
- `godot --path . --script res://tools/banner_shot.gd -- <photo.png> [vedette]` puis
  `python tools/make_banner.py <photo.png> [titre] [sous-titre]` → `assets/ui/banner_legendaires.png`
  (clé `art` de la bannière dans `data/gacha.json`).

## Décors de combat (Bible D.A.)
`scripts/ui/battle_decor.gd` construit chaque décor sans texture : silhouettes de papier découpé en dégradé
(bokashi), ciel, sol qui se fond dans la brume, arène à échiquier discret (`arena_checker.gdshader`),
accessoires 3D et particules. Le décor vient des données : `decor` / `boss_decor` d'un univers
(`data/tower.json`), `decor` d'un boss de butin (`data/loot_bosses.json`).

| id | Lieu |
|---|---|
| `dojo` | cour de temple au crépuscule (combats libres) |
| `acier` | Cité d'Acier : pagodes d'acier, cheminées, engrenage géant (étages 1 à 11) |
| `forge` | sommet de Prométhée : éclipse, volcan, chaînes, braseros (étage 12) |
| `orion` | sanctuaire du Chronophage : horloges flottantes, sabliers, Orion |
| `givre` | lac gelé du Wyrm : monts enneigés, côtes de dragon, Grande Ourse |
| `sirius` | désert du Serpent solaire : dunes, pyramides, serpent géant, obélisques |

- Photo d'un décor : `godot --path . --script res://tools/decor_shot.gd -- <id> sortie.png`.
- Forcer un décor en combat : `res://scenes/battle.tscn -- --smoke --decor=<id>` ; `--manual` garde la main
  au joueur (captures des boutons de compétences).
- Effets figés à mi-course : `godot --path . --script res://tools/fx_shot.gd -- sortie.png [décor]`.

## Rendu (Bible D.A.)
- Caméra de combat : FOV 40, reculée ; léger flou du lointain (`BattleDecor.camera_blur`) ; glow en lumière
  douce, contraste 1,18, saturation 1,2, ombres ambiantes teintées de bleu minéral.
- Personnages : `assets/materials/shaders/toon_ukiyoe.gdshader` (deux tons, ombre bleu minéral, liseré d'or),
  contour couleur encre `#332C29` (`CharacterModel.ukiyoe_material`).
- Effets : tranchant d'encre à défilement d'UV (`ink_slash.gdshader`, `BattleFx.ink_slash`), sceau doré sous
  chaque unité (`unit_seal.gdshader`), frame d'impact noir et blanc sur les ultimes (`impact_flash.gdshader`).
