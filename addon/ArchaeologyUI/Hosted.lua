-- With DragonUI's professions window (DragonUI 2.12 and later: its host takes pages of other
-- addons), the research view is a page of that window with a side tab of its own after the
-- profession tabs. The races go in the list column, the project on the recipe card and your skill
-- on the rank bar, in DragonUI's art. /arch, the key binding, the survey button's right-click and
-- the fragments bar open that page; our own window (Research.lua) isn't used then. The tab shows
-- once you know Archaeology.
--
-- The collection (Collection.lua) is a second page under the same tab: its races in the list
-- column, the race's page on the card, and the artifacts you have found on the rank bar.

local A = ArchaeologyUI
local R = A.Research
local C = A.Collection
local PAGE = "archaeology"
local COLLECTION = "archaeology-collection"
local TITLE = "Archaeology"

-- DragonUI's window layout: the crafting page's rank bar, list column and recipe card.
local BAR_X, BAR_Y, BAR_W, BAR_FILL_W = 110, -40, 453, 441
local LIST_X, LIST_Y, LIST_W, LIST_H = 5, -72, 304, 517
local CARD_X, CARD_Y, CARD_INSET = 311, -72, 4
-- The recipe list's header strips: where they start in the column, their size, the indent under them.
local AREA_X, AREA_Y, AREA_W, HEADER_H, INDENT = 8, -8, LIST_W - 8 - 20, 25, 10
-- Archaeology has no art of its own in DragonUI: the bar's animated fill and the card's drawing are Mining's.
local ART_KEY = "Mining"

-- DragonUI's professions host and art, when this DragonUI has them and its professions window is on.
local function api()
    local D = _G.DragonUI
    local P = D and D.Professions
    local H = P and P.Host
    local Art = P and P.Art
    if not (H and (H.VERSION or 0) >= 3 and H.Enabled and H.AddPage and H.AddTab and H.TogglePage
            and H.SetPage and H.Page and H.RefreshTabs and Art and Art.Set and Art.SetInset
            and Art.NineSlice and Art.PlaceNineSlice and Art.RankText and Art.ThreeSlice and P.Fill
            and P.Fill.Create and P.Fill.Update and P.Atlas and P.Atlas["card-base"] and P.Atlas.header) then
        return nil
    end
    if not H.Enabled() then return nil end
    return H, P, D
end

local holder, bar, rows = nil, nil, {}

-- A category header of the recipe list: its strip, a gold label and a small note on the right.
local function header(parent, P, D, text)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(AREA_W, HEADER_H)
    P.Art.ThreeSlice(h, "BACKGROUND", "header", 8)
    h.label = h:CreateFontString(nil, "ARTWORK", "GameFontHighlightLeft")
    local fonts = D.ForeverUI and D.ForeverUI.Fonts
    if fonts and fonts.HighlightMedium then h.label:SetFontObject(fonts.HighlightMedium) end
    h.label:SetPoint("LEFT", h, "LEFT", 8, 0)
    h.label:SetTextColor(1, 0.82, 0)
    h.label:SetText(text or "")
    h.note = h:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    h.note:SetPoint("RIGHT", h, "RIGHT", -8, 0)
    h.note:SetJustifyH("RIGHT")
    return h
end

-- The relic header and its line go when there is no relic; the races header moves up.
local function layout(hasRelic)
    local relic = holder.relic
    if hasRelic then
        relic:Show()
        relic.line:Show()
    else
        relic:Hide()
        relic.line:Hide()
    end
    local y = hasRelic and AREA_Y - HEADER_H - 30 or AREA_Y
    holder.races:ClearAllPoints()
    holder.races:SetPoint("TOPLEFT", holder.list, "TOPLEFT", AREA_X, y)
end

local function rowFor(list, i)
    local row = rows[i]
    if row then return row end
    row = R.NewRaceRow(list)
    row:SetPoint("TOPLEFT", holder.races, "BOTTOMLEFT", INDENT, -4 - (i - 1) * R.ROW_HEIGHT)
    row:SetPoint("RIGHT", holder.races, "RIGHT", 0, 0)
    rows[i] = row
    return row
end

-- The crafting page's rank bar: its fill (Forever's default blue) and "<what> n/max" on it.
local function rankBar(parent, P)
    local Art = P.Art
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(BAR_W, 18)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", BAR_X, BAR_Y)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    Art.Set(bg, "rankbar-bg", true)
    bg:SetPoint("TOPLEFT")
    b.fx = P.Fill.Create(b, BAR_W, 0, 18)
    b.fx:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -3)
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel(b.fx:GetFrameLevel() + 1)
    local border = top:CreateTexture(nil, "ARTWORK")
    Art.Set(border, "rankbar-border", true)
    border:SetPoint("TOPLEFT")
    b.rank = Art.RankText(top)
    b.rank:SetCenter(b, "TOPLEFT", 5 + BAR_FILL_W / 2, -12)
    return b
end

local function listColumn(parent)
    local list = CreateFrame("Frame", nil, parent)
    list:SetPoint("TOPLEFT", parent, "TOPLEFT", LIST_X, LIST_Y)
    list:SetSize(LIST_W, LIST_H)
    return list
end

-- The recipe card: its parchment, the crafting card's drawing (withDrawing) and the inside frame.
local function recipeCard(parent, P, withDrawing)
    local Art = P.Art
    local size = P.Atlas["card-base"]
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", CARD_X, CARD_Y)
    card:SetSize(size[2], size[3])
    local base = card:CreateTexture(nil, "BACKGROUND")
    Art.SetInset(base, "card-base", CARD_INSET)
    base:ClearAllPoints()
    base:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET, -CARD_INSET)
    base:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_INSET, CARD_INSET)
    local drawing = withDrawing and Art.CardDrawing and Art.CardDrawing(ART_KEY)
    local at = P.ArtLayout and P.ArtLayout.cardDraw
    if drawing and at and Art.SetClipped then
        local draw = card:CreateTexture(nil, "BORDER")
        draw:SetPoint("TOPLEFT", card, "TOPLEFT", at[1], at[2])
        Art.SetClipped(draw, drawing, size[2] - CARD_INSET - at[1], size[3] - CARD_INSET + at[2])
    end
    local frame = Art.NineSlice(card, "ARTWORK", "insideframe", 53)
    Art.PlaceNineSlice(frame, card, 53)
    return card
end

-- The collection page: the races under a "Races" strip, the race's page on the card (no drawing:
-- the race's crest is the art there), the artifacts found on the rank bar, and the way back.
local collection
local function buildCollection(H, P, D, parent)
    if collection then
        collection:SetParent(parent)
        return collection
    end
    collection = CreateFrame("Frame", nil, parent)
    local totals = rankBar(collection, P)

    local list = listColumn(collection)
    local races = header(list, P, D, "Races")
    races:SetPoint("TOPLEFT", list, "TOPLEFT", AREA_X, AREA_Y)
    local research = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    research:SetSize(AREA_W - INDENT, 22)
    research:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", AREA_X + INDENT, 8)
    research:SetText("Back to Research")
    research:SetScript("OnClick", function() H.SetPage(PAGE) end)

    local card = recipeCard(collection, P, false)
    local page = C.card
    page:SetParent(card)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -18)
    page:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 14)
    local raceList = C.list
    raceList:SetParent(list)
    raceList:ClearAllPoints()
    raceList:SetPoint("TOPLEFT", races, "BOTTOMLEFT", INDENT, -4)
    raceList:SetPoint("RIGHT", races, "RIGHT", 0, 0)
    raceList:SetPoint("BOTTOM", research, "TOP", 0, 6)
    C.SetInk(false)
    if D.SkinRedButton then
        pcall(D.SkinRedButton, research)
        for _, b in ipairs(C.buttons) do pcall(D.SkinRedButton, b) end
    end
    C.drawTotals = function(loaded, done, count)
        if not loaded or count == 0 then
            totals:Hide()
            return
        end
        totals:Show()
        P.Fill.Update(totals.fx, ART_KEY, done / count, done >= count)
        totals.rank:Set("Artifacts " .. done, count)
    end
    if ArchaeologyUICollection then ArchaeologyUICollection:Hide() end
    return collection
end

local function build(H, P, D, parent)
    if holder then
        holder:SetParent(parent)
        return holder
    end
    holder = CreateFrame("Frame", nil, parent)

    -- The skill, on the crafting page's rank bar (Forever's default blue fill).
    bar = rankBar(holder, P)

    -- The list column, in the recipe list's headers: the relic on top (where the search box is on
    -- the crafting page), then the races.
    local list = listColumn(holder)
    holder.list = list

    local relic = header(list, P, D, "Unearthed Relic")
    relic:SetPoint("TOPLEFT", list, "TOPLEFT", AREA_X, AREA_Y)
    relic:EnableMouse(true)
    relic:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Unearthed Relic")
        GameTooltip:AddLine(self.tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    relic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    relic.line = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    relic.line:SetPoint("TOPLEFT", relic, "BOTTOMLEFT", 8, -6)
    relic.line:SetPoint("RIGHT", relic, "RIGHT", -8, 0)
    relic.line:SetJustifyH("LEFT")
    relic.line:SetWordWrap(false)
    holder.relic = relic
    holder.races = header(list, P, D, "Races")
    layout(false)

    -- The project, on the recipe card's parchment in its inside frame, with the crafting card's
    -- drawing under the reagents.
    local card = recipeCard(holder, P, true)

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
    if D.SkinRedButton then
        pcall(D.SkinRedButton, R.solve)
        pcall(D.SkinRedButton, C.entry)
    end
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
        P.Fill.Update(bar.fx, ART_KEY, maxSkill > 0 and math.min(skill / maxSkill, 1) or 0, maxSkill > 0 and skill >= maxSkill)
        bar.rank:Set(string.format("%s %d", TITLE, skill), maxSkill)
    end
    R.drawRelic = function(text)
        if fallback then return own.drawRelic(text) end
        if not holder then return end
        local r = A.relic
        if not (r and text and text ~= "") then
            layout(false)
            return
        end
        local relic = holder.relic
        local color = r.rank > 0 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality]
        if color then
            relic.label:SetTextColor(color.r, color.g, color.b)
        else
            relic.label:SetTextColor(0.9, 0.8, 0.5)
        end
        local power = r.cost > 0 and string.format("Relic Power %d/%d", r.power, r.cost)
            or string.format("Relic Power %d", r.power)
        if r.rank > 0 then
            relic.note:SetText(string.format("Rank %d/%d", r.rank, r.ranks))
            relic.line:SetText(string.format("Item level %d  -  %s", r.itemLevel, power))
        else
            relic.note:SetText("")
            relic.line:SetText(power)
        end
        -- The server's note (how to get it, what holds it back) is too long for the column.
        relic.tip = r.note ~= "" and r.note or nil
        if relic.tip and r.rank == 0 then relic.line:SetText(power .. "  -  " .. r.note) end
        layout(true)
    end
    R.drawRaces = function(races, current)
        if fallback then return own.drawRaces(races, current) end
        if not holder then return end
        for i, race in ipairs(races) do
            R.DrawRaceRow(rowFor(holder.list, i), race, current)
        end
        for i = #races + 1, #rows do
            R.DrawRaceRow(rows[i], nil)
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
            R.PlacePage(R.page)
            R.empty:SetParent(ArchaeologyUIFrame)
            R.empty:ClearAllPoints()
            R.empty:SetPoint("CENTER")
            R.empty:SetWidth(340)
            C.TakeBack()
        end
        own.toggle(open)
    end
    -- The collection page, the window opened (or switched) there; false sends it to our window.
    C.openHosted = function()
        if fallback then return false end
        if TradeSkillFrame and TradeSkillFrame:IsShown() then
            if H.Page() ~= COLLECTION then H.SetPage(COLLECTION) end
            return H.Page() == COLLECTION
        end
        return H.TogglePage(COLLECTION)
    end

    H.AddPage(PAGE, {
        standalone = true,
        title = TITLE,
        portrait = A.Icon(),
        build = function(parent) return build(H, P, D, parent) end,
    })
    H.AddPage(COLLECTION, {
        standalone = true,
        title = "Archaeology Collection",
        portrait = A.Icon(),
        build = function(parent) return buildCollection(H, P, D, parent) end,
    })
    -- One tab for both pages: it shows the research page and stays lit on the collection.
    H.AddTab({
        key = PAGE, label = TITLE, icon = A.Icon, after = "professions", standalone = true,
        onClick = function() H.SetPage(PAGE) end,
        selected = function(page) return page == PAGE or page == COLLECTION end,
        shown = function() return (A.skill or 0) > 0 end,
    })
    A.On("STATE", function() H.RefreshTabs() end)
    -- Our own window, if it was open before the page took over.
    if ArchaeologyUIFrame then ArchaeologyUIFrame:Hide() end
end

A.On("LOGIN", start)
