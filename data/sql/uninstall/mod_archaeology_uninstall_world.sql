-- Removes everything mod-archaeology adds to the world database.
DROP TABLE IF EXISTS `mod_archaeology_race`, `mod_archaeology_site`, `mod_archaeology_site_point`,
  `mod_archaeology_site_spawn`, `mod_archaeology_project`, `mod_archaeology_item_source`;
DELETE FROM `creature` WHERE `id` BETWEEN 9503400 AND 9503499;
DELETE FROM `creature_template_model` WHERE `CreatureID` BETWEEN 9503400 AND 9503499;
DELETE FROM `creature_template` WHERE `entry` BETWEEN 9503400 AND 9503499;
DELETE FROM `npc_text` WHERE `ID` BETWEEN 9503400 AND 9503409;
DELETE FROM `gameobject_template` WHERE `entry` BETWEEN 9503400 AND 9503449;
DELETE FROM `item_template` WHERE `entry` BETWEEN 9504000 AND 9504499;
