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
            local seen = current.seen[key]
            if seen then
                seen.p = math.min(seen.p, price)
                seen.q = seen.q + quantity
            else
                current.seen[key] = { p = price, q = quantity }
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
    end
    if complete then
        for key, item in pairs(data.items) do
            local last = item.s[#item.s]
            if not seen[key] and last and last[3] > 0 then
                AddSnapshot(item, t, nil, 0)
            end
        end
        table.insert(data.scans, t)
    end
end

ns:Listen("SCAN_FINISHED", function(outcome)
    if not current then return end
    local c = current
    current = nil
    Market.Store(c.started, c.seen, outcome == "done")
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
--   price, quantity  -- now (last snapshot), quantity 0 if gone
--   listed           -- quantity > 0 in the last snapshot
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

-- All item keys with market data.
function Market.Keys()
    local keys = {}
    for key in pairs(data and data.items or {}) do keys[#keys + 1] = key end
    return keys
end
