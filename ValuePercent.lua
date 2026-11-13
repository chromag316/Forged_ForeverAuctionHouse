local _, ns = ...

-- % of market value in Blizzard's auction lists
--
-- Shows each price as a percentage of its market value (price history),
-- colored like aux: blue < 50%, green < 80%, yellow < 110%, orange < 135%,
-- red above.
--   Browse results  min price      text in the left part of the Price cell
--   Commodity list  unit price     text right of the unit price
--   Item list       buyout / qty   text right of the buyout price
--
-- How: Blizzard's lists are ScrollBoxes whose rows are (re)initialized as
-- you scroll. After Blizzard fills a row, we read its rowData and set our
-- own font string on the row. Blizzard's functions and layouts are never
-- replaced, so its buy buttons stay untainted.
--
-- Toggle with /fah percent.

local History = ns.History

ns.DEFAULTS.percent = true

local NONE = ""

-- Browse row's % of market value as a number (nil if unknown); used by the
-- experimental % column (PercentColumn.lua) for display and sorting.
function ns.BrowsePercent(rowData)
    if type(rowData) ~= "table" or not rowData.itemKey or (rowData.totalQuantity or 0) == 0 then return end
    local price = rowData.minPrice
    local value = History.Value(History.KeyFromItemKey(rowData.itemKey))
    if not price or price <= 0 or not value or value <= 0 then return end
    return price / value * 100
end

local function PercentText(price, value)
    if not price or price <= 0 or not value or value <= 0 then return NONE end
    local pct = math.floor(price / value * 100 + .5)
    local color = pct < 50 and "2992ff" or pct < 80 and "16ff16" or pct < 110 and "ffff00"
        or pct < 135 and "ff9218" or "ff0000"
    return ("|cff%s%s%%|r"):format(color, pct > 9999 and ">9999" or pct)
end
ns.PercentText = PercentText

-- The row's child cell drawn by the given Blizzard cell mixin (cells get the
-- mixin's functions copied in, so the Populate function identifies them).
local function FindCell(row, mixin)
    if not mixin or not mixin.Populate then return end
    for _, child in ipairs({ row:GetChildren() }) do
        if child.Populate == mixin.Populate then return child end
    end
end

local function GetLabel(row)
    if not row.fahPercent then
        row.fahPercent = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
    return row.fahPercent
end

local function Hide(row)
    if row.fahPercent then row.fahPercent:Hide() end
end

------------------------------------------------------------------------
-- Per list: price, value and where the text goes
------------------------------------------------------------------------

-- Browse results (BrowseResultInfo): minPrice per item key.
local function BrowseRow(row, rowData)
    -- The experimental % column shows it instead.
    if ns.PercentColumnActive and ns.PercentColumnActive() then return Hide(row) end
    if not rowData.itemKey or (rowData.totalQuantity or 0) == 0 then return Hide(row) end
    local cell = FindCell(row, AuctionHouseTableCellMinPriceMixin)
    if not cell then return Hide(row) end
    local label = GetLabel(row)
    label:ClearAllPoints()
    label:SetPoint("LEFT", cell, "LEFT", 4, 0)
    label:SetText(PercentText(rowData.minPrice, History.Value(History.KeyFromItemKey(rowData.itemKey))))
    label:Show()
end

-- In the commodity and item lists the % goes right after the price, in a
-- fixed-width, right-aligned box (so the numbers line up), in the same font
-- as the quantity ("Available") numbers.
local AFTER_PRICE_GAP = 4
local AFTER_PRICE_WIDTH = 50

-- Font of the row's quantity cell, else Blizzard's price font.
local function QuantityFont(row)
    local mixin = AuctionHouseTableCellCommoditiesQuantityMixin
    local cell = mixin and FindCell(row, mixin)
    if cell and cell.Text and cell.Text.GetFontObject then
        local font = cell.Text:GetFontObject()
        if font then return font end
    end
    return _G.PriceFontWhite
end

-- Anchored to the price itself (the cell's MoneyDisplay, like Blizzard's
-- "yours" checkmark), not the cell: the cell is much wider than the price,
-- so its right edge is next to the quantity column.
local function PlaceAfterPrice(row, label, cell)
    local price = cell.MoneyDisplay or cell
    label:ClearAllPoints()
    label:SetPoint("LEFT", price, "RIGHT", AFTER_PRICE_GAP, 0)
    label:SetWidth(AFTER_PRICE_WIDTH)
    label:SetJustifyH("RIGHT")
    local font = QuantityFont(row)
    if font then label:SetFontObject(font) end
end

-- Commodity auctions (CommoditySearchResultInfo): unitPrice.
local function CommodityRow(row, rowData)
    if not rowData.itemID or not rowData.unitPrice then return Hide(row) end
    local cell = FindCell(row, AuctionHouseTableCellUnitPriceMixin)
    if not cell then return Hide(row) end
    local label = GetLabel(row)
    PlaceAfterPrice(row, label, cell)
    label:SetText(PercentText(rowData.unitPrice, History.Value(rowData.itemID .. ":0")))
    label:Show()
end

-- Item auctions (ItemSearchResultInfo): buyout per item.
local function ItemRow(row, rowData)
    if not rowData.itemKey or not rowData.buyoutAmount then return Hide(row) end
    local cell = FindCell(row, AuctionHouseTableCellBuyoutMixin)
    if not cell then return Hide(row) end
    local unitPrice = rowData.buyoutAmount / math.max(1, rowData.quantity or 1)
    local label = GetLabel(row)
    PlaceAfterPrice(row, label, cell)
    label:SetText(PercentText(unitPrice, History.Value(History.KeyFromItemKey(rowData.itemKey))))
    label:Show()
end

------------------------------------------------------------------------
-- Hooking the lists' rows
------------------------------------------------------------------------

local function RowData(row)
    if row.GetRowData then return row:GetRowData() end
    return row.rowData
end

local function Watch(itemList, update)
    local scrollBox = itemList and itemList.ScrollBox
    if not scrollBox then return end
    -- Counters for /fah percent debug.
    local stats = { calls = 0, noData = 0, shown = 0, hidden = 0, errors = 0 }
    itemList.fahStats = stats
    local function OnRow(_, row)
        stats.calls = stats.calls + 1
        if not ns.db or not ns.db.percent then return Hide(row) end
        local rowData = RowData(row)
        if type(rowData) ~= "table" then
            stats.noData = stats.noData + 1
            return Hide(row)
        end
        local ok, err = pcall(update, row, rowData)
        if not ok then
            stats.errors = stats.errors + 1
            Hide(row)
            geterrorhandler()(err)
        elseif row.fahPercent and row.fahPercent:IsShown() then
            stats.shown = stats.shown + 1
        else
            stats.hidden = stats.hidden + 1
        end
    end
    -- Callbacks get (frame, elementData) or (owner, frame, elementData);
    -- the row is whichever argument is a frame.
    --
    -- Our callback runs before Blizzard's table builder fills the row (it
    -- registers its own callback later), so the row has no rowData yet, or a
    -- reused row still has the previous entry's. So: hide our text now and
    -- fill it in on the next frame, if the row still shows the same entry.
    local function OnCallback(a, b, c)
        local row, elementData
        if type(a) == "table" and a.GetObjectType then
            row, elementData = a, b
        else
            row, elementData = b, c
        end
        if type(row) ~= "table" or not row.GetObjectType then return end
        Hide(row)
        C_Timer.After(0, function()
            if row.GetElementData and elementData ~= nil and row:GetElementData() ~= elementData then return end
            if not row:IsShown() then return end
            OnRow(nil, row)
        end)
    end
    -- Don't iterate existing rows here: when Blizzard's UI has just loaded the
    -- scroll box has no view yet (it's set up when the list is first shown),
    -- and ForEachFrame errors without one.
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(scrollBox, OnCallback, ns, false)
        stats.hook = "ScrollUtil.AddInitializedFrameCallback"
    elseif ScrollBoxListMixin and ScrollBoxListMixin.Event and scrollBox.RegisterCallback then
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, OnCallback, ns)
        stats.hook = "OnInitializedFrame"
    else
        stats.hook = "none"
    end
    -- Visible rows are already filled, so redraw them right away.
    itemList.fahRefresh = function()
        local hasView = scrollBox.GetView and scrollBox:GetView()
        if hasView and scrollBox.ForEachFrame then
            scrollBox:ForEachFrame(function(row) OnRow(nil, row) end)
        end
    end
end

local lists = {}

ns:Listen("AUCTION_UI_LOADED", function(frame)
    local browse = frame.BrowseResultsFrame and frame.BrowseResultsFrame.ItemList
    local commodities = frame.CommoditiesBuyFrame and frame.CommoditiesBuyFrame.ItemList
    local items = frame.ItemBuyFrame and frame.ItemBuyFrame.ItemList
    -- Each list on its own, so a problem with one doesn't stop the others.
    for _, entry in ipairs({ { browse, BrowseRow }, { commodities, CommodityRow }, { items, ItemRow } }) do
        local ok, err = pcall(Watch, entry[1], entry[2])
        if not ok then geterrorhandler()(err) end
    end
    lists = { browse, commodities, items }
end)

-- Redraws the visible rows (after toggling).
local function RefreshAll()
    for _, list in pairs(lists) do
        if list.fahRefresh then list.fahRefresh() end
    end
end

-- /fah percent debug: what the hook sees in the browse results list.
local function Debug()
    local frame = AuctionHouseFrame
    local list = frame and frame.BrowseResultsFrame and frame.BrowseResultsFrame.ItemList
    ns:Print(("debug: AuctionHouseFrame=%s, browse ItemList=%s, ScrollBox=%s, enabled=%s"):format(
        tostring(frame ~= nil), tostring(list ~= nil), tostring(list and list.ScrollBox ~= nil), tostring(ns.db.percent)))
    if not list or not list.ScrollBox then return end
    local s = list.fahStats
    if s then
        ns:Print(("hook=%s calls=%d noRowData=%d shown=%d hidden=%d errors=%d"):format(
            tostring(s.hook), s.calls, s.noData, s.shown, s.hidden, s.errors))
    else
        ns:Print("hook not installed on the browse list")
    end
    local scrollBox = list.ScrollBox
    if not (scrollBox.GetView and scrollBox:GetView()) then
        ns:Print("list has no view yet - search first, then run this again")
        return
    end
    local first
    scrollBox:ForEachFrame(function(row) first = first or row end)
    if not first then
        ns:Print("no visible rows")
        return
    end
    local rowData = RowData(first)
    ns:Print(("first row: type=%s rowData=%s GetRowData=%s"):format(
        first:GetObjectType(), type(rowData), tostring(first.GetRowData ~= nil)))
    if type(rowData) == "table" then
        local key = History.KeyFromItemKey(rowData.itemKey)
        ns:Print(("  itemKey=%s minPrice=%s totalQuantity=%s value=%s"):format(
            tostring(key), tostring(rowData.minPrice), tostring(rowData.totalQuantity), tostring(History.Value(key))))
    end
    for i, child in ipairs({ first:GetChildren() }) do
        local match = child.Populate == AuctionHouseTableCellMinPriceMixin.Populate and " <- MinPrice cell" or ""
        ns:Print(("  child %d: %s Populate=%s MoneyDisplay=%s%s"):format(
            i, child:GetObjectType(), tostring(child.Populate ~= nil), tostring(child.MoneyDisplay ~= nil), match))
    end
    if first.fahPercent then
        ns:Print(("  our text: shown=%s text=%s"):format(tostring(first.fahPercent:IsShown()), tostring(first.fahPercent:GetText())))
    else
        ns:Print("  our text: never created on this row")
    end
end

ns:RegisterCommand("percent", "[column|debug] - toggle % of market value in the auction lists", function(args)
    if args:lower() == "debug" then
        Debug()
        return
    end
    if args:lower() == "column" then
        ns.PercentColumn.Toggle()
        return
    end
    ns.db.percent = not ns.db.percent
    ns:Print("% of market value in the auction lists: " .. (ns.db.percent and "|cff16ff16on|r" or "|cffff0000off|r"))
    RefreshAll()
end)
