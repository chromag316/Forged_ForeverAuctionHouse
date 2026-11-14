local now = 1700000000
time = function(t) if t then return os.time(t) end return now end
date = function(f) return os.date(f, now) end
C_Item = { GetItemInfo = function() return nil end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local registered = {}
local frame = { RegisterEvent = function(_, e) registered[e] = true end, SetScript = function(self, _, fn) self.onEvent = fn end }
CreateFrame = function() return frame end
geterrorhandler = function() return error end
SlashCmdList = {}
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Alliance" end
C_AddOns = { IsAddOnLoaded = function() return false end }
local commodity = { {unitPrice = 300}, {unitPrice = 250}, {unitPrice = 400} }
local items = { {buyoutAmount = 1000, quantity = 1}, {buyoutAmount = nil, quantity = 1}, {buyoutAmount = 1800, quantity = 2} }
C_AuctionHouse = {
  GetBrowseResults = function() return { {itemKey = {itemID = 2589, itemSuffix = 0}, minPrice = 120}, {itemKey = {itemID = 15210, itemSuffix = 1182}, minPrice = 50000} } end,
  GetNumCommoditySearchResults = function() return #commodity end,
  GetCommoditySearchResultInfo = function(_, i) return commodity[i] end,
  GetNumItemSearchResults = function() return #items end,
  GetItemSearchResultInfo = function(_, i) return items[i] end,
}
local printed = {}
print = function(s) printed[#printed + 1] = s end

local ns = {}
for _, f in ipairs({"Core.lua", "History.lua"}) do assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns) end
local function fire(e, ...) frame.onEvent(frame, e, ...) end

local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end

fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")
local H = ns.History
eq(type(ForgedForeverAuctionHouseDB.history["Realm|Alliance"]), "table", "db created per realm/faction")

fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
eq(H.MarketValue("2589:0"), 120, "browse recorded")
eq(H.MarketValue("15210:1182"), 50000, "browse suffix key")
fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { {itemKey = {itemID = 2589}, minPrice = 100} })
eq(H.MarketValue("2589:0"), 100, "added page lowers min")
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
eq(H.MarketValue("2770:0"), 250, "commodity lowest")
fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 15210, itemSuffix = 1182})
eq(H.MarketValue("15210:1182"), 900, "item unit price from 1800/2")
eq(H.Value("2770:0"), 250, "value = today without points")

now = now + 86400 * 1.5
eq(H.MarketValue("2770:0"), nil, "rolled over")
eq(#H.DataPoints("2770:0"), 1, "data point")
eq(H.Value("2770:0"), 250, "value from point")

eq(H.KeyFromLink("|cff1eff00|Hitem:15210:0:0:0:0:0:1182:0|h[x]|h|r"), "15210:1182", "link suffix")
eq(H.KeyFromLink("|Hitem:2589::::::::60|h[Linen Cloth]|h"), "2589:0", "link empty fields")

SlashCmdList.FORGEDFOREVERAH("value 2770")
eq(printed[#printed]:find("2770") ~= nil or printed[#printed]:find("item") ~= nil, true, "value command prints")
SlashCmdList.FORGEDFOREVERAH("history")
eq(printed[#printed]:find("3 items") ~= nil, true, "history count")
SlashCmdList.FORGEDFOREVERAH("history clear")
eq(H.Count(), 0, "cleared")
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
