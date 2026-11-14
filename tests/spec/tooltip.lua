local now = 1700000000
time = function(t) if t then return os.time(t) end return now end
date = function(f) return os.date(f, now) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
geterrorhandler = function() return error end
SlashCmdList = {}
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Alliance" end
C_AddOns = { IsAddOnLoaded = function() return false end }
SELL_PRICE = "Sell Price"
GameTooltipText = { name = "GameTooltipText" }
GameTooltipMoneyFormat = {}
MoneyFormatterUtil = { FormatMoney = function(c) return tostring(c) .. "c" end }
unpack = unpack or table.unpack
local printed = {}
print = function(s) printed[#printed + 1] = s end
local eventFrame
CreateFrame = function() local f = { RegisterEvent = function() end, SetScript = function(self, _, fn) self.onEvent = fn end }; eventFrame = eventFrame or f; return f end
local function fire(e, ...) eventFrame.onEvent(eventFrame, e, ...) end

-- name, link, quality, ilvl, minLvl, type, subtype, stack, equipLoc, icon, sellPrice, class, sub, bindType
local ITEMS = {
  [2589] = { "Linen Cloth", "|Hitem:2589::::::::|h[Linen Cloth]|h", 1, 5, 0, "", "", 20, "", 0, 13, 7, 5, 0 },
  [9999] = { "Green Chest", "|Hitem:9999::::::::|h[Green Chest]|h", 2, 25, 20, "", "", 1, "INVTYPE_CHEST", 0, 500, 4, 1, 2 },
  [7777] = { "Soulbound Thing", "|Hitem:7777::::::::|h[Soulbound Thing]|h", 2, 25, 20, "", "", 1, "INVTYPE_CHEST", 0, 100, 4, 1, 1 },
  [5555] = { "No Vendor", "|Hitem:5555::::::::|h[No Vendor]|h", 1, 5, 0, "", "", 20, "", 0, 0, 7, 5, 0 },
  [11083] = { "Soul Dust" }, [11082] = { "Greater Astral Essence" }, [11084] = { "Large Glimmering Shard" },
}
local function info(x)
  local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
  local t = ITEMS[id]; if not t then return end
  return t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12], t[13], t[14]
end
C_Item = { GetItemInfo = info }
local bagStack = 20
C_Container = { GetContainerItemInfo = function() return { stackCount = bagStack } end }
local itemCallback, sellCallback
TooltipDataProcessor = {
  AddTooltipPostCall = function(_, fn) itemCallback = fn end,
  AddLinePostCall = function(_, fn) sellCallback = fn end,
}
Enum = { TooltipDataType = { Item = 0 }, TooltipDataLineType = { SellPrice = 11 } }
C_MerchantFrame = { GetItemInfo = function(i) return ({ { price = 100, stackCount = 5, numAvailable = -1 }, { price = 900, stackCount = 1, numAvailable = 3 } })[i] end }
GetMerchantNumItems = function() return 2 end
GetMerchantItemLink = function(i) return ({ "|Hitem:2589::|h", "|Hitem:9999::|h" })[i] end

local ns = {}
for _, f in ipairs({"Core.lua", "History.lua", "Vendor.lua", "Disenchant.lua", "Tooltip.lua"}) do assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns) end
fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")

-- Fake named tooltip with TextLeftN / TextRightN font strings.
local function newFont()
  local f = { text = nil, shown = false, font = nil, color = { 1, 1, 1 } }
  function f:SetText(t) self.text = t end
  function f:GetText() return self.text end
  function f:Show() self.shown = true end
  function f:SetFontObject(o) self.font = o end
  function f:GetFontObject() return self.font end
  function f:SetTextColor(r, g, b) self.color = { r, g, b } end
  function f:GetTextColor() return unpack(self.color) end
  return f
end
local function newTooltip(itemID, owner)
  local t = { n = 0 }
  function t:GetName() return "FakeTip" end
  function t:NumLines() return self.n end
  local function line(l, r, lr, lg, lb, rr, rg, rb)
    t.n = t.n + 1
    local left, right = newFont(), newFont()
    left.font, right.font = { name = "default" }, { name = "small" }
    left:SetText(l); left.color = { lr or 1, lg or 1, lb or 1 }
    if r then right:SetText(r); right.shown = true; right.color = { rr or 1, rg or 1, rb or 1 } end
    _G["FakeTipTextLeft" .. t.n], _G["FakeTipTextRight" .. t.n] = left, right
  end
  function t:AddLine(text, r, g, b) line(text, nil, r, g, b) end
  function t:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb) line(l, r, lr, lg, lb, rr, rg, rb) end
  function t:GetItem() local name, link = info(itemID); return name, link end
  function t:GetOwner() return owner end
  return t
end
local function lines(t)
  local out = {}
  for i = 1, t.n do
    local l, r = _G["FakeTipTextLeft" .. i], _G["FakeTipTextRight" .. i]
    out[#out + 1] = l.text .. (r.shown and (" => " .. tostring(r.text)) or "")
  end
  return table.concat(out, " | ")
end
-- Shows a tooltip the way Blizzard does: sell price line (stack total), then post calls.
local function tip(itemID, stack, owner)
  local t = newTooltip(itemID, owner)
  local _, _, _, _, _, _, _, _, _, _, unitSell = info(itemID)
  local data = { id = itemID, lines = {} }
  if unitSell and unitSell > 0 then
    local price = unitSell * (stack or 1)
    t:AddLine(("Sell Price: %dc"):format(price), 1, 1, 1)
    local lineData = { type = 11, price = price }
    data.lines[1] = lineData
    sellCallback(t, lineData)
  end
  itemCallback(t, data)
  return lines(t), t
end

local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end
local function has(s, sub, msg) if not s:find(sub, 1, true) then fails = fails + 1; io.write("FAIL " .. msg .. ": '" .. s .. "' lacks '" .. sub .. "'\n") end end

-- 1. Blizzard's sell price split: label left, price right
local s = tip(2589, 20)
has(s, "Vendor: => 13c", "sell price relabeled Vendor:, one item")
eq(_G.FakeTipTextLeft1.color[1], 1, "Vendor label white")
eq(_G.FakeTipTextRight1.color[1], 1, "Vendor price white")
eq(_G.FakeTipTextRight1.font.name, "default", "sell price right uses left font")
-- 2. our lines white, body font, label with colon
eq(s, "Vendor: => 13c | Market: => |cff808080?|r", "unknown market line")
eq(_G.FakeTipTextLeft2.color[1] == 1 and _G.FakeTipTextLeft2.color[3] == 1, true, "value label white")
eq(_G.FakeTipTextLeft2.font, GameTooltipText, "value label body font")
eq(_G.FakeTipTextRight2.font, GameTooltipText, "value price body font")
-- 3. stack totals from the sell price line
ns.History.Observe("2589:0", 50)
eq(tip(2589, 20), "Vendor: => 13c | Market: => 50c", "stack of 20 shows one item")
eq(tip(2589, 1), "Vendor: => 13c | Market: => 50c", "single item")
-- no sell price: falls back to bag stack
ns.History.Observe("5555:0", 7)
bagStack = 4
local bagButton = { GetBagID = function() return 0 end, GetID = function() return 1 end }
eq(tip(5555, 4, bagButton), "Market: => 7c", "no sell price: one item")
eq(tip(5555, 4, nil), "Market: => 7c", "no sell price, no bag: single")
-- soulbound: no value line
eq(tip(7777, 1), "Vendor: => 100c", "soulbound only sell price")
-- alignment toggle
SlashCmdList.FORGEDFOREVERAH("tooltip sell price")
has(tip(2589, 3), "Sell Price: 39c | Market: => 50c", "alignment off keeps Blizzard's stack line")
SlashCmdList.FORGEDFOREVERAH("tooltip sell price")

-- other lines
SlashCmdList.FORGEDFOREVERAH("tooltip daily")
has(tip(2589, 2), "Today: => 50c (|cffffff00100%|r)", "today line one item with percent")
fire("MERCHANT_SHOW")
SlashCmdList.FORGEDFOREVERAH("tooltip vendor buy")
has(tip(2589, 5), "Vendor Buy: => 20c", "vendor buy one item")
has(tip(9999, 1), "Vendor Buy (limited): => 900c", "limited vendor buy")
local function find(label) for i = 1, 10 do local l = _G["FakeTipTextLeft" .. i]; if l and l.text == label then return i end end end
tip(2589, 3)
local vi, mi = find("Vendor Buy:"), find("Market:")
eq(_G["FakeTipTextLeft" .. vi].color[1], 1, "vendor buy label white")
eq(_G["FakeTipTextRight" .. vi].color[1], 1, "vendor buy price white")
eq(_G["FakeTipTextRight" .. vi].text, "20c", "vendor buy price text")
eq(_G["FakeTipTextLeft" .. mi].color[1], 1, "market label still white")
eq(_G["FakeTipTextRight" .. mi].color[1], 1, "market price still white")
SlashCmdList.FORGEDFOREVERAH("tooltip disenchant value")
SlashCmdList.FORGEDFOREVERAH("tooltip disenchant distribution")
s = tip(9999, 1)
has(s, "Disenchant: => |cff808080?|r", "de value unknown")
has(s, "Disenchants into: |     75% Soul Dust (1-2)", "de outcomes")
has(s, "5% Large Glimmering Shard (1)", "de shard")
ns.History.Observe("11083:0", 100); ns.History.Observe("11082:0", 400); ns.History.Observe("11084:0", 1000)
has(tip(9999, 1), "Disenchant: => 283c", "de expected value")
eq(tip(2589, 1):find("Disenchant", 1, true), nil, "no DE lines for cloth")

SlashCmdList.FORGEDFOREVERAH("tooltip")
has(printed[#printed], "sell price", "list shows sell price option")
has(printed[#printed - 5], "market", "list shows market option")
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
