local now = 1700000000
time = function(t) if t then return os.time(t) end return now end
date = function(f) return os.date(f, now) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
geterrorhandler = function() return error end
SlashCmdList = {}
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Alliance" end
C_AddOns = { IsAddOnLoaded = function() return false end }
unpack = unpack or table.unpack
print = function() end
local eventFrame
CreateFrame = function() local f = { RegisterEvent = function() end, SetScript = function(self, _, fn) self.onEvent = fn end }; eventFrame = eventFrame or f; return f end
local function fire(e, ...) eventFrame.onEvent(eventFrame, e, ...) end

-- Blizzard cell mixins
AuctionHouseTableCellMinPriceMixin = { Populate = function() end }
AuctionHouseTableCellUnitPriceMixin = { Populate = function() end }
AuctionHouseTableCellBuyoutMixin = { Populate = function() end }
AuctionHouseTableCellBidMixin = { Populate = function() end }
AuctionHouseTableCellCommoditiesQuantityMixin = { Populate = function() end }
PriceFontWhite = { name = "PriceFontWhite" }
local QTY_FONT = { name = "QuantityFont" }

-- ScrollUtil: remembers callbacks per scroll box, calls callback(frame, elementData)
-- Like Blizzard: iterating existing frames needs a view, which only exists once the list is shown.
ScrollUtil = { AddInitializedFrameCallback = function(sb, cb, owner, iterate)
  if iterate then sb:ForEachFrame(cb) end
  sb.cb = cb
end }
local function newScrollBox()
  local sb = { frames = {} }
  function sb:GetView() return self.view end
  function sb:ForEachFrame(fn)
    if not self.view then error("ScrollBox.lua:595: attempt to index a nil value") end
    for _, f in ipairs(self.frames) do fn(f, 1) end
  end
  return sb
end
local function newCell(mixin) return { Populate = mixin.Populate, GetObjectType = function() return "Frame" end } end
-- Timers run when flush() is called (= the next frame).
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flush() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
local function newRow(cells, rowData)
  local row = { rowData = rowData, cells = cells }
  function row:GetObjectType() return "Button" end
  function row:IsShown() return true end
  function row:GetElementData() return self.element end
  function row:GetChildren() return unpack(self.cells) end
  function row:GetRowData() return self.rowData end
  function row:CreateFontString()
    local fs = { shown = false }
    function fs:ClearAllPoints() self.point = nil end
    function fs:SetPoint(p, rel, rp, x) self.point = { p, rel, rp, x } end
    function fs:SetText(t) self.text = t end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    function fs:IsShown() return self.shown end
    function fs:GetText() return self.text end
    function fs:SetWidth(w) self.width = w end
    function fs:SetJustifyH(j) self.justify = j end
    function fs:SetFontObject(f) self.font = f end
    return fs
  end
  return row
end

local browseSB, commSB, itemSB = newScrollBox(), newScrollBox(), newScrollBox()
AuctionHouseFrame = {
  BrowseResultsFrame = { ItemList = { ScrollBox = browseSB } },
  CommoditiesBuyFrame = { ItemList = { ScrollBox = commSB } },
  ItemBuyFrame = { ItemList = { ScrollBox = itemSB } },
}
C_Item = { GetItemInfo = function() end }

local ns = {}
for _, f in ipairs({"Core.lua", "History.lua", "ValuePercent.lua"}) do assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns) end
fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")
local errors = {}
geterrorhandler = function() return function(e) errors[#errors + 1] = e end end
fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
geterrorhandler = function() return error end

local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end

eq(#errors, 0, "no error at UI load (no view yet): " .. tostring(errors[1]))
eq(type(browseSB.cb), "function", "browse callback registered")
eq(type(itemSB.cb), "function", "item callback registered")
ns.History.Observe("2589:0", 100)
ns.History.Observe("15210:1182", 10000)

-- Like the game: our callback fires first (row empty, or still holding the
-- previous entry's data), then Blizzard's table builder fills the row.
local function init(sb, row, data, idx, ownerStyle)
  if ownerStyle then sb.cb(ns, row, idx) else sb.cb(row, idx) end
  row.rowData, row.element = data, idx
  flush()
end

-- browse row: no data at callback time
local priceCell = newCell(AuctionHouseTableCellMinPriceMixin)
local row = newRow({ {}, priceCell }, nil)
init(browseSB, row, { itemKey = { itemID = 2589, itemSuffix = 0 }, minPrice = 75, totalQuantity = 20 }, 1)
eq(row.fahPercent.text, "|cff16ff1675%|r", "browse 75% green")
eq(row.fahPercent.shown, true, "browse shown")
eq(row.fahPercent.point[2], priceCell, "anchored to price cell")
eq(row.fahPercent.point[1], "LEFT", "left part of price cell")
-- reused row: old % hidden at once, new entry's % after Blizzard fills it
browseSB.cb(row, 5)
eq(row.fahPercent.shown, false, "reused row: stale % hidden immediately")
row.rowData, row.element = { itemKey = { itemID = 2589 }, minPrice = 150, totalQuantity = 2 }, 5
flush()
eq(row.fahPercent.text, "|cffff0000150%|r", "reused row: new entry's %")
-- row moved on before the next frame: skipped (newer callback handles it)
browseSB.cb(row, 6)
row.rowData, row.element = { itemKey = { itemID = 2589 }, minPrice = 40, totalQuantity = 2 }, 7
flush()
eq(row.fahPercent.shown, false, "moved row skipped")
-- unknown value: empty
local row2 = newRow({ priceCell }, nil)
init(browseSB, row2, { itemKey = { itemID = 1 }, minPrice = 75, totalQuantity = 1 }, 2)
eq(row2.fahPercent.text, "", "no value: empty text")
-- none available: hidden
init(browseSB, row, { itemKey = { itemID = 2589 }, minPrice = 0, totalQuantity = 0 }, 1)
eq(row.fahPercent.shown, false, "none available hidden")

-- commodity row
local unitCell = newCell(AuctionHouseTableCellUnitPriceMixin)
unitCell.MoneyDisplay = { name = "unit money" }
local qtyCell = newCell(AuctionHouseTableCellCommoditiesQuantityMixin)
qtyCell.Text = { GetFontObject = function() return QTY_FONT end }
local crow = newRow({ unitCell, qtyCell }, nil)
init(commSB, crow, { itemID = 2589, unitPrice = 150, quantity = 40 }, 1)
eq(crow.fahPercent.text, "|cffff0000150%|r", "commodity 150% red")
eq(crow.fahPercent.point[3], "RIGHT", "right of unit price")
eq(crow.fahPercent.point[2], unitCell.MoneyDisplay, "anchored to the price, not the wide cell")
eq(crow.fahPercent.point[4], 4, "just right of the price")
eq(crow.fahPercent.justify, "RIGHT", "right-aligned")
eq(crow.fahPercent.width, 50, "fixed width so numbers line up")
eq(crow.fahPercent.font, QTY_FONT, "same font as the quantity column")

-- item row: buyout per item, uses buyout cell not bid cell
local bidCell, buyCell = newCell(AuctionHouseTableCellBidMixin), newCell(AuctionHouseTableCellBuyoutMixin)
local irow = newRow({ bidCell, buyCell }, nil)
init(itemSB, irow, { itemKey = { itemID = 15210, itemSuffix = 1182 }, buyoutAmount = 20000, quantity = 2 }, 1)
eq(irow.fahPercent.text, "|cffffff00100%|r", "item buyout/qty 100% yellow")
eq(irow.fahPercent.point[2], buyCell, "no MoneyDisplay: falls back to the buyout cell")
eq(irow.fahPercent.font, PriceFontWhite, "item list: price font fallback")
eq(irow.fahPercent.justify, "RIGHT", "item list right-aligned")
-- no buyout: hidden
init(itemSB, irow, { itemKey = { itemID = 15210, itemSuffix = 1182 }, bidAmount = 500, quantity = 1 }, 2)
eq(irow.fahPercent.shown, false, "bid-only hidden")

-- owner-style callback (owner, frame, elementData)
local row3 = newRow({ priceCell }, nil)
init(browseSB, row3, { itemKey = { itemID = 2589 }, minPrice = 40, totalQuantity = 3 }, 3, true)
eq(row3.fahPercent.text, "|cff2992ff40%|r", "owner-style callback, 40% blue")

-- toggle with no view yet: no error
SlashCmdList.FORGEDFOREVERAH("percent")
SlashCmdList.FORGEDFOREVERAH("percent")
-- toggle off hides visible rows (list shown, has a view)
browseSB.view = {}
browseSB.frames = { row3 }
SlashCmdList.FORGEDFOREVERAH("percent")
eq(row3.fahPercent.shown, false, "toggle off hides")
SlashCmdList.FORGEDFOREVERAH("percent")
eq(row3.fahPercent.shown, true, "toggle on shows again")
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
-- debug command runs without errors
local out = {}
print = function(s) out[#out + 1] = s end
row3.GetObjectType = function() return "Button" end
SlashCmdList.FORGEDFOREVERAH("percent debug")
local all = table.concat(out, "\n")
io.write(all:find("calls=", 1, true) and "DEBUG OK\n" or ("DEBUG MISSING\n" .. all .. "\n"))
