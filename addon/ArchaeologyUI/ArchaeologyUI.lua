-- ArchaeologyUI: the client half of mod-archaeology. Asks the server for your Archaeology skill,
-- races, projects and dig sites, keeps them here, and works out where you stand so the map,
-- minimap and survey button can draw them.
--
-- Wire format, both directions: an addon whisper to yourself, prefix "ARCH".
--   to the server    HELLO, SITES, RACES, PROJ:<id>, SURVEY, DIG, SOLVE:<race>:<keystones>, COLLECTION, TRAITS, ABANDON:<site>
--   from the server  S:<skill>:<max skill>                       (0 = not learned)
--                    R:<race>,<name>,<fragments>,<cap>,<project>,<cost>,<sockets>,<rare>,<keystones owned>,<unlocked>;... ... REND
--                    T:<site>,<map>,<race>,<finds left>,<name>;... then G:<site>:<x>,<y>;... (outline,
--                      world coordinates) ... TEND
--                    P:<id>:<race>:<rare>:<cost>:<sockets>:<item>:<name>, D:<id>:<text> ... DEND:<id>
--                    V:RED|YELLOW|GREEN:<angle> | V:FOUND | V:NONE   survey result
--                    O:1 | O:0                                    you stand on the hidden find (or left it)
--                    Q:<ms> | Q:0                                 digging started (for ms) | stopped
--                    F:<race>:<gained>:<total>                    fragments looted
--                    X:<project>:<item>:<rare>                    project solved
--                    LN:<item>:<off item>:<next item level>:<next quality>:<held>:<held level>:<held item level>
--                    L:<rank>:<ranks>:<power>:<next cost>:<item level>:<quality>:<form>:<note>   the relic
--                      (LN comes first; older servers send only L)
--
-- Other files hook in with ArchaeologyUI.On(event, fn). Events: STATE, RACES, SITES, PROJECT (id),
-- SURVEY (band, angle), OVERFIND (on), DIG (seconds, 0 = stopped), FRAGMENTS (race, gained, total), SOLVED (project, item, rare), POSITION,
-- RELIC, LOGIN (A.db is ready), MINIMAP (shown).

local PREFIX = "ARCH"
local POSITION_INTERVAL = 0.1
local REZONE_INTERVAL = 2       -- seconds between SetMapToCurrentZone retries while the map is closed
local REQUEST_SPACING = 1.1     -- the server ignores a second request of one kind within a second

ArchaeologyUI = {
    connected = false,  -- the server answered, so mod-archaeology is there
    skill = 0, maxSkill = 0,
    races = {},         -- by race id: { id, name, fragments, cap, project, cost, sockets, rare, keystones, unlocked }
    raceOrder = {},     -- race ids in the order the server sent them
    sites = {},         -- by site id: { id, map, race, finds, name, points = { x1, y1, x2, y2, ... }, cx, cy }
    projects = {},      -- by project id: { id, race, rare, cost, sockets, item, name, text }
    position = { valid = false, map = nil, x = 0, y = 0 },   -- the player's world position
    KEYSTONE_VALUE = 12,    -- fragments a keystone is worth (the server's Archaeology.KeystoneValue default)
    SHOVEL = "Interface\\Icons\\INV_Misc_Shovel_01",
}
local A = ArchaeologyUI

local listeners = {}
function A.On(event, fn)
    listeners[event] = listeners[event] or {}
    tinsert(listeners[event], fn)
end

function A.Fire(event, ...)
    for _, fn in ipairs(listeners[event] or {}) do
        fn(...)
    end
end

function A.Send(message)
    SendAddonMessage(PREFIX, message, "WHISPER", UnitName("player"))
end

-- Requests the server throttles go out one per kind per REQUEST_SPACING seconds; later ones wait.
local queue, lastSent = {}, {}
local function request(kind, message)
    for _, q in ipairs(queue) do
        if q.message == message then
            return
        end
    end
    tinsert(queue, { kind = kind, message = message })
end
A.Request = request

local function flushQueue(now)
    for i = 1, #queue do
        local q = queue[i]
        if not lastSent[q.kind] or now - lastSent[q.kind] >= REQUEST_SPACING then
            lastSent[q.kind] = now
            tremove(queue, i)
            A.Send(q.message)
            return
        end
    end
end

function A.RequestProject(id)
    if id and id > 0 and not (A.projects[id] and A.projects[id].complete) then
        request("PROJ", "PROJ:" .. id)
    end
end

function A.Survey()
    A.Send("SURVEY")
end

function A.Dig()
    A.Send("DIG")
end

function A.Solve(race, keystones)
    request("SOLVE", "SOLVE:" .. race .. ":" .. (keystones or 0))
end

-- Race ids that are open to this character, in server order.
function A.UnlockedRaces()
    local list = {}
    for _, id in ipairs(A.raceOrder) do
        local r = A.races[id]
        if r and r.unlocked then
            tinsert(list, r)
        end
    end
    return list
end

-- Fragments still needed for the race's project when `keystones` of them go in.
function A.FragmentsNeeded(race, keystones)
    local need = (race.cost or 0) - (keystones or 0) * A.KEYSTONE_VALUE
    return math.max(0, need - race.fragments)
end

local function split(text, sep)
    local out = {}
    for part in text:gmatch("[^" .. sep .. "]+") do
        tinsert(out, part)
    end
    return out
end

local pendingRaces, pendingSites, pendingRelic

local function onMessage(message)
    local command, rest = message:match("^(%u+):?(.*)$")
    if command == "S" then
        local skill, maxSkill = rest:match("^(%d+):(%d+)")
        A.connected = true
        A.skill, A.maxSkill = tonumber(skill) or 0, tonumber(maxSkill) or 0
        A.Fire("STATE")
    elseif command == "CBEGIN" then
        A.pendingCollection = {}
    elseif command == "C" then
        local id, race, rare, item, solves, name = rest:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(.*)$")
        if id and A.pendingCollection then
            A.pendingCollection[tonumber(id)] = {id=tonumber(id), race=tonumber(race), rare=rare=="1", item=tonumber(item), solves=tonumber(solves), name=name}
        end
    elseif command == "CEND" then
        A.collection = A.pendingCollection or {}
        A.pendingCollection = nil
        A.Fire("COLLECTION")
    elseif command == "U" then
        local race, skill, state, era = rest:match("^(%d+):(%d+):(%d+):(%d+)$")
        A.unlocks = A.unlocks or {}
        if race then A.unlocks[tonumber(race)] = {skill=tonumber(skill), state=tonumber(state), era=era=="1"} end
    elseif command == "JBEGIN" then
        A.pendingTraits = {}
    elseif command == "J" then
        local race, aura, awake, commons, need, strength, bonus, status, name = rest:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):([^:]+):([^:]+):(.*)$")
        if race and A.pendingTraits then
            A.pendingTraits[tonumber(race)] = {aura=tonumber(aura), awake=awake=="1", commons=tonumber(commons), need=tonumber(need), strength=tonumber(strength), bonus=tonumber(bonus), status=status, name=name}
        end
    elseif command == "K" then
        local race, effect = rest:match("^(%d+):(.*)$")
        local trait = race and A.pendingTraits and A.pendingTraits[tonumber(race)]
        if trait then trait.effect = effect end
    elseif command == "JEND" then
        A.traits = A.pendingTraits or {}
        A.pendingTraits = nil
        A.Fire("COLLECTION")
    elseif command == "W" then
        local site, done, need = rest:match("^(%d+):(%d+):(%d+)$")
        site = tonumber(site or 0)
        A.digOrder = site > 0 and { site = site, done = tonumber(done), need = tonumber(need) } or nil
        A.Fire("SITES")
    elseif command == "E" then
        local id, level, challenge = rest:match("^(%d+):(%d+):(%d+)$")
        local site = id and A.sites[tonumber(id)]
        if site then site.level, site.challenge = tonumber(level), challenge=="1" end
    elseif command == "R" then
        pendingRaces = pendingRaces or {}
        for _, row in ipairs(split(rest, ";")) do
            local f = split(row, ",")
            local id = tonumber(f[1])
            if id and #f >= 10 then
                tinsert(pendingRaces, {
                    id = id, name = f[2], fragments = tonumber(f[3]) or 0, cap = tonumber(f[4]) or 0,
                    project = tonumber(f[5]) or 0, cost = tonumber(f[6]) or 0, sockets = tonumber(f[7]) or 0,
                    rare = f[8] == "1", keystones = tonumber(f[9]) or 0, unlocked = f[10] == "1",
                })
            end
        end
    elseif command == "REND" then
        A.connected = true
        A.races, A.raceOrder = {}, {}
        for _, r in ipairs(pendingRaces or {}) do
            A.races[r.id] = r
            tinsert(A.raceOrder, r.id)
        end
        pendingRaces = nil
        A.Fire("RACES")
    elseif command == "T" then
        pendingSites = pendingSites or {}
        for _, row in ipairs(split(rest, ";")) do
            local id, map, race, finds, name = row:match("^(%d+),(%d+),(%d+),(%d+),(.*)$")
            if id then
                id = tonumber(id)
                pendingSites[id] = { id = id, map = tonumber(map), race = tonumber(race), finds = tonumber(finds), name = name, points = {} }
            end
        end
    elseif command == "G" then
        local id, points = rest:match("^(%d+):(.*)$")
        local site = id and pendingSites and pendingSites[tonumber(id)]
        if site then
            for x, y in points:gmatch("(-?%d+),(-?%d+)") do
                tinsert(site.points, tonumber(x))
                tinsert(site.points, tonumber(y))
            end
        end
    elseif command == "TEND" then
        A.connected = true
        A.sites = {}
        for id, site in pairs(pendingSites or {}) do
            local n, sx, sy = #site.points / 2, 0, 0
            for i = 1, #site.points, 2 do
                sx, sy = sx + site.points[i], sy + site.points[i + 1]
            end
            if n >= 3 then
                site.cx, site.cy = sx / n, sy / n
                A.sites[id] = site
            end
        end
        pendingSites = nil
        A.Fire("SITES")
    elseif command == "P" then
        local id, race, rare, cost, sockets, item, name = rest:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(.*)$")
        if id then
            id = tonumber(id)
            A.projects[id] = {
                id = id, race = tonumber(race), rare = rare == "1", cost = tonumber(cost), sockets = tonumber(sockets),
                item = tonumber(item), name = name, chunks = {},
            }
        end
    elseif command == "D" then
        local id, text = rest:match("^(%d+):(.*)$")
        local p = id and A.projects[tonumber(id)]
        if p and p.chunks then
            tinsert(p.chunks, text)
        end
    elseif command == "DEND" then
        local p = A.projects[tonumber(rest) or 0]
        if p then
            p.text = table.concat(p.chunks or {})
            p.chunks = nil
            p.complete = true
            A.Fire("PROJECT", p.id)
        end
    elseif command == "O" then
        A.overFind = rest == "1"
        A.Fire("OVERFIND", A.overFind)
    elseif command == "Q" then
        A.Fire("DIG", (tonumber(rest) or 0) / 1000)
    elseif command == "V" then
        local band, angle = rest:match("^(%u+):?(.*)$")
        A.Fire("SURVEY", band, tonumber(angle))
    elseif command == "F" then
        local race, gained, total = rest:match("^(%d+):(%d+):(%d+)$")
        if race then
            race, total = tonumber(race), tonumber(total)
            if A.races[race] then
                A.races[race].fragments = total
            end
            A.Fire("FRAGMENTS", race, tonumber(gained), total)
        end
    elseif command == "LN" then
        local fields = { rest:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$") }
        pendingRelic = #fields == 7 and fields or nil
    elseif command == "L" then
        local rank, ranks, power, cost, ilvl, quality, form, note = rest:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):([^:]*):(.*)$")
        if rank then
            local more = pendingRelic or {}
            pendingRelic = nil
            A.relic = {
                rank = tonumber(rank), ranks = tonumber(ranks), power = tonumber(power), cost = tonumber(cost),
                itemLevel = tonumber(ilvl), quality = tonumber(quality), form = form, note = note,
                -- From LN (nil from an older server): the item it holds, the next rank's item level,
                -- and what keeps the item below its rank (1 level, 2 progression).
                item = tonumber(more[1]), offItem = tonumber(more[2]),
                nextItemLevel = tonumber(more[3]), nextQuality = tonumber(more[4]),
                held = tonumber(more[5]), heldLevel = tonumber(more[6]), heldItemLevel = tonumber(more[7]),
            }
            A.Fire("RELIC")
        end
    elseif command == "X" then
        local project, item, rare = rest:match("^(%d+):(%d+):(%d+)$")
        if project then
            A.Fire("SOLVED", tonumber(project), tonumber(item), rare == "1")
        end
    end
end

-- Where the open map sits in the world: map id, left, top, width, height (see MapData.lua).
-- zoneOnly skips continent maps, whose player position is off for the Burning Crusade start zones.
function A.MapBounds(zoneOnly)
    if GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() > 0 then
        return nil
    end
    if GetCurrentMapZone() > 0 then
        return A.ZONES[GetMapInfo() or ""]
    end
    local continent = GetCurrentMapContinent()
    if not zoneOnly and continent and continent > 0 then
        return A.CONTINENTS[continent]
    end
end

-- World (x, y) to 0..1 coordinates on the map with these bounds.
function A.WorldToMap(bounds, x, y)
    return (bounds[2] - y) / bounds[4], (bounds[3] - x) / bounds[5]
end

function A.InPolygon(points, x, y)
    local inside, n = false, #points
    local jx, jy = points[n - 1], points[n]
    for i = 1, n, 2 do
        local ix, iy = points[i], points[i + 1]
        if ((iy > y) ~= (jy > y)) and (x < (jx - ix) * (y - iy) / (jy - iy) + ix) then
            inside = not inside
        end
        jx, jy = ix, iy
    end
    return inside
end

-- The dig site you are standing in, if any.
function A.CurrentSite()
    local pos = A.position
    if not pos.valid then
        return nil
    end
    for _, site in pairs(A.sites) do
        if site.map == pos.map and A.InPolygon(site.points, pos.x, pos.y) then
            return site
        end
    end
end

-- The player's world position comes from their spot on the zone map. With the world map closed
-- the map is kept on the player's zone; with it open, the last position stands until the player
-- looks at their own zone again.
local lastRezone = -REZONE_INTERVAL
local function updatePosition(now)
    local pos = A.position
    local bounds = A.MapBounds(true)
    local px, py = GetPlayerMapPosition("player")
    local onMap = bounds and (px > 0 or py > 0) and px <= 1 and py <= 1
    if not onMap and not WorldMapFrame:IsShown() and now - lastRezone >= REZONE_INTERVAL then
        lastRezone = now
        SetMapToCurrentZone()
        bounds = A.MapBounds(true)
        px, py = GetPlayerMapPosition("player")
        onMap = bounds and (px > 0 or py > 0) and px <= 1 and py <= 1
    end
    if onMap then
        pos.valid, pos.map = true, bounds[1]
        pos.y, pos.x = bounds[2] - px * bounds[4], bounds[3] - py * bounds[5]
    elseif not WorldMapFrame:IsShown() then
        pos.valid = false
    end
    A.Fire("POSITION")
end

local frame = CreateFrame("Frame")
local clock, nextPosition = 0, 0
frame:SetScript("OnUpdate", function(self, elapsed)
    clock = clock + elapsed
    if #queue > 0 then
        flushQueue(clock)
    end
    if clock >= nextPosition then
        nextPosition = clock + POSITION_INTERVAL
        updatePosition(clock)
    end
end)

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if prefix == PREFIX and channel == "WHISPER" and sender == UnitName("player") then
            onMessage(message)
        end
    elseif event == "PLAYER_LOGIN" then
        ArchaeologyUIDB = ArchaeologyUIDB or {}
        A.db = ArchaeologyUIDB
        A.Fire("LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not A.helloSent then
            A.helloSent = true
            A.Send("HELLO")
        end
        lastRezone = -REZONE_INTERVAL
    elseif not WorldMapFrame:IsShown() then
        -- ZONE_CHANGED*: follow the player onto the new zone's map
        SetMapToCurrentZone()
    end
end)

BINDING_HEADER_ARCHAEOLOGYUI = "ArchaeologyUI"
BINDING_NAME_ARCHAEOLOGYUI_SURVEY = "Survey / Dig"
BINDING_NAME_ARCHAEOLOGYUI_TOGGLE = "Toggle Archaeology window"
BINDING_NAME_ARCHAEOLOGYUI_MINIMAP = "Toggle dig sites on the minimap"

SLASH_ARCHAEOLOGYUI1 = "/archaeology"
SLASH_ARCHAEOLOGYUI2 = "/arch"
SlashCmdList.ARCHAEOLOGYUI = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "survey" then
        A.Survey()
    elseif msg == "dig" then
        A.Dig()
    elseif msg == "reset" then
        if A.ResetSurveyButton then
            A.ResetSurveyButton()
        end
    elseif msg == "refresh" then
        A.Send("HELLO")
    elseif msg == "minimap" then
        A.ToggleMinimap()
    elseif msg == "collection" or msg == "bonuses" then
        if A.OpenCollection then A.OpenCollection() end
    elseif msg == "options" then
        if A.OpenOptions then
            A.OpenOptions()
        end
    elseif A.ToggleWindow then
        A.ToggleWindow()
    end
end
