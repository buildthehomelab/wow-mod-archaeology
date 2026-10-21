"""Validate generated WotLK access upgrades, exact evidence points and persistent cooldown schema."""
import importlib.util
import json
from pathlib import Path
import re
import sqlite3
import unittest
ROOT=Path(__file__).resolve().parent.parent
SQL=ROOT/'data/sql/db-world'

def sqlite(sql):
    sql=re.sub(r'\) ENGINE=InnoDB[^;]*;', ');', sql)
    sql=sql.replace(" COMMENT '0 both, 1 Alliance, 2 Horde'",'')
    return sql.replace('ON DUPLICATE KEY UPDATE `min_level` = VALUES(`min_level`)', 'ON CONFLICT(id) DO UPDATE SET min_level=excluded.min_level')

class AccessDataTest(unittest.TestCase):
    def setUp(self):
        self.db=sqlite3.connect(':memory:')
        self.db.executescript('CREATE TABLE mod_archaeology_site (id INTEGER PRIMARY KEY,map,race,name,min_skill,min_level,enabled); CREATE TABLE mod_archaeology_site_point (site,idx,x,y); CREATE TABLE mod_archaeology_site_spawn (site,idx,x,y,z);')
        text=(SQL/'mod_archaeology_world_data.sql').read_text()
        for table in ('mod_archaeology_site','mod_archaeology_site_point','mod_archaeology_site_spawn'):
            block='INSERT INTO `'+table+'`'+text.split('INSERT INTO `'+table+'`',1)[1].split(';',1)[0]+';'
            self.db.executescript(block)
        self.upgrade=sqlite((SQL/'mod_archaeology_world_zz_access.sql').read_text())
        self.db.executescript(self.upgrade)

    def test_complete_starter_pools_and_evidence(self):
        beginners=json.loads((ROOT/'tools/beginner-sites.json').read_text())['sites']
        self.assertEqual(len(beginners),24)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM mod_archaeology_site').fetchone()[0],180)
        for zone,team in ((12,1),(1,1),(85,2),(141,1),(215,2),(14,2)):
            self.assertEqual(self.db.execute('SELECT COUNT(*) FROM mod_archaeology_site_access WHERE starter_zone=? AND team=?',(zone,team)).fetchone()[0],4)
        for site in beginners:
            points=self.db.execute('SELECT x,y,z FROM mod_archaeology_site_spawn WHERE site=? ORDER BY idx',(site['id'],)).fetchall()
            self.assertEqual(points,[(p['x'],p['y'],p['z']) for p in site['points']])
            self.assertGreaterEqual(len(points),3)
            xmin,xmax,ymin,ymax=site['bounds']
            self.assertTrue(all(xmin<x<xmax and ymin<y<ymax for x,y,_ in points))
            self.assertLess(max(z for _,_,z in points)-min(z for _,_,z in points),10)
            self.assertGreater(max((x-x2)**2+(y-y2)**2 for x,y,_ in points for x2,y2,_ in points),40**2)

    def test_upgrade_idempotent_and_operator_holds_preserved(self):
        self.db.execute('UPDATE mod_archaeology_site SET enabled=0 WHERE id IN (9,1000)')
        before=self.db.execute('SELECT * FROM mod_archaeology_site ORDER BY id').fetchall()
        self.db.executescript(self.upgrade)
        self.assertEqual(before,self.db.execute('SELECT * FROM mod_archaeology_site ORDER BY id').fetchall())
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM mod_archaeology_site_point WHERE site>=1000').fetchone()[0],96)
        self.assertGreaterEqual(self.db.execute('SELECT min_level FROM mod_archaeology_site WHERE id=281').fetchone()[0],50)

    def test_generator_matches_checked_in_upgrade(self):
        spec=importlib.util.spec_from_file_location('access',ROOT/'tools/build_site_access.py')
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        self.assertEqual(mod.generate(),(SQL/'mod_archaeology_world_zz_access.sql').read_text())
        levels=json.loads((ROOT/'tools/site-level-overrides.json').read_text())
        for sid,rule in levels.items():
            self.assertEqual(self.db.execute('SELECT min_level FROM mod_archaeology_site WHERE id=?',(int(sid),)).fetchone()[0],rule['min_level'])

    def test_persistent_cooldown_migration(self):
        schema=sqlite((ROOT/'data/sql/db-characters/mod_archaeology_char_expedition.sql').read_text())
        self.db.executescript(schema)
        self.db.execute('INSERT INTO mod_archaeology_char_expedition VALUES (42,1900)')
        self.db.executescript(schema)
        self.assertEqual(self.db.execute('SELECT until_time FROM mod_archaeology_char_expedition WHERE guid=42').fetchone()[0],1900)

if __name__=='__main__':unittest.main()
