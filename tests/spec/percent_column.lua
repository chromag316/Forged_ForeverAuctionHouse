local now = 1700000000
time = function(t) if t then return os.time(t) end return now end
date = function(f) return os.date(f, now) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
geterrorhandler = function() return error end
SlashCmdList = {}
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Alliance" end
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Item = { GetItemInfo = function() end }
unpack = unpack or table.unpack
local printed = {}
print = function(s) printed[#printed + 1] = s end
C_Timer = { After = function(_, fn) fn() end }
ScrollUtil = { AddInitializedFrameCallback = function(sb, cb) sb.cb = cb end }
AuctionHouseTableCellMinPriceMixin = { Populate = function() end }
AuctionHouseTableCellUnitPriceMixin = { Populate = function() end }
AuctionHouseTableCellBuyoutMixin = { Populate = function() end }
AuctionHouseTableCellMixin = { Init = function() end, GetOwner = function(self) return self.owner end, BaseThing = function() return "base" end }
hooksecurefunc = function(t, name, fn)
  local orig = t[name]
  t[name] = function(...) local r = orig(...); fn(...); return r end
end
local eventFrame
CreateFrame = function() local f = { RegisterEvent = function() end, SetScript = function(self, _, fn) self.onEvent = fn end }; eventFrame = eventFrame or f; return f end
local function fire(e, ...) eventFrame.onEvent(eventFrame, e, ...) end

-- Fake table builder: columns array, header frames, Arrange count.
local function newTableBuilder()
  local tb = { columns = {}, arranged = 0 }
  function tb:Reset() self.columns = {} end
  function tb:Arrange() self.arranged = self.arranged + 1 end
  local function newColumn(name)
    local hdr = { enabled = false, scripts = {}, Arrow = { shown = false } }
    function hdr:SetEnabled(v) self.enabled = v end
    function hdr:SetScript(n, fn) self.scripts[n] = fn end
    function hdr.Arrow:SetTexCoord(...) self.coords = { ... } end
    function hdr.Arrow:Show() self.shown = true end
    function hdr.Arrow:Hide() self.shown = false end
    local c = { name = name, header = hdr }
    function c:GetHeaderFrame() return self.header end
    return c
  end
  function tb:AddCol(name) local c = newColumn(name); table.insert(self.columns, c); return c end
  function tb:AddUnsortableFixedWidthColumn(owner, pad, width, l, r, text, template)
    local c = self:AddCol("ours"); c.width, c.text, c.template = width, text, template; return c
  end
  return tb
end
-- Blizzard browse layout: Price, Name, Quantity, Favorite
local function blizzLayout(tb) tb:AddCol("price"); tb:AddCol("name"); tb:AddCol("qty"); tb:AddCol("fav") end

local itemList = { tableBuilder = newTableBuilder(), tableBuilderLayoutDirty = true, shown = false, dirtied = 0, ScrollBox = {} }
function itemList:UpdateTableBuilderLayout()
  if self.tableBuilderLayoutDirty then
    self.tableBuilder:Reset(); self.layout(self.tableBuilder); self.tableBuilder:Arrange(); self.tableBuilderLayoutDirty = false
  end
end
function itemList:SetTableBuilderLayout(fn)
  self.layout = fn; self.tableBuilderLayoutDirty = true
  if self.shown then self:UpdateTableBuilderLayout() end
end
function itemList:DirtyScrollFrame() self.dirtied = self.dirtied + 1 end
itemList:SetTableBuilderLayout(blizzLayout) -- OnLoad, before our hooks

local browse = { ItemList = itemList, browseResults = {} }
function browse:UpdateBrowseResults(added) if added then for _, r in ipairs(added) do table.insert(self.browseResults, r) end end end
function browse:SetSortOrder() end
AuctionHouseFrame = { BrowseResultsFrame = browse }

local ns = {}
for _, f in ipairs({"Core.lua", "History.lua", "ValuePercent.lua", "PercentColumn.lua"}) do assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns) end
fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")

local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end
local function names(tb) local t = {}; for i, c in ipairs(tb.columns) do t[i] = c.name end; return table.concat(t, ",") end

-- off by default: nothing added
eq(ns.db.percent_column, false, "off by default")
fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
itemList.shown = true
itemList:UpdateTableBuilderLayout()
eq(names(itemList.tableBuilder), "price,name,qty,fav", "off: Blizzard layout unchanged")
eq(ns.PercentColumnActive(), false, "off: not active")

-- toggle on prints reload note
SlashCmdList.FORGEDFOREVERAH("percent column")
eq(ns.db.percent_column, true, "toggle on")
eq(printed[#printed - 1]:find("/reload", 1, true) ~= nil, true, "mentions /reload")

-- "/reload": fresh addon state, saved variables kept, fresh Blizzard frames
eventFrame = nil
local il = { tableBuilder = newTableBuilder(), tableBuilderLayoutDirty = true, shown = false, dirtied = 0, ScrollBox = {} }
il.UpdateTableBuilderLayout = itemList.UpdateTableBuilderLayout
il.SetTableBuilderLayout = itemList.SetTableBuilderLayout
il.DirtyScrollFrame = itemList.DirtyScrollFrame
il:SetTableBuilderLayout(blizzLayout)
local bf = { ItemList = il, browseResults = {} }
bf.UpdateBrowseResults = browse.UpdateBrowseResults
bf.SetSortOrder = function() end
AuctionHouseFrame = { BrowseResultsFrame = bf }
ForgedForeverAuctionHouseCellMixinBefore = nil
ns = {}
for _, f in ipairs({"Core.lua", "History.lua", "ValuePercent.lua", "PercentColumn.lua"}) do assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns) end
fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")
eq(ns.db.percent_column, true, "setting survived reload")
fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
eq(ForgedForeverAHPercentCellMixin.BaseThing ~= nil, true, "base cell methods copied into mixin")

-- first show applies the OnLoad layout: our column after Price
il.shown = true
il:UpdateTableBuilderLayout()
eq(names(il.tableBuilder), "price,ours,name,qty,fav", "column added after Price")
local ours = il.tableBuilder.columns[2]
eq(ours.text, "%", "header text")
eq(ours.template, "ForgedForeverAHPercentCellTemplate", "cell template")
eq(ours.header.enabled, true, "header clickable")
eq(type(ours.header.scripts.OnClick), "function", "header OnClick set")
eq(ns.PercentColumnActive(), true, "active")
-- no duplicate on later calls
il:UpdateTableBuilderLayout()
eq(names(il.tableBuilder), "price,ours,name,qty,fav", "no duplicate column")
-- category change while shown: Blizzard rebuilds inside SetTableBuilderLayout
il:SetTableBuilderLayout(function(tb) tb:AddCol("price"); tb:AddCol("name"); tb:AddCol("level"); tb:AddCol("qty"); tb:AddCol("fav") end)
eq(names(il.tableBuilder), "price,ours,name,level,qty,fav", "re-added after layout rebuild while shown")
-- not shown: added on next show
il.shown = false
il:SetTableBuilderLayout(blizzLayout)
eq(names(il.tableBuilder), "price,ours,name,level,qty,fav", "hidden: old table kept until shown")
il.shown = true
il:UpdateTableBuilderLayout()
eq(names(il.tableBuilder), "price,ours,name,qty,fav", "added on next show")
ours = il.tableBuilder.columns[2]

-- cell
ns.History.Observe("1:0", 100); ns.History.Observe("2:0", 100); ns.History.Observe("3:0", 100)
local cell = { Text = { SetText = function(self, t) self.text = t end } }
for k, v in pairs(ForgedForeverAHPercentCellMixin) do cell[k] = v end
cell:Init("owner")
cell:Populate({ itemKey = { itemID = 1 }, minPrice = 85, totalQuantity = 2 })
eq(cell.Text.text, "|cffffff0085%|r", "cell shows 85%")
cell:Populate({ itemKey = { itemID = 99 }, minPrice = 85, totalQuantity = 2 })
eq(cell.Text.text, "", "cell empty without value")

-- inline % hidden while column active
local row = { cells = {}, GetObjectType = function() return "Button" end, IsShown = function() return true end }
row.GetChildren = function() return end
row.rowData = { itemKey = { itemID = 1 }, minPrice = 85, totalQuantity = 2 }
row.fahPercent = { shown = true, Hide = function(self) self.shown = false end, IsShown = function(self) return self.shown end }
il.ScrollBox.cb(row, 1)
eq(row.fahPercent.shown, false, "inline % hidden in browse list while column active")

-- sorting
local A = { itemKey = { itemID = 1 }, minPrice = 150, totalQuantity = 1, n = "A" } -- 150%
local B = { itemKey = { itemID = 2 }, minPrice = 50, totalQuantity = 1, n = "B" }  -- 50%
local C = { itemKey = { itemID = 99 }, minPrice = 10, totalQuantity = 1, n = "C" } -- no value
local D = { itemKey = { itemID = 3 }, minPrice = 100, totalQuantity = 1, n = "D" } -- 100%
bf.browseResults = { A, B, C, D }
local function order() local t = {}; for i, r in ipairs(bf.browseResults) do t[i] = r.n end; return table.concat(t) end
local click = ours.header.scripts.OnClick
click()
eq(order(), "BDAC", "asc: 50,100,150, no value last")
eq(ours.header.Arrow.shown, true, "arrow shown")
eq(il.dirtied > 0, true, "list refreshed")
click()
eq(order(), "ADBC", "desc: 150,100,50, no value last")
click()
eq(order(), "ABCD", "third click: server order restored")
eq(ours.header.Arrow.shown, false, "arrow hidden")
-- added page while sorted
click()
local E = { itemKey = { itemID = 1 }, minPrice = 20, totalQuantity = 1, n = "E" } -- 20%
bf:UpdateBrowseResults({ E })
eq(order(), "EBDAC", "added page sorted in")
click(); click()
eq(order(), "ABCDE", "server order incl. added page")
-- new search ends sort
click()
bf:UpdateBrowseResults()
eq(ours.header.Arrow.shown, false, "new search ends % sort")
click()
bf:SetSortOrder(1)
eq(ours.header.Arrow.shown, false, "Blizzard header click ends % sort")

-- toggle off note
SlashCmdList.FORGEDFOREVERAH("percent column")
eq(ns.db.percent_column, false, "toggle off")
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
