-- mod-archaeology: character database. Every table is keyed by character guid: archaeology is
-- learned and levelled on each character, nothing is shared across an account.

CREATE TABLE IF NOT EXISTS `mod_archaeology_char` (
  `guid` INT UNSIGNED NOT NULL,
  `skill` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `max_skill` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_archaeology_char_site` (
  `guid` INT UNSIGNED NOT NULL,
  `continent` TINYINT UNSIGNED NOT NULL COMMENT '0 Eastern Kingdoms, 1 Kalimdor, 2 Outland, 3 Northrend',
  `slot` TINYINT UNSIGNED NOT NULL,
  `site` SMALLINT UNSIGNED NOT NULL,
  `finds` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `continent`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_archaeology_char_race` (
  `guid` INT UNSIGNED NOT NULL,
  `race` TINYINT UNSIGNED NOT NULL,
  `fragments` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `project` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `race`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_archaeology_char_history` (
  `guid` INT UNSIGNED NOT NULL,
  `project` SMALLINT UNSIGNED NOT NULL,
  `solved` INT UNSIGNED NOT NULL DEFAULT 0,
  `first_solved` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'unix time',
  PRIMARY KEY (`guid`, `project`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
