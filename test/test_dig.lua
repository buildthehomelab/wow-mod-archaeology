-- Exercise the real addon receiver and survey button: standing on the find turns Survey into Dig.
tinsert,tremove=table.insert,table.remove
unpack=unpack or table.unpack
UISpecialFrames,StaticPopupDialogs,SlashCmdList={},{},{}
ACCEPT,CANCEL="Accept","Cancel"
local sent={}
local methods={}
local function object(name)
    local o={name=name,scripts={},shown=true,text=""}
    setmetatable(o,{__index=function(_,key) return methods[key] or function() end end})
    if name then _G[name]=o end
    return o
end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:GetScript(k) return self.scripts[k] end
function methods:GetName() return self.name end
function methods:CreateFontString() return object() end
function methods:CreateTexture() return object() end
function methods:SetText(t) self.text=t end
function methods:SetTexture(t) self.texture=t; return true end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown end
function methods:IsOwned() return false end
local frames={}
function CreateFrame(_,name,_,template)
    local o=object(name)
    tinsert(frames,o)
    if template=="ActionButtonTemplate" then
        for _,part in ipairs({"Icon","Border","Cooldown","HotKey"}) do object(name..part) end
    end
    return o
end
function UnitName() return "Tester" end
function GetItemIcon() return "icon" end
function GetTime() return 100 end
function SendAddonMessage(_,msg) tinsert(sent,msg) end
function CooldownFrame_SetTimer(cd,start,dur) cd.cooldown=dur end
function PlaySound() end
UIParent,WorldMapFrame,GameTooltip=object(),object(),object()
UIErrorsFrame=object()
TOOLTIP_DEFAULT_BACKGROUND_COLOR={r=0,g=0,b=0}
TOOLTIP_DEFAULT_COLOR={r=1,g=1,b=1}
assert(loadfile('addon/ArchaeologyUI/ArchaeologyUI.lua'))()
local receiver=frames[1]
local function msg(s) receiver.scripts.OnEvent(receiver,"CHAT_MSG_ADDON","ARCH",s,"WHISPER","Tester") end
local A=ArchaeologyUI
A.db={}
assert(loadfile('addon/ArchaeologyUI/Survey.lua'))()
local button,icon,cooldown=ArchaeologyUISurveyButton,ArchaeologyUISurveyButtonIcon,ArchaeologyUISurveyButtonCooldown
assert(icon.texture:find('Spyglass'),'Survey shows the spyglass')
button.scripts.OnClick(button,"LeftButton")
assert(sent[#sent]=='SURVEY','Off the find the button surveys')
msg('O:1')
assert(A.overFind and icon.texture==A.SHOVEL,'On the find the button is the shovel')
button.scripts.OnClick(button,"LeftButton")
assert(sent[#sent]=='DIG','On the find the button digs')
msg('Q:1500')
assert(cooldown.cooldown==1.5,'The dig time shows on the button')
local n=#sent
button.scripts.OnClick(button,"LeftButton")
assert(#sent==n,'No second dig while digging')
msg('Q:0');msg('V:FOUND');msg('O:0')
assert(not A.overFind and icon.texture:find('Spyglass'),'After the find comes up the button surveys again')
print('PASS: survey/dig button follows O: and Q:, sends SURVEY or DIG, one dig at a time')
