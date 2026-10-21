-- Exercise the relic's LN/L messages, its link lookup, row and tooltip under a minimal 3.3.5 frame API.
tinsert,tremove=table.insert,table.remove
unpack=unpack or table.unpack
UISpecialFrames,StaticPopupDialogs,SlashCmdList,UIPanelWindows={},{},{},{}
ACCEPT,CANCEL,NUM_BAG_SLOTS="Accept","Cancel",4
ITEM_QUALITY_COLORS={[3]={r=0,g=0.44,b=0.87,hex="|cff0070dd"},[4]={r=0.64,g=0.21,b=0.93,hex="|cffa335ee"}}
local frames={}
local methods={}
local function object(name)
    local o={name=name,scripts={},shown=true,text="",lines={}}
    setmetatable(o,{__index=function(_,key) return methods[key] or function() end end})
    if name then _G[name]=o end
    return o
end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:GetScript(k) return self.scripts[k] end
function methods:CreateFontString() return object() end
function methods:CreateTexture() return object() end
function methods:SetText(t) self.text=t; self.lines={t} end
function methods:GetText() return self.text end
function methods:SetTexture(t) self.texture=t; return true end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetValue(v) self.value=v end
function methods:AddLine(t) tinsert(self.lines,t) end
function methods:AddDoubleLine(l,r) tinsert(self.lines,l.."="..r) end
function methods:SetHyperlink(l) self.lines={"LINK "..l} end
function CreateFrame(_,name) local o=object(name);tinsert(frames,o);return o end
function UnitName() return "Tester" end
function GetItemIcon(id) return "icon"..id end
function SendAddonMessage() end
function PlaySound() end
local equipped,bags={},{}
function GetInventoryItemLink(_,slot) return equipped[slot] end
function GetContainerNumSlots(bag) return bag==0 and 2 or 0 end
function GetContainerItemLink(bag,slot) return bags[slot] end
function GetItemInfo(link) if tostring(link):find("cached") then return "Relic", link end end
UIParent,WorldMapFrame,GameTooltip=object(),object(),object()
assert(loadfile('addon/ArchaeologyUI/ArchaeologyUI.lua'))()
local receiver=frames[1]
local function msg(s) receiver.scripts.OnEvent(receiver,"CHAT_MSG_ADDON","ARCH",s,"WHISPER","Tester") end
local A=ArchaeologyUI
A.db={}
assert(loadfile('addon/ArchaeologyUI/Research.lua'))()
local R=A.Research

-- An older server sends only L: no item, no next rank; the link falls back to any relic step on the character.
msg('L:3:9:40:120:30:3:Staff:')
assert(A.relic.rank==3 and A.relic.form=="Staff" and A.relic.item==nil,'L alone still parses')
equipped[16]="|cff0070dd|Hitem:9505062:0:0:0:0:0:0:0:30|h[Relic]|h|r cached"
assert(A.RelicLink()==equipped[16],'An equipped relic step is found without LN')

-- LN then L: the server names the item, the next rank and what holds it back.
msg('LN:9505095:0:33:3:1:24:33')
msg('L:3:9:40:120:30:3:Staff:')
local r=A.relic
assert(r.item==9505095 and r.nextItemLevel==33 and r.held==1 and r.heldLevel==24,'LN is attached to the relic')
assert(A.RelicLink()=="item:9505095",'Not on the character: the plain item the server named')
bags[2]="|cff0070dd|Hitem:9505095:1:0:0:0:0:0:0:30|h[Relic]|h|r cached"
assert(A.RelicLink()==bags[2],'In the bags: its own link')
assert(A.RelicIcon()=="icon9505095",'The icon is the named item')

-- The row under the header.
local header=object(); header.label=object(); header.note=object()
R.NewRelicRow(object(),header)
R.DrawRelicRow(header)
assert(header.note.text=="Rank 3/9",'Rank on the header')
assert(header.row.line.text=="Staff, item level 30",'Form and item level on the row')
assert(header.row.power.text=="40/120" and header.row.bar.value==40,'Power on the right and on the bar')

-- The tooltip: the weapon, then the relic's story and the traits.
msg('JBEGIN')
A.raceOrder={1,2}
msg('J:1:90507:1:10:10:100:1.5:Active:Ember')
msg('J:2:90508:0:4:10:100:1.5:Locked:Focus')
msg('JEND')
header.scripts.OnEnter(header)
local text=table.concat(GameTooltip.lines,"\n")
assert(text:find("LINK "..bags[2],1,true),'The item tooltip comes first')
assert(text:find("Relic Power=40 / 120  (80 to go)",1,true),'Power to go')
assert(text:find("Rank 4=",1,true) and text:find("item level 33",1,true),'The next rank')
assert(text:find("at level 24 it grows to item level 33",1,true),'What holds it back')
assert(text:find("Traits: 1 of 2 awake",1,true) and text:find("4/10 commons",1,true),'Traits')

-- Rank 0: the note on the row, power on the right, no link.
msg('LN:0:0:0:0:0:0:0')
msg('L:0:9:70:0:0:0::Ask an archaeology trainer about A Weapon in Pieces.')
R.DrawRelicRow(header)
assert(A.RelicLink()==nil,'No relic, no link')
assert(header.row.line.text:find("Weapon in Pieces"),'The note on the row')
assert(header.row.power.text=="70",'Power without a cost')
print("relic ok")
