"""Run the actual assignment/abandonment function bodies against a deterministic realm fixture."""
import pathlib
import subprocess
import tempfile
import unittest
ROOT = pathlib.Path(__file__).resolve().parent.parent

PREAMBLE = r'''
#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <cmath>
#include <map>
#include <random>
#include <string>
#include <unordered_map>
#include <vector>
using uint8=unsigned char; using uint32=unsigned; using int32=int;
struct Point {float x=0,y=0;};
struct Site {uint32 id=0,map=0;uint8 race=1;uint32 minSkill=0,minLevel=1;uint8 team=0;uint32 starterZone=0;Point center;};
struct ActiveSite {uint32 site=0,finds=0;int32 spot=-1;};
struct CharState {uint32 skill=1,abandonUntil=0,excludedSite=0;std::array<std::vector<ActiveSite>,4> sites;std::unordered_map<uint32,uint32> solved;};
struct Config {uint32 sitesPerContinent=4,challengeLevels=3,abandonSeconds=1800;} config;
struct Guid {uint32 GetCounter() const {return 1;}};
struct Player {uint32 level=1,map=0,zone=12,team=0;uint32 GetLevel(){return level;}uint32 GetMapId(){return map;}uint32 GetZoneId(){return zone;}uint32 GetTeamId(){return team;}float GetPositionX(){return 0;}float GetPositionY(){return 0;}Guid GetGUID(){return {};}};
CharState state; unsigned forgotten=0,saves=0,notifications=0,dbWrites=0;bool expansionOpen=false;
std::array<uint32,4> CONTINENTS={0,1,530,571};
std::unordered_map<uint32,Site> sites;
std::unordered_map<uint32,std::vector<uint32>> sitesByMap;
std::unordered_map<uint8,std::vector<uint32>> projectsByRace;
struct Project {bool rare=false;}; std::unordered_map<uint32,Project> projects;
CharState* GetState(Player*) {return &state;}
Site const* GetSite(uint32 id) {auto i=sites.find(id);return i==sites.end()?nullptr:&i->second;}
bool CanDigContinent(Player*,uint32 c) {return c<2 || expansionOpen;}
void ForgetFinds(Player*) {++forgotten;}
void SaveSites(Player*,uint32) {++saves;}
void SendSites(Player*) {}
void Notify(Player*,std::string const&) {++notifications;}
struct DB {template<class... T>void Execute(char const*,T...){++dbWrites;}} CharacterDatabase;
namespace GameTime {unsigned seconds=100; std::chrono::seconds GetGameTime(){return std::chrono::seconds(seconds);}}
namespace Acore {
template<class... T>std::string StringFormat(char const* text,T...){return text;}
namespace Containers {
std::mt19937 generator(42);
template<class V> auto SelectRandomWeightedContainerElement(V& pool,std::vector<double> const& weights) {std::discrete_distribution<std::size_t> pick(weights.begin(),weights.end());return pool.begin()+pick(generator);}
}}
void add(uint32 id,uint32 level=1,uint8 team=1,uint32 zone=12,uint32 map=0) {Site s;s.id=id;s.minLevel=level;s.team=team;s.starterZone=zone;s.map=map;sites[id]=s;sitesByMap[map].push_back(id);}
void reset() {state=CharState();sites.clear();sitesByMap.clear();forgotten=saves=notifications=dbWrites=0;GameTime::seconds=100;}
'''
TESTS = r'''
int main() {
 Player p;
 reset();for(unsigned i=1;i<=4;++i)add(i);for(unsigned i=5;i<=8;++i)add(i,1,1,1);for(unsigned i=9;i<=12;++i)add(i,1,2,85);add(281,51);add(339,58,0,0,530);
 RollSites(&p);assert(state.sites[0].size()==4);for(auto a:state.sites[0])assert(a.site<=4);assert(state.sites[2].empty());
 // Source revalidation preserves valid partial progress while repairing invalid faction/level seats.
 state.sites[0]={{1,2,-1},{9,1,-1},{281,0,-1}};RollSites(&p);assert(forgotten==1);assert(state.sites[0][0].site==1 && state.sites[0][0].finds==2);for(auto a:state.sites[0])assert(a.site<=4);
 // A cooldown-backed replacement must differ and cannot be rerolled again immediately.
 std::string error;assert(AbandonSite(&p,1,error));assert(state.abandonUntil==1900 && dbWrites==1);for(auto a:state.sites[0])assert(a.site!=1);assert(state.sites[0].size()==4);assert(!AbandonSite(&p,state.sites[0][0].site,error));assert(dbWrites==1);
 // With no replacement pool, failure consumes neither progress nor cooldown.
 reset();for(unsigned i=1;i<=4;++i)add(i);RollSites(&p);assert(!AbandonSite(&p,1,error));assert(state.abandonUntil==0 && dbWrites==0 && state.sites[0].size()==4);
 assert(!AbandonSite(&p,9999,error));
 // Enough comfortable choices reserve a baseline even with numerous challenge candidates.
 for(unsigned run=0;run<200;++run){reset();p.level=20;for(unsigned i=1;i<=8;++i)add(i,10,0,0);for(unsigned i=9;i<=20;++i)add(i,19,0,0);RollSites(&p);unsigned hard=0;for(auto a:state.sites[0])hard+=sites[a.site].minLevel>17;assert(hard<=1);}
 // Expired cooldowns allow the next real replacement, not a fabricated site id.
 reset();p.level=20;for(unsigned i=1;i<=8;++i)add(i,10,0,0);RollSites(&p);auto old=state.sites[0][0].site;state.abandonUntil=100;assert(AbandonSite(&p,old,error));for(auto a:state.sites[0])assert(a.site!=old);
}
'''

class ExpeditionTest(unittest.TestCase):
    def test_real_assignment_and_abandonment(self):
        source=(ROOT/'src/ArchaeologyData.cpp').read_text()
        bodies=source[source.index('    void RollSites(Player* player)'):source.index('    void PickProject(Player* player')]
        with tempfile.TemporaryDirectory() as d:
            cpp=pathlib.Path(d)/'expeditions.cpp';binary=pathlib.Path(d)/'expeditions'
            cpp.write_text(PREAMBLE+bodies+TESTS)
            subprocess.run(['c++','-std=c++17','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',str(cpp),'-o',str(binary)],check=True)
            subprocess.run([str(binary)],check=True)

if __name__=='__main__':unittest.main()
