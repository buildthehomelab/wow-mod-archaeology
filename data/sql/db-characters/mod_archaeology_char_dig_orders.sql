-- Dig Orders: the dig site a character's daily orders name (the quest system keeps the progress).
-- Days are daily reset times: orders taken again the same day keep the site, one cache a day.
CREATE TABLE IF NOT EXISTS `mod_archaeology_char_dig_orders` (
  `guid` INT UNSIGNED NOT NULL,
  `site` SMALLINT UNSIGNED NOT NULL,
  `day` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'daily reset time the site was named for',
  `cache_day` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'daily reset time of the last fragment cache',
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
