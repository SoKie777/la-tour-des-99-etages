# T99 — Game Design Document (à jour v0.15.0)

Synthèse de la *Bible d'univers* et du document *MVP : triangle des nations et roster* (14/10/2026),
complétée par les systèmes de **Dislyte** que l'on reprend. La direction musicale de Dislyte
(personnages et identité construits autour de la musique) est **écartée**.

Tout ce qui est chiffré vit dans `data/*.json` et se règle sans toucher au code.

---

## 1. Vision

Un gacha RPG mobile au tour par tour, 3 contre 3, en 3D stylisée. On y monte la Tour des 99 étages
pour atteindre le Vœu. Trois nations s'affrontent autour de la Tour.

Piliers :
1. **Combat lisible et tactique** : barre d'action pilotée par la Vitesse, 3 compétences par
   personnage, contrôles et bonus d'équipe (le « speed tuning » de Dislyte).
2. **Composer selon le triangle** : Orion > Grande Ourse > Sirius > Orion. Chaque boss de butin
   pousse à monter une équipe de la constellation qui le domine.
3. **Progression longue par l'équipement** : reliques à sets et stats secondaires aléatoires.
4. **Récit vertical** : 8 univers, 99 étages, une nation par porte.

## 2. Ce que l'on reprend de Dislyte

| Système Dislyte | Dans la Tour | Statut |
|---|---|---|
| Barre d'action, la VIT décide l'ordre, effets sur les PA | Identique (doc MVP) | **Codé** |
| 3 compétences, S2 parfois passive, ultime avec recharge | Identique | **Codé** |
| Rôles : DPS, tank, contrôle, soutien | DPS mono/zone, Tank off/déf, Neutralisateur, Support | **Codé** |
| Éléments en triangle | Constellations (étiquette de porte, pas un élément) | **Codé** |
| Reliques : 6 emplacements, 4 « Una » (set de 4) + 2 « Mui » (set de 2), stat principale par emplacement, secondaires à +3/6/9/12/15 | 6 emplacements, un set de 4 + un set de 2 **ou** trois sets de 2 (choix du doc MVP) | **Codé** (génération, montée, sets) |
| Invocation 90 / 9 / 1 %, Légendaire garanti en 120, Épique au moins toutes les 20, vedette x2 | Rare / Épique / Légendaire 70 / 25 / 5 % (fiche, pièces d'échecs), garanties 80 et 10, vedette x2 | **Codé** |
| Capitaine : bonus passif du chef d'équipe | « Chef d'escouade » : 1 bonus d'équipe par personnage | À concevoir |
| Niveau plafonné par les étoiles (30/40/50/60), promotion par sacrifice | Paliers 30/40/50/60, promotion par « Fragments d'étage » | À concevoir |
| Ascension 1 à 6 par matériau élémentaire, stats + amélioration de compétence | Ascension par « Éclats de constellation » (Orion, Grande Ourse ou Sirius) | À concevoir |
| Histoire : 12 chapitres, 4 difficultés (Facile, Difficile, Purgatoire, Enfer) | Ascension : 8 univers, 99 étages, 4 difficultés | **Codé** : univers 01 (12 étages), 1 difficulté |
| Ritual Miracle (boss à reliques) | 3 boss de butin, un par constellation | Règles posées |
| Sonic Miracle (matériaux élémentaires, rotation quotidienne) | Sanctuaires de constellation (matériaux d'ascension) | À concevoir |
| Cube Miracle (donjon roguelite) | Archives des Mille Vérités : labyrinthe à choix | Plus tard |
| Point War / Arène (défense contre attaque) | Guerre de territoire autour de la Tour (triangle actif) | Plus tard |
| Musique au cœur des personnages et de l'identité | — | **Écarté** |

## 3. Univers (résumé de la Bible)

- La Tour : 99 étages, 8 univers ; au sommet, un Vœu unique.
- Nations et constellations (attribuées par la porte d'entrée, quelle que soit l'affinité) :
  - **Nation A**, constellation **Orion** : noms nordiques ;
  - **Nation B**, constellation **Grande Ourse** : noms asiatiques et ibériques ;
  - **Nation C**, constellation **Sirius** : noms égyptiens et ouest-africains.
- Univers : 01 Cité d'Acier (1-12) · 02 Forêt des Gemmes (13-25) · 03 Désert de Verre (26-38) ·
  04 Abysses de Glace (39-50) · 05 Archives des Mille Vérités (51-63) · 06 Mer Céleste (64-75) ·
  07 Royaume des Serments (76-88) · 08 Domaine des Clans & Terres de Ragnarök (89-99).
- 12 Voies (Puer Aeternus, Sage, Souverain, Guerrier, Chercheur, Protecteur, Magicien, Orphelin,
  Amant, Destructeur, Créateur, Clown) : elles fixent la nature des pouvoirs. La classe fixe le rôle.

## 4. Boucles de jeu

- **Session (5 à 15 min)** : énergie → étages de la Tour ou boss de butin → reliques → équiper ou
  monter → retenter un étage bloquant.
- **Quotidienne** : missions, sanctuaire du jour, guerre de territoire, invocation gratuite.
- **Long terme** : ascension des personnages, reliques parfaites, haut de la Tour en Enfer,
  classement PvP.

## 5. Combat (règles codées)

Source : doc MVP (le plus récent). Les écarts avec la Bible sont tranchés en §11.

- 3 contre 3. Jauge de PA de 0 à 100 %. Gain = VIT ÷ 1 000 par tic. À 100 %, l'unité joue, puis sa
  jauge retombe à 0. Égalité : la VIT la plus haute joue d'abord.
- **Tic continu** (`tick_mode` dans `rules.json`) : on avance directement jusqu'au prochain 100 %.
  Avec des tics discrets de 1/1 000, toutes les VIT de 100 à 111 jouent au même rythme (10 tics) :
  la VIT perdrait son intérêt. Le mode continu garde les mêmes proportions sans cet effet de palier.
- Compétence 1 sans recharge. Compétence 2 : recharge 3, disponible dès le début. Compétence 3 :
  recharge 5, démarre avec 2 tours à attendre (utilisable au 3e tour).
- Dégâts = Stat × multiplicateur × 1 000 / (1 000 + DEF) × (1 + DC si critique) × variance (0,95 à 1,05).
- Chance d'effet = chance de la compétence + PRÉ − RÉS, bornée entre 15 et 100 %.
- Effets : Brûlure, Ralentissement, Défense brisée, Désorientation, Silence, Provocation, Poison,
  Malédiction, Sommeil (réveil quand touché), Étourdissement, Gel, plus les bonus ATK/DEF/VIT/TC/DC,
  Bouclier et Immunité.
- Précisions d'implémentation (à valider) :
  - un effet posé pendant le tour de sa cible ne perd pas de tour à la fin de ce tour (sinon un
    bonus « 2 tours » posé sur soi n'en durerait qu'un) ;
  - les dégâts sur la durée ignorent la DEF et ne réveillent pas ;
  - le Poison frappe aussi après un tour passé sous contrôle ;
  - réappliquer un effet déjà présent le rafraîchit (durée et valeur max), sans cumul.

## 6. Triangle des constellations

- Dominant contre dominé : **+20 points de TC** (plafond 100 %).
- Dominé contre dominant : **−15 % de dégâts**.
- Leviers non actifs : −10 PRÉ ou −20 RÉS pour le dominé.
- PvE : gardiens d'univers neutres ; seuls les 3 boss de butin portent une constellation.

## 7. Roster (24 personnages)

**Fiche v2** (« Personnages jouables et boss », kits façon Dislyte : Tyr, Raven, Cecilia, Sieg) : 15
personnages, noms d'AWAKE conservés pour l'instant. Kits, interprétations et barème de stats : `docs/KITS.md`.

| Constellation | Légendaires (5★) | Épiques (4★) |
|---|---|---|
| Orion | Montana Legend (Neutralisateur, Gel), Mikhaïla Osborne (Support) | Ghost (DPS mono), Nyssa Morghulis (DPS zone), Selene Lace (Tank défensif) |
| Grande Ourse | Adrian Ross (Tank offensif), Mello Legend (DPS mono) | Tarkhan Blaze (DPS zone), Yass Ming (Neutralisateur, Malédiction), Saraya Belrose (Support) |
| Sirius | Noor-El (DPS zone), Ezra Lux (Neutralisateur, Étourdissement), Don Selah (Titan) | Jo Prince (DPS mono), Flint Davidson (Support) |

**Rares (3★)** : les 9 personnages du MVP (Eiríkr, Ymir, Nidhogg, Don Diego Lopez, Général de Métal,
Espion de Lumière, Moussa, Issa, Mohamed). Ils sont nettement plus faibles que les Épiques et Légendaires
(voir `docs/KITS.md`).

## 8. Reliques

- 6 emplacements. Stat principale par emplacement (calquée sur Dislyte) :
  I ATK plate · II ATK%/DEF%/PV%/TC/DC · III DEF plate · IV ATK%/DEF%/PV%/PRÉ/RÉS · V PV plats ·
  VI ATK%/DEF%/PV%/VIT.
- Niveaux 0 à 15 ; 3 secondaires au départ ; aux paliers +3/6/9/12/15, une 4e secondaire est ajoutée
  puis une secondaire existante est renforcée.
- Sets validés (fiche, partie 4), par boss de butin : 2 sets de 4 pièces et 1 set de 2.
  Orion → Attaque (4 : +15 % ATK à 2 pièces, +30 DC à 4), Vitesse (4 : +12 % VIT, puis +13 %),
  Taux critique (2 : +12 TC) · Sirius → Vampirisme (4 : +10 % PV, vol de vie 20 % à 4), Défense (4 :
  +15 % DEF, puis +15 %), Immunité (2 : Immunité au 1er tour) · Grande Ourse → Gel (4 : +15 RÉS, 10 % de
  geler l'attaquant à 4), Vie (2 : +15 % PV), Précision (2 : +20 PRÉ).
- Plus tard (fiche, parties 4 et 5) : sets type Ocean, Astralis, Calamity, Aegis ; Poursuite, Bain de sang,
  Effort, Tissage du temps ; qualité des reliques (6 niveaux), recyclage intégral, pitié de relique.

## 8 bis. Cinématique d'invocation (fiche, partie 3) — codée

Plateau d'échecs en marbre, trois couloirs éclairés (Orion bleu glacé, Grande Ourse rouge sang, Sirius
or pâle). Chaque tirage : un pion blanc sur l'avant-dernière case du couloir de sa constellation, qui
avance vers la promotion et devient cavalier ou fou (Rare), tour (Épique) ou dame (Légendaire, qui tourne
et s'illumine). En invocation simple, le personnage sort ensuite de la pièce ; en x10, les dix pions
avancent ensemble et les résultats s'affichent. Bouton « Passer ». Pion noir et roi réservés.
`scripts/ui/summon_cinematic.gd`.

## 8 ter. Boss de butin (v0.4) — noms et mécaniques PROVISOIRES

Un boss par constellation (`data/loot_bosses.json`), chacun donne les reliques de sa constellation ; 12
d'énergie par combat (rendue en cas de défaite). Mécaniques inspirées des boss de Dislyte (fiche, partie 4) :

| Boss | Constellation (dominé par) | Mécanique | Reliques |
|---|---|---|---|
| Le Chronophage | Orion (Sirius) | +5 % de jauge à chaque tour d'un héros, +6 % de dégâts par tour | Attaque, Vitesse, Taux critique |
| Le Wyrm de givre | Grande Ourse (Orion) | 3 barres de PV ; bouclier à chaque barre ; s'il tient jusqu'à son tour, Gel et écrasement du héros le plus fort | Gel, Vie, Précision |
| Le Serpent solaire | Sirius (Grande Ourse) | Venin solaire : explose au bout de 3 tours (20 % des PV) sauf purge | Vampirisme, Défense, Immunité |

Paliers Facile / Difficile / Purgatoire / Enfer : puissance ×1 / 1,35 / 1,8 / 2,4, 2 à 3 reliques déjà
montées à +0 / +3 / +6 / +9. Battre un palier débloque le suivant. En Purgatoire et en Enfer, les équipes
qui ne dominent pas le boss ratent 30 à 40 % de leurs attaques et subissent +20 à 35 % de dégâts.
Pitié : une relique du set choisi toutes les 8 victoires. Réglage (`tools/tune_loot.gd`, équipes de 2
attaquants + 1 soutien, sans reliques) : tout le monde gagne en Facile ; en Difficile la constellation
dominante gagne presque toujours ; Purgatoire et Enfer demandent des reliques.

## 9. Invocation et économie (v0.2, réglable dans `data/progression.json` et `data/tower.json`)

- Monnaie premium : **Éclats de Vœu** (1 invocation = 1 éclat). Gagnés à la **première victoire** de chaque
  étage : 3, 6 pour un étage Élite, 10 pour un boss.
- **Pièces** : gagnées à chaque victoire (300 + 60 × étage). Elles servent à monter les reliques
  (100 + 100 × niveau actuel, soit 12 000 pour aller de +0 à +15).
- **Reliques** : 1 relique aléatoire (set et emplacement) à chaque victoire, même en rejouant un étage.
- **Nouveau joueur** : Eiríkr seul, 0 Éclat, 2 000 Pièces, puis le **prologue** (section 9 bis). Les
  cadeaux de test (`grants`) ne sont versés qu'à la fin du prologue.
- Bannières : standard + vedette (taux de la vedette x2 parmi les 5★). Garanties : Légendaire à
  80, Épique au moins toutes les 10. Les compteurs sont communs à toutes les bannières et sauvegardés.
- Taux de la fiche : Rare 70 %, Épique 25 %, Légendaire 5 % (indicatifs, à régler avec l'économie).
- Doublons → **Fragments d'étage** (1 par Rare, 10 par Épique, 40 par Légendaire), pour la promotion (v0.4).
- Revenu gratuit à cibler : environ 1 Légendaire par mois pour un joueur actif (à chiffrer).
- **Énergie** (fiche, partie 5 : généreuse) : 120 au maximum, +1 toutes les 5 minutes, y compris pendant
  l'absence. Étages 1 à 4 gratuits, puis 6 par combat ; une défaite rend l'énergie.
- **Balayage** : un étage déjà gagné se rejoue sans combat (x1 ou x5), au même coût en énergie.
- **Recyclage intégral** : démonter une relique rend toutes les Pièces investies, plus 50.
- **Formations** : 3 emplacements qui mémorisent l'équipe et ses reliques ; les appliquer déplace les
  reliques au besoin.

### Ascension de la Tour (univers 01, Cité d'Acier)

12 étages ; l'étage 6 est Élite, l'étage 12 est le boss **Prométhée** (`data/bosses.json`, fiche partie 2) :
Ignis Divinus (2 coups, retire des buffs, pose des Clefs : +8 % de dégâts subis par Clef, purgeables),
Aletheia (désactive 1 tour un héros qui a utilisé la même compétence deux tours de suite, sinon échoue),
Surcharge (3 coups sur toute l'équipe) ; ressuscite une fois à 20 % ; phase 2 sous 50 % PV (−2 % PV par
tour, +30 % de dégâts). Règles des boss : Gel impossible sur un boss final, Étourdissement et Sommeil
deux fois moins probables. Paliers Facile / Difficile / Purgatoire / Enfer (×1 / 1,3 / 1,7 / 2,2), la Tour
utilise Facile. Réglage (`tools/tune_boss.gd`, sans reliques) : les Rares seuls perdent toujours, une
équipe d'Épiques ou de Légendaires gagne environ 2 fois sur 3. Les ennemis sont
des personnages du roster dont PV, ATK et DEF sont multipliés par la **puissance** de l'étage. Les
personnages du joueur ont leurs stats de niveau max (pas encore de niveaux), d'où des puissances autour
de 1. La difficulté dépend surtout de la composition adverse : quelques % de puissance font basculer un
combat. Réglage mesuré (IA des deux côtés, sans reliques, `tests/run_tests.gd`) :

| Équipe | 1-4 | 5 | 6 (Élite) | 7 | 8-12 |
|---|---|---|---|---|---|
| Départ (Nidhogg, Espion, Issa) | 90-100 % | 30 % | 38 % | 93 % | 0 % |
| Mixte (Eiríkr, Issa, Don Diego) | 98-100 % | 100 % | 100 % | 90 % | 100 → 33 % (boss) |

Intention : l'équipe de départ bute aux étages 5-6 (il faut invoquer ou s'équiper), le haut de l'univers
demande une bonne composition et le boss demande des reliques. `tools/tune_tower.gd` mesure les taux pour
plusieurs puissances.

### Mode tactique de la Tour (v0.7, inspiré de Honkai: Star Rail)

Seulement dans l'Ascension : le JcJ, les combats libres et les boss de butin gardent les règles de base.
Réglages : `data/rules.json` → `tower_tactics` ; moteur : `BattleEngine.enable_tactics()`.

- **Sceaux d'équipe** (réserve commune, 5 max, 3 au départ) : S1 en donne 1, S2 en coûte 1. Les
  personnages à S2 passive alimentent naturellement les autres.
- **Énergie et ultime hors tour (contre un boss seulement ; ailleurs l'ultime reste classique)** : chaque héros remplit sa jauge (S1 +20, S2 +30, coup reçu +8,
  ennemi achevé +10, départ 40). Pleine, l'ultime se lance d'un bouton sur la fiche du héros, **à tout
  moment** : il coupe la ligne de temps sans consommer le tour ni la jauge d'action.
- **Ténacité et Rupture** : chaque ennemi a une Ténacité (60, Élite 100, boss 180). Seule la
  constellation qui domine la sienne l'entame (S1 10, S2 20, ultime 30 ; ×0,6 en zone) ; un boss a ses
  propres faiblesses (`weakness`). À zéro : recul de 30 % sur la barre d'action, dégâts de Rupture (120 %
  de l'ATK du briseur), effet selon la constellation du briseur (Orion : Lenteur, Grande Ourse :
  Brûlure, Sirius : DEF −30 %), +50 % de dégâts subis jusqu'à son prochain tour, et **assaut coordonné**
  des autres héros (40 % de leur ATK). La Ténacité revient au tour suivant de l'ennemi.
- **Charge des boss** : tous les 4 tours, le boss charge (son marqueur clignote, icône « ! ») ; s'il n'est
  pas brisé avant son tour suivant, **Oblitération** sur toute l'équipe (200 % de son ATK).
- **Résonance** : 2 héros d'une même constellation → Orion +10 % VIT, Grande Ourse +12 % ATK, Sirius
  +15 % PV ; les 3 constellations (**Triade**) → un Sceau max de plus.
- **Tutoriel** : au premier combat de la Tour (et page « boss » au premier boss), réaffichable avec le
  bouton « ? » ; un cadre doré montre la zone expliquée (`scripts/ui/tower_tutorial.gd`). Factions
  visibles : emblème de constellation devant chaque nom, au-dessus des ennemis et sur la ligne de temps ;
  faiblesses du boss en grand au-dessus de lui.
- **Étoiles** (comme la Mémoire du Chaos) : victoire, aucun héros K.O., victoire en 15 actions d'équipe au
  plus. Chaque nouvelle étoile rapporte 2 Éclats ; les étoiles et les faiblesses s'affichent dans la Tour.

### Univers 02 : Forêt des Gemmes (étages 13 à 25)

Ennemis du roster v2 (puissance 0,9 à 1,1), Élites aux étages 18 et 24, boss **l'Impératrice Géode**
(étage 25, faible à Grande Ourse et Sirius ; Éclat tranchant, Pluie de gemmes, Prisme cristallin ; phase
Cœur de quartz sous 50 % PV). Modèle VRoid dédié (tenue repeinte en améthyste) depuis la v0.12.
Réglage mesuré en mode tactique, sans reliques : une équipe 5★ (Montana, Adrian, Noor-El) passe presque
tous les étages et bat la Géode environ 1 fois sur 5 ; une équipe d'Épiques bloque dès l'étage 18.
Le boss demande donc des reliques. Don Selah n'est pas un adversaire de la Tour tant que son kit n'est
pas revu (S3 déjà réduite : 130 % ATK + 45 % DEF par coup au lieu de 150 % + 50 %).

### Armes anti-boss (kits, v0.7.2)

Une action du kit, toujours active, qui a l'air anodine mais renverse le combat contre un boss précis
(clé `boss_bane` : boss visé et explication pour l'interface). Un 5★ avantagé (tiré au sort) l'a en entier,
un Épique de la même nation en version réduite. Portraits étoilés sur l'étage du boss, fiche en Collection.

| Boss | 5★ | Épique |
|---|---|---|
| Prométhée | Montana : Kairos (Room) efface les Clefs de toute l'équipe et empêche la cible de se relever (annule sa résurrection) | Nyssa : chaque S1 retire une Clef à chaque allié |
| Impératrice Géode | Mello : chaque coup de S1 brise boucliers et protections (le Prisme cristallin) | Yass : chaque coup de S1 a 25 % de chance de briser le bouclier |

### Montana, poursuites en chaîne (v0.7.1)

S1 : frappe puis poursuites (1re certaine, puis 50 %, 30 %, 10 %), à 50 / 45 / 40 / 35 % de l'ATK, +15 %
sous Room. Toute compétence de Montana qui touche un ennemi gelé déclenche la même chaîne ; Selah (S3)
qui gèle la déclenche donc aussitôt. En moyenne 1,67 poursuite par S1.

## 9 bis. Prologue (v0.8, `data/prologue.json`)

Joué dès le lancement d'une nouvelle partie : le menu et la Tour restent fermés jusqu'à la fin.
Objectif : sortir du prologue avec les bases (tour de jeu, Sceaux, triangle, Ténacité et Rupture,
composition d'équipe et Résonance, boss et armes anti-boss, élites), **au moins 2 Légendaires** et
**8 invocations x10** en poche.

- On commence avec **Eiríkr** (Orion) seul. 8 niveaux en mode tactique ; chaque victoire rapporte
  **10 Éclats** (une x10) et 1 500 Pièces. Les pages du tutoriel arrivent niveau par niveau.
- Niveaux 1 à 3 **impossibles à perdre** (les héros ne descendent pas sous 1 PV).
  1. Le Réveil : un espion de la Grande Ourse. Tour de jeu, compétences, Sceaux.
  2. Le Triangle : deux ennemis de la Grande Ourse, dominés par Orion. Triangle, Ténacité, Rupture.
  3. L'Équipe : trois gardiens de Sirius (qui domine Orion) : il faut composer une équipe de 3 avec la
     Grande Ourse (Yass). Le bouton « Combattre » n'apparaît qu'une fois l'équipe complète.
  4. L'Écho de Prométhée (boss, 80 %) : page des boss (faiblesses Orion et Sirius : Eiríkr).
  5. Les Trois Voies : une constellation de chaque. 6. La Garde d'Acier (élite de la Grande Ourse).
  7. Les Sentinelles (Orion, dominés par Sirius). 8. L'Écho de la Géode (boss, 85 %) : armes de Mello et Yass.
- **Bannière de départ « Premier Appel »** (cachée ensuite) : deux x10 **offertes**, après les niveaux 2
  et 3. Le prix (10 Éclats, que le joueur possède) est affiché barré en grand. Aucun Légendaire avant la
  garantie, fixée à 20 :
  - 1re x10 : Rares et Épiques seulement, la 10e invocation donne **Yass** (arme contre la Géode) ;
  - 2e x10 : la 20e invocation touche la garantie et donne **Mello** (arme contre la Géode). Choix de
    l'auteur : Mello plutôt que Montana, vedette de la bannière payante.
  Les compteurs de garantie sont partagés : après la bannière de départ, la garantie Légendaire repart
  de zéro, et les 80 Éclats du prologue (80 invocations) assurent un 2e Légendaire.
- Simulation (sans reliques, IA) : Mello + Yass + Eiríkr (ou un Épique) gagnent 100 % des niveaux 4 à 8 ;
  sans Légendaire (Eiríkr, Yass, Issa) 27 à 90 % ; Mello sans Yass perd souvent contre Prométhée.
- Les sauvegardes d'avant la v0.8 sont considérées comme ayant fini le prologue.

## 9 ter. Direction artistique (v0.11 à v0.15)

- **Personnages** : modélisés dans VRoid Studio, exportés en VRM 0.0, puis convertis par
  `tools/vroid/vrm_to_fbx.py` (squelette renommé en Mixamo, pour garder les animations existantes).
  Depuis la v0.15, **les 24 personnages jouables** et les boss Prométhée et Géode sont en VRoid. Les Rares
  (3★), qui servent aussi d'adversaires dans la Tour, gardent des tenues simples. Le pipeline est décrit dans
  `docs/PIPELINE.md`.
- **Identités visuelles fixées** : Montana a les cheveux noirs en locks vanille et une tenue kente noir et or ;
  la Géode a une tenue repeinte en améthyste.
- **Portraits** : buste rendu dans le jeu puis stylisé en estampe (`tools/ukiyoe_portraits.py --soft` :
  rendu anime conservé, seul le contour est encré) ; disque de la constellation et rang en kanji.
- **Interface** : police Fredoka (OFL), or et cartes sombres, pastilles de ressources, boutons « CTA » ;
  chaque bouton réagit au toucher (zoom, clic, rebond) et les fenêtres apparaissent sur fond flou.
- **Combat** : caméra cinématique (FOV 38, cadrage fixe validé), profondeur de champ, étalonnage
  Filmic, ombres 4096, liseré de lumière sur les personnages ; décors enrichis par univers (dojo à torii,
  forge volcanique, toundra) ; VFX par shaders (entailles, tornades, orbes, impacts, bris de cristal,
  aura au début du tour) et signature visuelle par personnage.
- **Invocation** : colonne de lumière dorée pour un 5★.
- **Licences** : aucun modèle VRM téléchargé (redistribution interdite) n'entre dans le dépôt ni dans
  l'APK ; seuls les personnages créés pour le jeu sont utilisés.

## 10. Résultats de simulation (IA simple des deux côtés, 400 combats par duel)

| Duel (équipes d'une seule nation) | Avec triangle | Sans triangle |
|---|---|---|
| A (Orion) vs B (Grande Ourse) | 39,5 % / 60,5 % | 1,8 % / 98,2 % |
| A (Orion) vs C (Sirius) | 0 % / 100 % | 0 % / 100 % |
| B (Grande Ourse) vs C (Sirius) | 97,8 % / 2,2 % | 56,2 % / 43,8 % |

Environ 5,5 à 6,5 tours par personnage et par combat : c'est dans la cible « 6 à 8 tours » du doc.

Ce que l'on en retient :
1. **Le triangle pèse très lourd** : il fait passer B contre C de 56/44 à 98/2. Les leviers −PRÉ/−RÉS
   sont inutiles ; il faudrait plutôt l'adoucir (par exemple +15 TC et −10 %).
2. **La nation A est faible par sa composition** : sans tank ni soin, avec un Sommeil qui saute au
   premier coup reçu, elle perd 98 % contre B quand le triangle est neutralisé. Ce n'est pas le
   triangle qui la fait perdre.
3. Une équipe mixte (Eiríkr, Issa, Don Diego) gagne 100 % contre B : les équipes mélangées sont bien
   plus fortes que les équipes d'une seule nation, ce qui est sain pour un gacha.

Réserve : l'IA vise toujours l'ennemi le plus blessé, même s'il dort. Une IA plus fine aiderait
Ymir. Ces chiffres sont des tendances ; il faut les refaire après chaque réglage
(`tests/run_tests.gd`).

## 11. Écarts entre les deux documents (tranchés en faveur du doc MVP, plus récent)

| Sujet | Bible | Doc MVP | Retenu |
|---|---|---|---|
| Courbe de DEF | 300 / (300 + DEF) | 1 000 / (1 000 + DEF) | 1 000 |
| Recharge de l'ultime | 4 tours | 5 tours, démarre à 2 | 5 / 2 |
| Eiríkr | Contrôleur Chrono, 11 200 PV | DPS mono-cible, 4 300 PV | DPS (doc MVP) |
| Montana Legend, Vane | Présents | Absents | Hors MVP, possible 2e vague |
| Set Vitesse | 4 pièces, +25 % | 2 pièces, +12 % | 2 pièces (doc MVP) |
| Set TC | 2 pièces, +12 % | Absent | Hors MVP |

## 12. Questions ouvertes

1. Liens constellation et affinité (proposition de l'ami : 3 familles de 4 affinités).
2. Noms définitifs du Général de Métal et de l'Espion de Lumière.
3. Zéro perte (Moussa) : trop fort ? À mesurer en simulation (avec et sans le passif).
4. Capitaine, promotion, ascension : à valider avant de les coder.
5. Rééquilibrage de la nation A (tank Tormund en 2e vague ?).
6. Style visuel : tranché en v0.11-v0.15, tous les personnages passent en VRoid (style anime, voir
   section 9 ter). Reste à faire : tenues d'univers sur mesure (armures, tenues de la Tour).

## 13. Feuille de route

1. **v0.1 (fait)** : moteur de combat, 9 kits, gacha, reliques, combat jouable avec des capsules,
   tests et simulation.
2. **v0.2 (fait)** : modèles 3D des 9 personnages (MPFB) et animations selon le rôle (Mixamo), profil
   sauvegardé, écrans Tour, Équipe, Collection (fiche, reliques) et Invocation, univers 01 de la Tour
   (12 étages) avec récompenses.
3. **v0.3** : roster v2 (15 Épiques et Légendaires, moteur de kits étendu : fait), modèles et animations
   des 15, équilibrage v2 (durée des combats, triangle), boss Prométhée (étage 12), cinématique
   d'invocation sur l'échiquier, 3 boss de butin, énergie.
4. **v0.4** : boss de butin (fait), puis progression (niveau, promotion, ascension), capitaine, premier tutoriel.
5. **v0.5** : guerre de territoire (PvP asynchrone), serveur.
6. **v0.11 à v0.15 (fait)** : direction artistique anime : les 24 personnages et les boss Prométhée et
   Géode en VRoid, portraits en estampe, police Fredoka, décors enrichis (dojo, forge, toundra), VFX
   par shaders, caméra cinématique et post-traitement, refonte de l'interface (or, cartes, « juice »).
