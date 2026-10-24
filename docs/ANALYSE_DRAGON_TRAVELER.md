# Analyse de Dragon Traveler (v1.19.0) — base de la refonte de T99

Source : `dragon-traveler-1-19-0.xapk` (package `com.gametree.lhlr.gp`, Unity 2020.3.25f1, IL2CPP +
HybridCLR), ouvert avec REA puis décodé (24/10/2026).

## 0. Comment on a lu le jeu

| Étape | Ce qu'on a trouvé |
|---|---|
| REA `open_binary` + `inspect_artifact` sur le XAPK | 4 APK : code (`com.gametree.lhlr.gp.apk`), lib arm64 (`libil2cpp.so`, 90 Mo), deux packs d'assets (530 Mo) |
| Bundles `res/config/*.b` et `res/hotfix/*.b` | Bundles UnityFS précédés de **faux en-têtes UnityFS** remplis de bruit (leurre anti-extraction). Le vrai bundle est celui dont la taille déclarée tombe pile à la fin du fichier. |
| `res/config` | **14 bases SQLite en clair** (`t_*.db`, 210 Mo) : **1 400 tables** de design (héros, compétences, buffs, étoiles, gacha, campagne, modes…). Colonnes `__BIN__*` = blobs (longueur + données). Textes dans les tables `*_Lang` (anglais disponible). |
| `res/hotfix` | DLL HybridCLR de la logique (`Game.Battle.Logic.dll`, `Hotfix.dll`…). En-têtes lisibles, corps de méthodes chiffrés : seuls les noms ont servi. |
| `global-metadata.dat` | Métadonnées IL2CPP v27 en clair (noms des classes du moteur). |
| `FunctionDes` / `FunctionDesPart` | **Les textes d'aide officiels de chaque système** : c'est le livre de règles du jeu. |

Exportateurs (hors dépôt, dans le scratchpad de la session) : `dump2.py` (bundles), `export.py`
(SQLite → JSON lisible avec textes anglais), `j.py` (lecture d'une table).

Légende : **[observé]** = lu dans les tables ou les textes du jeu ; **[déduit]** = notre interprétation des
chiffres ; **[inconnu]** = dans le code chiffré, à régler nous-mêmes.

---

## 1. Le genre en une phrase

Un **RPG gacha « idle » à combat automatique en temps réel** (filiation AFK Arena) : 6 héros sur une
grille 3 × 3 + 1 dragon, qui avancent, frappent et lancent leurs compétences seuls, pendant que le joueur
**déclenche les Overdrive** (ultimes) en dépensant une **jauge d'énergie commune**. La progression repose
sur les **doublons** (montée d'étoiles par fusion), la **résonance de classe** (un niveau partagé) et une
campagne de ~5 500 étapes qui rapporte des ressources **même hors ligne** (patrouille).

---

## 2. Boucle de combat

### 2.1 Terrain et équipe [observé]
- **Grille de 3 × 3** (positions `1_1` à `3_3`, table `Formation`) + **1 case Dragon** (`2_4`).
- **6 héros au maximum** (cases débloquées par la campagne : 4e à 1-6, 5e à 1-9, 6e à 2-16) + 1 Wyrm.
- Pas de doublon, pas deux versions d'un même personnage (« Shared Origin »).
- **Placement selon la classe** : Gardien devant seulement ; Guerrier devant ou milieu ; Prêtre,
  Archer, Mage milieu ou fond ; Assassin partout.
- Modes à règles spéciales : seulement des héros à distance (Défense de la forêt), seulement de la mêlée
  (Casse du trésor), un héros par classe (Ralliement sauvage, Duel de slimes), 1 contre 1 enchaîné
  (Colisée), 2 équipes de 4 (Guerre de guilde).

### 2.2 Temps réel [observé]
- Chaque héros a une **vitesse de déplacement**, un **rayon d'attaque** (1,1 m mêlée à 4,5 m distance), une
  **vitesse d'attaque**, un rayon de garde et une **IA de ciblage** (table `Heroes` : `speed`,
  `attack_radius`, `AtkSpd`, `initTargetSelect`). Les unités avancent jusqu'à portée puis attaquent.
- Combats limités dans le temps (1 à 2 min en PvP ; à l'expiration, le camp avec le plus de PV en %
  gagne). Mode **Berserk** deux fois par combat en PvP (ATK en hausse pour accélérer).
- Vitesse ×1/×2, auto (2-4), pause, recommencer, et un bouton **« ordre des Overdrive »** (2-4) pour
  programmer l'ordre de lancement en auto.

### 2.3 Le kit d'un héros : 5 compétences [observé]
Exemple Athena (`HeroesSkill` 1701 → `BattleSkill` 17011…17015) :

| Type | Rôle | Exemple |
|---|---|---|
| 1 Talent de faction | Passif lié à la mécanique de faction | *Battle Resolve* : dégâts en % des PV perdus ; entre en état **Grâce** avec Moral + Ferveur |
| 2 **Overdrive** | Ultime **manuel**, coûte de l'énergie d'équipe, ciblage au doigt | *Martial Verdict* : sacrifie 40 % PV → bouclier, provoque une zone 8 s. **Coût 3, recharge 20 s, disponible à 6,5 s** |
| 3 Compétence active | Lancée seule, recharge 14 s | *Aegis of Echoes* : bouclier qui ricoche 5 fois |
| 4 Passif | Réaction | *Life Link* : allié sous 30 % PV → lien, 60 % des dégâts redirigés |
| 5 Passif | Réaction | *Counter Helix* : 25 % de contre-attaque de zone quand touché |

+ l'**attaque de base** automatique. Chaque compétence a **9 niveaux** (montés par le niveau de classe).
Les **étoiles** changent le Talent (nouvel effet à 6, 9, 12, 15, 18, 19 étoiles).

### 2.4 Énergie d'Overdrive (le cœur du gameplay manuel) [observé + déduit]
- **Jauge partagée par l'équipe** (stats « Énergie partagée initiale » et « Régénération d'énergie
  partagée », `Attr` 991/992), qui se remplit avec le temps.
- Chaque Overdrive a un **coût** (répartition sur 160 Overdrive : 2 → 33, **3 → 61**, 4 → 34, 5 → 10,
  6 → 5 ; quelques 0-1 et 7-12), une **recharge propre** (18 ou 20 s le plus souvent, 25-30 s pour les
  plus forts), un **délai d'ouverture** (6,5 s presque toujours) et une **recharge globale** de 1,2 s entre
  deux Overdrive de l'équipe (`ASkill.team_cd`).
- Le coût est une **ressource tactique** : beaucoup d'effets le manipulent (« prochain Overdrive de la
  cible +1 », « −1 pour soi et l'allié le plus cher », une faction punit les ennemis dont le coût est ≥ 4,
  boss « coût des Prêtres −2 »).
- **[inconnu]** maximum et vitesse de la jauge (dans le code chiffré). Repère : un effet « commence avec
  6 énergies » existe, les coûts vont de 2 à 6 → jauge de **10** et ~1 énergie / 1,5 s est cohérent.
  Énergie restante conservée d'un combat à l'autre dans les modes en plusieurs combats.

### 2.5 Ressources individuelles [observé]
Selon le héros : **Mana** (1 000, regen 10/s), **Rage** (1 000 ; gagnée en frappant, en étant touché, par
les dégâts subis), **Énergie** personnelle (petites charges). Elles alimentent les mécaniques de faction.

### 2.6 Stats [observé]
ATK, PV, DEF physique, DEF magique, Pénétration (ignore 40 % de base de DEF ?), Vitesse d'attaque,
Critique / Dégâts critiques / Résistance critique, Esquive / Précision, Blocage / Brise-garde / Valeur de
blocage, Soins / Soins reçus, Vol de vie, Renvoi, Bonus de dégâts / Réduction de dégâts, **Hâte**
(réduit toutes les recharges). Chaque stat existe en version plate, % et « aptitude ».

- **Stat finale = base de classe au niveau × aptitude du héros × multiplicateur d'étoiles** [déduit de
  `HeroLevel.PostAttr`, `Heroes.AttrTalent`, `HeroesStar.StarMag`].
- Base niveau 1 par classe (ATK / PV / DEF ph. / DEF mag.) : Gardien 189/262/136/148, Prêtre
  249/224/105/157, Assassin 257/231/123/123, Guerrier 250/225/137/125, Archer 297/199/126/113,
  Mage 303/193/113/126. **Croissance ×5 entre le niveau 1 et 100** (`LevelRate` 1 → 5,02).

### 2.7 Classes et factions [observé]
- **6 classes** : Gardien, Prêtre, Assassin, Guerrier, Archer, Mage (+ sous-classes déblocables).
- **6 factions**, chacune avec une **mécanique de combat propre** :
  | Faction | Mécanique |
  |---|---|
  | Écho élémentaire | Brûlure, Choc, Gel → **réactions élémentaires** |
  | Esprit sauvage | La Rage monte en perdant des PV ; pleine → état **Sauvage** |
  | Sagesse arcanique | Stacks d'**Éveil** gagnés quand un allié lance un Overdrive |
  | Gloire du sanctuaire | **Moral + Ferveur** → état **Grâce** |
  | Retour de l'autre monde | Stacks de **Râle d'agonie** quand un allié tombe |
  | Voile d'illusion | **Châtiment** contre les ennemis dont l'Overdrive coûte ≥ 4 |
- Un héros R+ a **2 factions**, la 2e s'active à **6 étoiles**.
- **Bonus de faction** : 4 / 5 / 6 héros de la même faction → ATK et PV +10 / 15 / 20 %.

### 2.8 Raretés et taux [observé]
N, R, SR, SSR, **SSR+**, **SSR Ex** (UR prévu). 248 héros dont ~100 jouables.

---

## 3. Progression d'un héros

### 3.1 Niveau [observé]
1 → 100 avec **XP de héros** et **Or**. Paliers à 40 / 60 / 80 / 100 qui demandent de l'**Essence de
Wyrm** et un minimum d'étoiles. **Plafond de niveau fixé par les étoiles** (40, 40, 60, 80, puis 100 à 5★).
Réinitialisation gratuite (tout est rendu sauf les étoiles).

### 3.2 Étoiles et doublons (le système central) [observé]
19 paliers : **1-6 or**, **1-6 violettes** (7-12), **1-6 rouges** (13-18), **arc-en-ciel** (19).
Multiplicateur de stats ×0,7 (1★) → ×1 (5★) → ×1,40 (violet 4) → ×1,88 (rouge 4) → **×2,12** (arc-en-ciel).

Coût (lecture de `HeroesStar`) [déduit] :
| De → à | Consomme |
|---|---|
| 1 → 2, 2 → 3 | 4 copies du même héros à la même étoile |
| 3 → 4 | 2 copies |
| 4 → 5, 5 → 6 | 1 copie |
| 6 → violet 1 | 1 héros **de la même classe** à 6★ |
| violet 1 → … → arc-en-ciel | en alternance 1 copie du héros 6★ (« principal ») et 1 à 6 héros 6★ de la même classe ; au total **18 copies principales** |

- **Substituts** : les **Slimes** remplacent une copie principale ; les **Poupées** remplacent un héros de
  classe. Les doublons N sont démontés en éclats de Slime 5★.
- **Origine partagée** : une version de rareté inférieure du même personnage sert de copie principale.
- **Réinitialisation d'étoiles** (5 gratuites par semaine) : tout est rendu (les fourrages reviennent en
  Poupées). **Échange d'étoiles** entre versions d'un même personnage.
- **Montée rapide** jusqu'à 6★ en un bouton.
- Plusieurs exemplaires du même héros sont possibles (étoiles indépendantes, niveau et équipement
  partagés) ; le combat prend le mieux étoilé.

### 3.3 Résonance de classe (après le niveau 100) [observé]
- Un héros niveau 100 entre en **Résonance de classe** : il prend le **niveau de sa classe**, qui monte
  ensuite pour tous ses membres et augmente leurs **niveaux de compétences** (jusqu'à 800 et plus).
- Le niveau de classe est plafonné par les étoiles et par les autres classes (pas d'avance d'une seule).
- **Résonance d'étoiles** : des emplacements (débloqués aux niveaux de classe 50 / 101 / 251, puis contre
  du Slime) où un héros prend une étoile calculée sur toute la collection, plafonnée au record de la classe.
- **Destin** de classe : arbre de bonus et sous-classes (première gratuite par rang, les suivantes contre
  de l'**Ambre primordial**).

### 3.4 Éveil divin (fin de jeu) [observé]
SSR et plus, après l'arc-en-ciel : une quête d'éveil, puis une **« renaissance »** d'attente réelle
(accélérable), puis **niveaux de Divinité** (Cristaux divins = 60 éclats). Chaque niveau donne 1-2
compétences divines au choix.

### 3.5 Autres couches
Équipement (6 pièces, fusion de pièces identiques, SR 4★ → SSR à set, SSR → UR à reforge), reliques
exclusives (à partir de violet 6), Codex (collection : bonus global + diamants à chaque étoile),
Serment (placer des héros pour des bonus de classe/faction), Affection (cadeaux, rendez-vous, donjon
du cœur), Expédition (envoyer des héros en mission).

### 3.6 Protagoniste et Dragon
Le joueur a un **protagoniste** qui se transforme en **dragon** en combat (case Dragon) : dragons
juvénile → adolescent → adulte, étoiles, 4 emplacements de **sorts de Wyrm**, rugissement qui booste
les héros de sa faction, trésors et artefacts. C'est la couche « compte » qui booste tout le monde.

---

## 4. Invocation [observé]

| Bannière | Taux | Garanties |
|---|---|---|
| Standard (Ticket) | SSR+ 0,857 %, SSR 2,143 %, SR 12 %, R 50 %, N 35 % | SR+ toutes les 10, **SSR+ en 40** |
| Limitée (Ticket du destin), ouvre à 61 invocations | SSR+ 2,2 %, SR 12 %, R 50 %, N 35,8 % | SR+ / 10, **SSR+ en 50** (vedette garantie), compteur partagé et reporté |
| Faction | idem limitée | Liste de souhaits : 50 % vœu 1, 25 % vœu 2 |
| Mythique (9-40) | choix 1 parmi 3 SSR Ex | éclats du héros choisi toutes les 5, paliers |
| Amitié | SSR 1 %, SR 7 % … | SSR en 150 |
| Odyssée | 100 x10 à refaire, on garde le meilleur | 1 SSR par x10 |
| Vœu (Lys) | | points de vœu → héros souhaité garanti |

- **Liste de souhaits** à 300 invocations : quand un SSR+ sort, chaque héros souhaité a 20 % de chance.
- x10 et x100 (x100 débloqué à 1 000 invocations).

---

## 5. Campagne, idle et économie [observé]

- **Histoire principale** : 79 chapitres, **5 488 étapes** (chapitre 1 : 9 étapes, puis 20-80 par
  chapitre). Chaque étape rapporte des récompenses de première victoire et **fixe le revenu de
  patrouille**.
- **Patrouille (idle)** : or, XP d'aventure, XP de héros produits à la minute selon l'étape atteinte,
  stockage limité, **patrouille rapide** (gratuite puis payante). Ennemis visibles qui errent sur la carte.
- Monnaies : Diamants (payés / liés), Or, XP d'aventure (niveau de compte), XP de héros, Essence de
  Wyrm, Endurance (modes annexes), Points d'amitié, Slime, tickets.
- **Déblocages par l'histoire** (`SystemOpen`) : héros 1-3, invocation 1-6, étoiles 1-9, auto 2-4,
  ×2 2-1, guilde 3-16, arène 3-28, Ruines 2-4, Faille divine 5-16, Défis 2-20 à 14-48, Colisée 4-12,
  Évasions 7-32…

---

## 6. Modes de jeu [observé]

| Mode | Règle |
|---|---|
| **Ruines d'os de Wyrm** (tour) | Étages de monstres, élites renforcées par une âme de Wyrm ; 6 **Royaumes d'épreuve** par faction (10/jour), effets d'environnement |
| **Tour de Babel** (événement) | 2 tours de faction, héros vedette obligatoire, choix de **difficulté en étoiles par étage**, « retour arrière », double équipe au-delà de l'étage 16 |
| **Faille du royaume divin** | Roguelite de 2 jours : **PV et énergie conservés** d'un combat à l'autre, élixirs |
| **Conquête des mythes** | 4 donjons de ressources : Défense de la forêt (distance seule), Casse du trésor (mêlée seule), Ralliement sauvage et Duel de slimes (score de kills, 1 héros par classe) |
| **Épreuve de la déesse** | Un donjon par classe, 2 classes par jour (toutes le samedi) |
| **Expédition des champions** | 3 boss d'équipement, rotation des pièces par jour de la semaine |
| **Colisée** | 1 contre 1 enchaîné (3 héros), contre la montre, saison de 14 jours |
| **Épreuve du feu** | Niveaux uniformisés, 25 étapes par période, règles spéciales |
| **Camp d'entraînement** | Puzzles à équipe imposée |
| **Évasions incroyables** | Labyrinthe dans le brouillard (glace, vent, téléporteurs, mini-jeux) |
| **Aventure de Phantasia** | Quêtes uniques (mini-jeux, combats) qui montent les stats du protagoniste |
| **Faille temporelle** | Saison de 2 mois sur une carte, niveaux uniformisés, revenu idle |
| Arène, Ligue de points, Choc des Dieux-rois, Choc des nuées | PvP asynchrone, rangs Bronze → Roi, tournois |
| Guilde | Boss de guilde (dégâts), expédition, guerre de bâtiments, enchères |

---

## 7. Ce qui reste inconnu

- Valeurs exactes de la jauge d'énergie (max, régénération) et formule de dégâts (code chiffré).
- Correspondance exacte rareté → étoile de départ à l'invocation (on fixe : N 1★, R 2★, SR 3★, SSR 5★).
- Valeurs de `AttrTalent` (aptitudes) pour chaque héros (décodage partiel).

Ces points se règlent par simulation dans T99 (`tools/tune_*.gd`), comme le reste de l'équilibrage.

## 8. Ce qu'on ne reprend pas

Aucun texte, nom, image, modèle ni son de Dragon Traveler n'entre dans T99 : on reprend **des règles
et des structures** (les mécaniques ne sont pas protégées), avec l'univers, les personnages et la
direction artistique de T99. Les systèmes purement commerciaux (packs, cartes mensuelles, enchères)
sont écartés.
