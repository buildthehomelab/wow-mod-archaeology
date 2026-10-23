-- Exercise the real addon receiver and collection view under a minimal 3.3.5 frame API.
tinsert,tremove=table.insert,table.remove
unpack=unpack or table.unpack
UISpecialFrames,StaticPopupDialogs,SlashCmdList={},{},{}
ACCEPT,CANCEL="Accept","Cancel"
local objects,frames={},{}
local methods={}
local function object(name)
    local o={name=name,scripts={},shown=true,enabled=true,text=""}
    setmetatable(o,{__index=function(_,key) return methods[key] or function() end end})
    tinsert(objects,o)
    if name then _G[name]=o end
    return o
end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:GetScript(k) return self.scripts[k] end
function methods:CreateFontString() return object() end
function methods:CreateTexture() return object() end
function methods:SetText(t) self.text=t end
function methods:GetText() return self.text end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetParent(p) self.parent=p end
function methods:GetParent() return self.parent end
function methods:GetWidth() return 0 end
function methods:IsMouseOver() return false end
function methods:Enable() self.enabled=true end
function methods:Disable() self.enabled=false end
function CreateFrame(_,name) local o=object(name);tinsert(frames,o);return o end
function UnitName() return "Tester" end
function GetItemIcon() return "icon" end
function GetItemInfo() end
function IsShiftKeyDown() end
function SendAddonMessage() end
UIParent,WorldMapFrame,GameTooltip=object(),object(),object()
assert(loadfile('addon/ArchaeologyUI/ArchaeologyUI.lua'))()
local receiver=frames[1]
local function msg(s) receiver.scripts.OnEvent(receiver,"CHAT_MSG_ADDON","ARCH",s,"WHISPER","Tester") end
local A=ArchaeologyUI
A.Research={page=object()}
A.RaceIcon=function() return "race" end
assert(loadfile('addon/ArchaeologyUI/Collection.lua'))()
msg('S:1:75')
msg('R:1,Dwarf,0,200,1,30,0,0,0,1;2,Draenei,0,200,0,0,0,0,0,0')
msg('REND')
assert(#A.Collection.raceRows==2,'Race rows are made as the races come in, before the first open')
msg('CBEGIN')
msg('U:1:0:0:1');msg('U:2:300:8:0')
msg('C:1:1:0:9504020:7:First Artifact')
msg('C:2:1:1:9504021:0:Missing Rare')
msg('C:3:2:1:9504022:0:Locked Race Rare')
assert(A.collection==nil,'Snapshots must commit only at CEND')
msg('CEND')
msg('JBEGIN')
msg('J:1:90507:0:7:10:40:2:Locked:Thaurissan Ember')
msg('K:1:Hits can add Fire damage equal to 8% of power.')
msg('JEND')
A.OpenCollection()
local function has(text)
 for _,o in ipairs(objects) do if type(o.text)=='string' and o.text:find(text,1,true) then return true end end
 return false
end
assert(has('Discovered 1/3 artifacts  -  Rares 0/2  -  2 left'),'Repeat solves must not inflate unique totals')
assert(has('Unlock: solve one rare or 10 commons (7/10).'),'Configured unlock progress')
assert(has('Missing Rare'),'Missing artifacts visible')
assert(A.traits[1].effect:find('8%%'),'Trait description committed')
for _,o in ipairs(objects) do if o.text=='Missing' then o.scripts.OnClick() end end
assert(has('Missing Rare'))
-- An artifact's page: its lore asked for, the solve count, Back returns to the list.
for _,o in ipairs(objects) do local p=rawget(o,'project'); if type(p)=='table' and p.id==2 and o.shown then o.scripts.OnClick(o) end end
assert(has('Rare artifact - not solved yet'),'Artifact page')
for _,o in ipairs(objects) do if o.text=='Back' then o.scripts.OnClick() end end
-- A later solve makes the unique catalogue complete for Dwarf, independent of inventory.
msg('CBEGIN');msg('C:1:1:0:9504020:8:First Artifact');msg('C:2:1:1:9504021:1:Missing Rare');msg('CEND')
assert(has('Race complete!'),'Completion state shown')
-- Locked races remain selectable and show both skill and progression gate.
for _,o in ipairs(objects) do if rawget(o,'race')==2 and o.scripts.OnClick then o.scripts.OnClick(o) end end
assert(has('Unlocks at Archaeology skill 300; needs progression stage 8'),'Locked race guidance')
-- Existing T protocol remains intact; E extends it after the polygon snapshot.
msg('T:1000,0,1,3,Starter Site');msg('G:1000:0,0;100,0;100,100;0,100');msg('TEND');msg('E:1000:1:0')
assert(A.sites[1000].level==1 and not A.sites[1000].challenge)
print('PASS: real protocol/view; repeat/unique/rare counts, missing filter, completion, locked race gates, trait progress, compatible site hints')
