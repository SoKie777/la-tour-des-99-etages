# T99 — Game Design Document (à jour v0.18.0, refonte Dragon Traveler)

Depuis la v0.17, T99 reprend la boucle de jeu de **Dragon Traveler** (analyse complète :
`docs/ANALYSE_DRAGON_TRAVELER.md`, faite avec REA sur l'APK 1.19.0) : combat automatique en
**temps réel**, **6 héros sur une grille 3 × 3**, **Overdrive** lancés avec une **jauge d'énergie
commune**, progression par **doublons** (étoiles), **niveaux** plafonnés par les étoiles,
**Résonance de classe**, campagne avec **Patrouille** (revenu hors ligne), Tour et Expédition.
L'univers, les personnages et la direction artistique restent ceux de T99 (estampe japonaise,
anime 3D, symbolique des échecs). Les anciennes règles (tour par tour façon Dislyte, triangle des
constellations, mode tactique) sont abandonnées ; elles restent dans l'historique git (v0.16).

Tout ce qui est chiffré vit dans `data/*.json` et se règle sans toucher au code.

---

## 1. Vision et piliers

Un gacha RPG mobile « idle » en 3D stylisée. On monte la Tour des 99 Étages pour atteindre le Vœu.

1. **Combat lisible, décisions au bon moment** : les héros se battent seuls ; le joueur choisit
   quand dépenser l'énergie commune (quel Overdrive, dans quel ordre) et compose sa grille.
2. **Composer** : 6 classes qui ont leur place sur la grille, 6 factions qui ont chacune une
   mécanique, bonus quand 4, 5 ou 6 héros partagent une faction.
3. **Progression longue par les doublons** : chaque exemplaire compte (19 paliers d'étoiles).
4. **Toujours avancer** : la Patrouille rapporte même hors ligne ; la campagne débloque tout.

## 2. Combat en temps réel (`scripts/core/rt_battle.gd`, `data/rt_rules.json`)

- **Terrain** : ton équipe à gauche, l'adversaire à droite. Grille 3 × 3 par camp (colonne devant,
  milieu, fond × 3 rangées). Jusqu'à **6 héros** (3 au départ, 4e case à l'étape 3, 5e à 6, 6e à 12).
- **Placement selon la classe** : Gardien devant ; Guerrier devant ou milieu ; Prêtre, Archer, Mage
  milieu ou fond ; Assassin partout (les Assassins plongent sur l'arrière-garde).
- **Déroulement** : simulation à pas fixe (0,05 s). Chaque héros choisit une cible, avance jusqu'à
  portée (1,2 m mêlée à 5,2 m distance), attaque à sa cadence et lance sa **compétence** dès qu'elle
  est prête (recharge 9 à 13 s). Combat limité à **90 s** : à l'expiration, l'attaquant perd.
- **Énergie d'Overdrive commune** (DT) : jauge de **10**, départ 2, +0,55 par seconde, +0,5 par
  ennemi achevé. Chaque Overdrive a un **coût** (2 à 5), une **recharge** propre (16 à 22 s) et
  n'est jamais prêt avant **6,5 s** ; deux Overdrive d'une même équipe sont séparés d'au moins
  **1,2 s**. Le joueur touche la carte d'un héros pour le lancer ; **AUTO** les lance à sa place
  (soins quand un allié passe sous 70 % de PV, sinon dès qu'un ennemi est à portée). Les boss
  **annoncent** leurs Overdrive (cercle rouge) : un contrôle pendant l'annonce l'annule.
- **Dégâts** = puissance × K / (K + DEF × (1 − pénétration)), K = 600 + 30 × niveau de
  l'attaquant ; DEF physique ou magique selon le type ; critique (8 % de base, +60 %) ; blocage
  (−30 %) ; bonus de dégâts, dégâts subis, réduction (plafond 70 %) ; variance ±5 %.
  PV multipliés par 2,6 en combat (combats de 30 s en moyenne).
- **Statuts** (`data/rt_statuses.json`, durées en secondes) : Étourdissement, Gel, Sommeil,
  Silence, Provocation, Lenteur, Brûlure, Choc, Givre, Poison, Saignement, Défense brisée,
  Faiblesse, Vulnérabilité, Malédiction, bonus d'ATK/DEF/vitesse/Hâte/dégâts/réduction/critique,
  Régénération, Immunité, Insaisissable, et les marques de faction. Chance de pose : chance de
  la compétence + PRÉ − RÉS (10 % minimum). Les boss ignorent Gel, Sommeil et Provocation et
  subissent les autres contrôles deux fois moins longtemps.

## 3. Classes et factions (`data/classes.json`, `data/factions.json`)

| Classe | Place | Portée | Rôle |
|---|---|---|---|
| Gardien | devant | 1,3 m | encaisse, provoque, protège |
| Guerrier | devant / milieu | 1,4 m | dégâts au contact, contrôle |
| Assassin | partout | 1,2 m | plonge sur l'arrière-garde |
| Archer | milieu / fond | 5,2 m | dégâts à distance |
| Mage | milieu / fond | 4,6 m | zones, contrôles, magie |
| Prêtre | milieu / fond | 4,6 m | soins, boucliers |

Stats de classe au niveau 100 reprises de DT (ex. Gardien 904 ATK, 13 186 PV, 1 381 / 1 507 DEF).

Les **6 factions** sont les 6 pièces d'échecs ; chacune transpose une faction de DT :

| Faction | DT | Mécanique |
|---|---|---|
| **Roi** | Écho élémentaire | Brûlure, Choc, Givre ; un 2e élément sur une cible déclenche une **Réaction** (Surcharge : zone + Défense brisée ; Vaporisation : gros dégâts ; Supraconduction : Étourdissement) |
| **Cavalier** | Esprit sauvage | **Rage** en frappant et en perdant des PV ; pleine : **Galop** 8 s (+35 % vitesse d'attaque, +14 % dégâts, −8 % dégâts subis) |
| **Fou** | Sagesse arcanique | **Éveil** à chaque Overdrive allié (6 max) : +3 % dégâts et +4 Hâte par Éveil |
| **Dame** | Gloire du sanctuaire | **Moral + Ferveur** sur un héros : **Grâce** 7 s (+28 % dégâts, +30 % soins, −16 % dégâts subis) |
| **Tour** | Voile d'illusion | **Châtiment** : +45 % de dégâts contre un ennemi dont l'Overdrive coûte 3 ou plus, et son prochain Overdrive coûte 1 de plus ; +25 % de dégâts contre ces cibles et 20 % de vol de vie pour les héros de la Tour |
| **Pion** | Retour de l'autre monde | Chaque allié tombé : +1 **Promesse** (4 max : +12 % ATK, −6 % dégâts subis par Promesse) et 10 % de PV rendus |

- Chaque héros R ou mieux a **2 factions** ; la 2e s'éveille à **6 étoiles**.
- **Bonus de faction** : 4 / 5 / 6 héros d'une même faction → ATK et PV de toute l'équipe +10 / 15 / 20 %.

## 4. Roster (`data/heroes.json`, fiche détaillée : `docs/KITS.md`)

24 héros (4 par classe, 4 par faction : 7 SSR, 8 SR, 9 R) + 6 **Pions d'encre** (N, un par classe)
+ 5 boss. Chaque héros a un **kit à 5 éléments** (comme DT) : attaque de base, **compétence**
(automatique), **Overdrive** (énergie), **passif** (débloqué au niveau 40) et **talent de faction**.

| Faction | SSR | SR | R |
|---|---|---|---|
| Roi | Montana (Mage), Noor-El (Archer) | Tarkhan (Mage) | Ymir (Mage) |
| Cavalier | Mello (Assassin) | Ghost (Assassin) | Eiríkr (Guerrier), Mohamed (Assassin) |
| Fou | Ezra (Mage) | Nyssa (Archer), Saraya (Prêtre) | Espion de Lumière (Assassin) |
| Dame | Mikhaïla (Prêtre) | Selene (Gardien), Jo Prince (Guerrier) | Issa (Prêtre) |
| Tour | Adrian (Gardien) | Yass (Archer) | Don Diego (Gardien), Général de Métal (Guerrier) |
| Pion | Don Selah (Guerrier) | Flint (Prêtre) | Nidhogg (Archer), Moussa (Gardien) |

Boss : Prométhée, l'Impératrice Géode, le Chronophage, le Wyrm de givre, le Serpent solaire.

## 5. Progression d'un héros (`scripts/core/profile.gd`)

- **Exemplaires** : chaque invocation donne un exemplaire (avec ses propres étoiles) ; le niveau,
  les reliques et la Résonance sont partagés par nom ; le combat prend l'exemplaire le mieux étoilé.
- **Niveau 1 → 100** (`data/levels.json`, courbes de DT) : Encre (XP) et Pièces ; Essence d'étoile
  aux paliers 10, 20, 40, 60, 80 ; plafond **selon les étoiles** (1-2★ : 40, 3★ : 60, 4★ : 80,
  5★ et plus : 100). Stats ×5 entre le niveau 1 et 100.
- **Étoiles** (`data/stars.json`, table HeroesStar de DT) : 19 paliers — 1-6 **or**, 1-6 **violet**,
  1-6 **rouge**, **arc-en-ciel** — de ×0,7 à ×2,12 sur les stats. Étoile de départ : N 1★, R 3★,
  SR 4★, SSR 5★ ; maximum : N 6★, R violet 6, SR rouge 6, SSR arc-en-ciel.
  - 1→2 et 2→3 : 4 copies à la même étoile ; 3→4 : 2 copies ; 4→5, 5→6 : 1 copie ;
  - 6★ → violet : 1 héros **de la même classe** à 6★ ; ensuite, en alternance, des copies 6★ du héros
    et 1 à 6 héros de classe 6★ ;
  - un **Pion d'encre** de la même classe remplace une copie (jusqu'à 6★) ; une **Poupée** remplace
    un héros de classe ; **montée rapide** jusqu'à 6★ en un bouton ;
  - **réinitialisation** (5 par semaine) : retour à 6★, copies rendues, héros de classe rendus en Poupées.
- **Doublons N** (Pions d'encre déjà possédés) : 10 **Gelée** ; 60 Gelée fabriquent un Pion 5★.
- **Résonance de classe** : un héros niveau 100 prend le **niveau de sa classe** (100 à 300), monté
  pour tous les héros 100 de cette classe ; plafond selon la meilleure étoile de la classe (5★ : 120,
  6★ : 140, violet 3 : 180… rouge 6 : 300) et pas plus de 40 niveaux d'avance sur la classe la plus basse.
- **Reliques** : 6 emplacements, sets, niveaux 0-15, recyclage intégral (inchangé ; « DEF » vaut
  pour les deux défenses, « VIT » devient de la Hâte). Elles tombent dans la Tour et l'Expédition.

## 6. Invocation (`data/gacha.json`, `scripts/core/gacha.gd`)

| Bannière | Taux | Garanties |
|---|---|---|
| **Appel de la Tour** (standard, Sceau) | SSR 3 %, SR 12 %, R 50 %, N 35 % | SR ou mieux toutes les 10 ; **SSR en 40** ; **liste de souhaits** après 100 invocations (5 SSR, 20 % chacun quand un SSR sort) |
| **Bannière limitée** (Sceau du destin) | idem | **SSR en 50**, chaque SSR est la vedette ; SR vedettes à 50 % |

1 invocation = 1 Sceau, ou 150 Éclats de Vœu. Compteurs séparés par bannière et sauvegardés.

## 7. Modes de jeu

- **Campagne** (`data/campaign.json`) : les 8 univers de la Tour en 8 chapitres, **240 étapes**
  (12 à 48 par chapitre), niveaux 1 à 100, boss en fin de chapitre. Première victoire : Éclats,
  Pièces, Encre, un Sceau toutes les 4 étapes. Débloque les cases, la Tour (étape 8) et
  l'Expédition (étape 12).
- **Patrouille** (idle) : Pièces, Encre et Essence à la minute selon l'étape atteinte, stockées
  jusqu'à 12 h ; **Patrouille rapide** = 2 h de revenu (1 gratuite par jour, puis 50, 80, 100… Éclats).
- **La Tour des 99 Étages** (`data/tower.json`) : étages générés, Élite tous les 6, boss à la fin de
  chaque univers (12, 25, 38, 50, 63, 75, 88, 99) ; Éclats à la première victoire, reliques à chaque
  victoire.
- **Expédition** (`data/loot_bosses.json`) : Chronophage, Wyrm de givre, Serpent solaire ; 4 paliers
  (niveau 30 à 100) ; reliques des sets de chaque boss, pitié toutes les 8 victoires ; 12 d'énergie
  (rendue en cas de défaite).
- **Défis** (`data/challenges.json`, « Conquête des mythes » de DT), 2 essais par jour ; tenter un
  nouveau palier est gratuit, le **balayage** du meilleur palier consomme un essai :
  - **Défense de la forêt** (étape 10) : Archers, Mages et Prêtres seulement, 3 vagues de mêlée,
    20 paliers → Pièces ;
  - **Casse du trésor** (étape 16) : Gardiens, Guerriers et Assassins seulement, 3 vagues de tireurs → Encre ;
  - **Épreuve de la déesse** (étape 20) : deux classes par jour (toutes le samedi), 15 paliers →
    Essence et **Poupées** de la classe du jour ;
  - **Ralliement sauvage** (étape 24) : un héros par classe, vagues sans fin pendant 60 s, récompense
    selon le nombre d'ennemis achevés (record balayable).
  L'équipe envoyée est faite automatiquement des héros autorisés les plus puissants.
- **Missions** (`data/dispatch.json`, « Dispatch » de DT, étape 8) : 4 missions par jour (1 à 8 h),
  2 à 4 héros d'une classe ou d'une faction à un minimum d'étoiles ; les héros envoyés peuvent toujours
  combattre ; récompenses : Pièces, Encre, Essence, Gelée, Sceaux, Éclats, Poupées.
- **Codex** : chaque étoile atteinte pour la première fois par un héros donne 5 Éclats et +0,12 %
  d'ATK et de PV à toute l'équipe (bonus de compte, appliqué en combat).

## 8. Équilibrage mesuré (`tests/run_tests.gd`, 100 combats par duel)

- **Factions** (6 héros, niv. 80, 6★, équipes mono-faction) : victoires totales Roi 42, Cavalier 56,
  Fou 57, Dame 50, Tour 32, Pion 63 ; durée moyenne **30 s**.
- **Campagne** avec une équipe type (2 SSR, 2 SR, 2 R au niveau de l'étape, étoiles qui montent avec
  les chapitres) : 100 % jusqu'au chapitre 6, ~60 % aux chapitres 7-8, mur en fin de chapitre 8 (il
  faut investir étoiles et Résonance, comme dans DT).

## 9. Direction artistique

Inchangée (voir v0.11 à v0.16) : personnages VRoid convertis au squelette Mixamo, portraits en
estampe, police Fredoka / Lilita One, or et cartes sombres, décors par univers, VFX par shaders.
Nouveautés v0.17 : vue de combat de côté (caméra 3/4 haute), animation de marche, cartes d'Overdrive,
jauge d'énergie cyan, icônes des 6 factions en pièces d'échecs (`tools/refonte_icons.py`).

## 10. Ce qu'il reste à reprendre de Dragon Traveler

- **Éveil divin** (après l'arc-en-ciel), **Serment** (bonus de classe/faction), **Affection**.
- Modes : **Duel de slimes**, **Colisée** (1 contre 1 enchaîné), **Faille** roguelite (PV et énergie
  conservés), **Évasions** (labyrinthe), **Arène** et ligues (PvP asynchrone), guilde.
- Protagoniste et **Dragon** (case Dragon de la grille, sorts de Wyrm).
- Équilibrage fin des kits (Tour et Roi un peu faibles en équipe pure) et portraits des Pions d'encre.
