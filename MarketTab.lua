local _, ns = ...

-- "Market" tab in Blizzard's auction house window
--
-- Laid out like Blizzard's Sell view: statistics in the left panel (where
-- the Sell view has its item and price inputs), the 30-day graph in the
-- right panel (where it has its list of auctions, same background).
--
-- Pick an item with the search box (the only way to pick one); the left
-- panel shows its current price, market value, volatility, sales velocity,
-- trend and order book (OrderBook.lua); the right panel a 30-day graph:
--   gold line   daily lowest price
--   gray line   daily highest price
--   blue line   market value (price history)
--   gray bars   estimated sales per day
-- Data: Market.lua (daily summaries for 30 days, scan snapshots for 3 days)
-- and the price history. The graph is drawn with the client's own line and
-- texture widgets. The tab itself is added by Tabs.lua.

local MarketTab = {}
ns.MarketTab = MarketTab

local TAB_ID = "Market"
local TAB_TEXT = "Market"
local DAYS = 30
local MAX_MATCHES = 8

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

-- Colors (r, g, b)
local LOW_COLOR = { 1, .82, 0 }
local HIGH_COLOR = { .6, .6, .6 }
local VALUE_COLOR = { .3, .6, 1 }
local BAR_COLOR = { .5, .5, .5 }

local panel, selectedKey

local function Money(c) return c and ns.FormatMoney(c) or "---" end
local function Count(n) return ns.FullScan and ns.FullScan.Count(n) or tostring(n) end
local function Hex(c)
    local function byte(v) return math.floor(v * 255 + .5) end
    return ("|cff%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

------------------------------------------------------------------------
-- Search
------------------------------------------------------------------------

-- Tracked items whose name contains `text` (exact name match first).
function MarketTab.Find(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return {} end
    local exact, partial = {}, {}
    for _, key in ipairs(ns.Market.Keys()) do
        local itemID = tonumber(key:match("^(%d+)"))
        -- Suffixed items ("of the Eagle"): only their full stored name.
        local name = itemID and (ns.Market.Name(key) or (not ns.Market.Suffixed(key) and GetItemInfo(itemID)) or nil)
        if name then
            local lower = name:lower()
            if lower == text then
                exact[#exact + 1] = { key = key, itemID = itemID, name = name }
            elseif lower:find(text, 1, true) then
                partial[#partial + 1] = { key = key, itemID = itemID, name = name }
            end
        end
    end
    table.sort(partial, function(a, b) return a.name < b.name end)
    for _, m in ipairs(partial) do exact[#exact + 1] = m end
    return exact
end

------------------------------------------------------------------------
-- Graph
------------------------------------------------------------------------

local function Pool(list, create)
    local used = 0
    return function()
        used = used + 1
        local obj = list[used]
        if not obj then
            obj = create()
            list[used] = obj
        end
        obj:Show()
        return obj
    end, function()
        for i = used + 1, #list do list[i]:Hide() end
    end
end

local function DrawGraph(key)
    local g = panel.graph
    local plot = g.plot
    local width, height = plot:GetWidth(), plot:GetHeight()
    local series = ns.Market.DailySeries(key, DAYS)
    local value = ns.History.Value(key)

    local lo, hi, maxSold = nil, nil, 0
    for _, e in ipairs(series) do
        if e.min then lo = lo and math.min(lo, e.min) or e.min end
        if e.max then hi = hi and math.max(hi, e.max) or e.max end
        maxSold = math.max(maxSold, e.sold or 0)
    end
    if value then
        lo = lo and math.min(lo, value) or value
        hi = hi and math.max(hi, value) or value
    end

    local nextLine, doneLines = Pool(g.lines, function() return plot:CreateLine(nil, "ARTWORK") end)
    local nextTex, doneTex = Pool(g.textures, function() return plot:CreateTexture(nil, "BORDER") end)
    local nextLabel, doneLabels = Pool(g.labels, function()
        return g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    end)

    if not lo then
        g.empty:Show()
        doneLines(); doneTex(); doneLabels()
        return
    end
    g.empty:Hide()
    if hi <= lo then hi = lo + math.max(1, lo * .1) end
    local pad = (hi - lo) * .08
    lo, hi = math.max(0, lo - pad), hi + pad

    local function X(i) return (i - 1) / (DAYS - 1) * width end
    local function Y(price) return (price - lo) / (hi - lo) * height end

    -- Price gridlines and labels
    for i = 0, 4 do
        local price = lo + (hi - lo) * i / 4
        local y = Y(price)
        local line = nextLine()
        line:SetThickness(1)
        line:SetColorTexture(1, 1, 1, .08)
        line:SetStartPoint("BOTTOMLEFT", plot, 0, y)
        line:SetEndPoint("BOTTOMLEFT", plot, width, y)
        local label = nextLabel()
        label:ClearAllPoints()
        label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -6, y)
        label:SetText(Money(price))
    end
    -- Day labels: the first starts at the graph's left edge and the last
    -- ends at its right edge (centered, they'd run into the price labels and
    -- past the border); the middle one is centered on its day.
    for _, mark in ipairs({ { 1, DAYS .. " days ago", "TOPLEFT" }, { 16, "15 days ago", "TOP" },
                            { DAYS, "today", "TOPRIGHT" } }) do
        local label = nextLabel()
        label:ClearAllPoints()
        label:SetPoint(mark[3], plot, "BOTTOMLEFT", X(mark[1]), -4)
        label:SetText(mark[2])
    end

    -- Sales bars (bottom quarter of the plot)
    if maxSold > 0 then
        local barWidth = math.max(2, width / DAYS - 3)
        for i, e in ipairs(series) do
            if (e.sold or 0) > 0 then
                local bar = nextTex()
                bar:SetColorTexture(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3], .5)
                bar:ClearAllPoints()
                bar:SetPoint("BOTTOM", plot, "BOTTOMLEFT", X(i), 0)
                bar:SetSize(barWidth, math.max(1, e.sold / maxSold * height * .25))
            end
        end
    end

    -- Market value line
    if value then
        local line = nextLine()
        line:SetThickness(1.5)
        line:SetColorTexture(VALUE_COLOR[1], VALUE_COLOR[2], VALUE_COLOR[3], .8)
        line:SetStartPoint("BOTTOMLEFT", plot, 0, Y(value))
        line:SetEndPoint("BOTTOMLEFT", plot, width, Y(value))
    end

    -- Lowest / highest price lines; gaps where the item wasn't listed, a dot
    -- for a lone day.
    local function Series(field, color, thickness)
        for i, e in ipairs(series) do
            local v = e[field]
            if v then
                local nextE = series[i + 1]
                local prevE = series[i - 1]
                if nextE and nextE[field] then
                    local line = nextLine()
                    line:SetThickness(thickness)
                    line:SetColorTexture(color[1], color[2], color[3], 1)
                    line:SetStartPoint("BOTTOMLEFT", plot, X(i), Y(v))
                    line:SetEndPoint("BOTTOMLEFT", plot, X(i + 1), Y(nextE[field]))
                elseif not (prevE and prevE[field]) then
                    local dot = nextTex()
                    dot:SetColorTexture(color[1], color[2], color[3], 1)
                    dot:ClearAllPoints()
                    dot:SetPoint("CENTER", plot, "BOTTOMLEFT", X(i), Y(v))
                    dot:SetSize(4, 4)
                end
            end
        end
    end
    Series("max", HIGH_COLOR, 1.5)
    Series("min", LOW_COLOR, 2)

    doneLines(); doneTex(); doneLabels()
end

------------------------------------------------------------------------
-- Item view: statistics in the left panel
------------------------------------------------------------------------

local function Pct(x, signed)
    if not x then return "---" end
    local v = math.floor(x + .5)
    return ((signed and v > 0) and "+" or "") .. v .. "%"
end

-- The left panel's rows: { key, label }; false = a small gap. The "buy"
-- labels are set per item (commodities 20 / 100 / 200, others 1 / 5 / 20).
local ROWS = {
    { "price", "Lowest now" }, { "value", "Market value" }, { "today", "Today's lowest" },
    { "volatility", "Volatility" }, { "sales", "Sales" }, { "trend", "Trend (24 h)" }, { "data", "Data" },
    false,
    { "buy1", "Buy 20" }, { "buy2", "Buy 100" }, { "buy3", "Buy 200" },
    { "below", "Below value" }, { "wall", "Wall" }, { "listed", "Listings" },
}
local ROW_TOP = -96    -- first row, below the item display (12 + 72 + 8 + 4)
local ROW_STEP = 22
local ROW_GAP = 8
local LABEL_WIDTH = 110

-- Values and labels for the rows (OrderBook.lua for buy / below / wall /
-- listed), and the order book's note. Without a book, the first buy row
-- says why.
function MarketTab.RowValues(key)
    local s = ns.Market.Stats(key)
    local v = {
        price = s.listed and ("%s (%s listed)"):format(Money(s.price), Count(s.quantity or 0)) or "not listed",
        value = Money(s.value),
        today = Money(s.today),
        volatility = s.volatility and Pct(s.volatility * 100) or "---",
        sales = s.salesPerDay and ("~%.1f sold/day"):format(s.salesPerDay) or "---",
        trend = Pct(s.trend, true),
        data = s.days and ("%.1f days"):format(s.days) or "---",
        buy1 = "---", buy2 = "---", buy3 = "---", below = "---", wall = "---", listed = "---",
    }
    local labels = { buy1 = "Buy 20", buy2 = "Buy 100", buy3 = "Buy 200" }
    local OB = ns.OrderBook
    local book = OB.Get(key)
    local note = ""
    if not book then
        if OB.IsLoading(key) then
            v.buy1 = "loading..."
        elseif OB.Failed(key) then
            v.buy1 = "no answer; try again in a minute"
        else
            v.buy1 = "not loaded (not during a scan)"
        end
        return v, labels, note
    end
    local age = time() - book.t
    note = "Order book: " .. (age < 60 and "just now" or (math.floor(age / 60) .. " min ago"))
        .. (book.complete and "" or ", partly loaded")
    if #book.levels == 0 then
        v.buy1 = "nothing listed with a buyout"
        return v, labels, note
    end
    local counts = book.commodity and { 20, 100, 200 } or { 1, 5, 20 }
    for i, n in ipairs(counts) do
        labels["buy" .. i] = "Buy " .. n
        local total, each = OB.CostToBuy(book, n)
        if total then
            v["buy" .. i] = ("%s (%s each)"):format(Money(total), Money(math.floor(each + .5)))
        else
            v["buy" .. i] = ("only %s listed"):format(Count(each))
            break
        end
    end
    if s.value then
        local below, cost = OB.BelowValue(book, s.value)
        v.below = below > 0 and ("%s for %s"):format(Count(below), Money(cost)) or "none"
    end
    local wallPrice, wallQuantity = OB.Wall(book)
    v.wall = wallPrice and ("%s at %s"):format(Count(wallQuantity), Money(wallPrice)) or "none"
    v.listed = ("%s at %d prices"):format(Count(book.total), #book.levels)
    return v, labels, note
end

local function ItemNameText(key, itemID)
    local name, link, quality = GetItemInfo(itemID)
    local stored, storedQuality = ns.Market.Name(key)
    if stored then
        name, quality = stored, storedQuality or quality -- full name with a random suffix
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return (color and color.hex or "|cffffffff") .. (name or ("item:" .. itemID)) .. "|r", link
end

function MarketTab.Show(key)
    -- The item's listings, for the order book rows (no-op while current,
    -- loading, or shortly after the server didn't answer).
    if key then ns.OrderBook.Request(key) end
    selectedKey = key
    panel.matches:Hide()
    local left, graph = panel.left, panel.graph
    if not key then
        left.content:Hide()
        panel.hint:Show()
        graph.plot:Hide()
        graph.legend:Hide()
        graph.empty:Hide()
        panel.count:SetText("")
        return
    end
    panel.hint:Hide()
    left.content:Show()
    graph.plot:Show()
    graph.legend:Show()

    local itemID = tonumber(key:match("^(%d+)"))
    local nameText, link = ItemNameText(key, itemID)
    local display = left.display
    display.name:SetText(nameText)
    display.link = link
    local icon = select(5, GetItemInfoInstant(itemID)) or 134400
    local b = display.itemButton
    local buttonIcon = b and (b.icon or b.Icon)
    if b and SetItemButtonTexture then
        SetItemButtonTexture(b, icon)
    elseif type(buttonIcon) == "table" and buttonIcon.SetTexture then
        buttonIcon:SetTexture(icon)
    elseif type(display.icon) == "table" then
        display.icon:SetTexture(icon)
    end

    local values, labels, note = MarketTab.RowValues(key)
    for rowKey, row in pairs(left.rows) do
        row.value:SetText(values[rowKey] or "---")
        if labels[rowKey] then row.label:SetText(labels[rowKey]) end
    end
    left.note:SetText(note)
    local s = ns.Market.Stats(key)
    panel.count:SetText(s.listed and (Count(s.quantity or 0) .. " listed") or "")
    DrawGraph(key)
end

-- The shown item's order book changed (or its request ended): redraw.
ns:Listen("ORDER_BOOK", function(key)
    if panel and panel:IsShown() and key == selectedKey then MarketTab.Show(selectedKey) end
end)

local function ShowMatches(matches)
    local list = panel.matches
    for i, button in ipairs(list.buttons) do
        local m = matches[i]
        button.match = m
        if m then
            button:SetText(m.name)
            button:Show()
        else
            button:Hide()
        end
    end
    list:SetHeight(math.min(#matches, MAX_MATCHES) * 18 + 8)
    list:SetShown(#matches > 0)
end

local function Search(text)
    local matches = MarketTab.Find(text)
    if #matches == 0 then
        MarketTab.Show(nil)
        panel.hint:SetText(("No tracked item matches \"%s\". Items appear here after a scan has seen them."):format(text))
    elseif #matches == 1 or matches[1].name:lower() == text:lower() then
        MarketTab.Show(matches[1].key)
    else
        ShowMatches(matches)
    end
end
MarketTab.Search = Search

------------------------------------------------------------------------
-- Panel: the Sell view's layout (Blizzard_AuctionHouseFrame.xml, branch
-- forever). Left like ItemSellFrame (AuctionHouseSellFrameTemplate: 363
-- wide, from 69 below the window's top to 2 above the money display, 4 in;
-- "auctionhouse-background-sell-left", the item display at the top; no
-- tab above it). The search box is where the Buy view's is. Right like ItemSellList
-- (AuctionHouseItemListTemplate: 1 right of the left panel to 5 from the
-- window's right; header row, "auctionhouse-background-sell-right" from 19
-- down, refresh button at (-4, +30)).
--
-- Both panels, their backgrounds and borders are anchored to Blizzard's own
-- frames, so they match exactly (anchoring to a frame only reads its
-- position); without them, the XML's values.
------------------------------------------------------------------------

-- An InsetFrameTemplate border (as AuctionHouseBackgroundTemplate's).
local function Border(parent)
    local ok, border = pcall(CreateFrame, "Frame", nil, parent, "NineSlicePanelTemplate")
    if ok then
        if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
            NineSliceUtil.ApplyLayoutByName(border, "InsetFrameTemplate")
        end
    else
        border = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
        if type(border.Bg) == "table" and border.Bg.Hide then border.Bg:Hide() end
    end
    return border
end

-- Anchors `region` to `blizz`'s corners if it's there; else `fallback()`.
local function Copy(region, blizz, fallback)
    region:ClearAllPoints()
    if type(blizz) == "table" and blizz.GetObjectType then
        region:SetPoint("TOPLEFT", blizz, "TOPLEFT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", blizz, "BOTTOMRIGHT", 0, 0)
    else
        fallback()
    end
end
MarketTab.Copy = Copy

local function BuildLeft(frame)
    local blizz = type(frame.ItemSellFrame) == "table" and frame.ItemSellFrame or nil
    local left = CreateFrame("Frame", nil, panel)
    Copy(left, blizz, function()
        local money = frame.MoneyFrameBorder
        left:SetPoint("TOP", frame, "TOP", 0, -69)
        if money then
            left:SetPoint("BOTTOM", money, "TOP", 0, 2)
        else
            left:SetPoint("BOTTOM", frame, "BOTTOM", 0, 27)
        end
        left:SetPoint("LEFT", frame, "LEFT", 4, 0)
        left:SetWidth(363)
    end)

    local bg = left:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("auctionhouse-background-sell-left", true)
    Copy(bg, blizz and blizz.Background, function() bg:SetPoint("TOPLEFT", 3, -3) end)
    local border = Border(left)
    Copy(border, blizz and blizz.NineSlice, function() border:SetAllPoints() end)
    left.bg, left.border = bg, border

    -- Everything shown for an item.
    local content = CreateFrame("Frame", nil, left)
    content:SetAllPoints()
    left.content = content

    -- Item display, like the Sell view's (342x72, "auctionhouse-itemheaderframe",
    -- 11 in and 12 down; item button 12 in, name 12 right of it).
    local display = CreateFrame("Button", nil, content)
    display:SetSize(342, 72)
    display:SetPoint("TOPLEFT", left, "TOPLEFT", 11, -12)
    local frameTex = display:CreateTexture(nil, "ARTWORK")
    frameTex:SetAtlas("auctionhouse-itemheaderframe", true)
    frameTex:SetPoint("CENTER")
    local okButton, itemButton = pcall(CreateFrame, "Button", nil, display, "GiantItemButtonTemplate")
    local iconAnchor
    if okButton and itemButton then
        itemButton:SetPoint("LEFT", display, "LEFT", 12, 0)
        itemButton:EnableMouse(false) -- display only; the display shows the tooltip
        display.itemButton = itemButton
        iconAnchor = itemButton
    else
        display.icon = display:CreateTexture(nil, "OVERLAY")
        display.icon:SetSize(52, 52)
        display.icon:SetPoint("LEFT", display, "LEFT", 12, 0)
        iconAnchor = display.icon
    end
    display.name = display:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Large")
    display.name:SetJustifyH("LEFT")
    display.name:SetHeight(64)
    display.name:SetPoint("LEFT", iconAnchor, "RIGHT", 12, 0)
    display.name:SetPoint("RIGHT", display, "RIGHT", -12, 0)
    display:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    display:SetScript("OnLeave", GameTooltip_Hide)
    left.display = display

    -- Rows: labels like the Sell view's (gold GameFontNormal, right-aligned),
    -- values 18 right of them.
    left.rows = {}
    local y = ROW_TOP
    for _, r in ipairs(ROWS) do
        if r then
            local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetWidth(LABEL_WIDTH)
            label:SetJustifyH("RIGHT")
            label:SetPoint("TOPLEFT", left, "TOPLEFT", 11, y)
            label:SetText(r[2])
            local value = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            value:SetJustifyH("LEFT")
            value:SetWordWrap(false)
            value:SetPoint("LEFT", label, "RIGHT", 18, 0)
            value:SetPoint("RIGHT", left, "RIGHT", -10, 0)
            left.rows[r[1]] = { label = label, value = value }
            y = y - ROW_STEP
        else
            y = y - ROW_GAP
        end
    end
    -- Where the Sell view has its Buyout Mode checkbox: the order book's age.
    left.note = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    left.note:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 14, 14)
    return left
end

local function BuildRight(frame, left)
    local blizz = type(frame.ItemSellList) == "table" and frame.ItemSellList or nil
    local right = CreateFrame("Frame", nil, panel)
    Copy(right, blizz, function()
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", 1, 0)
        right:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 1, 0)
        right:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
    end)

    local bg = right:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("auctionhouse-background-sell-right", true)
    Copy(bg, blizz and blizz.Background, function() bg:SetPoint("TOPLEFT", 3, -22) end)
    local border = Border(right)
    Copy(border, blizz and blizz.NineSlice, function()
        border:SetPoint("TOPLEFT", 0, -19)
        border:SetPoint("BOTTOMRIGHT")
    end)
    right.bg, right.border = bg, border

    -- Header row (4, -1) to (-26, -1), 19 high: one Blizzard header button.
    local headers = CreateFrame("Frame", nil, right)
    headers:SetPoint("TOPLEFT", 4, -1)
    headers:SetPoint("TOPRIGHT", -26, -1)
    headers:SetHeight(19)
    local ok, header = pcall(CreateFrame, "Button", nil, headers, "AuctionHouseTableHeaderStringTemplate")
    if not ok then
        header = CreateFrame("Button", nil, headers)
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", 8, 0)
        header:SetFontString(fs)
    end
    header:SetScript("OnClick", nil)
    if header.SetEnabled then header:SetEnabled(false) end
    if type(header.Arrow) == "table" and header.Arrow.Hide then header.Arrow:Hide() end
    header:SetPoint("TOPLEFT")
    header:SetPoint("BOTTOMRIGHT")
    header:SetText("Price History (30 days)")
    right.header = header

    -- The graph inside the list area (price labels on the left, day labels
    -- below, the legend at the top).
    right.plot = CreateFrame("Frame", nil, right)
    right.plot:SetPoint("TOPLEFT", 66, -19 - 30)
    right.plot:SetPoint("BOTTOMRIGHT", -36, 26)
    right.lines, right.textures, right.labels = {}, {}, {}
    right.legend = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    right.legend:SetPoint("TOPRIGHT", -34, -19 - 9)
    -- Colored words (the game font has no line/box glyphs).
    right.legend:SetText(("%sLowest|r   %sHighest|r   %sMarket value|r   %sSold/day|r"):format(
        Hex(LOW_COLOR), Hex(HIGH_COLOR), Hex(VALUE_COLOR), Hex(BAR_COLOR)))
    right.empty = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    right.empty:SetPoint("TOP", right, "TOP", 0, -19 - 45)
    right.empty:SetPoint("LEFT", 45, 0)
    right.empty:SetPoint("RIGHT", -67, 0)
    right.empty:SetText("No price data for this item in the last 30 days.")
    right.empty:Hide()
    right.plot:Hide()
    right.legend:Hide()

    -- Refresh button like the Sell list's: RIGHT of a 200x20 refresh frame at
    -- the list's TOPRIGHT (-4, +30). Asks the server for the order book again.
    local okRefresh, refresh = pcall(CreateFrame, "Button", nil, right, "RefreshButtonTemplate")
    local function OnRefresh()
        if selectedKey then
            ns.OrderBook.Request(selectedKey, true)
            MarketTab.Show(selectedKey)
        end
    end
    MarketTab.Refresh = OnRefresh
    if okRefresh and refresh.SetOnClickHandler then
        refresh:SetOnClickHandler(OnRefresh)
        if refresh.SetTooltipInfo then
            refresh:SetTooltipInfo(AUCTION_HOUSE_REFRESH_BUTTON_TOOLTIP or REFRESH or "Refresh")
        end
    else
        refresh = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        refresh:SetSize(80, 22)
        refresh:SetText(REFRESH or "Refresh")
        refresh:SetScript("OnClick", OnRefresh)
    end
    refresh:SetPoint("RIGHT", right, "TOPRIGHT", -4, 30 - 10)
    right.refresh = refresh
    -- Like Blizzard's "N available" left of its refresh button.
    panel.count = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.count:SetPoint("RIGHT", refresh, "LEFT", -3, 0)
    return right
end

local function BuildPanel(frame)
    panel = CreateFrame("Frame", "ForgedForeverAHMarketPanel", frame)
    panel:SetAllPoints(frame)
    panel:Hide()

    panel.left = BuildLeft(frame)
    panel.graph = BuildRight(frame, panel.left)

    -- Search box exactly where the Buy view's is: on Blizzard's own search
    -- box (SearchBar.SearchBox; anchoring only reads its position). Without
    -- it, its position measured from the Buy view.
    local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    local blizzSearch = type(frame.SearchBar) == "table" and frame.SearchBar.SearchBox
    Copy(search, type(blizzSearch) == "table" and blizzSearch or nil, function()
        search:SetPoint("TOPLEFT", frame, "TOPLEFT", 208, -40)
        search:SetSize(245, 20)
    end)
    search:SetAutoFocus(false)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Search(self:GetText())
    end)
    panel.search = search

    panel.hint = panel.left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.hint:SetPoint("TOP", panel.left, "TOP", 0, -60)
    panel.hint:SetPoint("LEFT", panel.left, "LEFT", 30, 0)
    panel.hint:SetPoint("RIGHT", panel.left, "RIGHT", -30, 0)
    panel.hint:SetText("Search for an item to see its statistics, order book and 30-day price history.")
    panel.left.content:Hide()

    -- Matches (below the search box, above everything else)
    local matches = CreateFrame("Frame", nil, panel, "TooltipBackdropTemplate")
    matches:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -2)
    matches:SetWidth(270)
    matches:SetFrameStrata("DIALOG")
    matches.buttons = {}
    for i = 1, MAX_MATCHES do
        local b = CreateFrame("Button", nil, matches)
        b:SetSize(260, 18)
        b:SetPoint("TOPLEFT", 5, -4 - (i - 1) * 18)
        b:SetNormalFontObject("GameFontHighlightSmall")
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", 4, 0)
        b:SetFontString(text)
        b:SetScript("OnClick", function(self)
            if self.match then
                search:SetText(self.match.name)
                MarketTab.Show(self.match.key)
            end
        end)
        matches.buttons[i] = b
    end
    matches:Hide()
    panel.matches = matches

    panel:SetScript("OnShow", function()
        if selectedKey then MarketTab.Show(selectedKey) end
    end)
end

ns:Listen("AUCTION_UI_LOADED", function(frame)
    BuildPanel(frame)
    MarketTab.Select = ns.AddAuctionTab(TAB_ID, TAB_TEXT, panel)
end)

-- New scan data: redraw the shown item.
ns:Listen("SCAN_FINISHED", function()
    if panel and panel:IsShown() and selectedKey then
        C_Timer.After(0.1, function() MarketTab.Show(selectedKey) end)
    end
end)
