local addonName, ns = ...

-- Forged Forever Auction House
-- Adds features from Forged Auction House (aux for 1.12) to Blizzard's own
-- auction house window on the WoW Forever client. Features are added one at
-- a time, each in its own file listed in the .toc after this one.

ns.name = addonName

------------------------------------------------------------------------
-- Chat output
------------------------------------------------------------------------

local PREFIX = "|cfff07d30<Forged AH>|r"

function ns:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    print(PREFIX .. " " .. table.concat(parts, " "))
end

-- Money as gold/silver/copper with coin icons ("---" for nil).
function ns.FormatMoney(copper)
    if not copper then return "---" end
    copper = math.floor(copper + .5)
    if GetMoneyString then return GetMoneyString(copper, true) end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

------------------------------------------------------------------------
-- Slash commands: /fah <command> [args]
------------------------------------------------------------------------

local commands, commandOrder = {}, {}

-- fn(args) gets the rest of the line after the command word.
function ns:RegisterCommand(name, usage, fn)
    commands[name] = { usage = usage, fn = fn }
    table.insert(commandOrder, name)
end

SLASH_FORGEDFOREVERAH1 = "/fah"
SlashCmdList.FORGEDFOREVERAH = function(input)
    local name, args = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local command = commands[(name or ""):lower()]
    if command then
        command.fn(args)
        return
    end
    ns:Print("commands:")
    for _, n in ipairs(commandOrder) do
        ns:Print("  /fah " .. n .. " " .. commands[n].usage)
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

-- ns:On("EVENT", fn): fn receives the event's payload.
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Internal messages between feature files.
local listeners = {}

function ns:Listen(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
    for _, fn in ipairs(listeners[message] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------

-- Features add their own defaults to ns.DEFAULTS before ADDON_LOADED.
ns.DEFAULTS = { version = 3 }

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = type(v) == "table" and ApplyDefaults({}, v) or v
        elseif type(v) == "table" and type(target[k]) == "table" then
            ApplyDefaults(target[k], v)
        end
    end
    return target
end

------------------------------------------------------------------------
-- Blizzard auction house UI
------------------------------------------------------------------------

-- Blizzard_AuctionHouseUI is load-on-demand: it loads the first time the
-- auction house opens. "AUCTION_UI_LOADED" fires once it exists, so features
-- can hook AuctionHouseFrame. Hook with hooksecurefunc / HookScript only;
-- replacing Blizzard functions or showing/hiding its panels taints them.
local auctionUILoaded = false

local function OnAuctionUILoaded()
    if auctionUILoaded or not AuctionHouseFrame then return end
    auctionUILoaded = true
    ns:Fire("AUCTION_UI_LOADED", AuctionHouseFrame)
end

function ns:IsAuctionUILoaded()
    return auctionUILoaded
end

-- "Realm|Faction": auction data is kept per realm and faction, as in aux.
-- Only valid after PLAYER_LOGIN.
function ns.RealmFactionKey()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
    return realm .. "|" .. (UnitFactionGroup("player") or "Neutral")
end

ns:On("PLAYER_LOGIN", function()
    ns:Fire("LOGIN")
end)

ns:On("ADDON_LOADED", function(name)
    if name == addonName then
        ForgedForeverAuctionHouseDB = ApplyDefaults(ForgedForeverAuctionHouseDB or {}, ns.DEFAULTS)
        ns.db = ForgedForeverAuctionHouseDB
        ns:Fire("DB_READY", ns.db)
        -- In case Blizzard's UI loaded before us (e.g. after /reload at the AH).
        if C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
            OnAuctionUILoaded()
        end
    elseif name == "Blizzard_AuctionHouseUI" then
        OnAuctionUILoaded()
    end
end)
