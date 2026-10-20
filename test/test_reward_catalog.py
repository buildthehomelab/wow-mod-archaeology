#!/usr/bin/env python3
"""Regression checks for catalog coverage and DBC safety. Optional real patch input:
ARCH_REWARD_DBC_DIR=/path/to/unpacked/with/files.json python3 -m unittest ...
"""
import csv
import io
import json
import os
import re
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_rewards
import reward_patch
import build_patch as bp


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.data = reward_patch.catalog()

    def test_every_rare_has_exactly_one_function(self):
        text = (ROOT / 'data/sql/db-world/mod_archaeology_world_data.sql').read_text()
        start = text.index('INSERT INTO `mod_archaeology_project`')
        block = text[start:text.index(';\n', start)]
        rows = [next(csv.reader(io.StringIO(line.rstrip(',;')[1:-1]), delimiter=',', quotechar="'", skipinitialspace=True))
                for line in block.splitlines()[1:] if line.startswith('(')]
        rare_items = {int(row[5]) for row in rows if row[4] == '1'}
        registered = [c['item'] for group in ['gear', 'toys', 'collectibles'] for c in self.data[group]]
        self.assertEqual(len(registered), len(set(registered)))
        self.assertEqual(set(registered), rare_items)
        self.assertEqual(len(rare_items), 26)

    def test_generated_upgrade_and_base_are_current(self):
        sql = build_rewards.generate(self.data)
        self.assertEqual(sql, build_rewards.OUT.read_text())
        self.assertTrue((ROOT / 'data/sql/db-world/mod_archaeology_world_data.sql').read_text().endswith(sql))
        self.assertNotIn('DELETE FROM `mod_forever_journal_toy`;', sql)

    def test_cpp_dispatch_matches_catalog(self):
        source = (ROOT / 'src/ArchaeologyRewards.cpp').read_text()
        dispatch = {int(a):int(b) for a,b in re.findall(r'case (\d+): return (\d+);', source)}
        self.assertEqual(dispatch, {t['spell']:t['item'] for t in self.data['toys'] if not t.get('external')})
        rules = (ROOT / 'src/ArchaeologyRewardRules.h').read_text()
        companions = {(int(a),int(b)) for a,b in re.findall(r'\{(\d+), (\d+)\}', rules)}
        self.assertEqual(companions, {(c['item'],c['spell']) for c in self.data['collectibles']})

    def test_equipment_is_usable_at_realm_levels(self):
        for g in self.data['gear']:
            self.assertLessEqual(g['level'], 80)
            self.assertLessEqual(g['ilvl'], 200)
            self.assertIn(g['cls'], [2, 4])
            self.assertGreater(g['slot'], 0)
            self.assertGreater(sum(v for _, v in g['stats']), 0)
            if g['cls'] == 2:
                self.assertGreater(g['delay'], 0)
                self.assertGreater(g['damage'][0], 0)
            if g['sub'] == 6:
                self.assertGreater(g['armor'], 0)
                self.assertGreater(g['block'], 0)

    def test_cosmetic_morphs_use_creature_entries_not_display_ids(self):
        for t in self.data['toys']:
            if t.get('aura') == 56:
                self.assertIn(t['misc'], [9503611, 9503612, 9503613])
        self.assertEqual({c['spell'] for c in self.data['collectibles'] if c.get('external')}, {400386, 410266})


@unittest.skipUnless(os.getenv('ARCH_REWARD_DBC_DIR'), 'requires actual realm DBC input')
class RealDbcTests(unittest.TestCase):
    def test_preservation_and_idempotence(self):
        files = json.loads((Path(os.environ['ARCH_REWARD_DBC_DIR']) / 'files.json').read_text())
        tables = {name: bp.Dbc(files['DBFilesClient\\'+name+'.dbc'], name) for name in reward_patch.TABLES}
        old = {name: {key:list(row) for key,row in t.rows.items()} for name,t in tables.items()}
        reward_patch.add_rewards(tables)
        allowed = {name:{r[0] for r in t.ours} for name,t in tables.items()}
        for name, before in old.items():
            for key, row in before.items():
                if key not in allowed[name]:
                    self.assertEqual(row, tables[name].rows[key], (name,key))
        for spell in range(90530,90543):
            r = tables['Spell'].rows[spell]
            self.assertIn(r[bp.F_EFFECT], [3,6])
            if r[bp.F_EFFECT] == 6:
                self.assertIn(r[bp.F_AURA], [12,56,61])
            self.assertEqual(r[72:74], [0,0]) # no inherited secondary combat effects
        self.assertEqual(tables['Spell'].rows[90536][bp.F_DURATION], tables['Spell'].rows[31884][bp.F_DURATION])
        with tempfile.TemporaryDirectory() as tmp:
            first = {}
            for name,t in tables.items():
                path = str(Path(tmp)/name)
                t.write(path)
                first[name] = Path(path).read_bytes()
            reward_patch.add_rewards(tables)
            for name,t in tables.items():
                path = str(Path(tmp)/name)
                t.write(path)
                self.assertEqual(first[name], Path(path).read_bytes(), name)


if __name__ == '__main__':
    unittest.main()
