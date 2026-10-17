-- mod-archaeology: world database tables, the trainer and the dig gameobjects.
--
-- Ids: creature / npc_text 9503500-9503599, gameobject_template 9503500-9503549,
-- items 9504000-9504499 (filled by mod_archaeology_world_data.sql). Idempotent: safe to run again.
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

-- The archaeology trainer. Not spawned: place one per city with .npc add 9503500.
DELETE FROM `creature_template_model` WHERE `CreatureID` BETWEEN 9503500 AND 9503599;
DELETE FROM `creature_template` WHERE `entry` BETWEEN 9503500 AND 9503599;
INSERT INTO `creature_template` (`entry`, `name`, `subname`, `gossip_menu_id`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `speed_walk`, `speed_run`, `BaseAttackTime`, `RangeAttackTime`, `unit_class`, `unit_flags`, `unit_flags2`, `type`, `flags_extra`, `ScriptName`) VALUES
(9503500, 'Harrison Jones', 'Archaeology Trainer', 0, 70, 70, 35, 1, 1, 1.14286, 2000, 2000, 1, 768, 2048, 7, 2, 'npc_archaeology_trainer');
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`) VALUES
(9503500, 0, 22340, 1, 1);

DELETE FROM `npc_text` WHERE `ID` BETWEEN 9503500 AND 9503509;
INSERT INTO `npc_text` (`ID`, `text0_0`, `text0_1`, `BroadcastTextID0`, `lang0`, `Probability0`) VALUES
(9503500, 'History is buried under our feet, $c. Every dwarf ruin, every troll altar, every fossil bed holds a piece of a story nobody has told yet.$B$BLearn to survey, and I''ll show you where to dig.', 'History is buried under our feet, $c. Every dwarf ruin, every troll altar, every fossil bed holds a piece of a story nobody has told yet.$B$BLearn to survey, and I''ll show you where to dig.', 0, 0, 1);

-- 9503500: the survey marker that points toward the find (an excavation banner until a client
-- patch ships the Cataclysm telescope). 9503510-9503517: one find per race, models the 3.3.5
-- client already has.
DELETE FROM `gameobject_template` WHERE `entry` BETWEEN 9503500 AND 9503549;
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
(9503517, 10, 8217, 'Vrykul Archaeology Find', '', '', '', 0.35, 'go_archaeology_find', 0);

-- Survey, the spell the client patch adds (90506): the module runs the survey when it is cast.
DELETE FROM `spell_script_names` WHERE `spell_id` = 90506 AND `ScriptName` = 'spell_archaeology_survey';
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES (90506, 'spell_archaeology_survey');
