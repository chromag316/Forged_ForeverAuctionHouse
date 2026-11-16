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

C_Item = { GetItemInfo = function(x) if itemInfoOverride then return itemInfoOverride(x) end local id = tonumber(tostring(x):match("(%d+)")); if id == 100 then return "Cloth", nil, 1 end end,
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
-- the Buy view's search box (SearchBar.SearchBox)
local blizzSearchBox = newFrame("EditBox")
AuctionHouseFrame.SearchBar = { SearchBox = blizzSearchBox }

local ns = {}
for _, f in ipairs({"Core.lua", "History.lua", "Market.lua", "OrderBook.lua", "Disenchant.lua", "Strategy.lua", "Tabs.lua", "ListTab.lua", "StrategyTab.lua", "MarketTab.lua", "Ledger.lua", "LedgerTab.lua"}) do
  assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns)
end
local eventFrame = created[1]
local function fire(e, ...) eventFrame.scripts.OnEvent(eventFrame, e, ...) end
fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")
-- Data confidence (Market.Confidence) is tested on its own below; the
-- other tests use items with only a few scans.
local realConfidence = { lowScans = 3, lowDays = 1, highScans = 8, highDays = 3 }
ns.Market.CONFIDENCE.lowScans, ns.Market.CONFIDENCE.lowDays = 0, 0
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
  if f.template == "WowScrollBoxList" and f.parent == panel.list then scrollBox = f end
  if f.template == "MinimalScrollBar" and f.parent == panel.list then scrollBar = f end
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
local function under(f, root) while type(f) == "table" do if f == root then return true end f = rawget(f, "parent") end return false end
for _, f in ipairs(created) do if f.template == "AuctionHouseTableHeaderStringTemplate" and under(f, panel) then headers[#headers + 1] = f end end
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
for _, f in ipairs(created) do if f.template == "RefreshButtonTemplate" and f.parent == panel then refreshBtn = f end end
eq(refreshBtn ~= nil, true, "Blizzard's refresh button template")
eq(refreshBtn.parent, panel, "refresh button on the panel")
eq(refreshBtn.points[1][2], list, "refresh anchored to the list's top right")
eq(refreshBtn.points[1][4], -4, "RefreshFrame x offset -4")
eq(refreshBtn.points[1][5], 24, "RefreshFrame y offset 34, button in the 20-high frame's middle")
-- type tabs: Blizzard's top tab template, first at (52, -43), selected via PanelTemplates (the Deals panel's)
local typeTabs = {}
for _, f in ipairs(created) do if f.template == "AuctionHouseFrameTopTabTemplate" and f.parent and f.parent.parent == panel then typeTabs[#typeTabs + 1] = f end end
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
-- Ledger tab: after Market, its own list panel with four lists
local ltab, lpanel
for _, f in ipairs(created) do
  if f.name == "ForgedForeverAHTabLedger" then ltab = f end
  if f.name == "ForgedForeverAHLedgerPanel" then lpanel = f end
end
eq(ltab ~= nil, true, "Ledger tab created"); eq(ltab.text, "Ledger", "Ledger tab text")
eq(ltab.points[1][2], mtab, "Ledger tab anchored after Market")
ltab.scripts.OnClick()
eq(lpanel.shown, true, "Ledger panel shown"); eq(panel.shown, false, "Deals hidden by Ledger")
eq(#lpanel.typeTabs.Tabs, 4, "Sales, Purchases, Unsold stock, Expired")
eq(lpanel.typeTabs.Tabs[3].text, "Unsold stock", "stock list")
eq(lpanel.headers[2].text, "Sold for", "sales columns"); eq(lpanel.itemHeader.text, "Item", "item column")
eq(lpanel.empty.text:find("Auction successful", 1, true) ~= nil, true, "empty sales text")
eq(lpanel.summary.text:find("Last 30 days", 1, true) ~= nil, true, "summary in the bottom bar")
ns.LedgerTab.SetType("purchases")
eq(lpanel.headers[2].text, "Paid each", "purchase columns")
AuctionHouseFrame:SetDisplayMode(modes.Buy)
eq(lpanel.shown, false, "Blizzard view hides the Ledger")

-- search: tracked items by name
local M = ns.MarketTab
eq(#M.Find("clo"), 1, "partial match"); eq(M.Find("cloth")[1].key, "100:0", "exact match")
eq(#M.Find("sword"), 0, "no match")
mtab.scripts.OnClick()
M.Search("Cloth")
eq(mpanel.left.content.shown, true, "item shown after search")
-- Sell view layout: panels, backgrounds and borders on Blizzard's sell frames
local L, R = mpanel.left, mpanel.graph
-- (no ItemSellFrame in this fake client: the XML's anchors)
eq(L.points[1][1], "TOP", "left: TOP"); eq(L.points[1][2], AuctionHouseFrame, "of the window"); eq(L.points[1][5], -69, "69 down")
eq(L.points[2][2], moneyBorder, "left: BOTTOM on the money display"); eq(L.points[2][5], 2, "2 above it")
eq(L.points[3][1], "LEFT", "left: LEFT"); eq(L.points[3][4], 4, "4 in")
eq(R.points[1][2], sellList, "right panel on ItemSellList"); eq(R.points[1][1], "TOPLEFT", "right TOPLEFT")
eq(R.points[2][2], sellList, "right panel BOTTOMRIGHT on ItemSellList"); eq(R.points[2][1], "BOTTOMRIGHT", "right BOTTOMRIGHT")
eq(R.bg.points[1][2], sellBg, "right background on Blizzard's background"); eq(R.border.points[1][2], sellNS, "right border on Blizzard's border")
eq(L.points[1][1] ~= nil, true, "left anchored")
eq(rawget(L, "tab"), nil, "no tab above the left panel")
eq(mpanel.search.points[1][1], "TOPLEFT", "search box TOPLEFT"); eq(mpanel.search.points[1][2], blizzSearchBox, "on the Buy view's search box")
eq(mpanel.search.points[2][1], "BOTTOMRIGHT", "search box BOTTOMRIGHT"); eq(mpanel.search.points[2][2], blizzSearchBox, "same size")
eq(R.header.text, "Price History (30 days)", "right header")
eq(mpanel.left.display.name.text, "|cffffffffCloth|r", "item name")
eq(mpanel.left.rows.price.value.text, "9c (35 listed)", "lowest now row")
eq(mpanel.left.rows.price.label.text, "Lowest now", "row label")
eq(mpanel.left.rows.sales.value.text:find("sold/day", 1, true) ~= nil, true, "sales row: " .. tostring(mpanel.left.rows.sales.value.text))
eq(mpanel.graph.plot.shown, true, "graph shown")
eq(mpanel.graph.empty.shown, false, "graph has data")
local dayLabels = {}
for _, l in ipairs(mpanel.graph.labels) do if l.text then dayLabels[l.text] = l end end
eq(dayLabels["30 days ago"] and dayLabels["30 days ago"].points[1][1], "TOPLEFT", "first day label starts at the left edge")
eq(dayLabels["30 days ago"] and dayLabels["30 days ago"].points[1][4], 0, "at x 0")
eq(dayLabels["today"] and dayLabels["today"].points[1][1], "TOPRIGHT", "last day label ends at the right edge")
eq(dayLabels["15 days ago"] and dayLabels["15 days ago"].points[1][1], "TOP", "middle label centered")
eq((rawget(mpanel.graph.plot, "linesMade") or 0) > 5, true, "graph lines drawn: " .. tostring(rawget(mpanel.graph.plot, "linesMade")))
M.Search("nothing here")
eq(mpanel.left.content.shown, false, "no match hides the item")
eq(mpanel.hint.shown, true, "hint shown")
eq(mpanel.hint.text:find("No tracked item matches", 1, true) ~= nil, true, "no-match hint")
-- order book: statistics
local OB = ns.OrderBook
local levels, loaded = OB.Levels({ { 16, 93 }, { 15, 60 }, { 15, 44 }, { 17, 4 }, { 0, 5 }, { 20, 0 }, { 133, 20 } })
eq(#levels, 4, "levels merged by price, empty/zero dropped"); eq(levels[1][1], 15, "cheapest first"); eq(levels[1][2], 104, "same price summed")
eq(loaded, 221, "loaded quantity")
local book = { levels = levels, loaded = loaded }
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
eq(mpanel.left.rows.below.value.text:find("no answer", 1, true) ~= nil, true, "no answer: " .. tostring(mpanel.left.rows.below.value.text))
M.Show("100:0")
eq(#sentQueries, before + 1, "not re-sent right after no answer")
commodityResults = {
  { unitPrice = 9, quantity = 30, owners = { "Ann", "Bo" }, totalNumberOfOwners = 2 },
  { unitPrice = 10, quantity = 5, owners = { "Me" }, totalNumberOfOwners = 1, numOwnerItems = 5, containsOwnerItem = true },
  { unitPrice = 40, quantity = 200, owners = { "Ann" }, totalNumberOfOwners = 3 },
}
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
local rows = mpanel.left.rows
eq(rawget(rows, "buy1"), nil, "no cost-to-buy rows"); eq(rawget(rows, "buy3"), nil, "none at all")
eq(ns.OrderBook.CostToBuy, nil, "CostToBuy removed")
eq(rows.wall.value.text, "30 at 9c", "wall row")
eq(rows.sellers.label.text, "Sellers", "sellers row")
eq(rows.sellers.value.text, "3 to 6 at 3 prices", "commodity: a range (a row names 1 of its 3 owners) at N prices")
eq(rawget(rows, "auctions"), nil, "no auctions row")
eq(rows.own.value.text, "|cffff5050undercut|r by 30: 5 at 10c", "your listings: undercut by 30 cheaper units")
eq(rows.supply.value.text:find("235 vs ", 1, true) ~= nil, true, "supply: now vs average: " .. tostring(rows.supply.value.text))
eq(rows.data.value.text:find("(medium)", 1, true) ~= nil, true, "data row: confidence: " .. tostring(rows.data.value.text))
eq(rows.supply.value.text:find("|cff808080", 1, true), nil, "medium confidence: nothing grayed")
ns.Market.CONFIDENCE.lowScans = realConfidence.lowScans
M.Show("100:0")
eq(rows.data.value.text:find("|cffff5050(low)|r", 1, true) ~= nil, true, "data row: low in red: " .. tostring(rows.data.value.text))
eq(rows.supply.value.text:sub(1, 10), "|cff808080", "low confidence: history figures grayed")
eq(rows.sales.value.text:sub(1, 10), "|cff808080", "sales grayed")
eq(rows.price.value.text:find("|cff808080", 1, true), nil, "current price not grayed")
ns.Market.CONFIDENCE.lowScans = 0
M.Show("100:0")
eq(rows.sales.value.text:find("days", 1, true), nil, "days of data no longer in the sales row: " .. tostring(rows.sales.value.text))
eq(rows.data.label.text, "Data", "data row")
eq(rows.data.value.text:find(" scans, ", 1, true) ~= nil, true, "data row: scans and days: " .. tostring(rows.data.value.text))
eq(rows.sellthrough.label.text, "Sell-through", "sell-through row")
eq(rows.sellthrough.value.text:find("% per day", 1, true) ~= nil, true, "sell-through value: " .. tostring(rows.sellthrough.value.text))
eq(rows.dayssupply.label.text, "Days of supply", "days of supply row")
eq(rawget(rows, "listed"), nil, "no listings row")
eq(mpanel.left.note.text, "Order book: just now", "order book age note")
eq(mpanel.count.text, "235 listed", "count left of the refresh button")
-- refresh button: asks again even though the book is current
local beforeRefresh = #sentQueries
ns.MarketTab.Refresh()
eq(#sentQueries, beforeRefresh + 1, "refresh re-sends the search")
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
before = before + 1
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
eq(mpanel.left.rows.below.value.text, "nothing listed with a buyout", "empty book row")
C_Timer.After = realAfter
-- competition: sellers, auctions, your listings
local C = ns.OrderBook.Competition
local c = C({ { 10, 5, owners = { "A" }, ownersTotal = 1 }, { 10, 3, owners = { "A" }, ownersTotal = 1 },
              { 12, 4, owners = { "B", "Me" }, ownersTotal = 2, own = 2 }, { 0, 9, owners = { "Z" } } })
eq(c.auctions, 3, "auctions: rows with a buyout"); eq(c.sellers, 3, "distinct sellers, you included"); eq(c.sellersMore, false, "all owners named")
eq(c.sellersLow, 3, "exact: low"); eq(c.sellersHigh, 3, "exact: high")
eq(c.own.quantity, 2, "your units"); eq(c.own.price, 12, "your lowest"); eq(c.otherLowest, 10, "others' lowest")
eq(c.cheaperUnits, 8, "others' units below your price")
local mt = ns.MarketTab
local a1, o1 = mt.CompetitionText(c)
eq(a1, "3 (3 auctions)", "items: sellers (auctions)")
eq((mt.CompetitionText(c, true)), "3 at 3 prices", "commodity: sellers at prices"); eq(o1, "|cffff5050undercut|r by 8: 2 at 12c", "undercut text")
c = C({ { 9, 2, owners = { "Me" }, ownersTotal = 1, own = 2 }, { 9, 4, owners = { "B" }, ownersTotal = 1 } })
eq(select(2, mt.CompetitionText(c)), "|cff40c040cheapest|r: 2 at 9c", "tied counts as cheapest")
c = C({ { 9, 4, owners = { "B" }, ownersTotal = 1 } })
eq(select(2, mt.CompetitionText(c)), "none", "no own listings")
eq(mt.CompetitionText(c), "1 (1 auction)", "singular auction")
eq((mt.CompetitionText(c, true)), "1 at 1 price", "singular price")
c = C({ { 5, 10, owners = { "A", "B" }, ownersTotal = 7 }, { 6, 10, owners = { "A" }, ownersTotal = 4 } })
eq(c.sellersLow, 7, "low: the most owners in one row"); eq(c.sellersHigh, 11, "high: rows added up")
eq((mt.CompetitionText(c, true)), "7 to 11 at 2 prices", "range text")
eq(mt.CompetitionText(nil), "---", "no book")
-- demand texts
local MT = ns.MarketTab
eq(MT.Decimal(2186.54), ns.FullScan and "2,186.5" or "2186.5", "decimal (separators come from FullScan.lua, not loaded here)"); eq(MT.Decimal(1.96), "2.0", "rounds up a tenth")
local st, ds = MT.DemandText(2000, 4000)
eq(st, "50% per day", "sell-through: 2,000 of 4,000 a day"); eq(ds, "2.0 days", "days of supply: 2.0, neither fast nor slow")
st, ds = MT.DemandText(3000, 4000)
eq(ds, "1.3 days |cff40c040(fast)|r", "under 2 days: fast")
st, ds = MT.DemandText(1, 30)
eq(st, "3% per day", "small sell-through"); eq(ds, "30.0 days |cffff5050(slow)|r", "over 14 days: slow")
st = MT.DemandText(1, 500); eq(st, "<1% per day", "under 1%")
st, ds = MT.DemandText(0, 50); eq(st, "0% per day", "no sales"); eq(ds, "no sales seen", "no sales: no days of supply")
st, ds = MT.DemandText(5, 0); eq(st, "nothing listed", "nothing listed"); eq(ds, "---", "no days of supply")
st, ds = MT.DemandText(nil, 50); eq(st, "---", "too little data")
eq(MT.DataText(6, 2.04), "6 scans, 2.0 days", "data text"); eq(MT.DataText(1, 0.5), "1 scan, 0.5 days", "one scan")
eq(MT.DataText(3, nil), "---", "no data")
-- profit after costs (the box under the graph)
local PV = MT.ProfitValues
local realStats, realGetItemInfo = ns.Market.Stats, C_Item.GetItemInfo
local stats = { value = 100, listed = true, price = 80, salesPerDay = 10, quantity = 40 }
ns.Market.Stats = function() return stats end
GetCVar = function(name) if name == "auctionHouseDurationDropdown" then return "2" end end
AUCTION_DURATION_TWO = "24 Hours"
local depositArgs
C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = true } end
C_AuctionHouse.CalculateCommodityDeposit = function(_, duration, quantity) depositArgs = { duration, quantity }; return 4 * quantity end
local idx, hours, dtext = MT.Duration()
eq(idx, 2, "duration from Blizzard's saved choice"); eq(hours, 24, "hours from its text"); eq(dtext, "24 Hours", "duration text")
local pv = PV("100:0")
eq(pv.flip, "|cff40c040+15c each (+19%)|r", "flip: 100 after 5% cut = 95, minus 80")
eq(depositArgs[1], 2, "deposit for the sell view's duration"); eq(depositArgs[2], 100, "per unit from 100")
-- sells 10 of 40 a day: 25% within 24 h, so 75% of the 4c deposit is lost
eq(pv.deposit, "4c each (24 Hours), ~3c lost", "deposit and expected loss")
eq(pv.breakeven, "92c to resell at value", "break-even: 95 - 3")
eq(pv.disenchant, "---", "no item info: no disenchant")
stats = { value = 100, listed = true, price = 120, salesPerDay = 100, quantity = 40 }
pv = PV("100:0")
eq(pv.flip, "|cffff5050-25c each (-21%)|r", "negative margin in red")
eq(pv.deposit, "4c each (24 Hours), ~0c lost", "sells within the duration: nothing lost")
eq(pv.breakeven, "95c to resell at value", "break-even without deposit loss")
stats = { listed = false }
pv = PV("100:0")
eq(pv.flip, "no market value yet", "no value"); eq(pv.breakeven, "---", "no break-even")
eq(pv.deposit, "4c each (24 Hours)", "no sales data: no expected loss")
stats = { value = 100, listed = false }
eq(PV("100:0").flip, "not listed", "not listed")
-- other items: the client needs one in your bags
C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = false } end
eq(PV("100:0").deposit, "--- (needs one in your bags)", "item not in bags")
-- vendor and disenchant from the item's info
itemInfoOverride = function() return "Sword", nil, 2, 12, nil, nil, nil, nil, "INVTYPE_WEAPON", nil, 25 end
ns.Vendor = { BuyPrice = function() return 120, true end }
pv = PV("100:0")
eq(pv.vendor, "pays 25c, sells for 120c (limited)", "vendor floor and ceiling")
eq(pv.disenchant, "--- (no material prices yet)", "disenchantable, materials unpriced")
itemInfoOverride = function() return "Cloth", nil, 1, 5, nil, nil, nil, nil, "", nil, 0 end
ns.Vendor = nil
pv = PV("100:0")
eq(pv.vendor, "pays nothing", "vendor pays nothing"); eq(pv.disenchant, "not disenchantable", "not gear")
ns.Market.Stats, itemInfoOverride = realStats, nil
-- layout: under the graph, which ends above it
local profit = mpanel.graph.profit
eq(profit.rows.flip.label.text, "Flip margin", "profit rows under the graph")
eq(profit.rows.breakeven.label.text, "Break-even buy", "break-even row")
eq(mpanel.graph.plot.points[2][3], 26 + 5 * 20 + 22, "graph ends above the profit box")
eq(profit.points[1][1], "BOTTOMLEFT", "box at the panel's bottom")
-- timing view: averages, summary, switching from the price history
eq(MT.AverageText(50, 7, 7, 60), "50c (now +20%)", "average vs. now")
eq(MT.AverageText(50, 3, 30, nil), "50c over 3 days", "fewer days than the period, not listed")
eq(MT.AverageText(50, 1, 7, 40), "50c over 1 day (now -20%)", "one day")
eq(MT.AverageText(nil, 0, 7, 40), "---", "no average")
local tm = { hours = { [2] = { price = 0.9, quantity = 0.5 }, [7] = { price = 1.1, quantity = 1.5 } },
             days = { [2] = { price = 0.95, quantity = 2 }, [7] = { price = 1.05, quantity = 0.2 } } }
eq(MT.TimingSummary(tm), "Cheapest at 3-6 h and on Tue; most listed at 18-21 h and on Tue.", "summary")
tm.days = { [3] = { price = 1, quantity = 1 } }
eq(MT.TimingSummary(tm), "Cheapest at 3-6 h; most listed at 18-21 h.", "one weekday: hours only")
eq(MT.TimingSummary({ hours = {}, days = {} }), "", "no data: no summary")
local g = mpanel.graph
eq(g.header.text, "Price History (30 days)", "history header"); eq(g.timingHeader.text, "Timing", "timing header")
M.Show("100:0")
eq(g.plot.shown, true, "history view by default"); eq(g.timing.shown, false, "timing hidden")
g.timingHeader.scripts.OnClick()
eq(g.timing.shown, true, "timing view shown"); eq(g.plot.shown, false, "graph hidden"); eq(g.legend.shown, false, "legend hidden")
eq(g.profit.shown, true, "profit box stays")
local labelShown = false; for _, l in ipairs(g.labels) do if l.shown then labelShown = true end end
eq(labelShown, false, "graph price and day labels hidden")
eq(#g.labels > 0, true, "the graph had labels")
eq(g.timing.rows.avg7.label.text, "7-day average", "7-day row")
eq(g.timing.rows.avg30.label.text, "30-day average", "30-day row")
eq(g.timing.note.text, "No timing data yet: every scan from now on adds to it.", "no timing yet")
eq(#g.timing.hours.bars, 8, "8 time-of-day bars"); eq(#g.timing.days.bars, 7, "7 weekday bars")
eq(g.timing.hours.bars[1].pct.text, "---", "empty slot")
local realTiming = ns.Market.Timing
ns.Market.Timing = function() return { hours = { [1] = { price = 0.8, quantity = 1, weight = 5 }, [2] = { price = 1.2, quantity = 1, weight = 1 } }, days = {}, samples = 6 } end
M.Show("100:0")
eq(g.timing.hours.bars[1].pct.text, "|cff40c040-20%|r", "cheaper slot in green")
eq(g.timing.hours.bars[2].pct.text, "|cffff5050+20%|r", "pricier slot in red")
eq(g.timing.note.text, "Vs. its usual level, from ~6 scans (recent ones count most).", "scans note")
ns.Market.Timing = realTiming
g.header.scripts.OnClick()
eq(g.plot.shown, true, "back to the history"); eq(g.timing.shown, false, "timing hidden again")
eq(g.labels[1].shown, true, "labels back with the graph")
M.Show(nil)
eq(g.timing.shown, false, "no item: no timing")
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
