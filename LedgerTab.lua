local _, ns = ...

-- "Ledger" tab in Blizzard's auction house window: your own results
-- (Ledger.lua), in the Deals tab's list (ListTab.lua):
--   Sales      sold for (after the cut), cost (first in, first out), profit
--   Purchases  paid each and in all, how many are still unsold
--   Stock      what you bought and haven't sold: its cost and what it's
--              worth at today's market value (after the cut)
--   Expired    expired and cancelled auctions, with the deposit lost (an
--              estimate: the client's deposit for the sell view's duration)
-- The bottom bar sums up the last 30 days.

local LedgerTab = {}
ns.LedgerTab = LedgerTab

local DAY = 24 * 60 * 60
local SUMMARY_DAYS = 30
local GOOD, BAD = "|cff40c040", "|cffff5050"

local function Money(c) return c and ns.FormatMoney(c) or "" end
local function Signed(c)
    if not c then return "" end
    if c < 0 then return BAD .. "-" .. Money(-c) .. "|r" end
    return GOOD .. Money(c) .. "|r"
end

function LedgerTab.Ago(t)
    local s = time() - t
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. " min ago" end
    if s < DAY then return math.floor(s / 3600) .. " h ago" end
    local days = math.floor(s / DAY)
    return days .. (days == 1 and " day ago" or " days ago")
end
local Ago = LedgerTab.Ago

local function ItemID(key) return key and tonumber(key:match("^(%d+)")) end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

local function NewestFirst(list)
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

function LedgerTab.Sales()
    local out = {}
    local data = ns.Ledger.Data()
    for _, sale in ipairs(data and data.sales or {}) do
        local net, cost, profit = ns.Ledger.SaleResult(sale)
        out[#out + 1] = { key = sale.key, itemID = ItemID(sale.key), name = sale.name, t = sale.t,
                          count = sale.count, net = net, cost = sale.matched > 0 and cost or nil,
                          profit = profit, unmatched = sale.count - sale.matched, char = sale.char }
    end
    return NewestFirst(out)
end

function LedgerTab.Purchases()
    local out = {}
    local data = ns.Ledger.Data()
    for _, buy in ipairs(data and data.buys or {}) do
        out[#out + 1] = { key = buy.key, itemID = ItemID(buy.key), name = buy.name, t = buy.t,
                          count = buy.qty, each = buy.total / buy.qty, total = buy.total, left = buy.left,
                          char = buy.char }
    end
    return NewestFirst(out)
end

function LedgerTab.Stock()
    local out = {}
    local data = ns.Ledger.Data()
    local cut = ns.Strategy and ns.Strategy.AH_CUT or 0.05
    for _, buy in ipairs(data and data.buys or {}) do
        if buy.left > 0 then
            local each = buy.total / buy.qty
            local value = ns.History.Value(buy.key)
            local worth = value and value * (1 - cut) * buy.left
            local cost = each * buy.left
            out[#out + 1] = { key = buy.key, itemID = ItemID(buy.key), name = buy.name, t = buy.t,
                              count = buy.left, each = each, cost = cost, worth = worth,
                              change = worth and (worth - cost), char = buy.char }
        end
    end
    table.sort(out, function(a, b) return a.cost > b.cost end)
    return out
end

-- Deposit lost on an expired or cancelled auction: the client's deposit
-- for the sell view's selected duration (stackable items; others only with
-- one in your bags). An estimate: the real one depended on the duration
-- you posted with.
local function DepositLost(e)
    local MT = ns.MarketTab
    if not (e.key and MT and MT.DepositPerUnit and MT.Duration) then return end
    local ok, perUnit = pcall(MT.DepositPerUnit, e.key, (MT.Duration()))
    if ok and perUnit then return perUnit * e.count end
end

function LedgerTab.Expired()
    local out = {}
    local data = ns.Ledger.Data()
    for _, e in ipairs(data and data.expired or {}) do
        out[#out + 1] = { key = e.key, itemID = ItemID(e.key), name = e.name, t = e.t, count = e.count,
                          kind = e.kind, deposit = DepositLost(e), char = e.char }
    end
    return NewestFirst(out)
end

------------------------------------------------------------------------
-- Columns
------------------------------------------------------------------------

local COLUMNS = {
    sales = {
        { "Count", 50, "RIGHT", function(r) return r.count end, "count" },
        { "Sold for", 120, "RIGHT", function(r) return Money(r.net) end, "net" },
        { "Cost", 110, "RIGHT", function(r) return r.cost and Money(r.cost) or "---" end, "cost" },
        { "Profit", 110, "RIGHT", function(r) return r.profit and Signed(r.profit) or "---" end, "profit" },
        { "When", 70, "RIGHT", function(r) return Ago(r.t) end, "t" },
    },
    purchases = {
        { "Count", 50, "RIGHT", function(r) return r.count end, "count" },
        { "Paid each", 120, "RIGHT", function(r) return Money(r.each) end, "each" },
        { "Paid", 110, "RIGHT", function(r) return Money(r.total) end, "total" },
        { "Unsold", 110, "RIGHT", function(r) return r.left end, "left" },
        { "When", 70, "RIGHT", function(r) return Ago(r.t) end, "t" },
    },
    stock = {
        { "Count", 50, "RIGHT", function(r) return r.count end, "count" },
        { "Cost each", 120, "RIGHT", function(r) return Money(r.each) end, "each" },
        { "Cost", 110, "RIGHT", function(r) return Money(r.cost) end, "cost" },
        { "Worth now", 110, "RIGHT", function(r) return r.worth and Money(r.worth) or "---" end, "worth" },
        { "Bought", 70, "RIGHT", function(r) return Ago(r.t) end, "t" },
    },
    expired = {
        { "Count", 50, "RIGHT", function(r) return r.count end, "count" },
        { "Deposit lost", 120, "RIGHT", function(r) return r.deposit and ("~" .. Money(r.deposit)) or "---" end, "deposit" },
        { "Outcome", 110, "RIGHT", function(r) return r.kind == "cancelled" and "Cancelled" or "Expired" end, "kind" },
        { "", 110, "RIGHT", function() return "" end },
        { "When", 70, "RIGHT", function(r) return Ago(r.t) end, "t" },
    },
}

local TYPES = {
    { "sales", "Sales", LedgerTab.Sales },
    { "purchases", "Purchases", LedgerTab.Purchases },
    { "stock", "Unsold stock", LedgerTab.Stock },
    { "expired", "Expired", LedgerTab.Expired },
}

local EMPTY = {
    sales = "No sales recorded yet. Sales are read from the \"Auction successful\" mails when you open your mailbox.",
    purchases = "No purchases recorded yet. Everything you buy in the auction house from now on is listed here.",
    stock = "Nothing bought and still unsold.",
    expired = "No expired or cancelled auctions. They're read from their mails when you open your mailbox.",
}

------------------------------------------------------------------------
-- Summary and tooltip
------------------------------------------------------------------------

function LedgerTab.Summary(now)
    local t = ns.Ledger.Totals((now or time()) - SUMMARY_DAYS * DAY)
    local text = ("Last %d days: sold %s after the cut (%d %s), profit %s, spent %s (%d %s)."):format(
        SUMMARY_DAYS, Money(t.sold), t.sales, t.sales == 1 and "sale" or "sales", Signed(t.profit),
        Money(t.spent), t.buys, t.buys == 1 and "purchase" or "purchases")
    if t.stockUnits > 0 then text = text .. (" Unsold: %s at cost."):format(Money(t.stock)) end
    return text
end

local function Tooltip(r, typeID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(date("%Y-%m-%d %H:%M", r.t) .. (r.char and (", " .. r.char) or ""), 1, 1, 1)
    if typeID == "sales" and r.unmatched and r.unmatched > 0 then
        GameTooltip:AddLine(("No purchase recorded for %d of %d: no cost or profit for them."):format(
            r.unmatched, r.count), .8, .8, .8, true)
    elseif typeID == "stock" and r.change then
        GameTooltip:AddLine(("Worth vs. cost: %s"):format(Signed(r.change)), 1, 1, 1)
    elseif typeID == "expired" then
        GameTooltip:AddLine("The deposit is an estimate: the deposit for the sell view's duration.", .8, .8, .8, true)
    end
end

------------------------------------------------------------------------
-- The tab
------------------------------------------------------------------------

local tab = ns.NewListTab({
    id = "Ledger", text = "Ledger", panelName = "ForgedForeverAHLedgerPanel",
    types = TYPES, columns = COLUMNS, summary = LedgerTab.Summary,
    emptyText = function(t) return EMPTY[t] end,
    countText = function(n) return n .. (n == 1 and " entry" or " entries") end,
    onClick = function(r) if r.key and ns.StrategyTab then ns.StrategyTab.OpenInBuyView(r) end end,
    tooltip = Tooltip,
})

LedgerTab.Refresh = tab.Refresh
LedgerTab.SetType = tab.SetType
LedgerTab.Panel = tab.Panel

ns:Listen("LEDGER_CHANGED", function()
    C_Timer.After(0.1, LedgerTab.Refresh)
end)
