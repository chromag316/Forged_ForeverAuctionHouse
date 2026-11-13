local _, ns = ...

-- Strategy engine
--
-- Turns market data (Market.lua, price history) into suggestions:
--
--   resale      Buy items listed well below market value, relist at market
--               value. Profit after the 5% auction house cut. Ranked by
--               expected profit per day (profit per item x estimated sales per
--               day, capped by the quantity listed); slow movers are skipped.
--   vendor      Items listed below what a vendor pays for them.
--   disenchant  Gear listed below its expected disenchant value (materials
--               sold on the auction house, minus the 5% cut).
--   sell        Items in your bags: suggested price just under the current
--               lowest listing (or the market value if none), expected proceeds
--               after the cut, and whether the market is high or rising.
--
-- The deposit is refunded when an auction sells, so it isn't counted as a
-- cost here; it's only lost on listings that don't sell.
--
-- The Deals tab (StrategyTab.lua) shows them; /fah strategy [type] prints
-- the top suggestions in chat.

local Strategy = {}
ns.Strategy = Strategy

local AH_CUT = 0.05
local MIN_RESALE_ROI = 0.10      -- resale: at least 10% return on the buy price
local MIN_SALES_PER_DAY = 0.5    -- resale: at least one sale every two days
local HIGH_MARKET = 1.10         -- sell: lowest listing at 110%+ of value
local RISING_TREND = 5           -- sell: 24 h average price up 5%+

Strategy.AH_CUT = AH_CUT

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local function ItemID(key)
    return tonumber(key:match("^(%d+)"))
end

local function Net(price)
    return price * (1 - AH_CUT)
end

------------------------------------------------------------------------
-- Suggestions; each returns a list sorted best first
------------------------------------------------------------------------

-- { key, itemID, buy, sell, profit, roi, salesPerDay, quantity, score }
function Strategy.Resale()
    local out = {}
    for _, key in ipairs(ns.Market.Keys()) do
        local s = ns.Market.Stats(key)
        if s.listed and s.price and s.value and s.salesPerDay and s.salesPerDay >= MIN_SALES_PER_DAY then
            local profit = Net(s.value) - s.price
            local roi = profit / s.price
            if profit > 0 and roi >= MIN_RESALE_ROI then
                out[#out + 1] = {
                    key = key, itemID = ItemID(key), buy = s.price, sell = s.value,
                    profit = profit, roi = roi, salesPerDay = s.salesPerDay, quantity = s.quantity,
                    score = profit * math.min(s.salesPerDay, s.quantity or 0),
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.score > b.score end)
    return out
end

-- { key, itemID, buy, vendor, profit, roi, quantity }
function Strategy.Vendor()
    local out = {}
    for _, key in ipairs(ns.Market.Keys()) do
        local s = ns.Market.Stats(key)
        local itemID = ItemID(key)
        local vendor = s.listed and s.price and select(11, GetItemInfo(itemID))
        if vendor and vendor > s.price then
            out[#out + 1] = {
                key = key, itemID = itemID, buy = s.price, vendor = vendor,
                profit = vendor - s.price, roi = (vendor - s.price) / s.price, quantity = s.quantity,
            }
        end
    end
    table.sort(out, function(a, b) return a.profit > b.profit end)
    return out
end

-- { key, itemID, buy, disenchant, profit, roi }
function Strategy.Disenchant()
    local out = {}
    for _, key in ipairs(ns.Market.Keys()) do
        local s = ns.Market.Stats(key)
        if s.listed and s.price then
            local itemID = ItemID(key)
            local _, _, quality, itemLevel, _, _, _, _, equipLoc = GetItemInfo(itemID)
            local value = equipLoc and ns.Disenchant.Value(equipLoc, quality, itemLevel, itemID)
            if value then
                local profit = Net(value) - s.price
                if profit > 0 then
                    out[#out + 1] = {
                        key = key, itemID = itemID, buy = s.price, disenchant = value,
                        profit = profit, roi = profit / s.price,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.profit > b.profit end)
    return out
end

-- Your auctionable bag items: { key, itemID, count, link, bag, slot }
-- (bag/slot: where the first stack is, for opening the sell view)
local function BagItems()
    local groups, order = {}, {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isBound then
                local key = ns.History.KeyFromLink(info.hyperlink)
                if key then
                    local g = groups[key]
                    if not g then
                        g = { key = key, itemID = info.itemID or ItemID(key), count = 0, link = info.hyperlink,
                              bag = bag, slot = slot }
                        groups[key] = g
                        order[#order + 1] = g
                    end
                    g.count = g.count + (info.stackCount or 1)
                end
            end
        end
    end
    return order
end
Strategy.BagItems = BagItems

-- Where an item with this key is in your bags now: bag, slot (the given
-- slot if it still holds it, else the first match), or nil.
function Strategy.FindInBags(key, bag, slot)
    local function holds(b, sl)
        local link = C_Container.GetContainerItemLink(b, sl)
        return link and ns.History.KeyFromLink(link) == key
    end
    if bag and slot and holds(bag, slot) then return bag, slot end
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for b = 0, lastBag do
        for sl = 1, C_Container.GetContainerNumSlots(b) or 0 do
            if holds(b, sl) then return b, sl end
        end
    end
end

-- { key, itemID, link, count, bag, slot, price, proceeds, high, rising, value }
function Strategy.Sell()
    local out = {}
    for _, item in ipairs(BagItems()) do
        local s = ns.Market.Stats(item.key)
        local price
        if s.listed and s.price then
            price = math.max(1, s.price - 1) -- just under the lowest listing
        elseif s.value then
            price = math.floor(s.value)
        end
        if price then
            out[#out + 1] = {
                key = item.key, itemID = item.itemID, link = item.link, count = item.count,
                bag = item.bag, slot = item.slot,
                price = price, proceeds = Net(price) * item.count, value = s.value,
                high = s.value and s.listed and s.price and s.price >= s.value * HIGH_MARKET or false,
                rising = s.trend and s.trend >= RISING_TREND or false,
            }
        end
    end
    table.sort(out, function(a, b) return a.proceeds > b.proceeds end)
    return out
end

------------------------------------------------------------------------
-- /fah strategy [resale|vendor|disenchant|sell]
------------------------------------------------------------------------

local SHOW = 5

local function Name(itemID, link)
    return link or select(2, GetItemInfo(itemID)) or ("item:" .. itemID)
end

local function Pct(x)
    return math.floor(x * 100 + .5) .. "%"
end

local LINES = {
    resale = function(r)
        return ("%s: buy %s, sell %s, +%s each (%s), ~%.1f sold/day"):format(Name(r.itemID),
            ns.FormatMoney(r.buy), ns.FormatMoney(r.sell), ns.FormatMoney(r.profit), Pct(r.roi), r.salesPerDay)
    end,
    vendor = function(r)
        return ("%s: buy %s, vendor pays %s, +%s each, %d listed"):format(Name(r.itemID),
            ns.FormatMoney(r.buy), ns.FormatMoney(r.vendor), ns.FormatMoney(r.profit), r.quantity or 0)
    end,
    disenchant = function(r)
        return ("%s: buy %s, disenchant %s, +%s (%s)"):format(Name(r.itemID),
            ns.FormatMoney(r.buy), ns.FormatMoney(r.disenchant), ns.FormatMoney(r.profit), Pct(r.roi))
    end,
    sell = function(r)
        local note = (r.high and " high" or "") .. (r.rising and " rising" or "")
        return ("%s x%d: post at %s, ~%s after cut%s"):format(Name(r.itemID, r.link), r.count,
            ns.FormatMoney(r.price), ns.FormatMoney(r.proceeds), note ~= "" and (" -" .. note) or "")
    end,
}

local SOURCES = {
    { "resale", "Resale", Strategy.Resale },
    { "vendor", "Vendor", Strategy.Vendor },
    { "disenchant", "Disenchant", Strategy.Disenchant },
    { "sell", "Sell from bags", Strategy.Sell },
}

ns:RegisterCommand("strategy", "[resale|vendor|disenchant|sell] - top suggestions", function(args)
    args = args:lower()
    local any = false
    for _, source in ipairs(SOURCES) do
        if args == "" or args == source[1] then
            any = true
            local list = source[3]()
            ns:Print(("%s (%d):"):format(source[2], #list))
            for i = 1, math.min(SHOW, #list) do
                ns:Print("  " .. LINES[source[1]](list[i]))
            end
        end
    end
    if not any then
        ns:Print("Usage: /fah strategy [resale|vendor|disenchant|sell]")
    end
end)
