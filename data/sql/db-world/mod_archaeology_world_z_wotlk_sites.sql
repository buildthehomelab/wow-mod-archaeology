-- Apply after mod_archaeology_world_data.sql, including on existing installations.
-- Keep imported points for later WotLK remapping; do not delete player progress.
UPDATE `mod_archaeology_site` SET `enabled` = 0
WHERE `id` IN (12, 13, 15, 20, 21, 144, 146, 150, 152, 154, 167, 177, 179, 181, 183, 185, 187, 189, 191, 197, 203, 221, 237, 289, 309, 319, 325);
