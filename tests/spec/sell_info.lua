-- SellInfo.lua: % of value next to the unit price and the Revenue row on
-- Blizzard's sell forms; reads the form, never writes to it.
local now = 1700000000
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

local function newFrame(parent)
  local f = { parent = parent, scripts = {}, hooks = {}, points = {}, shown = false, level = 5 }
  local methods = {
    SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
    SetAllPoints = function(self, rel) self.allPoints = rel end,
    SetScript = function(self, name, fn) self.scripts[name] = fn end,
    HookScript = function(self, name, fn) self.hooks[name] = fn end,
    Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    SetShown = function(self, v) self.shown = v and true or false end,
    GetFrameLevel = function(self) return self.level end,
    SetFrameLevel = function(self, l) self.level = l end,
    CreateFontString = function(self) return newFrame(self) end,
    SetText = function(self, t) self.text = t end,
    SetWidth = function(self, w) self.width = w end,
    SetJustifyH = function(self, j) self.justify = j end,
    RegisterEvent = function() end,
  }
  return setmetatable(f, { __index = methods })
end
local eventFrame
CreateFrame = function(_, _, parent)
  local f = newFrame(parent)
  eventFrame = eventFrame or f
  return f
end
local function fire(e, ...) eventFrame.scripts.OnEvent(eventFrame, e, ...) end

-- A sell form as Blizzard builds it: price input, deposit and total displays, item.
local function money(amount) return { amount = amount, GetAmount = function(self) return self.amount end } end
local function newForm(amount, total, deposit, link)
  local form = newFrame(nil)
  form.PriceInput = { MoneyInputFrame = { name = "money input" }, amount = amount,
                      GetAmount = function(self) return self.amount end }
  form.Deposit = { MoneyDisplayFrame = money(deposit) }
  form.TotalPrice = { Label = { name = "total label" }, MoneyDisplayFrame = money(total) }
  form.link = link
  form.QuantityInput = { quantity = 1, GetQuantity = function(self) return self.quantity end }
  form.GetItem = function(self)
    if not self.link then return nil end
    return { IsValid = function() return true end, link = self.link }
  end
  return form
end
-- Rough Stone: vendors pay 2c each (11th value of GetItemInfo)
C_Item = { GetItemInfo = function(x)
  if tostring(x):find("item:2836", 1, true) then return "Rough Stone", x, 1, 1, 1, "", "", 20, "", 0, 2 end
end, GetItemLink = function(location) return location.link end }

local commodityForm = newForm(10, 10, 100, "|Hitem:2836::::::::|h[Rough Stone]|h")
local itemForm = newForm(0, 0, 0, nil)
AuctionHouseFrame = newFrame(nil)
AuctionHouseFrame.CommoditiesSellFrame = commodityForm
AuctionHouseFrame.ItemSellFrame = itemForm

local ns = {}
for _, f in ipairs({ "Core.lua", "History.lua", "ValuePercent.lua", "SellInfo.lua" }) do
  assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns)
end
fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")
ns.History.Observe("2836:0", 5) -- market value 5c
fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")

local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end

local SI = ns.SellInfo
-- revenue: the cut comes off a sale, the deposit is lost only if it doesn't sell
local sold, unsold = SI.Revenue(10, 100)
eq(sold, 9, "10c sold: 10c - 5% cut, rounded down"); eq(unsold, -100, "unsold: the deposit")
sold = SI.Revenue(1000, 30); eq(sold, 950, "10s sold: 9s 50c")
eq(SI.RevenueText(10, 100), "9c if it sells, |cffff5050-100c|r if not", "revenue text")
eq(SI.RevenueText(0, 100), "", "no price: empty")
eq(SI.RevenueText(nil, 100), "", "nothing entered: empty")

-- reading the form
local unitPrice, total, deposit, key, quantity = SI.Read(commodityForm)
eq(quantity, 1, "quantity input")
eq(unitPrice, 10, "unit price input"); eq(total, 10, "total price display"); eq(deposit, 100, "deposit display")
eq(key, "2836:0", "item key from the form's item")

-- our text: own frames on the auction house window, not in Blizzard's form
local h = SI.holders.CommoditiesSellFrame
eq(h ~= nil, true, "commodity form attached")
eq(h.parent, AuctionHouseFrame, "our frame is the auction house window's child, not the form's")
eq(h.allPoints, commodityForm, "covering the form")
eq(rawget(commodityForm, "fahSellInfo"), nil, "nothing written into the form")
eq(h.percent.points[1][2], commodityForm.PriceInput.MoneyInputFrame, "% right of the unit price input")
eq(h.label.points[1][2], commodityForm.TotalPrice.Label, "Revenue label aligned with Total Price's")
eq(h.label.points[1][5], -82, "one row below the Create Auction button")
eq(h.label.text, "Revenue", "label")
eq(h.label.width, 93, "Blizzard's label width"); eq(h.label.justify, "RIGHT", "right-aligned like Blizzard's")

-- shown with the form, updated while shown
eq(h.shown, false, "hidden while the form is")
commodityForm:Show(); commodityForm.hooks.OnShow()
eq(h.shown, true, "shown with the form")
eq(h.percent.text, "|cffff0000200%|r", "10c vs market value 5c: 200%")
eq(h.value.text, "9c if it sells, |cffff5050-100c|r if not", "revenue row")
eq(h.vendor.text, "|cffffffffVendor:|r 2c", "vendor: 1 x 2c, less than the auction house's 9c")
eq(h.vendor.points[1][2], commodityForm.TotalPrice.Label, "vendor on the Total Price row")
eq(h.vendor.points[1][4], 148, "right of the total amount")
-- the player changes the price: picked up on the next update
commodityForm.PriceInput.amount = 4
commodityForm.TotalPrice.MoneyDisplayFrame.amount = 12
h.scripts.OnUpdate(h, 0.2)
eq(h.percent.text, "|cffffff0080%|r", "4c: 80% (yellow: green is under 80)")
eq(h.value.text, "11c if it sells, |cffff5050-100c|r if not", "3 x 4c = 12c: 11c after the cut")
-- 6 at 2c: 12c, 11c after the cut; a vendor pays 6 x 2c = 12c: green
commodityForm.QuantityInput.quantity = 6
commodityForm.PriceInput.amount = 2
h.scripts.OnUpdate(h, 0.2)
eq(h.vendor.text, "|cff40c040Vendor:|r 12c", "vendor beats the auction house: green")
commodityForm.hooks.OnHide()
eq(h.shown, false, "hidden with the form")

-- empty item form: nothing shown, no errors
local ih = SI.holders.ItemSellFrame
itemForm.hooks.OnShow()
eq(ih.percent.text, "", "no item: no %")
eq(ih.value.text, "", "no price: no revenue")
eq(ih.label.shown, false, "Revenue label hidden without a price")

-- vendor text on its own
eq(SI.VendorText(nil, 3, 30), "Vendor: none", "vendors don't buy it")
eq(SI.VendorText(5, 0, 30), "", "no quantity")
eq(SI.VendorText(5, 3, 0), "", "no price entered")
eq(ih.vendor.text, "", "no item: no vendor text")
-- item form without a quantity input: quantity from total / unit price
local f2 = newForm(50, 150, 10, "|Hitem:2836::::::::|h[Rough Stone]|h"); f2.QuantityInput = nil
eq(select(5, SI.Read(f2)), 3, "quantity = total / unit price")
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
