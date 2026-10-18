-- Removes mod-archaeology's character data. Items it created stay in bags until deleted.
DROP TABLE IF EXISTS `mod_archaeology_char`, `mod_archaeology_char_site`, `mod_archaeology_char_race`, `mod_archaeology_char_history`,
  `mod_archaeology_char_relic`;
-- The relic's quests, achievements and trait auras.
DELETE FROM `character_queststatus` WHERE `quest` BETWEEN 9503500 AND 9503519;
DELETE FROM `character_queststatus_rewarded` WHERE `quest` BETWEEN 9503500 AND 9503519;
DELETE FROM `character_achievement` WHERE `achievement` BETWEEN 9240 AND 9259;
DELETE FROM `character_achievement_progress` WHERE `criteria` BETWEEN 19240 AND 19279;
DELETE FROM `character_aura` WHERE `spell` BETWEEN 90500 AND 90529;
