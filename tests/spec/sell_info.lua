-- SellInfo.lua: % of value next to the unit price on Blizzard's sell forms;
-- reads the form, never writes to it.
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
  form.GetItem = function(self)
    if not self.link then return nil end
    return { IsValid = function() return true end, link = self.link }
  end
  return form
end
C_Item = { GetItemInfo = function() end, GetItemLink = function(location) return location.link end }

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
-- reading the form
local unitPrice, key = SI.Read(commodityForm)
eq(unitPrice, 10, "unit price input")
eq(key, "2836:0", "item key from the form's item")

-- our text: own frames on the auction house window, not in Blizzard's form
local h = SI.holders.CommoditiesSellFrame
eq(h ~= nil, true, "commodity form attached")
eq(h.parent, AuctionHouseFrame, "our frame is the auction house window's child, not the form's")
eq(h.allPoints, commodityForm, "covering the form")
eq(rawget(commodityForm, "fahSellInfo"), nil, "nothing written into the form")
eq(h.percent.points[1][2], commodityForm.PriceInput.MoneyInputFrame, "% right of the unit price input")
eq(h.percent.points[1][4], 8, "8 px right of it")
eq(rawget(h, "label"), nil, "no Revenue row"); eq(rawget(h, "value"), nil, "no Revenue value")
eq(rawget(h, "vendor"), nil, "no vendor comparison")
eq(SI.Revenue, nil, "Revenue removed"); eq(SI.VendorText, nil, "VendorText removed")

-- shown with the form, updated while shown
eq(h.shown, false, "hidden while the form is")
commodityForm:Show(); commodityForm.hooks.OnShow()
eq(h.shown, true, "shown with the form")
eq(h.percent.text, "|cffff0000200%|r", "10c vs market value 5c: 200%")
-- the player changes the price: picked up on the next update
commodityForm.PriceInput.amount = 4
h.scripts.OnUpdate(h, 0.2)
eq(h.percent.text, "|cffffff0080%|r", "4c: 80% (yellow: green is under 80)")
commodityForm.hooks.OnHide()
eq(h.shown, false, "hidden with the form")

-- empty item form: nothing shown, no errors
local ih = SI.holders.ItemSellFrame
itemForm.hooks.OnShow()
eq(ih.percent.text, "", "no item: no %")

io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
