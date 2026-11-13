local _, ns = ...

-- "Market" tab in Blizzard's auction house window
--
-- Pick an item with the search box (the only way to pick one); the panel
-- shows its current price, market value, volatility, sales velocity and
-- trend, and a 30-day graph:
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
    -- Day labels
    for _, mark in ipairs({ { 1, DAYS .. " days ago" }, { 16, "15 days ago" }, { DAYS, "today" } }) do
        local label = nextLabel()
        label:ClearAllPoints()
        label:SetPoint("TOP", plot, "BOTTOMLEFT", X(mark[1]), -4)
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
-- Item view
------------------------------------------------------------------------

local function Pct(x, signed)
    if not x then return "---" end
    local v = math.floor(x + .5)
    return ((signed and v > 0) and "+" or "") .. v .. "%"
end

function MarketTab.Show(key)
    selectedKey = key
    panel.matches:Hide()
    if not key then
        panel.item:Hide()
        panel.graph:Hide()
        panel.hint:Show()
        return
    end
    panel.hint:Hide()
    panel.item:Show()
    panel.graph:Show()
    local itemID = tonumber(key:match("^(%d+)"))
    local name, link, quality = GetItemInfo(itemID)
    local stored, storedQuality = ns.Market.Name(key)
    if stored then
        name, quality = stored, storedQuality or quality -- full name with a random suffix
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    panel.item.icon:SetTexture(select(5, GetItemInfoInstant(itemID)) or 134400)
    panel.item.name:SetText((color and color.hex or "|cffffffff") .. (name or ("item:" .. itemID)) .. "|r")
    panel.item.link = link

    local s = ns.Market.Stats(key)
    local now = s.listed and ("%s (%s listed)"):format(Money(s.price), Count(s.quantity or 0)) or "not listed"
    panel.item.prices:SetText(("Lowest now: %s    Market value: %s    Today's lowest: %s"):format(
        now, Money(s.value), Money(s.today)))
    panel.item.stats:SetText(("Volatility: %s    Sales: %s    Trend (24 h): %s    Data: %s"):format(
        s.volatility and Pct(s.volatility * 100) or "---",
        s.salesPerDay and ("~%.1f sold/day"):format(s.salesPerDay) or "---",
        Pct(s.trend, true),
        s.days and ("%.1f days"):format(s.days) or "---"))
    DrawGraph(key)
end

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
-- Panel
------------------------------------------------------------------------

local function BuildPanel(frame)
    panel = CreateFrame("Frame", "ForgedForeverAHMarketPanel", frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 28)
    panel:Hide()

    local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    search:SetSize(260, 20)
    search:SetPoint("TOPLEFT", 60, -4) -- right of the window's portrait
    search:SetAutoFocus(false)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Search(self:GetText())
    end)
    panel.search = search

    panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.hint:SetPoint("CENTER", 0, 20)
    panel.hint:SetWidth(520)
    panel.hint:SetText("Search for an item to see its 30-day price history, volatility and sales.")

    -- Item header
    local item = CreateFrame("Button", nil, panel)
    item:SetPoint("TOPLEFT", 0, -30)
    item:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    item:SetHeight(48)
    item.icon = item:CreateTexture(nil, "ARTWORK")
    item.icon:SetSize(36, 36)
    item.icon:SetPoint("LEFT", 4, 0)
    item.name = item:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    item.name:SetPoint("TOPLEFT", item.icon, "TOPRIGHT", 8, 0)
    item.prices = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    item.prices:SetPoint("TOPLEFT", item.name, "BOTTOMLEFT", 0, -4)
    item.stats = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    item.stats:SetPoint("TOPLEFT", item.prices, "BOTTOMLEFT", 0, -3)
    item:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self.icon, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    item:SetScript("OnLeave", GameTooltip_Hide)
    item:Hide()
    panel.item = item

    -- Graph
    local graph = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
    graph:SetPoint("TOPLEFT", 0, -84)
    graph:SetPoint("BOTTOMRIGHT", 0, 0)
    graph.plot = CreateFrame("Frame", nil, graph)
    graph.plot:SetPoint("TOPLEFT", 90, -24)
    graph.plot:SetPoint("BOTTOMRIGHT", -16, 24)
    graph.lines, graph.textures, graph.labels = {}, {}, {}
    graph.legend = graph:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    graph.legend:SetPoint("TOPRIGHT", -12, -6)
    -- Colored words (the game font has no line/box glyphs).
    graph.legend:SetText(("%sLowest|r    %sHighest|r    %sMarket value|r    %sSold per day (bars)|r"):format(
        Hex(LOW_COLOR), Hex(HIGH_COLOR), Hex(VALUE_COLOR), Hex(BAR_COLOR)))
    graph.empty = graph:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    graph.empty:SetPoint("CENTER")
    graph.empty:SetText("No price data for this item in the last 30 days.")
    graph:Hide()
    panel.graph = graph

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
