# La Tour des 99 Étages — Game Design Document (v0.1)

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
| Invocation 90 / 9 / 1 %, Légendaire garanti en 120, Épique au moins toutes les 20, vedette x2 | Identique au départ | **Codé** |
| Capitaine : bonus passif du chef d'équipe | « Chef d'escouade » : 1 bonus d'équipe par personnage | À concevoir |
| Niveau plafonné par les étoiles (30/40/50/60), promotion par sacrifice | Paliers 30/40/50/60, promotion par « Fragments d'étage » | À concevoir |
| Ascension 1 à 6 par matériau élémentaire, stats + amélioration de compétence | Ascension par « Éclats de constellation » (Orion, Grande Ourse ou Sirius) | À concevoir |
| Histoire : 12 chapitres, 4 difficultés (Facile, Difficile, Purgatoire, Enfer) | Ascension : 8 univers, 99 étages, 4 difficultés | À concevoir |
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

## 7. Roster MVP (9 personnages)

| Perso | Nation | Classe | Voie | Rareté proposée |
|---|---|---|---|---|
| Eiríkr | A · Orion | DPS mono-cible | Puer Aeternus | 5★ (vedette) |
| Ymir | A · Orion | Neutralisateur (Sommeil) | Sage | 5★ |
| Nidhogg | A · Orion | Support | Souverain | 4★ |
| Don Diego Lopez | B · Grande Ourse | Tank défensif | Souverain | 5★ |
| Général de Métal | B · Grande Ourse | DPS zone | Guerrier | 5★ |
| Espion de Lumière | B · Grande Ourse | Neutralisateur (Poison) | Chercheur | 4★ |
| Moussa | C · Sirius | Tank offensif | Protecteur | 5★ |
| Issa | C · Sirius | Support | Chercheur | 4★ |
| Mohamed | C · Sirius | DPS mono-cible | Magicien | 5★ |

Kits et stats : `data/characters.json` (repris tels quels du doc MVP). Les 3★ du gacha sont pour
l'instant des « recrues » génériques, une par nation, à créer.

## 8. Reliques

- 6 emplacements. Stat principale par emplacement (calquée sur Dislyte) :
  I ATK plate · II ATK%/DEF%/PV%/TC/DC · III DEF plate · IV ATK%/DEF%/PV%/PRÉ/RÉS · V PV plats ·
  VI ATK%/DEF%/PV%/VIT.
- Niveaux 0 à 15 ; 3 secondaires au départ ; aux paliers +3/6/9/12/15, une 4e secondaire est ajoutée
  puis une secondaire existante est renforcée.
- Sets (doc MVP) : Orion → Attaque (2), Vitesse (2), set de 4 à créer · Sirius → Défense (2),
  Immunité (2), Vampirisme (4) · Grande Ourse → Vie (2), Précision (2), Gel (4).
- Effets spéciaux codés : Vampirisme 20 %, Immunité au 1er tour, Gel 10 % quand le porteur est
  attaqué.
- Suggestion pour le set de 4 d'Orion (offensif, ATK/VIT) : **Assaut** — « après une attaque
  critique, +10 % de PA (une fois par tour) ». Il sert les DPS rapides et reste dans l'esprit
  « vitesse » d'Orion.

## 9. Invocation et économie (proposition)

- Monnaie premium : **Éclats de Vœu** (1 invocation = 1 éclat, ou 160 gemmes).
- Bannières : standard + vedette (taux de la vedette x2 parmi les 5★). Garanties : Légendaire à
  120, Épique au moins toutes les 20. Le compteur Légendaire est conservé d'une bannière vedette à
  l'autre.
- Mesuré sur 100 000 invocations simulées : 3★ 88,4 % · 4★ 10,2 % · 5★ 1,42 % (le 1 % affiché
  monte à environ 1,4 % réel grâce à la garantie).
- Doublons → « Fragments d'étage » (promotion). Échange en boutique contre une monnaie de doublons.
- Revenu gratuit à cibler : environ 1 Légendaire par mois pour un joueur actif (à chiffrer).

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
6. Style visuel : MakeHuman donne un rendu réaliste et des vêtements de ville. C'est proche de
   Dislyte (urbain moderne), mais les tenues de la Tour (armures, tenues d'univers) demanderont des
   vêtements sur mesure.

## 13. Feuille de route

1. **v0.1 (fait)** : moteur de combat, 9 kits, gacha, reliques, combat jouable avec des capsules,
   tests et simulation.
2. **v0.2** : premiers modèles 3D (pipeline MakeHuman → Mixamo → Godot), écran d'équipe, collection
   et équipement des reliques, sauvegarde locale.
3. **v0.3** : Ascension de la Tour (univers 01, 12 étages), 3 boss de butin, énergie.
4. **v0.4** : progression (niveau, promotion, ascension), capitaine, premier tutoriel.
5. **v0.5** : guerre de territoire (PvP asynchrone), serveur.
