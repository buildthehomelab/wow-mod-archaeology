-- mod-archaeology: world database tables, the trainer and the dig gameobjects.
--
-- Ids: creature / npc_text / quest 9503500-9503599, gameobject_template 9503500-9503549,
-- items 9504000-9504499 (filled by mod_archaeology_world_data.sql), relic items 9505000-9505999
-- (mod_archaeology_world_relic.sql). Idempotent: safe to run again.
-- Undo with data/sql/uninstall/mod_archaeology_uninstall_world.sql.

CREATE TABLE IF NOT EXISTS `mod_archaeology_race` (
  `id` TINYINT UNSIGNED NOT NULL COMMENT 'Cataclysm ResearchBranch id',
  `name` VARCHAR(32) NOT NULL,
  `keystone_item` INT UNSIGNED NOT NULL DEFAULT 0,
  `unlock_skill` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `find_go` INT UNSIGNED NOT NULL COMMENT 'gameobject_template entry of this race''s find',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_archaeology_site` (
  `id` SMALLINT UNSIGNED NOT NULL COMMENT 'Cataclysm ResearchSite id',
  `map` SMALLINT UNSIGNED NOT NULL,
  `race` TINYINT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL,
  `min_skill` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `min_level` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `enabled` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'set 0 for a site that does not fit this map',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_archaeology_site_point` (
  `site` SMALLINT UNSIGNED NOT NULL,
  `idx` TINYINT UNSIGNED NOT NULL,
  `x` FLOAT NOT NULL,
  `y` FLOAT NOT NULL,
  PRIMARY KEY (`site`, `idx`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='dig site outline, world coordinates';

CREATE TABLE IF NOT EXISTS `mod_archaeology_site_spawn` (
  `site` SMALLINT UNSIGNED NOT NULL,
  `idx` SMALLINT UNSIGNED NOT NULL,
  `x` FLOAT NOT NULL,
  `y` FLOAT NOT NULL,
  `z` FLOAT NOT NULL,
  PRIMARY KEY (`site`, `idx`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='spots a find can be hidden';

CREATE TABLE IF NOT EXISTS `mod_archaeology_project` (
  `id` SMALLINT UNSIGNED NOT NULL COMMENT 'Cataclysm ResearchProject id',
  `race` TINYINT UNSIGNED NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `description` TEXT NOT NULL,
  `rare` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `item` INT UNSIGNED NOT NULL COMMENT 'item_template entry the solve creates',
  `cost` SMALLINT UNSIGNED NOT NULL COMMENT 'fragments',
  `sockets` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'keystones that can be used',
  `min_skill` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `chance` FLOAT NOT NULL DEFAULT 100 COMMENT 'rares: percent chance to come up when a project is picked',
  `cata_class` TINYINT UNSIGNED NOT NULL DEFAULT 15,
  `cata_subclass` TINYINT UNSIGNED NOT NULL DEFAULT 4,
  `enabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_archaeology_item_source` (
  `item` INT UNSIGNED NOT NULL,
  `cata_item` INT UNSIGNED NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  PRIMARY KEY (`item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='which Cataclysm item each artifact was built from';

-- The archaeology trainer, who also gives the relic quest. Not spawned: place one per city with .npc add 9503500.
DELETE FROM `creature_template_model` WHERE `CreatureID` BETWEEN 9503500 AND 9503599;
DELETE FROM `creature_template` WHERE `entry` BETWEEN 9503500 AND 9503599;
INSERT INTO `creature_template` (`entry`, `name`, `subname`, `gossip_menu_id`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `speed_walk`, `speed_run`, `BaseAttackTime`, `RangeAttackTime`, `unit_class`, `unit_flags`, `unit_flags2`, `type`, `flags_extra`, `ScriptName`) VALUES
(9503500, 'Harrison Jones', 'Archaeology Trainer', 0, 70, 70, 35, 3, 1, 1.14286, 2000, 2000, 1, 768, 2048, 7, 2, 'npc_archaeology_trainer'),
-- Kill credit for the capstone quests (never spawned; the module gives the credit).
(9503510, 'Kel''Thuzad slain with the Unearthed Relic', '', 0, 1, 1, 35, 0, 1, 1.14286, 2000, 2000, 1, 0, 0, 10, 128, ''),
(9503511, 'Kil''jaeden slain with the Unearthed Relic', '', 0, 1, 1, 35, 0, 1, 1.14286, 2000, 2000, 1, 0, 0, 10, 128, ''),
(9503512, 'The Lich King slain with the Unearthed Relic', '', 0, 1, 1, 35, 0, 1, 1.14286, 2000, 2000, 1, 0, 0, 10, 128, ''),
-- Kill credit for Dig Orders: one per find dug up at the ordered dig site.
(9503513, 'Find dug up at your ordered dig site', '', 0, 1, 1, 35, 0, 1, 1.14286, 2000, 2000, 1, 0, 0, 10, 128, '');
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`) VALUES
(9503500, 0, 22340, 1, 1);

DELETE FROM `npc_text` WHERE `ID` BETWEEN 9503500 AND 9503509;
INSERT INTO `npc_text` (`ID`, `text0_0`, `text0_1`, `BroadcastTextID0`, `lang0`, `Probability0`) VALUES
(9503500, 'History is buried under our feet, $c. Every dwarf ruin, every troll altar, every fossil bed holds a piece of a story nobody has told yet.$B$BLearn to survey, and I''ll show you where to dig.', 'History is buried under our feet, $c. Every dwarf ruin, every troll altar, every fossil bed holds a piece of a story nobody has told yet.$B$BLearn to survey, and I''ll show you where to dig.', 0, 0, 1),
(9503501, 'Every relic remembers the hand that dug it up. What shape should yours take?$B$BChoose well, but don''t fret: I can reshape it later, and its rank stays with it.', 'Every relic remembers the hand that dug it up. What shape should yours take?$B$BChoose well, but don''t fret: I can reshape it later, and its rank stays with it.', 0, 0, 1);

-- 9503500: the survey marker that points toward the find (an excavation banner until a client
-- patch ships the Cataclysm telescope). 9503510-9503517: one find per race, models the 3.3.5
-- client already has. Stops at 9503529: the rare rewards' gameobjects (9503530+) come from other files.
DELETE FROM `gameobject_template` WHERE `entry` BETWEEN 9503500 AND 9503529;
INSERT INTO `gameobject_template` (`entry`, `type`, `displayId`, `name`, `IconName`, `castBarCaption`, `unk1`, `size`, `ScriptName`, `VerifiedBuild`) VALUES
(9503500, 5, 10101, 'Survey Tool', '', '', '', 1, '', 0),
(9503501, 5, 10102, 'Survey Tool', '', '', '', 1, '', 0),
(9503502, 5, 10103, 'Survey Tool', '', '', '', 1, '', 0),
(9503503, 5, 5191, 'Survey Tool', '', '', '', 1, '', 0),
(9503510, 10, 53, 'Dwarf Archaeology Find', '', '', '', 0.5, 'go_archaeology_find', 0),
(9503511, 10, 256, 'Night Elf Archaeology Find', '', '', '', 0.5, 'go_archaeology_find', 0),
(9503512, 10, 5, 'Troll Archaeology Find', '', '', '', 0.35, 'go_archaeology_find', 0),
(9503513, 10, 379, 'Fossil Archaeology Find', '', '', '', 0.5, 'go_archaeology_find', 0),
(9503514, 10, 403, 'Draenei Archaeology Find', '', '', '', 0.5, 'go_archaeology_find', 0),
(9503515, 10, 6365, 'Orc Archaeology Find', '', '', '', 2, 'go_archaeology_find', 0),
(9503516, 10, 8541, 'Nerubian Archaeology Find', '', '', '', 1, 'go_archaeology_find', 0),
(9503517, 10, 8217, 'Vrykul Archaeology Find', '', '', '', 0.35, 'go_archaeology_find', 0),
-- The fragment cache the last find of a Dig Orders turns up (the excavation supply crate model).
(9503520, 10, 31, 'Fragment Cache', '', '', '', 1, 'go_archaeology_dig_orders_cache', 0);

-- Survey, the spell the client patch adds (90506): the module runs the survey when it is cast.
DELETE FROM `spell_script_names` WHERE `spell_id` = 90506 AND `ScriptName` = 'spell_archaeology_survey';
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES (90506, 'spell_archaeology_survey');

-- The rank spells the client patch adds (90500-90505, Apprentice to Grand Master), a chain like
-- Cooking's. The module teaches the rank that matches the skill, so Archaeology is in the spellbook.
DELETE FROM `spell_ranks` WHERE `first_spell_id` = 90500;
INSERT INTO `spell_ranks` (`first_spell_id`, `spell_id`, `rank`) VALUES
(90500, 90500, 1), (90500, 90501, 2), (90500, 90502, 3), (90500, 90503, 4), (90500, 90504, 5), (90500, 90505, 6);

-- A Weapon in Pieces: offered at 50 Archaeology (the module checks the skill), turned in at once.
-- 9503501-9503503: the capstone quests, one per era (Archaeology.Relic.CapstoneQuest.*). The last
-- rank of each era waits for one: slay the era's last boss with the relic equipped. Kel'Thuzad
-- counts in Naxxramas at 40 and at 80. Raid quests (QuestInfoID 62), so raid groups get the credit.
-- 9503504: Dig Orders, a daily for anyone who knows Archaeology (the module checks). The module
-- names one of the character's own dig sites; finds there give the credit, 3 by default
-- (RequiredNpcOrGoCount1), and a site dug out fills the orders. A raid quest too (QuestInfoID 62):
-- the core gives no kill credit for other quests in a raid group, and bot raids dig together.
DELETE FROM `creature_queststarter` WHERE `quest` BETWEEN 9503500 AND 9503519;
DELETE FROM `creature_questender` WHERE `quest` BETWEEN 9503500 AND 9503519;
DELETE FROM `quest_offer_reward` WHERE `ID` BETWEEN 9503500 AND 9503519;
DELETE FROM `quest_request_items` WHERE `ID` BETWEEN 9503500 AND 9503519;
DELETE FROM `quest_template_addon` WHERE `ID` BETWEEN 9503500 AND 9503519;
DELETE FROM `quest_template` WHERE `ID` BETWEEN 9503500 AND 9503519;
INSERT INTO `quest_template` (`ID`, `QuestType`, `QuestLevel`, `MinLevel`, `QuestSortID`, `QuestInfoID`, `Flags`, `LogTitle`, `LogDescription`, `QuestDescription`, `AreaDescription`, `QuestCompletionLog`, `RequiredNpcOrGo1`, `RequiredNpcOrGoCount1`, `ObjectiveText1`, `RewardXPDifficulty`, `VerifiedBuild`) VALUES
(9503500, 2, -1, 20, 0, 0, 0, 'A Weapon in Pieces', 'Bring the odd fragments from your digs to Harrison Jones.',
 'You keep turning up the same odd pieces at every dig, $n. A sliver of hilt here, a curl of old steel there, and none of it from any one people.$B$BSomebody, long ago, made a weapon out of all of history, and it broke. Bring me what you have found and we will put it back together. It won''t look like much at first. The more you dig, the more of it wakes up.',
 '', 'Return to Harrison Jones.', 0, 0, '', 0, 0),
(9503501, 2, 60, 60, 0, 62, 64, 'The Lich in the Necropolis', 'Slay Kel''Thuzad in Naxxramas with your Unearthed Relic equipped, then return to Harrison Jones.',
 'Your relic has soaked up every age of the old world, $n, every people you have dug up. But it has never seen an age end.$B$BKel''Thuzad holds Naxxramas over the Plaguelands. Carry the relic into his necropolis and be there when he falls. Whatever is still asleep in that steel will wake up to that.',
 '', 'Return to Harrison Jones.', 9503510, 1, 'Kel''Thuzad slain with your relic', 0, 0),
(9503502, 2, 70, 70, 0, 62, 64, 'The Deceiver''s Fall', 'Slay Kil''jaeden at the Sunwell Plateau with your Unearthed Relic equipped, then return to Harrison Jones.',
 'Draenei tomes and orc blood texts, and every one of them ends with the same name: Kil''jaeden. Your relic has read them all, $n.$B$BThe Deceiver is trying to come through at the Sunwell. Take the relic there and see him thrown back. Legends are made of less.',
 '', 'Return to Harrison Jones.', 9503511, 1, 'Kil''jaeden slain with your relic', 0, 0),
(9503503, 2, 80, 80, 0, 62, 64, 'The Frozen Throne', 'Slay the Lich King in Icecrown Citadel with your Unearthed Relic equipped, then return to Harrison Jones.',
 'Nerubian obelisks, vrykul rune sticks. Northrend''s past is all buried under one man''s ice, $n.$B$BThe relic is nearly whole. Take it up the Frozen Throne and be there when the Lich King falls. After that, there is nothing left in it to wake but the relic itself.',
 '', 'Return to Harrison Jones.', 9503512, 1, 'The Lich King slain with your relic', 0, 0),
(9503504, 2, -1, 1, 0, 62, 4096, 'Dig Orders', 'Dig up the finds at the dig site named in your orders, then return to an archaeology trainer.',
 'There''s more ground than diggers, $n, and every season the farmers plough a little more of it under.$B$BHere are today''s orders. One of your own dig sites, written at the top. Work it properly: survey, dig, catalogue. Whoever was there before you tends to leave a cache of loose fragments lying about, and you may keep whatever you find in it.',
 '', 'Return to an archaeology trainer.', 9503513, 3, 'Finds dug up at your ordered dig site', 5, 0);
INSERT INTO `quest_template_addon` (`ID`, `PrevQuestID`, `SpecialFlags`) VALUES
(9503501, 9503500, 0),
(9503502, 9503500, 0),
(9503503, 9503500, 0),
(9503504, 0, 1);
INSERT INTO `quest_request_items` (`ID`, `CompletionText`, `VerifiedBuild`) VALUES
(9503501, 'Has your relic seen Kel''Thuzad fall yet?', 0),
(9503502, 'Has your relic seen the Deceiver fall yet?', 0),
(9503503, 'Has your relic seen the Lich King fall yet?', 0),
(9503504, 'Have you worked through today''s orders?', 0);
INSERT INTO `quest_offer_reward` (`ID`, `RewardText`, `VerifiedBuild`) VALUES
(9503500, 'Ah, you kept them. Good. Hold still while I fit these together...', 0),
(9503501, 'Feel that? It''s colder than it was, and heavier. Something in it remembers Naxxramas now. Dig on, and it will grow into it.', 0),
(9503502, 'There''s fel in the grain now, and light too, both at once. I''ve never seen a weapon hold both. Keep digging.', 0),
(9503503, 'It''s humming. It never did that before. It has seen the end of every age now; all it lacks is the rest of its history.', 0),
(9503504, 'Good, careful work. I''ll file your notes with the rest. Come back tomorrow; there''s always another site.', 0);
INSERT INTO `creature_queststarter` (`id`, `quest`) VALUES (9503500, 9503500), (9503500, 9503501), (9503500, 9503502), (9503500, 9503503), (9503500, 9503504);
INSERT INTO `creature_questender` (`id`, `quest`) VALUES (9503500, 9503500), (9503500, 9503501), (9503500, 9503502), (9503500, 9503503), (9503500, 9503504);
