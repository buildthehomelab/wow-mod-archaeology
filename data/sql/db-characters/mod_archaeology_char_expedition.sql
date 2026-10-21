-- Persistent abandonment cooldown: relogging must not bypass it.
CREATE TABLE IF NOT EXISTS `mod_archaeology_char_expedition` (
  `guid` INT UNSIGNED NOT NULL,
  `until_time` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
