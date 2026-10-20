-- Functional archaeology rewards. Apply after generated world_data.
-- Requires mod-retail-collection and its existing client patch for pet 410266.
-- Keep the archaeology item ID/display/class so previously solved items and
-- the archaeology client patch remain valid. Use the stock companion-learning
-- path: slot 1 casts Learn Companion, slot 2 identifies the learned summon.
-- A negative single charge consumes the item only on successful learning.
UPDATE `item_template`
SET `spellid_1` = 55884, `spelltrigger_1` = 0, `spellcharges_1` = -1,
    `spellid_2` = 410266, `spelltrigger_2` = 6, `spellcharges_2` = 0
WHERE `entry` = 9504036;
