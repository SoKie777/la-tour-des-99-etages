# T99

Gacha RPG mobile au tour par tour (3 contre 3, barre d'action), inspiré de Dislyte, dans un univers
d'estampe japonaise : anime 3D, encre ukiyo-e et symbolique des échecs. Moteur : **Godot 4.7**.
Version actuelle : **v0.6.0** (fichier `VERSION`).

- **Jouer sur Android :** Releases → **[`apk-latest`](../../releases/tag/apk-latest)** (toujours la dernière version).
  L'APK est signé avec une clé fixe : on installe chaque nouvelle version **par-dessus** l'ancienne et la
  sauvegarde est conservée.
- **Jouer sur PC :** `Lancer le jeu.bat` · **Modifier :** `Ouvrir dans Godot.bat`

## Ce qu'on peut faire

- **Ascension de la Tour** : univers 01, la Cité d'Acier (12 étages, une Élite, le boss **Prométhée**).
  Chaque victoire rapporte des Pièces et une relique, la première des Éclats de Vœu ; énergie, balayage
  des étages gagnés.
- **Boss de butin** : le Chronophage (Orion), le Wyrm de givre (Grande Ourse), le Serpent solaire (Sirius),
  4 paliers (Facile à Enfer), reliques ciblées et garantie après plusieurs victoires.
- **Combats** à la barre d'action : 24 personnages en 3 nations / constellations (triangle Orion › Grande
  Ourse › Sirius), compétences, ultimes avec gros plan, effets visibles, mode auto, vitesse ×1 à ×3.
- **Invocation** sur bannière (taux et garanties affichés) avec cinématique sur l'échiquier.
- **Équipe** de 3 et formations, **Collection** (fiche, stats, compétences) et **reliques** (6 emplacements,
  ensembles, niveaux, recyclage).
- Progression **sauvegardée** sur l'appareil.

## Direction artistique (Bible D.A.)

- **Décors imaginés pour chaque lieu**, en papier découpé façon estampe : Cité d'Acier (pagodes d'acier,
  engrenage géant), forge de Prométhée (éclipse, volcan, chaînes), sanctuaire d'Orion (horloges flottantes),
  lac gelé du Wyrm (monts enneigés, côtes de dragon), désert de Sirius (pyramides, serpent géant), cour de temple.
- **Personnages en cel-shading** : ombre bleu minéral, liseré d'or, contour à l'encre ; portraits en estampe.
- **Effets à l'encre** : tranchants de pinceau, taches d'encre, sceau doré sous chaque unité, éclair noir et
  blanc sur le coup d'un ultime.
- **Interface sans texte superflu** : ressources, stats et effets en icônes vectorielles ; palette officielle
  indigo `#21172F`, or ancien `#D1AD62`, ivoire `#E8DEC5`, rouge sceau `#B83A35`, bleu minéral `#263C4A`.

## Le pipeline

```
 ┌──────────────────────┐      ┌──────────────────────┐      ┌───────────────────────────┐
 │ MPFB2 (dans Blender) │      │ Mixamo (site web)    │      │ Godot 4.7                 │
 │ fabrique le CORPS    │      │ fournit les          │      │ recible les anims sur     │
 │ de chaque perso +    │      │ ANIMATIONS           │      │ chaque perso (BoneMap),   │
 │ squelette Mixamo     │      │ (idle, coups, KO…)   │      │ fait tourner le JEU       │
 └──────────┬───────────┘      └──────────┬───────────┘      └─────────────▲─────────────┘
            │ assets/models/<id>.fbx      │ assets/mixamo/anims/*.fbx      │
            └─────────────────────────────┴────────────────────────────────┘
```

| Outil | À quoi il sert | Qui |
|---|---|---|
| **MPFB2** | **MakeHuman dans Blender** : corps 3D de chaque personnage (morphologie, peau, cheveux, vêtements peints) avec un squelette compatible Mixamo, exporté en FBX. | Claude : `tools/mpfb/make_characters.py` + `tools/mpfb/characters.json` |
| **Mixamo** | Bibliothèque d'**animations** (Adobe). Pas d'API : il faut se connecter. | Toi : télécharger les FBX (*Without Skin*) |
| **Godot** | Le **moteur du jeu**. À l'import, il recible les animations Mixamo sur tous les personnages (`assets/mixamo/mixamo_bonemap.tres`). | Claude |
| **GitHub Actions** | Teste le jeu, construit et signe l'**APK** quand `VERSION` change, et le publie dans les Releases. | Automatique |

Détails et commandes (portraits, icônes, décors, shaders, captures) : **`docs/PIPELINE.md`**.

## Contenu du dépôt

| Dossier | Contenu |
|---|---|
| `docs/GDD.md` | Game design : lore, combat, triangle, roster, reliques, gacha, simulations, feuille de route |
| `docs/PIPELINE.md` | Pipeline 3D, icônes, décors, rendu, APK |
| `docs/CAPTOLOGIE.md` | Principes de motivation du joueur (sans manipulation) |
| `data/` | Tout l'équilibrage en JSON (personnages, règles, statuts, gacha, reliques, Tour, boss, progression) |
| `scripts/core/` | Moteur de combat, gacha, reliques, profil, Tour, boss de butin (sans affichage, testable) |
| `scripts/ui/` | Écrans, combat, décors (`battle_decor.gd`), effets (`battle_fx.gd`), `character_model.gd`, `ui_kit.gd` |
| `assets/` | Modèles, animations, portraits, icônes SVG, shaders (`materials/shaders/`), polices, image de bannière |
| `tools/` | Génération (personnages, portraits, icônes, bannière) et outils de contrôle (captures, réglages) |
| `tests/` | Tests des règles et simulations d'équilibrage (headless) |

## Sortir un APK

Changer le numéro dans `VERSION`, committer, pousser sur `main`. On obtient une Release `vX.Y.Z`, et la
Release `apk-latest` est mise à jour.
