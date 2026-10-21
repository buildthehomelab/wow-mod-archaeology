-- A server-authoritative catalogue. Solve history survives selling/deleting rewards.
-- Shared entry on Research.page follows its host into DragonUI/RetailProfessions.
local A = ArchaeologyUI
local view = CreateFrame("Frame", "ArchaeologyUICollection", UIParent)
view:SetSize(660, 560)
view:SetPoint("CENTER")
view:SetFrameStrata("DIALOG")
view:SetToplevel(true)
view:SetClampedToScreen(true)
view:SetMovable(true)
view:EnableMouse(true)
view:RegisterForDrag("LeftButton")
view:SetScript("OnDragStart", view.StartMoving)
view:SetScript("OnDragStop", view.StopMovingOrSizing)
view:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=32, insets={left=11,right=12,top=12,bottom=11}})
view:Hide()
tinsert(UISpecialFrames, "ArchaeologyUICollection")
local close = CreateFrame("Button", nil, view, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)
local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -20)
title:SetText("Archaeology Collection & Race Bonuses")
local total = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
total:SetPoint("TOP", 0, -45)
local filter, selected, offset = "All", nil, 0
local tabs, rows = {}, {}
local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end
local filters = {}
local redraw
for i, label in ipairs({"All", "Collected", "Missing"}) do
    local b = button(view, label, 85)
    b:SetPoint("TOPLEFT", 175 + (i-1)*91, -72)
    b:SetScript("OnClick", function() filter, offset = label, 0; redraw() end)
    filters[label] = b
end
local progress = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
progress:SetPoint("TOPLEFT", 177, -106)
progress:SetWidth(445)
progress:SetJustifyH("LEFT")
local traitText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
traitText:SetPoint("TOPLEFT", 177, -134)
traitText:SetWidth(445)
traitText:SetHeight(125)
traitText:SetJustifyH("LEFT")
traitText:SetJustifyV("TOP")
for i=1,8 do
    local b = button(view, "", 140)
    b:SetPoint("TOPLEFT", 22, -73 - (i-1)*34)
    tabs[i] = b
end
for i=1,7 do
    local row = CreateFrame("Button", nil, view)
    row:SetSize(443, 30)
    row:SetPoint("TOPLEFT", 177, -268 - (i-1)*32)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26,26)
    row.icon:SetPoint("LEFT")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 34, 0)
    row.text:SetWidth(405)
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnEnter", function(self)
        if not self.project then return end
        local p = self.project
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(p.name)
        GameTooltip:AddLine((p.rare and "Rare" or "Common") .. " - " .. (p.solves > 0 and "Collected" or "Missing"), 1,1,1)
        GameTooltip:AddLine("Times solved: " .. p.solves, 1,1,1)
        GameTooltip:AddLine("Reward item: " .. p.item, 0.8,0.8,0.8)
        local detail = A.projects[p.id]
        if detail and detail.text then GameTooltip:AddLine(detail.text, 0.9,0.85,0.7, true) end
        GameTooltip:AddLine("Click for lore; Shift-click to inspect reward.", 0.7,0.7,0.7)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local p = self.project
        if not p then return end
        if IsShiftKeyDown() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. p.item)
            GameTooltip:Show()
        else
            A.RequestProject(p.id)
            self:GetScript("OnEnter")(self)
        end
    end)
    rows[i] = row
end
local previous, nextPage = button(view,"Previous",85), button(view,"Next",85)
previous:SetPoint("BOTTOMLEFT",177,22)
nextPage:SetPoint("BOTTOMRIGHT",-35,22)
previous:SetScript("OnClick", function() offset=math.max(0,offset-7); redraw() end)
nextPage:SetScript("OnClick", function() offset=offset+7; redraw() end)
local refresh = button(view,"Refresh",100)
refresh:SetPoint("BOTTOMLEFT",25,22)
refresh:SetScript("OnClick", function() A.Request("COLLECTION", "COLLECTION") end)
redraw = function()
    if not view:IsShown() then return end
    local catalogue = A.collection or {}
    local done, count, rareDone, rareCount = 0,0,0,0
    local summaries = {}
    for _, p in pairs(catalogue) do
        local c = summaries[p.race] or {done=0,count=0,rareDone=0,rareCount=0}
        summaries[p.race] = c
        count, c.count = count+1,c.count+1
        if p.solves>0 then done,c.done=done+1,c.done+1 end
        if p.rare then
            rareCount,c.rareCount=rareCount+1,c.rareCount+1
            if p.solves>0 then rareDone,c.rareDone=rareDone+1,c.rareDone+1 end
        end
    end
    total:SetText(A.collection and string.format("Discovered %d/%d artifacts - Rares %d/%d - %d left",done,count,rareDone,rareCount,count-done) or "Loading collection from realm...")
    selected = selected or (A.raceOrder and A.raceOrder[1])
    for i,b in ipairs(tabs) do
        local id = A.raceOrder and A.raceOrder[i]
        local race = id and A.races[id]
        if race then
            local c = summaries[id] or {done=0,count=0}
            b:SetText(race.name .. " " .. c.done .. "/" .. c.count)
            b:SetScript("OnClick",function() selected,offset=id,0; redraw() end)
            b:Show()
            if id==selected then b:Disable() else b:Enable() end
        else b:Hide() end
    end
    for label,b in pairs(filters) do if label==filter then b:Disable() else b:Enable() end end
    local c = summaries[selected] or {done=0,count=0,rareDone=0,rareCount=0}
    local race = selected and A.races[selected]
    local unlock = (A.unlocks or {})[selected]
    local lock = race and not race.unlocked and (" - unlock at skill " .. (unlock and unlock.skill or "?")) or ""
    if unlock and not unlock.era then lock = lock .. " - requires progression stage " .. unlock.state end
    progress:SetText(string.format("%d/%d discovered - Rares %d/%d%s%s", c.done,c.count,c.rareDone,c.rareCount,c.count>0 and c.done==c.count and " - Race complete!" or "",lock))
    local t = (A.traits or {})[selected]
    if t then
        traitText:SetText(t.name .. " - " .. t.status .. "\n" .. (t.effect or "") .. "\n" ..
            (t.awake and ("Unlocked - current relic strength " .. t.strength .. "%") or ("Unlock: solve one rare OR " .. t.need .. " commons (" .. t.commons .. "/" .. t.need .. ").")) ..
            "\nCollection completion: " .. t.bonus .. "x effect (Mercy: faster recovery). Equip the relic to use unlocked traits.")
    else traitText:SetText("Race bonus information is loading or unavailable on this realm.") end
    local list = {}
    for _,p in pairs(catalogue) do
        if p.race==selected and (filter=="All" or (filter=="Collected" and p.solves>0) or (filter=="Missing" and p.solves==0)) then tinsert(list,p) end
    end
    table.sort(list,function(a,b) if a.rare~=b.rare then return a.rare end; return a.name<b.name end)
    offset=math.min(offset, math.max(0,math.floor((#list-1)/7)*7))
    for i,row in ipairs(rows) do
        local p=list[offset+i]
        row.project=p
        if p then
            row.icon:SetTexture(GetItemIcon(p.item) or A.SHOVEL)
            row.text:SetText((p.solves>0 and "|cff55dd77Collected|r" or "|cffaaaaaaMissing|r") .. " - " .. p.name .. (p.rare and " |cffa335ee[Rare]|r" or "") .. (p.solves>1 and (" x" .. p.solves) or ""))
            row:Show()
        else row:Hide() end
    end
    if offset>0 then previous:Enable() else previous:Disable() end
    if offset+7<#list then nextPage:Enable() else nextPage:Disable() end
end
function A.OpenCollection()
    view:Show()
    A.Request("COLLECTION", "COLLECTION")
    redraw()
end
-- Anchored below the shared lore box to avoid covering host-specific headers.
local entry = button(A.Research.page,"Collection & Bonuses",160)
entry:SetPoint("BOTTOMLEFT",4,4)
entry:SetScript("OnClick", A.OpenCollection)
A.On("COLLECTION",redraw)
A.On("RACES",redraw)
A.On("PROJECT",function(id)
    for _,row in ipairs(rows) do
        if row:IsMouseOver() and row.project and row.project.id==id then row:GetScript("OnEnter")(row) end
    end
end)
A.On("SOLVED",function() if view:IsShown() then A.Request("COLLECTION", "COLLECTION") end end)
local elapsed=0
view:SetScript("OnUpdate",function(_,dt)
    elapsed=elapsed+dt
    if elapsed>=5 then elapsed=0; A.Request("TRAITS", "TRAITS") end
end)
