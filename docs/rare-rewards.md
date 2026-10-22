# Functional rare Archaeology rewards

All 26 rare projects award functional items. These are 3.3.5 adaptations; the original Cataclysm level-85 equipment budgets and toy combat effects are not copied. Not yet tried in a game client: the rewards (pets and mounts, each toy, cooldowns, interrupted casts, movement and progression restrictions, gear equip, stats and models, Journal ownership and sources).

## Collectibles

| Reward | Item | Summon | Implementation |
| --- | --- | --- | --- |
| Fossilized Hatchling | 9504036 | 410266 | Existing Retail Collection ownership |
| Fossilized Raptor | 9504083 | 400386 | Existing Retail Collection ownership |
| Clockwork Gnome | 9504070 | 90560 | New stock-model companion |
| Pterrordax Hatchling | 9504144 | 90561 | New stock-model companion |
| Voodoo Figurine | 9504145 | 90562 | New stock-model companion |

The Gnome uses the stock clockwork-gnome model; Pterrordax Hatchling is a small stock pterrordax, and Voodoo Figurine uses the stock animated tiki mask. No additional model conversion is required. Existing zero-charge placeholder items are repaired on use, before normal companion learning. Raptor learning requires Apprentice Riding.

## Toys

| Reward | Item | Behavior | Cooldown |
| --- | --- | --- | --- |
| Highborne Soul Mirror | 9504063 | Creates a harmless reflection of yourself for 1 minute. | 600 sec |
| Druid and Priest Statue Set | 9504064 | Summons two ancient statues and a shower of green light for 10 seconds. | 900 sec |
| Chalice of the Mountain Kings | 9504071 | Summons four dwarven dancers for 30 seconds. | 600 sec |
| Kaldorei Wind Chimes | 9504079 | Plays a gentle wind chime and surrounds you with nature magic for 10 seconds. | 60 sec |
| Arrival of the Naaru | 9504101 | Summons a harmless image of a naaru for 30 seconds. | 180 sec |
| The Last Relic of Argus | 9504102 | Teleports you to a random refuge in an era you have unlocked. Cannot be used while in combat, flying, travelling or inside an instance. | 1200 sec |
| Blessing of the Old God | 9504119 | Take the appearance of a faceless one for 20 seconds. | 600 sec |
| Puzzle Box of Yogg-Saron | 9504120 | Attempts to open the puzzle box. Something whispers back. | 60 sec |
| The Innkeeper's Daughter | 9504126 | Returns you to your home. Shares the ordinary Hearthstone cooldown. Sometimes a spectral innkeeper appears. | Hearthstone shared (5 min on the target realm) |
| Bones of Transformation | 9504129 | Take the appearance of a naga for 20 seconds. | 600 sec |
| Wisp Amulet | 9504133 | Take the appearance of a wisp for 10 minutes. Does not grant flight or invisibility. | 900 sec |
| Haunted War Drum | 9504141 | Places a haunted drum and plays a spectral drumbeat for 30 seconds. | 60 sec |
| Ancient Amber | 9504142 | Encases you in cosmetic amber for 10 seconds. Prevents movement but grants no immunity. | 300 sec |
| Vrykul Drinking Horn | 9504143 | Drink deeply, becoming larger and drunk for a time. Size lasts 10 minutes. | 600 sec |

Cosmetic toys cannot be used in combat or battlegrounds/arenas. Morphs grant no stat bonuses, flight, invisibility or immunity. The amber effect prevents movement and grants no protection. Statues, reflections, dancers and the naaru have no combat or loot role and expire. Whispers are original flavor text. Wind chimes and the drum reuse verified non-looping stock sounds.

Argus destinations are Ratchet, Booty Bay, Gadgetzan, Moonglade, Shattrath and Dalaran, filtered by character level and the same configured era gates as Archaeology dig sites. Travel is rejected during combat, flights, transport/vehicle use and in instances. The destination is selected only at cast completion. Landing positions must still be checked in-game.

## Equipment

Usable gear, capped at early Wrath item level 200. Earlier rewards have Classic/TBC level requirements. Items retain their archaeology IDs, soulbinding and icons; the client patch supplies real equipment types and stock meshes. Gear has no durability, so previously awarded placeholders do not become broken when converted.

| Reward | Item | Level / item level | Type |
| --- | --- | --- | --- |
| Zin'rokh, Destroyer of Worlds | 9504074 | 80 / 200 | class 2, subclass 8, slot 17 |
| Queen Azshara's Dressing Gown | 9504080 | 60 / 63 | class 4, subclass 1, slot 20 |
| Headdress of the First Shaman | 9504093 | 70 / 115 | class 4, subclass 3, slot 1 |
| Nifflevar Bearded Axe | 9504105 | 80 / 187 | class 2, subclass 0, slot 13 |
| Staff of Sorcerer-Thane Thaurissan | 9504127 | 80 / 200 | class 2, subclass 10, slot 17 |
| Tyrande's Favorite Doll | 9504128 | 80 / 200 | class 4, subclass 0, slot 12 |
| Extinct Turtle Shell | 9504140 | 80 / 200 | class 4, subclass 6, slot 14 |

Tyrande's Favorite Doll grants Intellect/spell power and restores 1800 mana on use every 2 minutes while equipped. This is a level-80 adaptation rather than Cataclysm's original mana-storage/damage mechanic. Models are stock equivalents, with the original Zin'rokh sword appearance used for the sword. Budget and appearance are implemented facts; balance and fitting are untested in-game.

## Generation

1. Edit `data/rare-rewards.json`, run `python3 tools/build_rewards.py`; `tools/build_data.py` includes these overrides in regenerated world data.
2. Rebuild the authoritative spell/item patch with `tools/build_patch.py`, or apply `tools/reward_patch.py --patch CURRENT.MPQ --out CANDIDATE.MPQ --sql data/sql/db-world/mod_archaeology_world_z_rewards_dbc.sql`. The smaller builder preserves all unrelated patch files and DBC rows and requires no Cataclysm source CSVs. Never overwrite the input.
3. Deploy the rebuilt module, the generated world SQL and the matching spell/item patch together, and refresh item caches.
4. Journal must include its companion seed-preservation change so its initial/reapplied built-in toy seed does not delete these custom rows. Archaeology registers toys and source notes; Journal discovers the pets/mounts from the learning items and source notes.

## Checks

`test/run-rewards.sh` exercises the real companion repair hook with legacy/fresh/misbound items. `python3 -m unittest discover -s test -p test_reward_catalog.py` checks all 26 rares, catalog/dispatch consistency and generated SQL. Set `ARCH_REWARD_DBC_DIR` to an unpacked realm patch directory containing `files.json` to additionally verify unrelated-row preservation, one-effect cosmetic spell safety and byte-for-byte repeat-build stability. CI checks actual core syntax and SQL apply/reapply/uninstall.
