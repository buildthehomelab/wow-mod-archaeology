-- With DragonUI's professions window (DragonUI 2.12 and later: its host takes pages of other
-- addons), the research view is a page of that window with a side tab of its own after the
-- profession tabs. The races go in the list column, the project on the recipe card and your skill
-- on the rank bar, in DragonUI's art. /arch, the key binding, the survey button's right-click and
-- the fragments bar open that page; our own window (Research.lua) isn't used then. The tab shows
-- once you know Archaeology.

local A = ArchaeologyUI
local R = A.Research
local PAGE = "archaeology"
local TITLE = "Archaeology"

-- DragonUI's window layout: the crafting page's rank bar, list column and recipe card.
local BAR_X, BAR_Y, BAR_W, BAR_FILL_W = 110, -40, 453, 441
local LIST_X, LIST_Y, LIST_W, LIST_H = 5, -72, 304, 517
local CARD_X, CARD_Y, CARD_INSET = 311, -72, 4
local ROW_HEIGHT = 44

-- DragonUI's professions host and art, when this DragonUI has them and its professions window is on.
local function api()
    local D = _G.DragonUI
    local P = D and D.Professions
    local H = P and P.Host
    local Art = P and P.Art
    if not (H and (H.VERSION or 0) >= 3 and H.Enabled and H.AddPage and H.AddTab and H.TogglePage
            and H.SetPage and H.Page and H.RefreshTabs and Art and Art.Set and Art.SetInset
            and Art.NineSlice and Art.PlaceNineSlice and Art.RankText and P.Fill and P.Fill.Create
            and P.Fill.Update and P.Atlas and P.Atlas["card-base"]) then
        return nil
    end
    if not H.Enabled() then return nil end
    return H, P, D
end

local holder, bar, rows = nil, nil, {}

local function rowFor(list, i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -12 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", list, "RIGHT", -10, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -7)
    row.count:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetHeight(8)
    row.bar:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
    row.bar:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    local bg = row.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row.bar)
    bg:SetTexture(0, 0, 0, 0.65)
    -- The race on show stays lit.
    row.lit = row:CreateTexture(nil, "BACKGROUND")
    row.lit:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.lit:SetBlendMode("ADD")
    row.lit:SetVertexColor(1, 0.82, 0, 0.3)
    row.lit:SetAllPoints(row)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(1, 1, 1, 0.35)
    hl:SetAllPoints(row)
    row:SetScript("OnClick", function(self)
        if self.race then R.Select(self.race) end
    end)
    row:SetScript("OnEnter", function(self)
        local race = self.race and A.races[self.race]
        if not race then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(race.name)
        GameTooltip:AddLine(string.format("%d fragments (holds up to %d)", race.fragments, race.cap), 1, 1, 1)
        GameTooltip:AddLine(string.format("%d %s", race.keystones, race.keystones == 1 and "keystone" or "keystones"), 1, 1, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

local function build(H, P, D, parent)
    if holder then
        holder:SetParent(parent)
        return holder
    end
    local Art = P.Art
    holder = CreateFrame("Frame", nil, parent)

    -- The skill, on the crafting page's rank bar (Forever's default blue fill).
    bar = CreateFrame("Frame", nil, holder)
    bar:SetSize(BAR_W, 18)
    bar:SetPoint("TOPLEFT", holder, "TOPLEFT", BAR_X, BAR_Y)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    Art.Set(barBg, "rankbar-bg", true)
    barBg:SetPoint("TOPLEFT")
    bar.fx = P.Fill.Create(bar, BAR_W, 0, 18)
    bar.fx:SetPoint("TOPLEFT", bar, "TOPLEFT", 5, -3)
    local top = CreateFrame("Frame", nil, bar)
    top:SetAllPoints()
    top:SetFrameLevel(bar.fx:GetFrameLevel() + 1)
    local border = top:CreateTexture(nil, "ARTWORK")
    Art.Set(border, "rankbar-border", true)
    border:SetPoint("TOPLEFT")
    bar.rank = Art.RankText(top)
    bar.rank:SetCenter(bar, "TOPLEFT", 5 + BAR_FILL_W / 2, -12)

    -- The relic line, under the rank bar.
    holder.relic = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.relic:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 6, -2)
    holder.relic:SetWidth(BAR_W)
    holder.relic:SetJustifyH("LEFT")

    -- The races, in the list column.
    local list = CreateFrame("Frame", nil, holder)
    list:SetPoint("TOPLEFT", holder, "TOPLEFT", LIST_X, LIST_Y)
    list:SetSize(LIST_W, LIST_H)
    holder.list = list

    -- The project, on the recipe card's parchment in its inside frame.
    local size = P.Atlas["card-base"]
    local card = CreateFrame("Frame", nil, holder)
    card:SetPoint("TOPLEFT", holder, "TOPLEFT", CARD_X, CARD_Y)
    card:SetSize(size[2], size[3])
    local base = card:CreateTexture(nil, "BACKGROUND")
    Art.SetInset(base, "card-base", CARD_INSET)
    base:ClearAllPoints()
    base:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET, -CARD_INSET)
    base:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_INSET, CARD_INSET)
    local frame = Art.NineSlice(card, "ARTWORK", "insideframe", 53)
    Art.PlaceNineSlice(frame, card, 53)

    local page = R.page
    page:SetParent(card)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -18)
    page:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 14)
    -- The parchment is the box: no tooltip border round the lore, DragonUI's thin scroll bar.
    R.loreBox:SetBackdrop(nil)
    local CP = D.CharacterPanel
    if CP and CP.ReskinScrollBar then
        pcall(CP.ReskinScrollBar, R.loreScroll, R.loreBox, 4, -2, 4, false)
    end
    if D.SkinRedButton then pcall(D.SkinRedButton, R.solve) end
    -- The project bar as it has always been on the card, not the stock skill bar of our window.
    local pr = R.progress
    pr.bar:SetHeight(16)
    pr.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    pr.bg:SetTexture(0, 0, 0, 0.5)
    pr.edge:Hide()
    pr.border:ClearAllPoints()
    pr.border:SetPoint("TOPLEFT", -3, 3)
    pr.border:SetPoint("BOTTOMRIGHT", 3, -3)
    pr.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    pr.border:SetBackdropBorderColor(0.6, 0.6, 0.6)
    pr.text:ClearAllPoints()
    pr.text:SetPoint("CENTER", pr.bar, "CENTER")

    local empty = R.empty
    empty:SetParent(holder)
    empty:ClearAllPoints()
    empty:SetPoint("CENTER", holder, "CENTER", 0, -20)
    empty:SetWidth(360)

    holder:SetScript("OnShow", R.Opened)
    return holder
end

local function start()
    local H, P, D = api()
    if not H then return end
    -- Our own window's, for when DragonUI's window won't open (its professions module turned
    -- off, or a replacement such as Skillet loaded since).
    local own = { shown = R.shown, drawSkill = R.drawSkill, drawRaces = R.drawRaces, drawRelic = R.drawRelic, toggle = R.toggle }
    local fallback = false

    R.shown = function()
        if fallback then return own.shown() end
        return holder ~= nil and holder:IsVisible() and true or false
    end
    R.drawSkill = function(skill, maxSkill)
        if fallback then return own.drawSkill(skill, maxSkill) end
        if not bar then return end
        if not skill then
            bar:Hide()
            return
        end
        bar:Show()
        P.Fill.Update(bar.fx, nil, maxSkill > 0 and math.min(skill / maxSkill, 1) or 0, maxSkill > 0 and skill >= maxSkill)
        bar.rank:Set(string.format("%s %d", TITLE, skill), maxSkill)
    end
    R.drawRelic = function(text)
        if fallback then return own.drawRelic(text) end
        if not holder then return end
        -- One line fits between the rank bar and the list.
        holder.relic:SetText(text and text:gsub("\n", "  ") or "")
    end
    R.drawRaces = function(races, current)
        if fallback then return own.drawRaces(races, current) end
        if not holder then return end
        for i, race in ipairs(races) do
            local row = rowFor(holder.list, i)
            row.race = race.id
            row.icon:SetTexture(A.RaceIcon(race.id))
            row.name:SetText(race.name)
            local cost = race.cost or 0
            if cost > 0 then
                row.count:SetText(string.format("%d / %d", math.min(race.fragments, cost), cost))
                row.bar:SetMinMaxValues(0, cost)
                row.bar:SetValue(math.min(race.fragments, cost))
            else
                row.count:SetText(race.fragments)
                row.bar:SetMinMaxValues(0, 1)
                row.bar:SetValue(0)
            end
            -- Green once the project can be solved without keystones.
            if cost > 0 and race.fragments >= cost then
                row.bar:SetStatusBarColor(0.2, 0.8, 0.2)
            else
                row.bar:SetStatusBarColor(0.95, 0.6, 0.1)
            end
            if race.id == current then row.lit:Show() else row.lit:Hide() end
            row:Show()
        end
        for i = #races + 1, #rows do
            rows[i]:Hide()
            rows[i].race = nil
        end
    end
    R.toggle = function(open)
        if not fallback then
            if open and H.Page() == PAGE and TradeSkillFrame and TradeSkillFrame:IsShown() then return end
            if H.TogglePage(PAGE) then return end
            -- The page and its pieces stay where they are; our window gets them back.
            fallback = true
            R.page:SetParent(ArchaeologyUIFrame)
            R.page:ClearAllPoints()
            R.page:SetPoint("TOPLEFT", 20, -56)
            R.page:SetPoint("BOTTOMRIGHT", -20, 38)
            R.empty:SetParent(ArchaeologyUIFrame)
            R.empty:ClearAllPoints()
            R.empty:SetPoint("CENTER")
            R.empty:SetWidth(340)
        end
        own.toggle(open)
    end

    H.AddPage(PAGE, {
        standalone = true,
        title = TITLE,
        portrait = A.Icon(),
        build = function(parent) return build(H, P, D, parent) end,
    })
    H.AddTab({
        key = PAGE, label = TITLE, icon = A.Icon, after = "professions", page = PAGE, standalone = true,
        shown = function() return (A.skill or 0) > 0 end,
    })
    A.On("STATE", function() H.RefreshTabs() end)
    -- Our own window, if it was open before the page took over.
    if ArchaeologyUIFrame then ArchaeologyUIFrame:Hide() end
end

A.On("LOGIN", start)
