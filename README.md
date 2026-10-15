# T99

Gacha RPG mobile au tour par tour (3 contre 3, barre d'action), inspiré de Dislyte. Moteur : **Godot 4.7**.

- **Jouer sur PC :** `Lancer le jeu.bat` · **Modifier :** `Ouvrir dans Godot.bat`
- **Jouer sur Android :** Releases → **`apk-latest`** (toujours la dernière version)

## Le pipeline (le même que Coup d'État)

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
| **MPFB2** | C'est **MakeHuman dans Blender** : il génère le corps 3D de chaque personnage (morphologie, peau, cheveux, vêtements peints) avec un squelette compatible Mixamo, et l'exporte en FBX. | Claude : `tools/mpfb/make_characters.py` + `tools/mpfb/characters.json` |
| **Mixamo** | Bibliothèque d'**animations** (Adobe). Pas d'API : il faut se connecter. | Toi : télécharger les FBX (*Without Skin*) |
| **Godot** | Le **moteur du jeu**. À l'import, il recible les animations Mixamo sur tous les personnages (`assets/mixamo/mixamo_bonemap.tres`). | Claude |
| **GitHub Actions** | Construit l'**APK** quand `VERSION` change, et le publie dans les Releases. | Automatique |

Les 9 personnages du roster ont leur modèle MPFB et un jeu d'animations selon leur rôle (sorts, soin, cri,
coups de pied…). Un personnage sans modèle s'affiche en **mannequin Y Bot**, teinté à la couleur de sa
constellation.

## Ce qu'on peut faire (v0.2)

- **Ascension de la Tour** : univers 01, la Cité d'Acier (12 étages, une Élite, un boss). Chaque victoire
  rapporte des Pièces et une relique ; la première rapporte des Éclats de Vœu.
- **Invocation** avec les Éclats, **Équipe** de 3, **Collection** (fiche, stats, compétences) et
  **reliques** (équiper, monter de niveau).
- Progression **sauvegardée** sur l'appareil.

Détails et commandes : **`docs/PIPELINE.md`**.

## Contenu du dépôt

| Dossier | Contenu |
|---|---|
| `docs/GDD.md` | Game design : lore, combat, triangle, roster, reliques, gacha, simulations, feuille de route |
| `docs/PIPELINE.md` | Pipeline MPFB2 → Mixamo → Godot, commandes, APK |
| `data/` | Tout l'équilibrage en JSON (personnages, règles, gacha, reliques, Tour, progression) |
| `scripts/core/` | Moteur de combat, gacha, reliques, profil du joueur, Tour (sans affichage, testable) |
| `scripts/ui/` | Écrans (hub, Tour, Équipe, Collection, Invocation), combat, `character_model.gd`, `ui_kit.gd` |
| `assets/mixamo/` | Y Bot, animations Mixamo, BoneMap |
| `assets/models/` | Modèles MPFB des personnages (`<id>.fbx`) |
| `tools/` | `mpfb/make_characters.py`, `set_retarget.py`, `make_bonemap.gd`, outils de contrôle (captures, réglage de la Tour) |
| `tests/` | Tests des règles et simulation d'équilibrage (headless) |

## Sortir un APK

Changer le numéro dans `VERSION`, committer, pousser sur `main`. On obtient une Release `vX.Y.Z`, et la Release `apk-latest` est mise à jour.
