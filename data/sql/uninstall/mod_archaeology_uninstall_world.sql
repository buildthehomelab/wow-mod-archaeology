-- Removes everything mod-archaeology adds to the world database.
DROP TABLE IF EXISTS `mod_archaeology_race`, `mod_archaeology_site`, `mod_archaeology_site_point`,
  `mod_archaeology_site_spawn`, `mod_archaeology_project`, `mod_archaeology_item_source`,
  `mod_archaeology_relic_step`, `mod_archaeology_relic_form`, `mod_archaeology_relic_item`, `mod_archaeology_relic_trait`;
DELETE FROM `creature` WHERE `id` BETWEEN 9503500 AND 9503599;
DELETE FROM `creature_template_model` WHERE `CreatureID` BETWEEN 9503500 AND 9503599;
DELETE FROM `creature_template` WHERE `entry` BETWEEN 9503500 AND 9503599;
DELETE FROM `npc_text` WHERE `ID` BETWEEN 9503500 AND 9503509;
DELETE FROM `gameobject_template` WHERE `entry` BETWEEN 9503500 AND 9503549;
DELETE FROM `item_template` WHERE `entry` BETWEEN 9504000 AND 9504499 OR `entry` BETWEEN 9505000 AND 9505999;
DELETE FROM `creature_queststarter` WHERE `quest` BETWEEN 9503500 AND 9503519;
DELETE FROM `creature_questender` WHERE `quest` BETWEEN 9503500 AND 9503519;
DELETE FROM `quest_offer_reward` WHERE `ID` BETWEEN 9503500 AND 9503519;
DELETE FROM `quest_request_items` WHERE `ID` BETWEEN 9503500 AND 9503519;
DELETE FROM `quest_template_addon` WHERE `ID` BETWEEN 9503500 AND 9503519;
DELETE FROM `quest_template` WHERE `ID` BETWEEN 9503500 AND 9503519;
DELETE FROM `spell_script_names` WHERE `ScriptName` = 'spell_archaeology_survey' OR `ScriptName` LIKE 'spell_archaeology_trait_%';
DELETE FROM `spell_proc` WHERE `SpellId` BETWEEN 90500 AND 90529;
DELETE FROM `spell_bonus_data` WHERE `entry` BETWEEN 90500 AND 90529;
DELETE FROM `spell_ranks` WHERE `first_spell_id` = 90500;
-- The client patch's rows (mod_archaeology_world_dbc.sql).
DELETE FROM `skillline_dbc` WHERE `ID` = 794;
DELETE FROM `skillraceclassinfo_dbc` WHERE `ID` = 90500;
DELETE FROM `skilllineability_dbc` WHERE `ID` BETWEEN 90500 AND 90529;
DELETE FROM `spell_dbc` WHERE `ID` BETWEEN 90500 AND 90529;
DELETE FROM `item_dbc` WHERE `ID` BETWEEN 9504000 AND 9505999;
DELETE FROM `itemdisplayinfo_dbc` WHERE `ID` BETWEEN 950400 AND 950899;
DELETE FROM `gameobjectdisplayinfo_dbc` WHERE `ID` BETWEEN 10101 AND 10103;
DELETE FROM `achievement_criteria_dbc` WHERE `ID` BETWEEN 19240 AND 19279;
DELETE FROM `achievement_dbc` WHERE `ID` BETWEEN 9240 AND 9259;

-- Functional rare reward rows. Journal's table may be shared with other modules.
DELETE FROM `creature_template_model` WHERE `CreatureID` BETWEEN 9503600 AND 9503613;
DELETE FROM `creature_template` WHERE `entry` BETWEEN 9503600 AND 9503613;
DELETE FROM `spell_script_names` WHERE `ScriptName` IN ('spell_archaeology_reward','spell_archaeology_innkeepers_daughter');
DELETE FROM `skilllineability_dbc` WHERE `ID` BETWEEN 90530 AND 90589;
DELETE FROM `spell_dbc` WHERE `ID` BETWEEN 90530 AND 90589;
DELETE FROM `mod_forever_journal_toy` WHERE `ItemID` IN (9504063,9504064,9504071,9504079,9504101,9504102,9504119,9504120,9504126,9504129,9504133,9504141,9504142,9504143);
DELETE FROM `mod_forever_journal_collection_note` WHERE `Sort`=90 AND `Note` LIKE 'Archaeology: solve %';

DROP TABLE IF EXISTS `mod_archaeology_site_access`;
