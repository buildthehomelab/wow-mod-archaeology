#!/usr/bin/env python3
"""Check generated site policy, upgrade SQL and race/continent availability without MySQL."""
import csv
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL = ROOT / 'data/sql/db-world'
policy = {int(k) for k in json.loads((ROOT / 'tools/wotlk-disabled-sites.json').read_text())}
text = (SQL / 'mod_archaeology_world_data.sql').read_text()
site_insert = 'INSERT INTO `mod_archaeology_site`' + text.split('INSERT INTO `mod_archaeology_site`', 1)[1].split(';', 1)[0] + ';'
db = sqlite3.connect(':memory:')
db.execute('CREATE TABLE mod_archaeology_site (id INTEGER PRIMARY KEY, map INTEGER, race INTEGER, name TEXT, min_skill INTEGER, min_level INTEGER, enabled INTEGER DEFAULT 1)')
db.executescript(site_insert)
rows = db.execute('SELECT * FROM mod_archaeology_site').fetchall()
assert len(rows) == 156, len(rows)
assert {r[0] for r in rows if not r[6]} == policy
assert len(policy) == 27
assert {r[1] for r in rows if r[6]} == {0, 1, 530, 571}
# Bael Modan is the only imported Kalimdor dwarf site; its hold removes that pool.
assert {(r[1], r[2]) for r in rows} - {(r[1], r[2]) for r in rows if r[6]} == {(1, 1)}
# Both old continents retain a starting pool without flying.
for map_id in (0, 1):
    assert any(r[1] == map_id and r[4] == 0 and r[5] <= 20 and r[6] for r in rows)
# Every archaeology race still has an enabled site somewhere.
assert {r[2] for r in rows} == {r[2] for r in rows if r[6]}
with (ROOT / 'docs/wotlk-digsite-audit.csv').open() as f:
    audit = {int(r['id']): r for r in csv.DictReader(f)}
assert set(audit) == {r[0] for r in rows}
assert all(int(audit[r[0]]['enabled']) == r[6] and audit[r[0]]['name'] == r[3] for r in rows)
# Simulate upgrading the original all-enabled data, preserving a local hold.
db.execute('UPDATE mod_archaeology_site SET enabled = 1')
local_hold = min(r[0] for r in rows if r[0] not in policy)
db.execute('UPDATE mod_archaeology_site SET enabled = 0 WHERE id = ?', (local_hold,))
upgrade = (SQL / 'mod_archaeology_world_z_wotlk_sites.sql').read_text()
db.executescript(upgrade)
first = db.execute('SELECT * FROM mod_archaeology_site ORDER BY id').fetchall()
db.executescript(upgrade)
assert first == db.execute('SELECT * FROM mod_archaeology_site ORDER BY id').fetchall()
assert {r[0] for r in first if not r[6]} == policy | {local_hold}
print(f'PASS: {len(rows)} sites; {len(policy)} held; {len(rows)-len(policy)} provisional; upgrade idempotent; local holds and race availability preserved')
