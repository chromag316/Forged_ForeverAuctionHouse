local _, ns = ...

-- Order book: an item's listings by price, from its exact search
--
-- An item's search (Blizzard's buy view, or the Market tab's own request)
-- lists every auction of it. This keeps them as price levels, cheapest
-- first, for the session only (live data, not saved):
--
--   book = { t = time, levels = { { price, quantity }, ... },
--            loaded = quantity in the levels, total = quantity listed,
--            complete = all results loaded, commodity = true/false }
--
-- Prices are per unit (buyouts; bid-only auctions can't be bought out and
-- are left out). Gear: only the item level whose price the lists use (as
-- Market.Check).
--
-- From a book: the cost to buy N, the units listed below market value and
-- what buying them costs, and the "wall": the first price level with a
-- large share of the quantity, where a new listing would end up.
--
-- OrderBook.Request(key) sends the search (C_AuctionHouse.SendSearchQuery,
-- what Blizzard's buy view sends; not a restricted call), waiting for the
-- server's rate limit. The internal message ORDER_BOOK(key) says a book
-- changed.

local OrderBook = {}
ns.OrderBook = OrderBook

local FRESH = 60          -- seconds a book counts as current (no new request)
local WALL_SHARE = 0.10   -- a wall holds at least 10% of the listed quantity
local WALL_MIN = 20       -- and at least 20 units
local THROTTLE_POLL = 0.5
local TIMEOUT = 15        -- seconds to wait for the search's results

local books = {}          -- [key] = book
local failed = {}         -- [key] = time a request got no answer
local pending             -- { key, itemKey, gen } while a request waits or runs
local gen = 0

function OrderBook.Get(key)
    return books[key]
end

------------------------------------------------------------------------
-- Statistics (pure; `book` as above)
------------------------------------------------------------------------

-- Cost of the cheapest `n` units: total, average unit price; nil and the
-- quantity available if fewer than `n` are loaded.
function OrderBook.CostToBuy(book, n)
    local total, left = 0, n
    for _, level in ipairs(book and book.levels or {}) do
        local take = math.min(left, level[2])
        total, left = total + take * level[1], left - take
        if left == 0 then return total, total / n end
    end
    return nil, n - left
end

-- Units listed below `value` and what buying all of them costs.
function OrderBook.BelowValue(book, value)
    local quantity, cost = 0, 0
    if not value then return quantity, cost end
    for _, level in ipairs(book and book.levels or {}) do
        if level[1] >= value then break end
        quantity, cost = quantity + level[2], cost + level[1] * level[2]
    end
    return quantity, cost
end

-- The first price level with a large share of the quantity: price,
-- quantity; nil if there's none (too little listed).
function OrderBook.Wall(book)
    if not book or not book.loaded or book.loaded < WALL_MIN then return end
    local need = math.max(WALL_MIN, book.loaded * WALL_SHARE)
    for _, level in ipairs(book.levels) do
        if level[2] >= need then return level[1], level[2] end
    end
end

------------------------------------------------------------------------
-- Collecting from search results
------------------------------------------------------------------------

-- entries: list of { unitPrice, quantity }
local function Levels(entries)
    local byPrice, levels, loaded = {}, {}, 0
    for _, e in ipairs(entries) do
        local price, quantity = e[1], e[2]
        if price and price > 0 and quantity and quantity > 0 then
            if byPrice[price] then
                byPrice[price][2] = byPrice[price][2] + quantity
            else
                byPrice[price] = { price, quantity }
                levels[#levels + 1] = byPrice[price]
            end
            loaded = loaded + quantity
        end
    end
    table.sort(levels, function(a, b) return a[1] < b[1] end)
    return levels, loaded
end
OrderBook.Levels = Levels

local function Store(key, entries, total, complete, commodity)
    if not key then return end
    local levels, loaded = Levels(entries)
    books[key] = {
        t = time(), levels = levels, loaded = loaded,
        total = math.max(total or 0, loaded), complete = complete and true or false,
        commodity = commodity,
    }
    if pending and pending.key == key then pending = nil end
    failed[key] = nil
    ns:Fire("ORDER_BOOK", key)
end

local function OnCommodity(itemID)
    if not itemID then return end
    local entries = {}
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if r then entries[#entries + 1] = { r.unitPrice, r.quantity } end
    end
    local complete = C_AuctionHouse.HasFullCommoditySearchResults(itemID)
    if #entries == 0 and not complete then return end -- nothing yet
    Store(itemID .. ":0", entries, C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID), complete, true)
end

local function OnItem(itemKey)
    if not itemKey then return end
    local key = ns.History.KeyFromItemKey(itemKey)
    local data = ns.Market.Data()
    local item = data and key and data.items[key]
    local level = itemKey.itemLevel
    if item and level and level > 0 and item.lvl and item.lvl > 0 and level ~= item.lvl then return end
    local entries = {}
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 then
            local quantity = math.max(1, r.quantity or 1)
            entries[#entries + 1] = { math.ceil(r.buyoutAmount / quantity), quantity }
        end
    end
    local complete = C_AuctionHouse.HasFullItemSearchResults(itemKey)
    if #entries == 0 and not complete then return end
    Store(key, entries, C_AuctionHouse.GetItemSearchResultsQuantity(itemKey), complete, false)
end

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodity)
ns:On("COMMODITY_SEARCH_RESULTS_ADDED", OnCommodity)
ns:On("ITEM_SEARCH_RESULTS_UPDATED", OnItem)
ns:On("ITEM_SEARCH_RESULTS_ADDED", OnItem)

ns:On("AUCTION_HOUSE_CLOSED", function()
    pending = nil
end)

------------------------------------------------------------------------
-- Requesting
------------------------------------------------------------------------

local function Sorts()
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    return { { sortOrder = order, reverseSort = false } }
end

local function TrySend(g)
    if not pending or pending.gen ~= g or pending.sent then return end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        pending = nil
        return
    end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        C_Timer.After(THROTTLE_POLL, function() TrySend(g) end)
        return
    end
    pending.sent = true
    C_AuctionHouse.SendSearchQuery(pending.itemKey, Sorts(), true)
    -- No answer: give up, so the view doesn't wait forever.
    C_Timer.After(TIMEOUT, function()
        if pending and pending.gen == g then
            local key = pending.key
            pending = nil
            failed[key] = time()
            ns:Fire("ORDER_BOOK", key)
        end
    end)
end

-- Asks the server for the item's listings (unless its book is current).
-- Returns the state: "current", "loading", "scanning" (a scan is running;
-- try again after it) or nil (can't: no item key / auction house closed).
function OrderBook.Request(key)
    local book = books[key]
    if book and time() - book.t < FRESH then return "current" end
    if pending and pending.key == key then return "loading" end
    if failed[key] and time() - failed[key] < FRESH then return "failed" end
    if ns.FullScan and ns.FullScan.IsScanning() then return "scanning" end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    local itemKey = ns.Market.ItemKey(key)
    if not itemKey then return end
    gen = gen + 1
    pending = { key = key, itemKey = itemKey, gen = gen }
    TrySend(gen)
    return "loading"
end

function OrderBook.IsLoading(key)
    return pending ~= nil and pending.key == key
end

function OrderBook.Failed(key)
    return failed[key] ~= nil and books[key] == nil
end
