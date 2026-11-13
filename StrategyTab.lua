local _, ns = ...

-- "Deals" tab in Blizzard's auction house window
-- (the strategy engine's suggestions; the tab was called "Strategy" before)
--
-- A "Deals" tab after Blizzard's Buy/Sell/Auctions tabs. Its panel shows
-- a market summary and the strategy engine's suggestions (Strategy.lua):
-- Resale, Vendor, Disenchant and Sell from bags.
--
-- The tab itself is added by Tabs.lua (LibAHTab's taint-free approach).

local StrategyTab = {}
ns.StrategyTab = StrategyTab

local TAB_ID = "Strategy"
local TAB_TEXT = "Deals"
local ROW_HEIGHT = 20     -- Blizzard's list rows
-- The list's left edge from the window's left (Blizzard's Auctions view starts
-- its lists 4 px in: AuctionsFrame at 5, SummaryList at -1).
local LIST_LEFT = 4
-- List background: the Post Auctions list's (ItemSellList backgroundAtlas).
local BACKGROUND_ATLAS = "auctionhouse-background-sell-right"
local HEADER_HEIGHT = 19  -- Blizzard's header buttons
local HEADER_OVERLAP = 2
-- Type tabs: first tab's top-left from the auction house window's top-left
-- (Blizzard's Auctions sub-tab: AuctionsFrame at (5, -42), tab at (47, -1)).
local TYPE_TAB_X, TYPE_TAB_Y = 52, -43
local TYPE_TAB_GAP = 5

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

local panel, tabButton
local currentType = "resale"
local results = {}

------------------------------------------------------------------------
-- Columns per suggestion type
------------------------------------------------------------------------

local function Money(c) return c and ns.FormatMoney(c) or "" end
local function Pct(x) return x and (math.floor(x * 100 + .5) .. "%") or "" end

-- Each column: { title, width, justify, text = function(row) }
local COLUMNS = {
    resale = {
        { "Buy at", 110, "RIGHT", function(r) return Money(r.buy) end },
        { "Sell at", 110, "RIGHT", function(r) return Money(r.sell) end },
        { "Profit each", 110, "RIGHT", function(r) return Money(r.profit) end },
        { "Return", 60, "RIGHT", function(r) return Pct(r.roi) end },
        { "Sold/day", 70, "RIGHT", function(r) return ("%.1f"):format(r.salesPerDay or 0) end },
    },
    vendor = {
        { "Buy at", 110, "RIGHT", function(r) return Money(r.buy) end },
        { "Vendor pays", 110, "RIGHT", function(r) return Money(r.vendor) end },
        { "Profit each", 110, "RIGHT", function(r) return Money(r.profit) end },
        { "Return", 60, "RIGHT", function(r) return Pct(r.roi) end },
        { "Listed", 70, "RIGHT", function(r) return r.quantity or "" end },
    },
    disenchant = {
        { "Buy at", 110, "RIGHT", function(r) return Money(r.buy) end },
        { "Disenchant", 110, "RIGHT", function(r) return Money(r.disenchant) end },
        { "Profit", 110, "RIGHT", function(r) return Money(r.profit) end },
        { "Return", 60, "RIGHT", function(r) return Pct(r.roi) end },
        { "", 70, "RIGHT", function() return "" end },
    },
    sell = {
        { "Count", 50, "RIGHT", function(r) return r.count end },
        { "Post at", 110, "RIGHT", function(r) return Money(r.price) end },
        { "Proceeds", 120, "RIGHT", function(r) return Money(r.proceeds) end },
        { "Market", 110, "RIGHT", function(r) return Money(r.value) end },
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
-- Drawing
------------------------------------------------------------------------

local function Ago(t)
    if not t then return "never" end
    local s = time() - t
    if s < 60 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " days ago"
end

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

local function ItemName(r)
    local name, _, quality = GetItemInfo(r.link or r.itemID)
    if not name then return "item:" .. tostring(r.itemID) end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return (color and color.hex or "|cffffffff") .. name .. "|r"
end

-- Fills a row the ScrollBox shows; `element` = { r = suggestion, i = index }.
local InitRow -- set in BuildPanel

local resetScroll = true -- scroll back to the top on the next draw

local function DrawRows()
    if not panel then return end
    local columns = COLUMNS[currentType]
    for i, header in ipairs(panel.headers) do
        local col = columns[i]
        header:SetText(col and col[1] or "")
    end
    local dataProvider = CreateDataProvider()
    for i, r in ipairs(results) do
        dataProvider:Insert({ r = r, i = i })
    end
    local keep = not resetScroll and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil
    panel.scrollBox:SetDataProvider(dataProvider, keep)
    resetScroll = false
    if #results == 0 then
        panel.empty:SetText(currentType == "sell"
            and "Nothing in your bags with a market price yet."
            or "No suggestions yet. They need price history and a few scans spread over at least 6 hours.")
        panel.empty:Show()
    else
        panel.empty:Hide()
    end
    local Count = ns.FullScan and ns.FullScan.Count or tostring
    panel.count:SetText(#results > 0 and (Count(#results) .. (#results == 1 and " suggestion" or " suggestions")) or "")
end

function StrategyTab.Refresh()
    if not panel or not panel:IsShown() then return end
    for _, t in ipairs(TYPES) do
        if t[1] == currentType then results = t[3]() end
    end
    for i, b in ipairs(panel.typeTabs.Tabs) do
        if b.type == currentType then
            if PanelTemplates_SetTab then PanelTemplates_SetTab(panel.typeTabs, i) end
        end
    end
    panel.summary:SetText(Summary())
    DrawRows()
end

-- Clicking a row opens Blizzard's buy view for the item, the same as
-- clicking it in Blizzard's Buy list: AuctionHouseFrame:SelectBrowseResult
-- with a browse-style result (item key + lowest price). It picks the
-- commodity or item buy view and switches the display mode, which also
-- hides this panel (Tabs.lua).
--
-- TEST: this calls Blizzard's frame code from addon code. If buying from
-- the opened view fails with "Interface action failed because of an
-- AddOn", this has to go.
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

function StrategyTab.SetType(t)
    currentType, resetScroll = t, true
    StrategyTab.Refresh()
end

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------

local NAME_WIDTH = 230

local function BuildPanel(frame)
    panel = CreateFrame("Frame", "ForgedForeverAHStrategyPanel", frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 28)
    panel:Hide()


    -- Market summary in the window's bottom bar, right after Blizzard's money
    -- display (where the scan status shows on the Buy view). Parented to the
    -- panel, so it's only shown on the Deals tab.
    panel.summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local money = frame.MoneyFrameBorder or frame.MoneyFrameInset
    if money then
        panel.summary:SetPoint("LEFT", money, "RIGHT", 12, 0)
    else
        panel.summary:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 180, 10)
    end
    panel.summary:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    panel.summary:SetJustifyH("LEFT")
    panel.summary:SetWordWrap(false)

    -- Type tabs, like the Auctions/Bids tabs on Blizzard's Auctions page:
    -- AuctionHouseFrameTopTabTemplate, the first one's top-left at (52, -43)
    -- from the auction house window, selection via PanelTemplates on our own
    -- container frame (not on AuctionHouseFrame).
    local tabs = CreateFrame("Frame", nil, panel)
    tabs:SetAllPoints()
    tabs.Tabs = {}
    for i, t in ipairs(TYPES) do
        local ok, b = pcall(CreateFrame, "Button", nil, tabs, "AuctionHouseFrameTopTabTemplate")
        if not ok then
            b = CreateFrame("Button", nil, tabs, "UIPanelButtonTemplate")
            b:SetSize(110, 22)
        end
        b:SetID(i)
        b:SetText(t[2])
        if i == 1 then
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", TYPE_TAB_X, TYPE_TAB_Y)
        else
            b:SetPoint("LEFT", tabs.Tabs[i - 1], "RIGHT", TYPE_TAB_GAP, 0)
        end
        if PanelTemplates_TabResize then PanelTemplates_TabResize(b, 20, nil, 70) end
        b.type = t[1]
        b:SetScript("OnClick", function()
            PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841)
            StrategyTab.SetType(t[1])
        end)
        tabs.Tabs[i] = b
    end
    if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(tabs, #TYPES) end
    panel.typeTabs = tabs

    -- Blizzard's square refresh button (RefreshButtonTemplate, as on the
    -- Auctions page); a plain button if the template isn't there.
    local ok, refresh = pcall(CreateFrame, "Button", nil, panel, "RefreshButtonTemplate")
    if ok and refresh.SetOnClickHandler then
        refresh:SetOnClickHandler(function() StrategyTab.Refresh() end)
        if refresh.SetTooltipInfo then
            refresh:SetTooltipInfo(AUCTION_HOUSE_REFRESH_BUTTON_TOOLTIP or REFRESH or "Refresh")
        end
    else
        refresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        refresh:SetSize(80, 22)
        refresh:SetText(REFRESH or "Refresh")
        refresh:SetScript("OnClick", StrategyTab.Refresh)
    end
    panel.refresh = refresh

    -- Like Blizzard's "N available" next to its refresh button.
    panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.count:SetPoint("RIGHT", refresh, "LEFT", -3, 0)

    -- The list, built exactly like Blizzard's item list on the Auctions page
    -- (AuctionHouseItemListTemplate, used there as AllAuctionsList), with
    -- Blizzard's own anchors:
    --   list:      top 1 below the type tabs' bottom, right edge 5 in from the
    --              window's, bottom 2 above the money display's top (the
    --              Auctions frame's bottom), left 4 in (no summary list here)
    --   border:    NineSlicePanelTemplate with the "InsetFrameTemplate" layout
    --              (AuctionHouseBackgroundTemplate), from (0, -19) to the
    --              list's bottom right (around the scroll bar too)
    --   background "auctionhouse-background-sell-right" (the Post Auctions
    --              list's) from (3, -22); Blizzard draws it at its natural
    --              size, so its right/bottom edges are copied from Blizzard's
    --              own sell list (ItemSellList) at runtime
    --   headers:   (4, -1) to (-26, -1), 19 high
    --   rows:      WowScrollBoxList 6 under the headers to 3 above the bottom
    --   scroll bar MinimalScrollBar 9 right of the rows, (9, 0) / (9, 4)
    --   refresh:   RefreshFrame (200x20) at the list's top right (-4, +34)
    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", tabs.Tabs[1], "BOTTOMLEFT", LIST_LEFT - TYPE_TAB_X, 1)
    -- Bottom: the money display's top (25 up: anchored at y = 6, 19 high) + 2.
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 27)
    panel.list = list

    -- Border: like AuctionHouseBackgroundTemplate, a NineSlicePanelTemplate
    -- child whose layout comes from the parent's layoutType.
    list.layoutType = "InsetFrameTemplate"
    local okBorder, border = pcall(CreateFrame, "Frame", nil, list, "NineSlicePanelTemplate")
    if okBorder then
        if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
            NineSliceUtil.ApplyLayoutByName(border, "InsetFrameTemplate")
        end
    else
        border = CreateFrame("Frame", nil, list, "InsetFrameTemplate")
        if type(border.Bg) == "table" and border.Bg.Hide then border.Bg:Hide() end
    end
    border:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -HEADER_HEIGHT)
    border:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    panel.border = border

    -- Column headers (display only; Blizzard's sort OnClick is replaced).
    local headerContainer = CreateFrame("Frame", nil, list)
    headerContainer:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -1)
    headerContainer:SetPoint("TOPRIGHT", list, "TOPRIGHT", -26, -1)
    headerContainer:SetHeight(HEADER_HEIGHT)

    local bg = list:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -(HEADER_HEIGHT + 3))
    bg:SetAtlas(BACKGROUND_ATLAS)
    panel.bg = bg
    -- Right/bottom edges: the same distance from the list's edges as on
    -- Blizzard's Post Auctions list (its texture has its natural size there),
    -- else the Auctions list.
    -- Read from Blizzard's frames when shown; only reading, no taint.
    -- Background and border edges: the same distance from the list's edges as
    -- on Blizzard's own Post Auctions list (ItemSellList; else the Auctions
    -- list), read when the panel opens. Only reading, no taint. Blizzard
    -- draws its background at its natural size and its border's art doesn't
    -- reach the list's right edge, so copying is the only exact way.
    local function BlizzardList()
        local blizzList = type(frame.ItemSellList) == "table" and frame.ItemSellList
        local name = "ItemSellList"
        if not (blizzList and blizzList.GetRight and blizzList:GetRight()) then
            local auctions = type(frame.AuctionsFrame) == "table" and frame.AuctionsFrame
            blizzList = auctions and type(auctions.AllAuctionsList) == "table" and auctions.AllAuctionsList
            name = "AuctionsFrame.AllAuctionsList"
        end
        return blizzList, name
    end
    -- Gaps (right, bottom) between a Blizzard list's edges and one of its parts.
    local function Gaps(blizzList, part)
        if not (blizzList and type(part) == "table" and part.GetRight and blizzList.GetRight) then return end
        local lr, pr = blizzList:GetRight(), part:GetRight()
        local lb, pb = blizzList:GetBottom(), part:GetBottom()
        if lr and pr and lb and pb then return lr - pr, pb - lb end
    end
    panel.layoutInfo = {}
    local function MatchBackground()
        local blizzList, name = BlizzardList()
        local info = { source = blizzList and name or "none" }
        local bgRight, bgBottom = Gaps(blizzList, blizzList and blizzList.Background)
        info.bg = bgRight and ("%.1f, %.1f"):format(bgRight, bgBottom) or "fallback 22, 3"
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -(HEADER_HEIGHT + 3))
        bg:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -(bgRight or 22), bgBottom or 3)
        local nsRight, nsBottom = Gaps(blizzList, blizzList and blizzList.NineSlice)
        info.border = nsRight and ("%.1f, %.1f"):format(nsRight, nsBottom) or "fallback 0, 0"
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -HEADER_HEIGHT)
        border:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -(nsRight or 0), nsBottom or 0)
        panel.layoutInfo = info
    end
    panel.MatchBackground = MatchBackground
    MatchBackground()

    -- Refresh button: RIGHT of a 200x20 RefreshFrame at the list's TOPRIGHT
    -- offset (-4, +34), i.e. 10 below that frame's top.
    refresh:SetPoint("RIGHT", list, "TOPRIGHT", -4, 34 - 10)

    local function ColumnX(c)
        local x = NAME_WIDTH
        for i = 1, c - 1 do x = x + COLUMNS.resale[i][2] end
        return x
    end
    local function Header(x, width, last)
        local ok, h = pcall(CreateFrame, "Button", nil, headerContainer, "AuctionHouseTableHeaderStringTemplate")
        if not ok then
            h = CreateFrame("Button", nil, headerContainer)
            h:SetHeight(HEADER_HEIGHT)
            local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("LEFT", 8, 0)
            h:SetFontString(fs)
        end
        h:SetScript("OnClick", nil)
        if type(h.Arrow) == "table" and h.Arrow.Hide then h.Arrow:Hide() end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", headerContainer, "TOPLEFT", x, 0)
        if last then
            h:SetPoint("TOPRIGHT", headerContainer, "TOPRIGHT", 0, 0)
        else
            h:SetWidth(width + HEADER_OVERLAP)
        end
        return h
    end
    panel.headers = {}
    Header(0, NAME_WIDTH):SetText("Item")
    for c = 1, 5 do
        panel.headers[c] = Header(ColumnX(c) - HEADER_OVERLAP, COLUMNS.resale[c][2], c == 5)
    end

    -- Rows: Blizzard's virtual scroll list. Only the visible rows exist; they
    -- are reused while scrolling.
    local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", headerContainer, "BOTTOMLEFT", 0, -6)
    scrollBox:SetPoint("RIGHT", headerContainer, "RIGHT", 0, 0)
    scrollBox:SetPoint("BOTTOM", list, "BOTTOM", 0, 3)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 9, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 9, 4)
    panel.scrollBox, panel.scrollBar = scrollBox, scrollBar

    local function BuildRow(row)
        row:SetHeight(ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")
        row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.stripe:SetAllPoints()
        row.stripe:SetAtlas("auctionhouse-rowstripe-1")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetAtlas("auctionhouse-ui-row-highlight")
        hl:SetBlendMode("ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
        row.icon:SetPoint("LEFT", 6, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetWidth(NAME_WIDTH - ROW_HEIGHT - 8)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.cells = {}
        for c = 1, 5 do
            local cell = row:CreateFontString(nil, "OVERLAY", "Number14FontWhite")
            cell:SetPoint("LEFT", row, "LEFT", ColumnX(c), 0)
            cell:SetWidth(COLUMNS.resale[c][2] - 10)
            cell:SetJustifyH("RIGHT")
            cell:SetWordWrap(false)
            row.cells[c] = cell
        end
        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.data.link then
                GameTooltip:SetHyperlink(self.data.link)
            else
                GameTooltip:SetItemByID(self.data.itemID)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(self)
            if self.data then StrategyTab.OpenInBuyView(self.data) end
        end)
    end

    InitRow = function(row, element)
        if not rawget(row, "cells") then BuildRow(row) end -- first use of this row frame
        local r = element.r
        row.data = r
        row.stripe:SetShown(element.i % 2 == 1)
        local icon = select(5, GetItemInfoInstant(r.itemID))
        row.icon:SetTexture(icon or 134400)
        row.name:SetText(ItemName(r))
        local columns = COLUMNS[currentType]
        for c, cell in ipairs(row.cells) do
            local col = columns[c]
            cell:SetText(col and tostring(col[4](r) or "") or "")
        end
    end

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, element) InitRow(row, element) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Like Blizzard's list text ("No items found"): gold GameFontNormal,
    -- 45 px below the top of the rows, inset 45 left / 67 right.
    panel.empty = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.empty:SetPoint("TOP", scrollBox, "TOP", 0, -45)
    panel.empty:SetPoint("LEFT", list, "LEFT", 45, 0)
    panel.empty:SetPoint("RIGHT", list, "RIGHT", -67, 0)

    panel:SetScript("OnShow", function()
        panel.MatchBackground()
        StrategyTab.Refresh()
    end)
end

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

ns:RegisterCommand("layout", "debug - show what the Deals list copies from Blizzard's", function(args)
    StrategyTab.LayoutDebug()
end)

------------------------------------------------------------------------
-- Tab (Tabs.lua, LibAHTab's approach)
------------------------------------------------------------------------

StrategyTab.Select = function() end

ns:Listen("AUCTION_UI_LOADED", function(frame)
    BuildPanel(frame)
    StrategyTab.Select = ns.AddAuctionTab(TAB_ID, TAB_TEXT, panel)
    tabButton = ns.AuctionTabButton(TAB_ID)
end)

-- New scan data: redraw if open.
ns:Listen("SCAN_FINISHED", function()
    C_Timer.After(0.1, StrategyTab.Refresh)
end)
ns:On("BAG_UPDATE_DELAYED", function()
    if currentType == "sell" then StrategyTab.Refresh() end
end)
