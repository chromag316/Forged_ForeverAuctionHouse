local _, ns = ...

-- "Deals" tab in Blizzard's auction house window
-- (the strategy engine's suggestions; the tab was called "Strategy" before)
--
-- A "Deals" tab after Blizzard's Buy/Sell/Auctions tabs. Its panel shows
-- a market summary and the strategy engine's suggestions (Strategy.lua):
-- Resale, Vendor, Disenchant and Sell from bags. The list itself is
-- ListTab.lua's; the tab is added by Tabs.lua (LibAHTab's taint-free
-- approach).

local StrategyTab = {}
ns.StrategyTab = StrategyTab

local TAB_ID = "Strategy"
local TAB_TEXT = "Deals"

------------------------------------------------------------------------
-- Columns per suggestion type
------------------------------------------------------------------------

local function Money(c) return c and ns.FormatMoney(c) or "" end
local function Pct(x) return x and (math.floor(x * 100 + .5) .. "%") or "" end

-- Each column: { title, width, justify, text = function(row), sort field }
-- (the field of the suggestion its header sorts by; none: not sortable)
local COLUMNS = {
    resale = {
        { "Buy at", 110, "RIGHT", function(r) return Money(r.buy) end, "buy" },
        { "Sell at", 110, "RIGHT", function(r) return Money(r.sell) end, "sell" },
        { "Profit each", 110, "RIGHT", function(r) return Money(r.profit) end, "profit" },
        { "Return", 60, "RIGHT", function(r) return Pct(r.roi) end, "roi" },
        { "Sold/day", 70, "RIGHT", function(r) return ("%.1f"):format(r.salesPerDay or 0) end, "salesPerDay" },
    },
    vendor = {
        { "Buy at", 110, "RIGHT", function(r) return Money(r.buy) end, "buy" },
        { "Vendor pays", 110, "RIGHT", function(r) return Money(r.vendor) end, "vendor" },
        { "Profit each", 110, "RIGHT", function(r) return Money(r.profit) end, "profit" },
        { "Return", 60, "RIGHT", function(r) return Pct(r.roi) end, "roi" },
        { "Listed", 70, "RIGHT", function(r) return r.quantity or "" end, "quantity" },
    },
    disenchant = {
        { "Buy at", 110, "RIGHT", function(r) return Money(r.buy) end, "buy" },
        { "Disenchant", 110, "RIGHT", function(r) return Money(r.disenchant) end, "disenchant" },
        { "Profit", 110, "RIGHT", function(r) return Money(r.profit) end, "profit" },
        { "Return", 60, "RIGHT", function(r) return Pct(r.roi) end, "roi" },
        { "", 70, "RIGHT", function() return "" end },
    },
    sell = {
        { "Count", 50, "RIGHT", function(r) return r.count end, "count" },
        { "Post at", 110, "RIGHT", function(r) return Money(r.price) end, "price" },
        { "Proceeds", 120, "RIGHT", function(r) return Money(r.proceeds) end, "proceeds" },
        { "Market", 110, "RIGHT", function(r) return Money(r.value) end, "value" },
        { "", 70, "RIGHT", function(r)
            local notes = {}
            if r.high then notes[#notes + 1] = "high" end
            if r.rising then notes[#notes + 1] = "rising" end
            return table.concat(notes, ", ")
        end },
    },
}

local TYPES = {
    { "resale", "Resale", function() return ns.Strategy.Resale() end },
    { "vendor", "Vendor", function() return ns.Strategy.Vendor() end },
    { "disenchant", "Disenchant", function() return ns.Strategy.Disenchant() end },
    { "sell", "Sell from bags", function() return ns.Strategy.Sell() end },
}

------------------------------------------------------------------------
-- Summary, tooltip
------------------------------------------------------------------------

local function Ago(t)
    if not t then return "never" end
    local s = time() - t
    if s < 60 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " days ago"
end
StrategyTab.Ago = Ago

local function Summary()
    local tracked, listed, withSales = 0, 0, 0
    for _, key in ipairs(ns.Market.Keys()) do
        tracked = tracked + 1
        local s = ns.Market.Stats(key)
        if s.listed then listed = listed + 1 end
        if s.salesPerDay then withSales = withSales + 1 end
    end
    local Count = ns.FullScan and ns.FullScan.Count or tostring
    return ("Market: %s items tracked, %s listed, %s with sales data. Last full scan: %s."):format(
        Count(tracked), Count(listed), Count(withSales), Ago(ns.Market.LastScan()))
end

-- How old the row's price is: checked when you opened the item, else from
-- a scan.
local function Tooltip(r)
    local s = r.key and ns.Market.Stats(r.key)
    if s and s.priceTime then
        GameTooltip:AddLine((s.checked and "Price checked %s" or "Price from scan %s"):format(Ago(s.priceTime)),
            1, 1, 1)
    end
end

------------------------------------------------------------------------
-- Opening an item in Blizzard's views
------------------------------------------------------------------------

-- Clicking a row opens Blizzard's buy view for the item, the same as
-- clicking it in Blizzard's Buy list: AuctionHouseFrame:SelectBrowseResult
-- with a browse-style result (item key + lowest price). It picks the
-- commodity or item buy view and switches the display mode, which also
-- hides this panel (Tabs.lua). Confirmed in game: buying from the opened
-- view works.
function StrategyTab.OpenInBuyView(r)
    local frame = AuctionHouseFrame
    if not frame or not frame.SelectBrowseResult or not r.key then return end
    local itemKey = ns.Market.ItemKey(r.key)
    if not itemKey then return end
    -- Blizzard's function needs the item key's info; it's nil until loaded
    -- (this call also requests it).
    if not C_AuctionHouse.GetItemKeyInfo(itemKey) then
        ns:Print("Item info is still loading; click the row again in a moment.")
        return
    end
    local price = r.buy or ns.Market.Stats(r.key).price or 0
    PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    frame:SelectBrowseResult({ itemKey = itemKey, minPrice = price, totalQuantity = 0 })
end

-- Sell from bags rows open Blizzard's sell view with the item in it, the
-- same as right-clicking it in your bags at the auction house:
-- AuctionHouseFrame:SetPostItem(itemLocation), which picks the item or
-- commodity sell view.
function StrategyTab.OpenInSellView(r)
    local frame = AuctionHouseFrame
    if not frame or not frame.SetPostItem or not r.key then return end
    local bag, slot = ns.Strategy.FindInBags(r.key, r.bag, r.slot)
    if not bag then
        ns:Print("That item isn't in your bags anymore.")
        return
    end
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    frame:SetPostItem(location)
end

------------------------------------------------------------------------
-- The tab
------------------------------------------------------------------------

local tab = ns.NewListTab({
    id = TAB_ID, text = TAB_TEXT, panelName = "ForgedForeverAHStrategyPanel",
    types = TYPES, columns = COLUMNS, summary = Summary,
    emptyText = function(t)
        return t == "sell" and "Nothing in your bags with a market price yet."
            or "No suggestions yet. They need price history and a few scans spread over at least 6 hours."
    end,
    countText = function(n)
        local Count = ns.FullScan and ns.FullScan.Count or tostring
        return Count(n) .. (n == 1 and " suggestion" or " suggestions")
    end,
    onClick = function(r, t)
        if t == "sell" then StrategyTab.OpenInSellView(r) else StrategyTab.OpenInBuyView(r) end
    end,
    tooltip = Tooltip,
})

StrategyTab.Refresh = tab.Refresh
StrategyTab.SetType = tab.SetType
StrategyTab.SortBy = tab.SortBy
StrategyTab.SortResults = tab.SortResults
StrategyTab.RedrawNames = tab.RedrawNames
StrategyTab.Select = function(...) return tab.Select(...) end

------------------------------------------------------------------------
-- /fah layout debug: what the Deals list copied from Blizzard's list, and
-- every visible frame/texture of the auction house window in the bottom
-- strip right of the money display.
------------------------------------------------------------------------

local function FrameLabel(obj, frame)
    local name = obj.GetName and obj:GetName()
    if name then return name end
    for key, value in pairs(frame) do
        if value == obj then return "AuctionHouseFrame." .. tostring(key) end
    end
    local parent = obj.GetParent and obj:GetParent()
    if parent and parent ~= frame then
        for key, value in pairs(parent) do
            if value == obj then return (parent.GetName and parent:GetName() or "?") .. "." .. tostring(key) end
        end
    end
    return tostring(obj.GetObjectType and obj:GetObjectType() or "?")
end

function StrategyTab.LayoutDebug()
    local frame = AuctionHouseFrame
    local panel = tab.Panel()
    if not frame or not panel then
        ns:Print("Open the auction house first.")
        return
    end
    local info = panel.layoutInfo or {}
    ns:Print(("layout: source=%s, background gaps=%s, border gaps=%s"):format(
        tostring(info.source), tostring(info.bg), tostring(info.border)))
    local bottom, left = frame:GetBottom(), frame:GetLeft()
    local money = frame.MoneyFrameBorder
    local stripLeft = money and money.GetRight and money:GetRight() or (left and left + 170)
    if not bottom or not stripLeft then return end
    local function Check(obj, depth)
        if not obj.IsVisible or not obj:IsVisible() then return end
        local l, b, w, h = obj:GetRect()
        if l and b and b < bottom + 30 and b + h > bottom and l + w > stripLeft + 10 then
            ns:Print(("  %s%s: left %.0f, bottom %.0f, %.0fx%.0f"):format(string.rep("  ", depth),
                FrameLabel(obj, frame), l - left, b - bottom, w, h))
        end
    end
    ns:Print("visible in the bottom strip (offsets from the window's bottom left):")
    for _, child in ipairs({ frame:GetChildren() }) do
        Check(child, 0)
        if child.IsVisible and child:IsVisible() then
            for _, sub in ipairs({ child:GetChildren() }) do Check(sub, 1) end
        end
    end
    for _, region in ipairs({ frame:GetRegions() }) do Check(region, 0) end
end

ns:RegisterCommand("layout", "debug - show what the Deals list copies from Blizzard's", function()
    StrategyTab.LayoutDebug()
end)

-- New scan data: redraw if open.
ns:Listen("SCAN_FINISHED", function()
    C_Timer.After(0.1, StrategyTab.Refresh)
end)
ns:On("BAG_UPDATE_DELAYED", function()
    if tab.Type() == "sell" then StrategyTab.Refresh() end
end)
