local _, ns = ...

-- Price history (same model as aux)
--
-- * daily_min_buyout: the lowest unit buyout seen today.
-- * At midnight, today's minimum becomes a data point (up to 11 are kept).
-- * Value = weighted median of the data points, each weighted .99^(days older
--   than the newest). With no data points yet, it is today's minimum.
--
-- Prices are recorded passively from the searches Blizzard's auction house
-- window makes: browse results (lowest price per item), and item / commodity
-- searches (individual auctions). Nothing is queried by this file.
--
-- Stored per realm and faction in ForgedForeverAuctionHouseDB.history:
--   history["Realm|Faction"]["itemID:suffix"] =
--       { next_push = time, daily_min_buyout = copper?, data_points = { {value, time}, ... } }

local History = {}
ns.History = History

local MAX_DATA_POINTS = 11
local DAY = 60 * 60 * 24

ns.DEFAULTS.history = {}

local valueCache = {}
local data -- this realm/faction's records, set at login

ns:Listen("LOGIN", function()
    local key = ns.RealmFactionKey()
    ns.db.history[key] = ns.db.history[key] or {}
    data = ns.db.history[key]
end)

------------------------------------------------------------------------
-- Item keys
------------------------------------------------------------------------

-- History key "itemID:suffix" from an auction house ItemKey table.
function History.KeyFromItemKey(itemKey)
    if not itemKey or not itemKey.itemID then return end
    return itemKey.itemID .. ":" .. (itemKey.itemSuffix or 0)
end

-- History key from an item link or item string:
-- item:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:...
function History.KeyFromLink(link)
    if type(link) ~= "string" then return end
    local itemString = link:match("item:([%-%d:]*)")
    if not itemString then return end
    local fields = {}
    for field in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    local itemID = tonumber(fields[1] or "")
    if not itemID then return end
    return itemID .. ":" .. (tonumber(fields[7] or "") or 0)
end

------------------------------------------------------------------------
-- Records
------------------------------------------------------------------------

local nextPush = 0
local function NextPush()
    if time() > nextPush then
        local d = date("*t")
        d.hour, d.min, d.sec = 24, 0, 0
        nextPush = time(d)
    end
    return nextPush
end

local function PushRecord(record)
    if record.daily_min_buyout then
        table.insert(record.data_points, 1, { value = record.daily_min_buyout, time = record.next_push })
        while #record.data_points > MAX_DATA_POINTS do
            table.remove(record.data_points)
        end
    end
    record.next_push, record.daily_min_buyout = NextPush(), nil
end

-- The record for `key`, rolled over to today. Created only if `create`.
local function ReadRecord(key, create)
    if not data or not key then return end
    local record = data[key]
    if not record then
        if not create then return end
        record = { next_push = NextPush(), data_points = {} }
        data[key] = record
    end
    if record.next_push <= time() then
        PushRecord(record)
        valueCache[key] = nil
    end
    return record
end

local function WeightedMedian(list)
    table.sort(list, function(a, b) return a.value < b.value end)
    local weight = 0
    for _, entry in ipairs(list) do
        weight = weight + entry.weight
        if weight >= .5 then return entry.value end
    end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

-- Records a unit buyout price seen for an item.
function History.Observe(key, unitPrice)
    if not key or not unitPrice or unitPrice <= 0 then return end
    local record = ReadRecord(key, true)
    if record and unitPrice < (record.daily_min_buyout or math.huge) then
        record.daily_min_buyout = unitPrice
        valueCache[key] = nil
    end
end

-- Historical value (copper per unit), or nil if never seen.
function History.Value(key)
    local cached = valueCache[key]
    if cached and cached.next_push > time() then return cached.value end
    local record = ReadRecord(key, false)
    if not record then return end
    local value
    local points = record.data_points
    if #points > 0 then
        local total, weighted = 0, {}
        for _, point in ipairs(points) do
            local weight = .99 ^ math.floor((points[1].time - point.time) / DAY + .5)
            total = total + weight
            weighted[#weighted + 1] = { value = point.value, weight = weight }
        end
        for _, entry in ipairs(weighted) do entry.weight = entry.weight / total end
        value = WeightedMedian(weighted)
    else
        value = record.daily_min_buyout
    end
    valueCache[key] = { value = value, next_push = record.next_push }
    return value
end

-- Today's lowest unit buyout, or nil.
function History.MarketValue(key)
    local record = ReadRecord(key, false)
    return record and record.daily_min_buyout
end

function History.DataPoints(key)
    local record = ReadRecord(key, false)
    return record and record.data_points or {}
end

function History.Count()
    local n = 0
    for _ in pairs(data or {}) do n = n + 1 end
    return n
end

function History.Clear()
    if data then wipe(data) end
    wipe(valueCache)
end

------------------------------------------------------------------------
-- Recording from Blizzard's searches
------------------------------------------------------------------------

local function ObserveBrowseResults(results)
    for _, result in ipairs(results or {}) do
        History.Observe(History.KeyFromItemKey(result.itemKey), result.minPrice)
    end
end

-- A new browse search (first page): the full list so far.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    ObserveBrowseResults(C_AuctionHouse.GetBrowseResults())
end)

-- Further pages: only the added rows.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(addedResults)
    ObserveBrowseResults(addedResults)
end)

local function ObserveCommodity(itemID)
    local lowest
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if result and result.unitPrice and (not lowest or result.unitPrice < lowest) then
            lowest = result.unitPrice
        end
    end
    History.Observe(itemID .. ":0", lowest)
end

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", ObserveCommodity)
ns:On("COMMODITY_SEARCH_RESULTS_ADDED", ObserveCommodity)

local function ObserveItem(itemKey)
    local lowest
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if result and result.buyoutAmount and result.buyoutAmount > 0 then
            local unit = math.ceil(result.buyoutAmount / math.max(1, result.quantity or 1))
            if not lowest or unit < lowest then lowest = unit end
        end
    end
    History.Observe(History.KeyFromItemKey(itemKey), lowest)
end

ns:On("ITEM_SEARCH_RESULTS_UPDATED", ObserveItem)
ns:On("ITEM_SEARCH_RESULTS_ADDED", ObserveItem)

------------------------------------------------------------------------
-- /fah value <item>, /fah history [clear]
------------------------------------------------------------------------

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

ns:RegisterCommand("value", "<item link or ID> - show recorded prices", function(args)
    local key = History.KeyFromLink(args)
    if not key and tonumber(args) then key = tonumber(args) .. ":0" end
    if not key then
        ns:Print("Usage: /fah value <shift-click an item, or an item ID>")
        return
    end
    local itemID = tonumber(key:match("^(%d+)"))
    local name = (args:find("|H") and args) or GetItemInfo(itemID) or ("item " .. itemID)
    local points = History.DataPoints(key)
    ns:Print(("%s  value: %s  today: %s  (%d days of history)"):format(
        name, ns.FormatMoney(History.Value(key)), ns.FormatMoney(History.MarketValue(key)), #points))
end)

ns:RegisterCommand("history", "[clear] - number of items recorded, or clear them", function(args)
    if args:lower() == "clear" then
        History.Clear()
        ns:Print("Price history cleared for " .. ns.RealmFactionKey() .. ".")
    else
        ns:Print(("%d items recorded for %s."):format(History.Count(), ns.RealmFactionKey()))
    end
end)
