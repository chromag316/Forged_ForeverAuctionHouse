local now = 1700006400
time = function(t) if t then return os.time(t) end return now end
date = function(f) return os.date(f, now) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
geterrorhandler = function() return error end
SlashCmdList = {}
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Alliance" end
C_AddOns = { IsAddOnLoaded = function() return false end }
GetMoneyString = function(c) return c .. "c" end
print = function() end
C_Timer = { After = function(_, fn) fn() end }
GameTooltip_Hide = function() end
PlaySound = function() end
GameTooltip = {}
IsShiftKeyDown = function() return false end
unpack = unpack or table.unpack

-- generic frame stub: records text, shown, points, scripts; unknown methods are no-ops
local created = {}
local function newFrame(ftype, name, parent, template)
  local f = { ftype = ftype, name = name, parent = parent, template = template, scripts = {}, shown = true, points = {} }
  local methods = {
    SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
    Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    SetScript = function(self, n, fn) self.scripts[n] = fn end,
    SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
    CreateFontString = function(self) return newFrame("FontString", nil, self) end,
    CreateTexture = function(self) return newFrame("Texture", nil, self) end,
    SetTexture = function(self, t) self.texture = t end,
    LockHighlight = function(self) self.locked = true end, UnlockHighlight = function(self) self.locked = false end,
    GetWidth = function() return 580 end, GetHeight = function() return 240 end,
    CreateLine = function(self) local l = newFrame("Line", nil, self); rawset(self, "linesMade", (rawget(self, "linesMade") or 0) + 1); return l end,
    SetStartPoint = function(self, ...) self.start = { ... } end, SetEndPoint = function(self, ...) self.finish = { ... } end,
    ClearAllPoints = function(self) self.points = {} end,
  }
  return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end
-- Blizzard's scroll list: the view's initializer fills reused row frames
-- for the first VISIBLE elements of the data provider.
local VISIBLE = 19
ScrollBoxConstants = { RetainScrollPosition = "retain" }
CreateDataProvider = function()
  local dp = { items = {} }
  function dp:Insert(e) self.items[#self.items + 1] = e end
  return dp
end
CreateScrollBoxListLinearView = function()
  local v = {}
  function v:SetElementExtent(h) self.extent = h end
  function v:SetElementInitializer(t, fn) self.frameType, self.init = t, fn end
  return v
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(sb, bar, view) sb.view, sb.bar = view, bar end }
CreateFrame = function(ftype, name, parent, template)
  local f = newFrame(ftype, name, parent, template)
  created[#created + 1] = f
  if template == "WowScrollBoxList" then
    f.rows = {}
    f.SetDataProvider = function(self, dp, retain)
      self.provider, self.retain = dp, retain
      for i = 1, VISIBLE do
        local e = dp.items[i]
        local row = self.rows[i]
        if e then
          if not row then row = newFrame("Button", nil, self); self.rows[i] = row end
          self.view.init(row, e)
          row:Show()
        elseif row then
          row:Hide()
        end
      end
    end
  end
  return f
end
local selected = {}
PanelTemplates_SelectTab = function(t) selected[t] = true end
PanelTemplates_DeselectTab = function(t) selected[t] = false end
PanelTemplates_TabResize = function() end
local tabIndex = {}
PanelTemplates_SetNumTabs = function(f, n) f.numTabs = n end
PanelTemplates_SetTab = function(f, i) tabIndex[f] = i end
hooksecurefunc = function(t, name, fn)
  local orig = t[name]
  t[name] = function(...) local r = orig(...); fn(...); return r end
end

C_Item = { GetItemInfo = function(x) local id = tonumber(tostring(x):match("(%d+)")); if id == 100 then return "Cloth", nil, 1 end end,
  GetItemInfoInstant = function() return 100, "", "", "", 134000 end }
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
local keyInfoLoaded = true
C_AuctionHouse = { GetBrowseResults = function() return {} end,
  MakeItemKey = function(id, lvl, suf) return { itemID = id, itemLevel = lvl or 0, itemSuffix = suf or 0 } end,
  GetItemKeyInfo = function() if keyInfoLoaded then return { isCommodity = true } end end }
-- item searches (order book)
local sentQueries, commodityResults, throttleReady = {}, {}, true
C_AuctionHouse.IsThrottledMessageSystemReady = function() return throttleReady end
C_AuctionHouse.SendSearchQuery = function(itemKey, sorts, separate) sentQueries[#sentQueries + 1] = { itemKey = itemKey, sorts = sorts, separate = separate } end
C_AuctionHouse.GetNumCommoditySearchResults = function() return #commodityResults end
C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i) return commodityResults[i] end
C_AuctionHouse.HasFullCommoditySearchResults = function() return true end
C_AuctionHouse.GetCommoditySearchResultsQuantity = function() local q = 0 for _, r in ipairs(commodityResults) do q = q + r.quantity end return q end
Enum = Enum or {}
Enum.AuctionHouseSortOrder = { Price = 0 }
-- bag 0: Cloth x20 in slot 3
local bagSlots = { [3] = { itemID = 100, hyperlink = "|Hitem:100::|h[Cloth]|h", stackCount = 20 } }
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and 8 or 0 end,
  GetContainerItemInfo = function(b, sl) return b == 0 and bagSlots[sl] or nil end,
  GetContainerItemLink = function(b, sl) local i = b == 0 and bagSlots[sl]; return i and i.hyperlink end,
}
ItemLocation = { CreateFromBagAndSlot = function(_, b, sl) return { bag = b, slot = sl } end }

-- Blizzard AH frame
local BuyTab, SellTab, AuctionsTab = newFrame("Button"), newFrame("Button"), newFrame("Button")
local modes = { Buy = { "BrowseResultsFrame" } }
local calls = {}
AuctionHouseFrame = newFrame("Frame", "AuctionHouseFrame")
AuctionHouseFrame.Tabs = { BuyTab, SellTab, AuctionsTab }
AuctionHouseFrame.displayMode = modes.Buy
AuctionHouseFrame.SetDisplayMode = function(self, m) calls[#calls + 1] = m; self.displayMode = m end
AuctionHouseFrame.SetTitle = function(self, t) self.title = t end
local selectedResult
AuctionHouseFrame.SelectBrowseResult = function(self, r) selectedResult = r end
local postedLocation
AuctionHouseFrame.SetPostItem = function(self, loc) postedLocation = loc end
local moneyBorder = newFrame("Frame")
AuctionHouseFrame.MoneyFrameBorder = moneyBorder
-- Blizzard's Auctions list with its natural-size background: 18 px short of the
-- list's right edge, 5 px above its bottom.
local blizzList = newFrame("Frame"); blizzList.GetRight = function() return 795 end; blizzList.GetBottom = function() return 27 end
local blizzBg = newFrame("Texture"); blizzBg.GetRight = function() return 777 end; blizzBg.GetBottom = function() return 32 end
blizzList.Background = blizzBg
AuctionHouseFrame.AuctionsFrame = { AllAuctionsList = blizzList }
-- Post Auctions list (preferred source): 20 px short on the right, 4 above the bottom
local sellList = newFrame("Frame"); sellList.GetRight = function() return 795 end; sellList.GetBottom = function() return 27 end
local sellBg = newFrame("Texture"); sellBg.GetRight = function() return 775 end; sellBg.GetBottom = function() return 31 end
sellList.Background = sellBg
-- its border's art stops 25 px short of the list's right edge
local sellNS = newFrame("Frame"); sellNS.GetRight = function() return 770 end; sellNS.GetBottom = function() return 27 end
sellList.NineSlice = sellNS
AuctionHouseFrame.ItemSellList = sellList

local ns = {}
for _, f in ipairs({"Core.lua", "History.lua", "Market.lua", "OrderBook.lua", "Disenchant.lua", "Strategy.lua", "Tabs.lua", "StrategyTab.lua", "MarketTab.lua"}) do
  assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns)
end
local eventFrame = created[1]
local function fire(e, ...) eventFrame.scripts.OnEvent(eventFrame, e, ...) end
fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")
fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")

local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end

local tab, panel, mtab, mpanel
for _, f in ipairs(created) do
  if f.name == "ForgedForeverAHTabStrategy" then tab = f end
  if f.name == "ForgedForeverAHTabMarket" then mtab = f end
  if f.name == "ForgedForeverAHMarketPanel" then mpanel = f end
  if f.name == "ForgedForeverAHStrategyPanel" then panel = f end
end
eq(tab ~= nil, true, "tab button created")
eq(tab.template, "AuctionHouseFrameDisplayModeTabTemplate", "Blizzard tab template")
eq(tab.points[1][2], AuctionsTab, "anchored after the last Blizzard tab")
eq(#AuctionHouseFrame.Tabs, 3, "not added to Blizzard's tab list")
eq(tab.text, "Deals", "tab text")
eq(panel.shown, false, "panel hidden at first")

-- click: Blizzard view cleared, tabs deselected, ours selected, panel shown
local data = ns.Market.Data()
data.items["100:0"] = { s = { { now - 12 * 3600, 10, 50 }, { now - 3600, 9, 35 } }, d = {} }
ns.db.history["Realm|Alliance"]["100:0"] = { next_push = now + 86400, data_points = { { value = 20, time = now - 86400 } } }
tab.scripts.OnClick()
eq(type(calls[#calls]), "table", "SetDisplayMode called"); eq(#calls[#calls], 0, "with an empty mode")
eq(rawget(AuctionHouseFrame, "displayMode"), nil, "displayMode cleared")
eq(selected[BuyTab], false, "Blizzard tabs deselected"); eq(selected[tab], true, "Strategy tab selected")
eq(AuctionHouseFrame.title, "Deals", "window title")
eq(panel.shown, true, "panel shown")
-- rows filled with resale suggestions
local inset
for _, f in ipairs(created) do if f.template == "NineSlicePanelTemplate" and f.parent == panel.list then inset = f end end
eq(inset ~= nil, true, "border is a NineSlicePanelTemplate like Blizzard's")
eq(panel.list.layoutType, "InsetFrameTemplate", "layoutType InsetFrameTemplate")
local scrollBox, scrollBar
for _, f in ipairs(created) do
  if f.template == "WowScrollBoxList" then scrollBox = f end
  if f.template == "MinimalScrollBar" then scrollBar = f end
end
eq(scrollBox ~= nil, true, "Blizzard's WowScrollBoxList")
eq(scrollBar ~= nil, true, "Blizzard's MinimalScrollBar")
eq(scrollBox.bar, scrollBar, "scroll box wired to the scroll bar")
eq(scrollBox.view.extent, 20, "20-high rows")
-- background edges copied from Blizzard's Auctions list
local bgTex = panel.bg
eq(bgTex.points[2][1], "BOTTOMRIGHT", "background bottom right set")
eq(bgTex.points[2][4], -20, "right edge: same gap as Blizzard's Post list (20)")
eq(bgTex.points[2][5], 4, "bottom edge: same gap as Blizzard's Post list (4)")
eq(inset.points[2][4], -25, "border right edge: same gap as Blizzard's Post list border (25)")
eq(inset.points[2][5], 0, "border bottom: same as Blizzard's")
eq(panel.layoutInfo.source, "ItemSellList", "copied from the Post Auctions list")
local okDebug, errDebug = pcall(SlashCmdList.FORGEDFOREVERAH, "layout debug")
eq(okDebug, true, "layout debug runs: " .. tostring(errDebug))
-- Blizzard's AuctionHouseItemListTemplate anchors (from its XML)
local list = panel.list
eq(scrollBar.points[1][2], scrollBox, "scroll bar right of the rows")
eq(scrollBar.points[1][4], 9, "ScrollBar TOPLEFT x=9"); eq(scrollBar.points[1][5], 0, "ScrollBar TOPLEFT y=0")
eq(scrollBar.points[2][4], 9, "ScrollBar BOTTOMLEFT x=9"); eq(scrollBar.points[2][5], 4, "ScrollBar BOTTOMLEFT y=4")
eq(scrollBox.points[3][1], "BOTTOM", "ScrollBox BOTTOM"); eq(scrollBox.points[3][5], 3, "ScrollBox 3 above the list bottom")
eq(inset.points[1][4], 0, "border from the list's left"); eq(inset.points[1][5], -19, "border 19 below the list top")
eq(inset.points[2][2], list, "border to the list's bottom right (around the scroll bar)")
eq(list.points[2][1], "BOTTOMRIGHT", "list bottom right"); eq(list.points[2][4], -5, "list 5 in from the window's right")
eq(list.points[2][5], 27, "list bottom 2 above the money display's top")
local rows = scrollBox.rows
-- Blizzard list look: header buttons from Blizzard's template, list background atlas
local headers = {}
for _, f in ipairs(created) do if f.template == "AuctionHouseTableHeaderStringTemplate" then headers[#headers + 1] = f end end
eq(#headers, 6, "6 Blizzard header buttons (Item + 5 columns)")
eq(headers[1].text, "Item", "first header")
eq(headers[2].text, "Buy at", "resale column header")
eq(type(headers[2].scripts.OnClick), "function", "header click sorts")
-- headers sit above the bordered list area (Blizzard's 19 px offset)
eq(headers[1].parent.parent, panel.list, "header row on the list, above the border")
local headerRow = headers[1].parent
eq(headerRow.points[1][4], 4, "HeaderContainer TOPLEFT x=4"); eq(headerRow.points[1][5], -1, "HeaderContainer y=-1")
eq(headerRow.points[2][4], -26, "HeaderContainer TOPRIGHT x=-26")
-- Blizzard's refresh button and list text
local refreshBtn
for _, f in ipairs(created) do if f.template == "RefreshButtonTemplate" then refreshBtn = f end end
eq(refreshBtn ~= nil, true, "Blizzard's refresh button template")
eq(refreshBtn.parent, panel, "refresh button on the panel")
eq(refreshBtn.points[1][2], list, "refresh anchored to the list's top right")
eq(refreshBtn.points[1][4], -4, "RefreshFrame x offset -4")
eq(refreshBtn.points[1][5], 24, "RefreshFrame y offset 34, button in the 20-high frame's middle")
-- type tabs: Blizzard's top tab template, first at (52, -43), selected via PanelTemplates
local typeTabs = {}
for _, f in ipairs(created) do if f.template == "AuctionHouseFrameTopTabTemplate" then typeTabs[#typeTabs + 1] = f end end
eq(#typeTabs, 4, "4 type tabs from Blizzard's top tab template")
eq(typeTabs[1].text, "Resale", "first tab"); eq(typeTabs[4].text, "Sell from bags", "last tab")
eq(typeTabs[1].points[1][2], AuctionHouseFrame, "first tab placed on the AH window")
eq(typeTabs[1].points[1][4], 52, "x like Blizzard's Auctions sub-tab"); eq(typeTabs[1].points[1][5], -43, "y like Blizzard's")
eq(typeTabs[2].points[1][2], typeTabs[1], "next tab after the previous")
eq(list.points[1][2], typeTabs[1], "list top right under the tabs"); eq(list.points[1][5], 1, "1 below the tabs' bottom")
eq(list.points[1][4], 4 - 52, "list 4 in from the window's left")
eq(tabIndex[typeTabs[1].parent], 1, "Resale tab selected")
typeTabs[2].scripts.OnClick()
eq(tabIndex[typeTabs[1].parent], 2, "clicking Vendor selects it")
typeTabs[1].scripts.OnClick()
eq(panel.summary.points[1][2], moneyBorder, "summary in the bottom bar after the money display")
eq(panel.summary.text:find("items tracked", 1, true) ~= nil, true, "summary text: " .. tostring(panel.summary.text))
eq(rows[1].data and rows[1].data.key, "100:0", "first row is the resale item")
eq(rows[1].name.text, "|cffffffffCloth|r", "item name colored by quality")
eq(rows[1].cells[1].text, "9c", "buy column")
-- clicking a row opens Blizzard's buy view for the item
ns.Market.Data().items["100:0"].lvl = 0
rows[1].scripts.OnClick(rows[1])
eq(selectedResult ~= nil, true, "SelectBrowseResult called")
eq(selectedResult.itemKey.itemID, 100, "item key for the row's item")
eq(selectedResult.minPrice, 9, "lowest price passed as minPrice")
selectedResult = nil
keyInfoLoaded = false
rows[1].scripts.OnClick(rows[1])
eq(selectedResult, nil, "not called while the item's info is loading")
keyInfoLoaded = true
-- Sell from bags: a click opens Blizzard's sell view with the item
ns.StrategyTab.SetType("sell")
eq(rows[1].data and rows[1].data.key, "100:0", "sell row for the bag item")
rows[1].scripts.OnClick(rows[1])
eq(postedLocation ~= nil, true, "SetPostItem called")
eq(postedLocation.bag, 0, "bag of the item"); eq(postedLocation.slot, 3, "slot of the item")
eq(selectedResult, nil, "sell rows don't open the buy view")
-- moved to another slot since the list was drawn: found again
bagSlots[5], bagSlots[3] = bagSlots[3], nil
postedLocation = nil
rows[1].scripts.OnClick(rows[1])
eq(postedLocation and postedLocation.slot, 5, "item found in its new slot")
-- gone from the bags: nothing opened
bagSlots[5] = nil
postedLocation = nil
rows[1].scripts.OnClick(rows[1])
eq(postedLocation, nil, "item not in bags: nothing opened")
ns.StrategyTab.SetType("resale")
eq(rows[1].shown, true, "row shown"); eq(rows[2], nil, "only rows for elements")
eq(rows[1].stripe.shown, true, "odd row striped")
eq(#scrollBox.provider.items, 1, "all suggestions in the data provider")
eq(rawget(scrollBox, "retain"), nil, "first draw starts at the top")
ns.StrategyTab.Refresh()
eq(scrollBox.retain, "retain", "a refresh keeps the scroll position")

-- switch type: vendor has none -> empty text
ns.StrategyTab.SetType("vendor")
eq(rows[1].shown, false, "vendor: no rows")
eq(panel.empty.shown, true, "empty message shown")
eq(panel.empty.text:find("No suggestions yet", 1, true) ~= nil, true, "empty message text")
eq(panel.empty.points[1][2], scrollBox, "ResultsText TOP relative to the ScrollBox"); eq(panel.empty.points[1][5], -45, "45 below its top")
eq(panel.empty.points[2][4], 45, "ResultsText LEFT x=45"); eq(panel.empty.points[3][4], -67, "ResultsText RIGHT x=-67")
ns.StrategyTab.SetType("resale")
eq(panel.empty.shown, false, "empty message hidden with results")

-- a Blizzard tab click hides the panel and deselects ours
AuctionHouseFrame:SetDisplayMode(modes.Buy)
eq(panel.shown, false, "Blizzard view hides the panel")
eq(selected[tab], false, "Strategy tab deselected")
-- our own empty-mode call doesn't hide it
tab.scripts.OnClick()
eq(panel.shown, true, "own click keeps panel shown")

-- Market tab: after Deals, own panel, switching between our tabs
eq(mtab ~= nil, true, "Market tab created")
eq(mtab.points[1][2], tab, "Market tab anchored after Deals")
eq(#AuctionHouseFrame.Tabs, 3, "still not in Blizzard's tab list")
mtab.scripts.OnClick()
eq(mpanel.shown, true, "Market panel shown")
eq(panel.shown, false, "Deals panel hidden by Market")
eq(selected[tab], false, "Deals tab deselected"); eq(selected[mtab], true, "Market tab selected")
eq(AuctionHouseFrame.title, "Market", "title Market")
tab.scripts.OnClick()
eq(mpanel.shown, false, "Market hidden by Deals"); eq(panel.shown, true, "Deals shown again")
AuctionHouseFrame:SetDisplayMode(modes.Buy)
eq(panel.shown, false, "Blizzard view hides Deals"); eq(mpanel.shown, false, "and Market")

-- search: tracked items by name
local M = ns.MarketTab
eq(#M.Find("clo"), 1, "partial match"); eq(M.Find("cloth")[1].key, "100:0", "exact match")
eq(#M.Find("sword"), 0, "no match")
mtab.scripts.OnClick()
M.Search("Cloth")
eq(mpanel.item.shown, true, "item shown after search")
eq(mpanel.item.name.text, "|cffffffffCloth|r", "item name")
eq(mpanel.item.prices.text:find("Lowest now: 9c (35 listed)", 1, true) ~= nil, true, "prices line: " .. tostring(mpanel.item.prices.text))
eq(mpanel.item.stats.text:find("sold/day", 1, true) ~= nil, true, "stats line: " .. tostring(mpanel.item.stats.text))
eq(mpanel.graph.shown, true, "graph shown")
eq(mpanel.graph.empty.shown, false, "graph has data")
eq((rawget(mpanel.graph.plot, "linesMade") or 0) > 5, true, "graph lines drawn: " .. tostring(rawget(mpanel.graph.plot, "linesMade")))
M.Search("nothing here")
eq(mpanel.item.shown, false, "no match hides the item")
eq(mpanel.hint.text:find("No tracked item matches", 1, true) ~= nil, true, "no-match hint")
-- order book: statistics
local OB = ns.OrderBook
local levels, loaded = OB.Levels({ { 16, 93 }, { 15, 60 }, { 15, 44 }, { 17, 4 }, { 0, 5 }, { 20, 0 }, { 133, 20 } })
eq(#levels, 4, "levels merged by price, empty/zero dropped"); eq(levels[1][1], 15, "cheapest first"); eq(levels[1][2], 104, "same price summed")
eq(loaded, 221, "loaded quantity")
local book = { levels = levels, loaded = loaded }
local total, each = OB.CostToBuy(book, 20)
eq(total, 300, "buy 20 from the first level"); eq(each, 15, "average")
total, each = OB.CostToBuy(book, 110)
eq(total, 104 * 15 + 6 * 16, "buy 110 spans two levels")
total, each = OB.CostToBuy(book, 500)
eq(total, nil, "not enough listed"); eq(each, 221, "how many are")
local q, cost = OB.BelowValue(book, 17)
eq(q, 197, "below value 17: 15c and 16c levels"); eq(cost, 104 * 15 + 93 * 16, "their cost")
eq(OB.BelowValue(book, nil), 0, "no value: none")
eq(OB.BelowValue(book, 10), 0, "nothing below")
local wp, wq = OB.Wall(book)
eq(wp, 15, "wall: first level with 10%+"); eq(wq, 104, "wall quantity")
eq(OB.Wall({ levels = { { 5, 1 }, { 6, 2 } }, loaded = 3 }), nil, "no wall with little listed")
eq(OB.Wall({ levels = { { 5, 5 }, { 6, 15 }, { 7, 180 } }, loaded = 200 }), 7, "small levels skipped")

-- order book: Market tab requests the item's search and shows the lines
AuctionHouseFrame.shown = true
mtab.scripts.OnClick()
now = now + 120 -- past the earlier test's "no answer" minute
local before = #sentQueries
M.Search("Cloth")
eq(#sentQueries, before + 1, "item search sent")
local q1 = sentQueries[#sentQueries]
eq(q1.itemKey.itemID, 100, "for the shown item"); eq(q1.sorts[1].sortOrder, 0, "sorted by price"); eq(q1.separate, true, "own items separate")
-- (C_Timer runs at once here, so the 15 s timeout has already passed)
eq(mpanel.item.book.text:find("no answer", 1, true) ~= nil, true, "no answer: " .. tostring(mpanel.item.book.text))
M.Show("100:0")
eq(#sentQueries, before + 1, "not re-sent right after no answer")
commodityResults = { { unitPrice = 9, quantity = 30 }, { unitPrice = 10, quantity = 5 }, { unitPrice = 40, quantity = 200 } }
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
local bookLine, depthLine = mpanel.item.book.text, mpanel.item.depth.text
eq(bookLine:find("Buy 20: 180c (9c each)", 1, true) ~= nil, true, "buy 20 line: " .. tostring(bookLine))
eq(bookLine:find("Buy 200: 6920c (35c each)", 1, true) ~= nil, true, "buy 200 line: " .. tostring(bookLine))
eq(bookLine:find("Buy 100: 2920c (29c each)", 1, true) ~= nil, true, "buy 100 line: " .. tostring(bookLine))
eq(depthLine:find("Wall: 30 at 9c", 1, true) ~= nil, true, "wall: " .. tostring(depthLine))
eq(depthLine:find("235 listed at 3 prices", 1, true) ~= nil, true, "listed: " .. tostring(depthLine))
eq(depthLine:find("order book just now", 1, true) ~= nil, true, "age: " .. tostring(depthLine))
M.Show("100:0")
eq(#sentQueries, before + 1, "current book: no new search")
-- throttled: waits, nothing sent
-- throttled: waits for the rate limit (timers queued here), then sends once
local queued = {}
local realAfter = C_Timer.After
C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
throttleReady = false
now = now + 120
M.Show("100:0")
eq(#sentQueries, before + 1, "rate limited: not sent yet")
eq(ns.OrderBook.IsLoading("100:0"), true, "waiting counts as loading")
local function step() local q = queued; queued = {}; for _, fn in ipairs(q) do fn() end end
step(); eq(#sentQueries, before + 1, "still limited")
throttleReady = true
step(); eq(#sentQueries, before + 2, "sent once the rate limit is ready")
M.Show("100:0"); eq(#sentQueries, before + 2, "no duplicate while loading")
-- sold out: an empty, complete search
now = now + 120; commodityResults = {}
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(ns.OrderBook.Get("100:0") and #ns.OrderBook.Get("100:0").levels, 0, "sold out: empty book")
eq(mpanel.item.book.text:find("nothing listed", 1, true) ~= nil, true, "empty book line: " .. tostring(mpanel.item.book.text))
C_Timer.After = realAfter
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
