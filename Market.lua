local _, ns = ...

-- Market data for the strategy engine
--
-- During every scan (auto or Full Scan) the lowest price and quantity
-- available of each item in the browse results are collected. When the
-- scan ends they're stored as snapshots; a snapshot is only added when
-- price or quantity changed since the item's last one. After a completed
-- scan, items that were listed before but are gone now get a quantity 0
-- snapshot (sold out, expired or cancelled).
--
-- Snapshots older than 3 days are folded into daily summaries, kept for
-- 30 days. Stored per realm and faction:
--
--   ForgedForeverAuctionHouseDB.market["Realm|Faction"] = {
--     scans = { time, ... },            -- completed scans (last 3 days)
--     items = { ["itemID:suffix"] = {
--         s = { { t, price, quantity }, ... },  -- snapshots, oldest first
--         lvl = itemLevel,                      -- for the item key (gear)
--         ik = { itemID, itemLevel, itemSuffix, ... }, -- cheapest variant's item key
--         n = name, nq = quality, nk = true?    -- item name (see Item names)
--         d = { { day, min, max, avgQty, sold }, ... }, -- daily summaries
--     } },
--   }
--
-- Market.Stats(key) turns that into: current price/quantity, market value,
-- estimated sales per day, price trend and volatility.

local Market = {}
ns.Market = Market

local DAY = 24 * 60 * 60
local DETAIL_DAYS = 3
local SUMMARY_DAYS = 30

ns.DEFAULTS.market = {}

local data -- this realm/faction's market table

ns:Listen("LOGIN", function()
    local key = ns.RealmFactionKey()
    ns.db.market[key] = ns.db.market[key] or { scans = {}, items = {} }
    data = ns.db.market[key]
    data.scans = data.scans or {}
    data.items = data.items or {}
    Market.Prune()
end)

function Market.Data()
    return data
end

------------------------------------------------------------------------
-- Collecting during a scan
------------------------------------------------------------------------

local current -- { started = time, seen = { [key] = { p, q } } } while a scan runs

local function Collect(results)
    if not current then return end
    for _, r in ipairs(results or {}) do
        local key = ns.History.KeyFromItemKey(r.itemKey)
        local price, quantity = r.minPrice, r.totalQuantity or 0
        if key and price and price > 0 and quantity > 0 then
            -- Several item levels can share a key: lowest price, summed quantity.
            -- The cheapest one's item level is kept to rebuild its item key.
            local level = r.itemKey.itemLevel or 0
            local seen = current.seen[key]
            if seen then
                if price < seen.p then seen.p, seen.lvl, seen.ik = price, level, r.itemKey end
                seen.q = seen.q + quantity
            else
                current.seen[key] = { p = price, q = quantity, lvl = level, ik = r.itemKey }
            end
        end
    end
end

ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if current then
        current.seen = {} -- a scan's first page replaces the list
        Collect(C_AuctionHouse.GetBrowseResults())
    end
end)

ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
    Collect(added)
end)

ns:Listen("SCAN_STARTED", function()
    current = { started = time(), seen = {} }
end)

local function AddSnapshot(item, t, price, quantity)
    local last = item.s[#item.s]
    if last and last[2] == price and last[3] == quantity then return end
    item.s[#item.s + 1] = { t, price, quantity }
end

-- Stores what the scan saw. `complete`: the scan covered the whole house,
-- so listed items it didn't see are now gone (quantity 0).
function Market.Store(t, seen, complete)
    if not data then return end
    for key, v in pairs(seen) do
        local item = data.items[key]
        if not item then
            item = { s = {}, d = {} }
            data.items[key] = item
        end
        AddSnapshot(item, t, v.p, v.q)
        if v.lvl and v.lvl > 0 then item.lvl = v.lvl end
        if type(v.ik) == "table" then
            -- The cheapest variant's item key, as Blizzard gave it (plain
            -- values only, for the saved variables).
            local ik = {}
            for k, val in pairs(v.ik) do
                if type(val) == "number" or type(val) == "string" or type(val) == "boolean" then ik[k] = val end
            end
            item.ik = ik
        end
        item.chk = nil -- the scan is newer than any checked price
    end
    if complete then
        for key, item in pairs(data.items) do
            local last = item.s[#item.s]
            if not seen[key] and last and last[3] > 0 then
                AddSnapshot(item, t, nil, 0)
            end
            if item.chk and item.chk[1] <= t then item.chk = nil end
        end
        table.insert(data.scans, t)
    end
end

------------------------------------------------------------------------
-- Checked prices: an item's exact search (opening it in Blizzard's buy
-- view, from the Deals list or anywhere) gives its real lowest price and
-- quantity right now. Stored as item.chk = { time, price, quantity } and
-- used as the current price until the next scan sees the item. Not a
-- snapshot: the sales, trend and volatility figures stay scan-only (an
-- item search can cover one item level of several).
------------------------------------------------------------------------

function Market.Check(key, price, quantity, level)
    local item = data and key and data.items[key]
    if not item then return end -- only items a scan has seen
    -- Gear: only the item level whose price the lists use.
    if level and level > 0 and item.lvl and item.lvl > 0 and level ~= item.lvl then return end
    if not price then quantity = 0 end
    item.chk = { time(), price, quantity or 0 }
end

local function CheckCommodity(itemID)
    if not itemID then return end
    local lowest
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.unitPrice > 0 and (not lowest or r.unitPrice < lowest) then lowest = r.unitPrice end
    end
    -- No results yet isn't "sold out" until the server says the list is complete.
    if not lowest and not C_AuctionHouse.HasFullCommoditySearchResults(itemID) then return end
    Market.Check(itemID .. ":0", lowest, C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID))
end

local function CheckItem(itemKey)
    if not itemKey then return end
    local lowest
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 then
            local unit = math.ceil(r.buyoutAmount / math.max(1, r.quantity or 1))
            if not lowest or unit < lowest then lowest = unit end
        end
    end
    if not lowest and not C_AuctionHouse.HasFullItemSearchResults(itemKey) then return end
    Market.Check(ns.History.KeyFromItemKey(itemKey), lowest,
        C_AuctionHouse.GetItemSearchResultsQuantity(itemKey), itemKey.itemLevel)
end

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", CheckCommodity)
ns:On("COMMODITY_SEARCH_RESULTS_ADDED", CheckCommodity)
ns:On("ITEM_SEARCH_RESULTS_UPDATED", CheckItem)
ns:On("ITEM_SEARCH_RESULTS_ADDED", CheckItem)

ns:Listen("SCAN_FINISHED", function(outcome)
    if not current then return end
    local c = current
    current = nil
    Market.Store(c.started, c.seen, outcome == "done")
    Market.LearnNames()
end)

------------------------------------------------------------------------
-- Retention: detail for 3 days, daily summaries for 30
------------------------------------------------------------------------

local function DayOf(t)
    return math.floor(t / DAY)
end

-- Folds a day's snapshots into one summary.
local function Summarize(day, snaps)
    local min, max, qtySum, n, sold = nil, nil, 0, 0, 0
    local prevQ
    for _, s in ipairs(snaps) do
        local p, q = s[2], s[3]
        if p then
            min = min and math.min(min, p) or p
            max = max and math.max(max, p) or p
        end
        qtySum, n = qtySum + q, n + 1
        if prevQ and q < prevQ then sold = sold + (prevQ - q) end
        prevQ = q
    end
    return { day, min, max, n > 0 and qtySum / n or 0, sold }
end

function Market.Prune(now)
    if not data then return end
    now = now or time()
    local detailCutoff = now - DETAIL_DAYS * DAY
    local summaryCutoff = DayOf(now) - SUMMARY_DAYS
    for key, item in pairs(data.items) do
        -- Fold old snapshots, by day, into summaries.
        local keep, byDay, days = {}, {}, {}
        for _, s in ipairs(item.s) do
            if s[1] < detailCutoff then
                local day = DayOf(s[1])
                if not byDay[day] then
                    byDay[day] = {}
                    days[#days + 1] = day
                end
                table.insert(byDay[day], s)
            else
                keep[#keep + 1] = s
            end
        end
        -- Keep the last old snapshot as the starting point of the detail.
        if #days > 0 then
            local lastDay = byDay[days[#days]]
            table.insert(keep, 1, lastDay[#lastDay])
        end
        item.s = keep
        for _, day in ipairs(days) do
            local merged = false
            for _, d in ipairs(item.d) do
                if d[1] == day then merged = true end
            end
            if not merged then table.insert(item.d, Summarize(day, byDay[day])) end
        end
        table.sort(item.d, function(a, b) return a[1] < b[1] end)
        while item.d[1] and item.d[1][1] < summaryCutoff do table.remove(item.d, 1) end
        -- Drop items with nothing recent left: no summaries, and the last
        -- snapshot either says "gone" and is past the detail window, or is
        -- older than the summary window.
        local last = item.s[#item.s]
        if #item.d == 0 and (not last
            or (last[3] == 0 and last[1] < detailCutoff)
            or last[1] < now - SUMMARY_DAYS * DAY) then
            data.items[key] = nil
        end
    end
    local scans = {}
    for _, t in ipairs(data.scans) do
        if t >= detailCutoff then scans[#scans + 1] = t end
    end
    data.scans = scans
end

------------------------------------------------------------------------
-- Statistics
------------------------------------------------------------------------

-- Time of the last completed scan, or nil.
function Market.LastScan()
    return data and data.scans[#data.scans]
end

-- {
--   price, quantity  -- now (checked price or last snapshot), quantity 0 if gone
--   listed           -- quantity > 0 now
--   priceTime        -- when that price was confirmed; checked = from an item search
--   value, today     -- market value / today's minimum (price history)
--   salesPerDay      -- estimated from quantity drops (nil: too little data)
--   trend            -- % change: last 24 h average vs. the 48 h before (nil if unknown)
--   volatility       -- price std. deviation / mean over the detail window
--   days             -- days of data (detail + summaries)
-- }
function Market.Stats(key, now)
    now = now or time()
    local stats = {
        value = ns.History.Value(key),
        today = ns.History.MarketValue(key),
    }
    local item = data and data.items[key]
    if not item or #item.s == 0 then return stats end

    local last = item.s[#item.s]
    stats.price, stats.quantity = last[2], last[3]
    stats.listed = last[3] > 0
    -- When the price was last confirmed: a checked price (item search), else
    -- the last snapshot or the last complete scan, which saw every item
    -- (snapshots are only stored on change).
    local lastScan = data.scans[#data.scans]
    stats.priceTime = math.max(last[1], lastScan or 0)
    if item.chk then
        stats.price, stats.quantity = item.chk[2], item.chk[3]
        stats.listed = item.chk[3] > 0 and item.chk[2] ~= nil
        stats.priceTime, stats.checked = item.chk[1], true
    end

    -- Sales: quantity drops between snapshots, plus daily summaries' sales.
    local sold, prevQ = 0, nil
    local first = item.s[1][1]
    for _, s in ipairs(item.s) do
        if prevQ and s[3] < prevQ then sold = sold + (prevQ - s[3]) end
        prevQ = s[3]
    end
    local span = (now - first) / DAY
    for _, d in ipairs(item.d) do
        sold = sold + (d[5] or 0)
    end
    span = span + #item.d
    stats.days = span
    if span >= 0.25 then stats.salesPerDay = sold / span end

    -- Trend and volatility from prices in the detail window.
    local recent, older, all = {}, {}, {}
    for _, s in ipairs(item.s) do
        if s[2] then
            all[#all + 1] = s[2]
            if s[1] >= now - DAY then
                recent[#recent + 1] = s[2]
            elseif s[1] >= now - 3 * DAY then
                older[#older + 1] = s[2]
            end
        end
    end
    local function mean(list)
        local sum = 0
        for _, v in ipairs(list) do sum = sum + v end
        return #list > 0 and sum / #list or nil
    end
    local mRecent, mOlder, mAll = mean(recent), mean(older), mean(all)
    if mRecent and mOlder and mOlder > 0 then
        stats.trend = (mRecent - mOlder) / mOlder * 100
    end
    if mAll and mAll > 0 and #all > 1 then
        local var = 0
        for _, v in ipairs(all) do var = var + (v - mAll) ^ 2 end
        stats.volatility = math.sqrt(var / #all) / mAll
    end
    return stats
end

-- Per-day series for the Market tab's graph, oldest first, one entry per day
-- for the last `days` days (today last):
--   { day, min, max, sold }  -- min/max nil on days without a listing
-- Days older than the detail window come from the daily summaries. Detail
-- days are built from snapshots; since a snapshot is only stored on change,
-- the price before a day's first change carries over from the day before
-- (while the item is listed).
function Market.DailySeries(key, days, now)
    now = now or time()
    days = days or SUMMARY_DAYS
    local today = DayOf(now)
    local first = today - days + 1
    local series = {}
    for i = 1, days do
        series[i] = { day = first + i - 1, sold = 0 }
    end
    local function entry(day)
        local i = day - first + 1
        return series[i]
    end
    local function widen(e, price)
        if not e or not price then return end
        e.min = e.min and math.min(e.min, price) or price
        e.max = e.max and math.max(e.max, price) or price
    end

    local item = data and data.items[key]
    if not item then return series end

    for _, d in ipairs(item.d) do
        local e = entry(d[1])
        if e then
            e.min, e.max, e.sold = d[2], d[3], d[5] or 0
        end
    end

    -- Snapshots: carry the listed price through days without changes.
    local prev -- previous snapshot
    for _, s in ipairs(item.s) do
        local day = DayOf(s[1])
        if prev and prev[3] > 0 and prev[2] then
            -- The previous price was active from its day until this change.
            for d = math.max(DayOf(prev[1]), first), math.min(day, today) do
                widen(entry(d), prev[2])
            end
        end
        if s[2] and s[3] > 0 then widen(entry(day), s[2]) end
        if prev and s[3] < prev[3] then
            local e = entry(day)
            if e then e.sold = e.sold + (prev[3] - s[3]) end
        end
        prev = s
    end
    -- The last price stays active until today (if still listed).
    if prev and prev[3] > 0 and prev[2] then
        for d = math.max(DayOf(prev[1]), first), today do widen(entry(d), prev[2]) end
    end
    return series
end

-- The auction house ItemKey for a history key ("itemID:suffix"), with the
-- item level last seen in a scan (gear's item keys include it).
-- Preferably an exact copy of the item key Blizzard's browse results gave
-- for the item's cheapest variant (item.ik, stored by scans), so it has all
-- the fields Forever's keys have; else rebuilt with MakeItemKey. Suffix IDs
-- can be negative.
function Market.ItemKey(key)
    local item = data and data.items[key]
    local itemID, suffix = key:match("^(%d+):(%-?%d+)$")
    itemID, suffix = tonumber(itemID), tonumber(suffix) or 0
    if not itemID then return end
    local level = item and item.lvl or 0
    if item and type(item.ik) == "table" then
        local copy = {}
        for k, v in pairs(item.ik) do copy[k] = v end
        copy.itemID = copy.itemID or itemID
        copy.itemLevel = copy.itemLevel or level
        copy.itemSuffix = copy.itemSuffix or suffix
        return copy
    end
    return C_AuctionHouse.MakeItemKey(itemID, level, suffix)
end

------------------------------------------------------------------------
-- Item names
------------------------------------------------------------------------
-- C_Item.GetItemInfo returns nothing until the client has loaded the item
-- from the server (the call starts the load). Names are stored with the
-- market data (item.n, quality item.nq) so lists and the Market tab's
-- search have them right away, also for items not loaded this session.
--
-- Items with a random suffix ("of the Eagle", "of the Boar", ...) share an
-- item ID, and C_Item.GetItemInfo(itemID) only knows the base name. Their
-- full name comes from the auction house's item key info, as in Blizzard's
-- lists; it's stored with item.nk = true, and a base name is never stored
-- (or returned) for them.
--
-- Missing names are requested after each scan and at login, and stored when
-- GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT / ITEM_KEY_ITEM_INFO_RECEIVED
-- arrives; the internal message ITEM_NAMES then tells the lists to redraw
-- (throttled).

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local waiting = {} -- [itemID] = true: requested, name not stored yet

local function Suffixed(key)
    return not key:match(":0$")
end
Market.Suffixed = Suffixed

-- name, quality, or nil (for suffixed items only the full name)
function Market.Name(key)
    local item = data and data.items[key]
    if item and item.n and (item.nk or not Suffixed(key)) then return item.n, item.nq end
end

-- fromKeyInfo: the name is the auction house's item key info name (full,
-- with the suffix).
function Market.SetName(key, name, quality, fromKeyInfo)
    local item = data and data.items[key]
    if not (item and name and name ~= "") then return end
    if Suffixed(key) and not fromKeyInfo then return end
    item.n, item.nq, item.nk = name, quality, fromKeyInfo or nil
end

-- Tries to store a key's name; true if it has one.
local function Learn(key, item)
    if Market.Name(key) then return true end
    local itemID = tonumber(key:match("^(%d+)"))
    if not itemID then return true end
    if Suffixed(key) then
        local itemKey = Market.ItemKey(key)
        local info = itemKey and C_AuctionHouse.GetItemKeyInfo(itemKey) -- also requests it
        if info and info.itemName then
            Market.SetName(key, info.itemName, info.quality, true)
            return true
        end
    else
        local name, _, quality = GetItemInfo(itemID) -- also requests the load
        if name then
            Market.SetName(key, name, quality)
            return true
        end
    end
    waiting[itemID] = true
end

-- Stores every loaded name; requests the rest.
function Market.LearnNames()
    if not data then return end
    for key, item in pairs(data.items) do Learn(key, item) end
end

local namesPending = false
local function NameArrived(itemID)
    if not (itemID and waiting[itemID] and data) then return end
    waiting[itemID] = nil
    local prefix = itemID .. ":"
    local learned = false
    for key, item in pairs(data.items) do
        if key:sub(1, #prefix) == prefix and not Market.Name(key) then
            learned = Learn(key, item) or learned -- re-adds waiting if still missing
        end
    end
    if learned and not namesPending then
        namesPending = true
        C_Timer.After(0.3, function()
            namesPending = false
            ns:Fire("ITEM_NAMES")
        end)
    end
end
ns:On("GET_ITEM_INFO_RECEIVED", NameArrived)
ns:On("ITEM_DATA_LOAD_RESULT", NameArrived)
ns:On("ITEM_KEY_ITEM_INFO_RECEIVED", NameArrived)

ns:Listen("LOGIN", function()
    C_Timer.After(5, Market.LearnNames)
end)

-- All item keys with market data.
function Market.Keys()
    local keys = {}
    for key in pairs(data and data.items or {}) do keys[#keys + 1] = key end
    return keys
end

------------------------------------------------------------------------
-- /fah itemkey <item ID or link>: debug for item names. For each tracked
-- variant of the item: its key, stored item key and name, and what the
-- auction house's item key info says; then the same for Blizzard's current
-- browse results of that item (search for it on the Buy tab first).
------------------------------------------------------------------------

local function Fields(t)
    if type(t) ~= "table" then return tostring(t) end
    local parts = {}
    for k, v in pairs(t) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function KeyInfoName(itemKey)
    local info = itemKey and C_AuctionHouse.GetItemKeyInfo(itemKey)
    return info and tostring(info.itemName) or "(not loaded)"
end

ns:RegisterCommand("itemkey", "<item ID or link> - debug: item keys and names of an item", function(args)
    local itemID = tonumber(args:match("item:(%d+)") or args:match("^%s*(%d+)"))
    if not itemID then
        ns:Print("Usage: /fah itemkey <item ID or shift-click an item>")
        return
    end
    local prefix = itemID .. ":"
    local any = false
    for key, item in pairs(data and data.items or {}) do
        if key:sub(1, #prefix) == prefix then
            any = true
            local itemKey = Market.ItemKey(key)
            ns:Print(("%s: stored name %s%s, lvl %s, stored key %s"):format(key, tostring(item.n),
                item.nk and " (full)" or "", tostring(item.lvl), Fields(item.ik)))
            ns:Print(("    key used %s -> %s"):format(Fields(itemKey), KeyInfoName(itemKey)))
        end
    end
    if not any then ns:Print("No tracked variants of item " .. itemID .. ".") end
    local browse = 0
    for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        if r.itemKey and r.itemKey.itemID == itemID then
            browse = browse + 1
            ns:Print(("  browse result %s -> %s"):format(Fields(r.itemKey), KeyInfoName(r.itemKey)))
        end
    end
    if browse == 0 then ns:Print("  (not in Blizzard's current browse results)") end
end)
