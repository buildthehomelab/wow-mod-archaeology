-- mod-archaeology: the Unearthed Relic's traits, one per race.
--
-- A trait wakes when one of its race's rares is solved, or after Archaeology.Relic.Traits.WakeCommons
-- common solves of that race. While the relic is equipped each awake trait is an aura (aura_spell);
-- what it does is set here, at full rank. It starts at Archaeology.Relic.Traits.FirstRankStrength
-- of that and doubles (RaceCompleteMultiplier) once every project of the race is solved.
-- Spells 90507-90521 come from the client patch rows in mod_archaeology_world_dbc.sql.
-- Idempotent: safe to run again.

CREATE TABLE IF NOT EXISTS `mod_archaeology_relic_trait` (
  `race` TINYINT UNSIGNED NOT NULL COMMENT 'mod_archaeology_race id',
  `kind` TINYINT UNSIGNED NOT NULL COMMENT '1 Ember, 2 Focus, 3 Vigor, 4 Amber, 5 Naaru, 6 Horde, 7 Venom, 8 Mercy',
  `name` VARCHAR(64) NOT NULL,
  `aura_spell` INT UNSIGNED NOT NULL COMMENT 'the trait, on the character while the relic is equipped',
  `effect_spell` INT UNSIGNED NOT NULL COMMENT 'what it casts (Mercy: its cooldown debuff)',
  `ppm` FLOAT NOT NULL DEFAULT 0 COMMENT 'procs per minute; Amber Ward: % chance per hit taken',
  `cooldown_ms` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'between procs; Mercy: between saves',
  `value` FLOAT NOT NULL DEFAULT 0 COMMENT 'the main number, at full rank (see the rows)',
  `value2` FLOAT NOT NULL DEFAULT 0 COMMENT 'a second number, where the trait has one',
  PRIMARY KEY (`race`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- value / value2 by kind:
--   Ember  value % of attack or spell power (the higher) as Fire damage
--   Focus  value % of max mana; value2 rage or runic power (energy: twice value2)
--   Vigor  value % melee, ranged and casting haste for 10 sec
--   Amber  value % of max health absorbed, for 10 sec
--   Naaru  value % of the target's max health healed: you or the most hurt group member within value2 yards
--   Horde  up to value % more damage, the whole of it at value2 % health or less
--   Venom  value % of attack or spell power per stack, over 12 sec (stacks to 5)
--   Mercy  a killing blow leaves you at value % health instead; the race-complete bonus divides the cooldown
DELETE FROM `mod_archaeology_relic_trait`;
INSERT INTO `mod_archaeology_relic_trait` (`race`, `kind`, `name`, `aura_spell`, `effect_spell`, `ppm`, `cooldown_ms`, `value`, `value2`) VALUES
(1, 1, 'Thaurissan''s Ember', 90507, 90515, 3, 0, 40, 0),
(4, 2, 'Highborne Focus', 90508, 90516, 2, 0, 4, 10),
(8, 3, 'Zandalari Vigor', 90509, 90517, 1.5, 0, 8, 0),
(3, 4, 'Amber Ward', 90510, 90518, 10, 15000, 5, 0),
(2, 5, 'Light of the Naaru', 90511, 90519, 2, 0, 4, 30),
(6, 6, 'Blood of the Horde', 90512, 90512, 0, 0, 8, 20),
(5, 7, 'Ahn''kahar Venom', 90513, 90520, 3, 0, 10, 0),
(27, 8, 'Val''kyr''s Mercy', 90514, 90521, 0, 600000, 20, 0);

DELETE FROM `spell_script_names` WHERE `spell_id` BETWEEN 90507 AND 90514 AND `ScriptName` LIKE 'spell_archaeology_trait_%';
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES
(90507, 'spell_archaeology_trait_proc'),
(90508, 'spell_archaeology_trait_proc'),
(90509, 'spell_archaeology_trait_proc'),
(90510, 'spell_archaeology_trait_proc'),
(90511, 'spell_archaeology_trait_proc'),
(90512, 'spell_archaeology_trait_horde'),
(90513, 'spell_archaeology_trait_proc'),
(90514, 'spell_archaeology_trait_mercy');

-- What the proc traits react to; the script rolls the chance itself (Chance 100 here), from the
-- weapon speed or cast time, and keeps cooldown_ms. Damage traits only from hits on enemies,
-- the others from heals too. Amber Ward from hits taken. ProcFlags: done melee, ranged and harmful
-- spells 69972; the same and helpful spells 87380; taken melee, ranged and harmful spells 139944.
DELETE FROM `spell_proc` WHERE `SpellId` BETWEEN 90507 AND 90514;
INSERT INTO `spell_proc` (`SpellId`, `SchoolMask`, `SpellFamilyName`, `SpellFamilyMask0`, `SpellFamilyMask1`, `SpellFamilyMask2`, `ProcFlags`, `SpellTypeMask`, `SpellPhaseMask`, `HitMask`, `AttributesMask`, `DisableEffectsMask`, `ProcsPerMinute`, `Chance`, `Cooldown`, `Charges`) VALUES
(90507, 0, 0, 0, 0, 0, 69972, 1, 2, 0, 0, 0, 0, 100, 0, 0),
(90508, 0, 0, 0, 0, 0, 87380, 3, 2, 0, 0, 0, 0, 100, 0, 0),
(90509, 0, 0, 0, 0, 0, 87380, 3, 2, 0, 0, 0, 0, 100, 0, 0),
(90510, 0, 0, 0, 0, 0, 139944, 1, 2, 0, 0, 0, 0, 100, 0, 0),
(90511, 0, 0, 0, 0, 0, 87380, 3, 2, 0, 0, 0, 0, 100, 0, 0),
(90513, 0, 0, 0, 0, 0, 69972, 1, 2, 0, 0, 0, 0, 100, 0, 0);

-- The amounts are worked out by the module; no spell or attack power on top.
DELETE FROM `spell_bonus_data` WHERE `entry` BETWEEN 90515 AND 90520;
INSERT INTO `spell_bonus_data` (`entry`, `direct_bonus`, `dot_bonus`, `ap_bonus`, `ap_dot_bonus`, `comments`) VALUES
(90515, 0, 0, 0, 0, 'Archaeology - Thaurissan''s Ember'),
(90518, 0, 0, 0, 0, 'Archaeology - Amber Ward'),
(90519, 0, 0, 0, 0, 'Archaeology - Light of the Naaru'),
(90520, 0, 0, 0, 0, 'Archaeology - Ahn''kahar Venom');
