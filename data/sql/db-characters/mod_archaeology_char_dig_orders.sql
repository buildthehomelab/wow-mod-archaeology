-- Dig Orders: the dig site a character's daily orders name (the quest system keeps the progress).
CREATE TABLE IF NOT EXISTS `mod_archaeology_char_dig_orders` (
  `guid` INT UNSIGNED NOT NULL,
  `site` SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
