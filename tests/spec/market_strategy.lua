local DAY = 86400
local now = 1700006400 -- a day boundary + some
time = function(t) if t then return os.time(t) end return now end
date = function(f) return os.date(f, now) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
geterrorhandler = function() return error end
SlashCmdList = {}
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Alliance" end
C_AddOns = { IsAddOnLoaded = function() return false end }
GetMoneyString = function(c) return c .. "c" end
local printed = {}
print = function(s) printed[#printed + 1] = s end
local eventFrame
CreateFrame = function() local f = { RegisterEvent = function() end, SetScript = function(self, _, fn) self.onEvent = fn end }; eventFrame = eventFrame or f; return f end
local function fire(e, ...) eventFrame.onEvent(eventFrame, e, ...) end

-- items: [id] = name, link, quality, ilvl, minLvl, type, sub, stack, equipLoc, icon, sellPrice
local ITEMS = {
  [100] = { "Cloth", "|Hitem:100::|h[Cloth]|h", 1, 5, 0, "", "", 20, "", 0, 5 },
  [200] = { "Junk Sword", "|Hitem:200::|h[Junk Sword]|h", 1, 10, 5, "", "", 1, "INVTYPE_WEAPON", 0, 300 },
  [300] = { "Green Chest", "|Hitem:300::|h[Green Chest]|h", 2, 25, 20, "", "", 1, "INVTYPE_CHEST", 0, 50 },
  [11083] = { "Soul Dust" }, [11082] = { "Greater Astral Essence" }, [11084] = { "Large Glimmering Shard" },
}
C_Item = { GetItemInfo = function(x)
  local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
  local t = ITEMS[id]; if not t then return end
  return t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11]
end }
local results = {}
C_AuctionHouse = { GetBrowseResults = function() return results end,
  MakeItemKey = function(id, lvl, suf) return { itemID = id, itemLevel = lvl, itemSuffix = suf } end }
local bag = {}
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and #bag or 0 end,
  GetContainerItemInfo = function(b, s) return bag[s] end,
}

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function runTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
local ns = {}
for _, f in ipairs({"Core.lua", "History.lua", "Market.lua", "Disenchant.lua", "Strategy.lua"}) do assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns) end
fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")

local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end
local function near(a, b, msg) if not a or math.abs(a - b) > 0.01 then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end

-- one scan: rows = { {id, price, qty}, ... }, outcome default "done"
local function scan(rows, outcome)
  ns:Fire("SCAN_STARTED", true)
  results = {}
  for _, r in ipairs(rows) do results[#results + 1] = { itemKey = { itemID = r[1] }, minPrice = r[2], totalQuantity = r[3] } end
  fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  ns:Fire("SCAN_FINISHED", outcome or "done", true)
end
local M = ns.Market
local data = M.Data()

-- snapshots and dedupe
scan({ { 100, 10, 50 }, { 200, 100, 3 } })
eq(#data.items["100:0"].s, 1, "first snapshot")
now = now + 3 * 3600; scan({ { 100, 10, 50 }, { 200, 100, 3 } })
eq(#data.items["100:0"].s, 1, "unchanged: no new snapshot")
eq(#data.scans, 2, "scan times recorded")
-- quantity drops = sales; item gone = 0
now = now + 3 * 3600; scan({ { 100, 11, 40 } })
eq(#data.items["100:0"].s, 2, "changed: new snapshot")
local last200 = data.items["200:0"].s[#data.items["200:0"].s]
eq(last200[3], 0, "item missing from a completed scan: quantity 0")
eq(last200[2], nil, "no price when gone")
-- partial scan doesn't mark missing items
now = now + 3 * 3600; scan({ { 300, 40, 2 } }, "user")
eq(data.items["100:0"].s[#data.items["100:0"].s][3], 40, "stopped scan keeps unseen items")
eq(#data.scans, 3, "stopped scan not counted as completed")
-- several item levels with one key: min price, summed quantity
now = now + 3 * 3600; scan({ { 100, 12, 30 }, { 100, 9, 5 }, { 200, 100, 3 }, { 300, 40, 2 } })
local l100 = data.items["100:0"].s[#data.items["100:0"].s]
eq(l100[2], 9, "lowest price across item levels"); eq(l100[3], 35, "summed quantity")

-- stats
-- earlier days of price history: market value 20 (today's minimum is 9)
ns.db.history["Realm|Alliance"]["100:0"].data_points = { { value = 20, time = now - DAY }, { value = 20, time = now - 2 * DAY } }
local s = M.Stats("100:0")
eq(s.price, 9, "current price"); eq(s.quantity, 35, "current quantity"); eq(s.listed, true, "listed")
eq(s.value, 20, "market value from history")
-- sold: 50->40 (10) + 40->35 (5) = 15 over 4h = 90/day
near(s.salesPerDay, 15 / (12 / 24), "sales per day: 15 sold over 12 h")
eq(s.volatility ~= nil, true, "volatility computed")
eq(M.Stats("200:0").listed, true, "back on the market")

-- trend: old prices 10, new 20 -> +100%
data.items["400:0"] = { s = { { now - 2 * DAY, 10, 5 }, { now - 1.5 * DAY, 10, 4 }, { now - 3600, 20, 3 } }, d = {} }
near(M.Stats("400:0").trend, 100, "trend last 24h vs before")

-- item level kept for the item key (gear): cheapest level wins
ns:Fire("SCAN_STARTED", true)
results = { { itemKey = { itemID = 300, itemLevel = 25 }, minPrice = 50, totalQuantity = 1 },
            { itemKey = { itemID = 300, itemLevel = 30 }, minPrice = 40, totalQuantity = 1 } }
fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
ns:Fire("SCAN_FINISHED", "user", true)
eq(data.items["300:0"].lvl, 30, "item level of the cheapest listing")
local ik = M.ItemKey("300:0")
eq(ik.itemID, 300, "item key id"); eq(ik.itemLevel, 30, "item key level"); eq(ik.itemSuffix, 0, "item key suffix")
eq(M.ItemKey("100:0").itemLevel, 0, "no level stored: 0")

-- daily series for the graph: item 100 listed all along, price 10 -> 11 -> 9
local series = M.DailySeries("100:0", 30)
eq(#series, 30, "30 days")
local todayE = series[30]
eq(todayE.min ~= nil, true, "today has a price")
eq(series[1].min, nil, "no data 30 days ago")
local lo, hi, sold = nil, nil, 0
for _, e in ipairs(series) do if e.min then lo = math.min(lo or e.min, e.min) end; if e.max then hi = math.max(hi or e.max, e.max) end; sold = sold + e.sold end
eq(lo, 9, "lowest over the window"); eq(hi, 11, "highest over the window"); eq(sold, 15, "sales counted (10 + 5)")

-- retention: detail older than 3 days folds into a daily summary
local base = now
data.items["500:0"] = { s = { { base - 5 * DAY, 30, 10 }, { base - 5 * DAY + 600, 20, 6 }, { base - DAY, 25, 6 } }, d = {} }
M.Prune(base)
local i5 = data.items["500:0"]
eq(#i5.d, 1, "one daily summary")
eq(i5.d[1][2], 20, "summary min"); eq(i5.d[1][3], 30, "summary max"); eq(i5.d[1][5], 4, "summary sales")
eq(#i5.s, 2, "recent detail kept plus the last old snapshot as start")
M.Prune(base)
eq(#i5.d, 1, "pruning again doesn't duplicate the summary")

-- suggestions
-- resale: item 100 lists at 9, value 20: net 19 - 9 = 10/each, roi 111%, ~30 sold/day
local resale = ns.Strategy.Resale()
eq(resale[1] and resale[1].key, "100:0", "resale top item")
near(resale[1].profit, 20 * 0.95 - 9, "resale profit after 5% cut")
-- vendor: Junk Sword listed 100, vendor pays 300
local vendor = ns.Strategy.Vendor()
eq(vendor[1] and vendor[1].key, "200:0", "vendor suggestion"); eq(vendor[1].profit, 200, "vendor profit")
-- disenchant: Green Chest ilvl 25 listed 40; mats valued -> DE value
ns.History.Observe("11083:0", 100); ns.History.Observe("11082:0", 400); ns.History.Observe("11084:0", 1000)
local de = ns.Strategy.Disenchant()
eq(de[1] and de[1].key, "300:0", "disenchant suggestion")
near(de[1].disenchant, 282.5, "expected disenchant value")
near(de[1].profit, 282.5 * 0.95 - 40, "disenchant profit after cut")
-- sell from bags: 20 Cloth, lowest listing 9 -> post 8, proceeds 20*8*.95; soulbound skipped
bag = { { itemID = 100, hyperlink = "|Hitem:100::|h[Cloth]|h", stackCount = 20 },
        { itemID = 300, hyperlink = "|Hitem:300::|h[Green Chest]|h", stackCount = 1, isBound = true } }
local sell = ns.Strategy.Sell()
eq(#sell, 1, "soulbound skipped")
eq(sell[1].price, 8, "just under the lowest listing")
near(sell[1].proceeds, 20 * 8 * 0.95, "proceeds after cut")
eq(sell[1].high, false, "9 vs value 20 is not high")

-- command prints all four sections
SlashCmdList.FORGEDFOREVERAH("strategy")
local all = table.concat(printed, "\n")
for _, h in ipairs({ "Resale (", "Vendor (", "Disenchant (", "Sell from bags (" }) do
  eq(all:find(h, 1, true) ~= nil, true, "command section " .. h)
end
-- checked prices from item searches
local comm, itemRes, full = {}, {}, true
C_AuctionHouse.GetNumCommoditySearchResults = function() return #comm end
C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i) return comm[i] end
C_AuctionHouse.GetCommoditySearchResultsQuantity = function() local q = 0 for _, r in ipairs(comm) do q = q + r.quantity end return q end
C_AuctionHouse.HasFullCommoditySearchResults = function() return full end
C_AuctionHouse.GetNumItemSearchResults = function() return #itemRes end
C_AuctionHouse.GetItemSearchResultInfo = function(_, i) return itemRes[i] end
C_AuctionHouse.GetItemSearchResultsQuantity = function() local q = 0 for _, r in ipairs(itemRes) do q = q + r.quantity end return q end
C_AuctionHouse.HasFullItemSearchResults = function() return full end
local before = M.Stats("100:0")
eq(before.checked, nil, "scan price before a check")
eq(before.priceTime ~= nil, true, "scan price has a time")
comm = { { unitPrice = 15, quantity = 104 }, { unitPrice = 16, quantity = 93 } }
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
local after = M.Stats("100:0")
eq(after.price, 15, "checked price used"); eq(after.quantity, 197, "checked quantity used"); eq(after.checked, true, "marked checked")
local snaps = #data.items["100:0"].s
eq(#data.items["100:0"].s, snaps, "a check adds no snapshot")
-- vendor deal for item 200 gone: item search with no buyouts, full results
eq(#ns.Strategy.Vendor() > 0 and ns.Strategy.Vendor()[1].key, "200:0", "vendor deal before check")
itemRes = {}
fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 200, itemLevel = 0 })
eq(M.Stats("200:0").listed, false, "sold out after check")
local still = false for _, r in ipairs(ns.Strategy.Vendor()) do if r.key == "200:0" then still = true end end
eq(still, false, "sold-out deal dropped")
-- partial (not full) empty results don't mark sold out
full = false; comm = {}
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(M.Stats("100:0").price, 15, "empty partial results ignored")
full = true
-- price above vendor via item search: per-unit buyout
itemRes = { { buyoutAmount = 1000, quantity = 2 } }
fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 200, itemLevel = 0 })
eq(M.Stats("200:0").price, 500, "item search unit price")
-- next scan clears the check
now = now + 60; scan({ { 100, 12, 30 }, { 200, 100, 3 } }, "user")
eq(M.Stats("100:0").checked, nil, "scan clears checked price"); eq(M.Stats("100:0").price, 12, "scan price again")
eq(M.Stats("200:0").price, 100, "scan price for 200 again")

-- item names: stored after a scan; unloaded ones stored when they arrive
eq(M.Name("100:0"), "Cloth", "name stored after scan")
scan({ { 999, 5, 1 } }, "user")
eq(M.Name("999:0"), nil, "unloaded item: no name yet")
local namesFired = 0
ns:Listen("ITEM_NAMES", function() namesFired = namesFired + 1 end)
ITEMS[999] = { "Late Item", "|Hitem:999::|h[Late Item]|h", 3 }
fire("GET_ITEM_INFO_RECEIVED", 999, true)
eq(M.Name("999:0"), "Late Item", "name stored when it arrives")
eq(select(2, M.Name("999:0")), 3, "quality stored")
fire("ITEM_DATA_LOAD_RESULT", 999, true)
runTimers()
eq(namesFired, 1, "ITEM_NAMES fired once (throttled)")
-- suffixed items: only the auction house's full name, never the base name
local keyInfo = {}
C_AuctionHouse.GetItemKeyInfo = function(k) return keyInfo[k.itemID .. ":" .. k.itemSuffix] end
M.Store(now, { ["200:7"] = { p = 50, q = 1, lvl = 0 } }, false)
eq(M.Suffixed("200:7"), true, "suffix key"); eq(M.Suffixed("200:0"), false, "no suffix")
M.LearnNames()
eq(M.Name("200:7"), nil, "base name not used for a suffixed item")
data.items["200:7"].n = "Junk Sword" -- base name stored by an older version
eq(M.Name("200:7"), nil, "old stored base name ignored")
M.SetName("200:7", "Junk Sword", 1)
eq(data.items["200:7"].n, "Junk Sword", "SetName without key info doesn't overwrite")
eq(M.Name("200:7"), nil, "and isn't returned")
keyInfo["200:7"] = { itemName = "Junk Sword of the Eagle", quality = 2 }
fire("ITEM_KEY_ITEM_INFO_RECEIVED", 200)
eq(M.Name("200:7"), "Junk Sword of the Eagle", "full name from item key info")
eq(select(2, M.Name("200:7")), 2, "its quality")
eq(M.Name("200:0"), "Junk Sword", "unsuffixed keeps the base name")
-- item keys: negative suffix, and the exact browse key kept from scans
M.Store(now, { ["300:-19"] = { p = 70, q = 1, lvl = 0 } }, false)
local k = M.ItemKey("300:-19")
eq(k and k.itemID, 300, "negative suffix parsed"); eq(k and k.itemSuffix, -19, "negative suffix kept")
ns:Fire("SCAN_STARTED", true)
results = { { itemKey = { itemID = 400, itemLevel = 12, itemSuffix = 5, extra = 7, fn = function() end }, minPrice = 90, totalQuantity = 2 },
            { itemKey = { itemID = 400, itemLevel = 15, itemSuffix = 5, extra = 8 }, minPrice = 80, totalQuantity = 1 } }
fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
ns:Fire("SCAN_FINISHED", "user", true)
local ik = M.ItemKey("400:5")
eq(ik.itemLevel, 15, "cheapest variant's key"); eq(ik.extra, 8, "all of Blizzard's key fields kept")
eq(data.items["400:5"].ik.fn, nil, "no functions saved")
ik.itemLevel = 1; eq(data.items["400:5"].ik.itemLevel, 15, "a copy is returned")
C_AuctionHouse.GetItemKeyInfo = function(k) if k.extra == 8 then return { itemName = "Thing of the Eagle", quality = 2 } end end
C_AuctionHouse.GetBrowseResults = function() return results end
printed = {}
SlashCmdList.FORGEDFOREVERAH("itemkey 400")
local out = table.concat(printed, " | ")
eq(out:find("Thing of the Eagle", 1, true) ~= nil, true, "itemkey command shows key info name: " .. out)
eq(out:find("browse result", 1, true) ~= nil, true, "itemkey command lists browse results")
M.SetName("400:5", "Thing of the Eagle", 2, true)
printed = {}
SlashCmdList.FORGEDFOREVERAH("itemkey thing of the")
eq(table.concat(printed, " | "):find("Item 400", 1, true) ~= nil, true, "itemkey by partial name: " .. table.concat(printed, " | "))
printed = {}
SlashCmdList.FORGEDFOREVERAH("itemkey junk sword")
eq(table.concat(printed, " | "):find("Item 200", 1, true) ~= nil, true, "itemkey by exact base name")
printed = {}
SlashCmdList.FORGEDFOREVERAH("itemkey nothing like this")
eq(table.concat(printed, " | "):find("No tracked item matches", 1, true) ~= nil, true, "itemkey no match")
-- item keys: Blizzard's own key from the scan, plain values only; negative suffixes
M.Store(now, { ["300:-12"] = { p = 70, q = 2, lvl = 25,
  ik = { itemID = 300, itemLevel = 25, itemSuffix = -12, battlePetSpeciesID = 0, junk = function() end } } }, false)
eq(rawget(data.items["300:-12"].ik, "junk"), nil, "functions not saved in the stored key")
local k = M.ItemKey("300:-12")
eq(k.itemSuffix, -12, "negative suffix kept"); eq(k.itemLevel, 25, "level from Blizzard's key")
eq(k.battlePetSpeciesID, 0, "all of Blizzard's fields kept")
k.itemLevel = 99
eq(M.ItemKey("300:-12").itemLevel, 25, "returns a copy, stored key unchanged")
eq(M.Suffixed("300:-12"), true, "negative suffix counts as suffixed")
data.items["100:0"].ik = nil
local mk = M.ItemKey("100:0")
eq(mk.itemID, 100, "no stored key: MakeItemKey fallback"); eq(mk.itemSuffix, 0, "fallback suffix 0")
eq(M.ItemKey("nonsense"), nil, "bad key")
-- /fah itemkey runs (by ID and by name)
C_AuctionHouse.GetBrowseResults = function() return { { itemKey = { itemID = 300, itemLevel = 25, itemSuffix = -12 } } } end
local n0 = #printed
SlashCmdList.FORGEDFOREVERAH("itemkey 300")
eq(#printed > n0 + 1, true, "itemkey by ID prints")
local out = table.concat(printed, " ", n0 + 1)
eq(out:find("300:-12", 1, true) ~= nil, true, "lists the variant")
eq(out:find("browse result", 1, true) ~= nil, true, "lists the browse result")
n0 = #printed
SlashCmdList.FORGEDFOREVERAH("itemkey green chest")
eq(table.concat(printed, " ", n0 + 1):find("Item 300", 1, true) ~= nil, true, "itemkey by name")
n0 = #printed
SlashCmdList.FORGEDFOREVERAH("itemkey zzz")
eq(table.concat(printed, " ", n0 + 1):find("No tracked item matches", 1, true) ~= nil, true, "itemkey no match")
M.Prune(base + 40 * DAY)
eq(data.items["500:0"], nil, "summaries older than 30 days dropped, item removed")
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
