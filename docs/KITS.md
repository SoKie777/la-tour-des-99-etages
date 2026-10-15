# Kits : vocabulaire des compétences (`data/characters.json`)

Tout kit s'écrit en données. Le moteur (`scripts/core/battle_engine.gd`) les interprète ; un réglage de
valeur ne demande jamais de toucher au code. Chaque mécanique est vérifiée dans `tests/run_tests.gd`
(`test_kits_v2`).

## Raretés et stats

| Rareté | Qui | Stats (PV, ATK, DEF) | VIT |
|---|---|---|---|
| Rare (3★) | les 9 personnages du MVP | référence de la classe | référence |
| Épique (4★) | 8 personnages de la fiche v2 | +10 % | +3 |
| Légendaire (5★) | 7 personnages de la fiche v2 | +20 % (+ TC, DC, PRÉ, RÉS) | +6 |
| Titan | Don Selah | Légendaire +40 % | 115 |

Contrôle par simulation (équipes tirées au hasard) : 5★ contre 3★ = 100 % de victoires, 4★ contre 3★ =
90 %, 5★ contre 4★ = 98 %.

## Une compétence

| Champ | Rôle | Exemple |
|---|---|---|
| `target` | `enemy`, `ally`, `other_ally` (jamais soi), `all_enemies`, `all_allies`, `self` | |
| `cd`, `initial_cd` | recharge, et recharge au début du combat (par défaut 2 pour la S3) | Don Selah S3 : 4 / 1 |
| `hits` | liste de frappes (voir plus bas) | |
| `effects` | sur chaque cible, après les frappes | Gel 70 % |
| `pre_effects` | sur chaque cible, avant les frappes | Ezra S2 : retirer les buffs |
| `to_allies`, `to_enemies` | sur toute l'équipe alliée / ennemie, en plus de la cible | Saraya S3 |
| `self_effects` | sur soi, toujours appliqués (prix compris) | Ghost S3 : ATK −10 % |
| `bonus` | multiplicateurs de dégâts : `per_stack` (marques de la cible), `per_self_stack`, `per_ally_alive`, `per_removed` (buffs retirés), `per_spd`; `consume: true` vide les marques | Mello S3 : +40 % par Visage |
| `self_cost` | prix : `hp_pct` (% des PV max), `unhealable` (PV max perdus) | Mello S3 : 15 %, non soignable |
| `while_cooldown` | auras données aux alliés tant que la compétence est en recharge | Montana S2 : +10 % VIT |
| `on_effect_success` | relance une compétence si un effet a réussi | Montana S3 : Gel → S1 |
| `heal_lowest_ally_pct_dmg`, `lifesteal` | soin selon les dégâts infligés | Mikhaïla S1 : 40 % |
| `revive` | ressuscite un allié (`hp_pct`, `ap`, `once`) | Mikhaïla S3 |
| `detonate` | fait exploser des marques (`stack`, `pct_atk`, `consume_curse`) | Yass S3 |
| `copy_last_skill`, `clones_strike` | rejoue la dernière S2/S3 du combat ; frappe des clones | Nyssa S3 |
| `strip_all_buffs`, `lock_skill` | retire les buffs de tout le monde ; bloque une compétence au tour suivant | Ezra S3, Yass S3 |
| `desc` | texte affiché dans la fiche | |

### Une frappe (`hits`)

`scale` : une stat (`"atk"`, `"def"`, `"hp"` = PV max) avec `mult`, ou plusieurs : `{"atk": 0.35, "def": 0.3}`.
`repeat` (frappe plusieurs fois), `ignore_def`, `on_hit` (effets à chaque coup, avec leur chance),
`if` (`target_cc`, `target_slowed`), `random_other` (un autre ennemi au hasard), `target_max_hp_pct`.

### Effets et actions

Effets durables (définis dans `data/rules.json`, avec `turns`, `value`, `chance`) : Poison, Malédiction,
Sommeil, Étourdissement, Gel, Ralentissement, `spd_down`, `def_down`, `atk_down`, `res_down` (Révélé),
`vulnerable` (Expulsé), `aging` (Vieillissement), bonus d'ATK/DEF/VIT/TC/DC/PRÉ, Bouclier, Immunité,
`dmg_reduce`, auras (`aura_spd`, `aura_dmg_reduce`, `aura_chill`, `guarded`), posture `bastion`.
Options : `no_roll` (certain), `certain_if_stack`, `ignore_immunity`, `of` (`caster_max_hp`, `target_max_hp`).

Actions immédiates : `ap_down`, `ap_up` (`lowest_value`), `strip_buffs`, `steal_buff`, `cleanse`, `heal`,
`stack` (`stack`, `value`, `max`, `on: self`), `cd_reduce`.

Les auras appartiennent à leur lanceur : elles ne se volent pas, ne se purgent pas et disparaissent à sa mort.

## Passifs (`"passive": "kit"` + `params`)

`damage_reduction`, `reflect_pct`, `counter` (`chance`, `crit_chance`, `once_per_turn`, `hits` ou `skill`),
`stack_on_hit_taken`, `stat_per_stack`, `survive_lethal_once`, `attacker_ap_down`, `enemy_spd_aura`,
`cc_immune`, `debuff_immune`, `start_ap`, `ignore_def`, `dmg_per_spd`, `dmg_if_ally_low`,
`clones` (`max`, `aoe_bonus_pct`, `strike_pct`).

## Interprétations de la fiche (à valider)

- Ghost : la contre-attaque a 50 % de chance (100 % contre un critique), sinon « certaine contre un
  critique » ne voudrait rien dire.
- Selene S3 : « immobile » = elle passe ses 2 tours ; le renvoi (150 %) ignore la DEF.
- Yass S3 : la Malédiction restante explose, puis une nouvelle Malédiction est posée à coup sûr.
- Don Selah : son immunité innée résiste même aux effets qui « passent l'Immunité ».
- Les réductions de PA ennemies se résistent (chance + PRÉ − RÉS) ; les bonus de PA alliés sont certains.
