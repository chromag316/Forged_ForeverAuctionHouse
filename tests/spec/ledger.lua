-- Ledger.lua and LedgerTab.lua: your purchases, sales and expired auctions.
local DAY = 86400
local now = 1700006400
time = function(t) if t then return os.time(t) end return now end
date = function(f, t) return os.date(f, t or now) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
geterrorhandler = function() return error end
SlashCmdList = {}
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Alliance" end
UnitName = function() return "Tester" end
C_AddOns = { IsAddOnLoaded = function() return false end }
GetMoneyString = function(c) return c .. "c" end
print = function() end
local eventFrame
CreateFrame = function() local f = { RegisterEvent = function() end, SetScript = function(self, _, fn) self.onEvent = fn end }; eventFrame = eventFrame or f; return f end
local function fire(e, ...) eventFrame.onEvent(eventFrame, e, ...) end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
StaticPopup_Show = function() end
hooksecurefunc = function(name, fn)
  local orig = _G[name]
  _G[name] = function(...) local r = orig(...); fn(...); return r end
end

local ITEMS = {
  [100] = { "Cloth", "|Hitem:100::|h[Cloth]|h" },
  [200] = { "Junk Sword", "|Hitem:200::|h[Junk Sword]|h" },
}
C_Item = { GetItemInfo = function(x)
  local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
  local t = ITEMS[id]; if not t then return end
  return t[1], t[2]
end }
local itemResults = {}
C_AuctionHouse = {
  MakeItemKey = function(id, lvl, suf) return { itemID = id, itemLevel = lvl, itemSuffix = suf } end,
  GetNumItemSearchResults = function() return #itemResults end,
  GetItemSearchResultInfo = function(_, i) return itemResults[i] end,
  GetItemSearchResultsQuantity = function() return #itemResults end,
  HasFullItemSearchResults = function() return true end,
}

local ns = {}
for _, f in ipairs({ "Core.lua", "History.lua", "Market.lua", "Strategy.lua", "ListTab.lua", "Ledger.lua", "LedgerTab.lua" }) do
  assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns)
end
fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")

local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end
local function near(a, b, msg) if not a or math.abs(a - b) > 0.01 then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end

local L = ns.Ledger
local data = L.Data()
eq(type(data.buys), "table", "ledger set up per realm and faction")

-- purchases: a commodity, when the server confirms (the last quote's price)
local start = now
now = now - 2 * DAY
AuctionHouseFrame = { BuyDialog = { itemID = 100, quantity = 20 } }
fire("COMMODITY_PRICE_UPDATED", 5, 100)
fire("COMMODITY_PURCHASE_SUCCEEDED")
eq(#data.buys, 1, "commodity purchase recorded")
local b1 = data.buys[1]
eq(b1.key, "100:0", "its key"); eq(b1.qty, 20, "quantity"); eq(b1.total, 100, "price from the quote")
eq(b1.name, "Cloth", "name"); eq(b1.left, 20, "all unsold"); eq(b1.char, "Tester", "character")
-- without a quote: the dialog's price
AuctionHouseFrame.BuyDialog = { itemID = 100, quantity = 2, PriceFrame = { GetAmount = function() return 14 end } }
fire("COMMODITY_PURCHASE_SUCCEEDED")
eq(data.buys[2].total, 14, "no quote: the dialog's total")
table.remove(data.buys, 2)

-- purchases: an item buyout (the confirmation popup says it's a buyout)
itemResults = { { auctionID = 7, quantity = 1, itemLink = ITEMS[200][2], buyoutAmount = 900 },
                { auctionID = 8, quantity = 1, itemLink = ITEMS[200][2], buyoutAmount = 950 } }
fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 200 })
StaticPopup_Show("BUYOUT_AUCTION", nil, nil, { auctionID = 7, buyout = 900 })
fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 7)
eq(#data.buys, 2, "item buyout recorded")
eq(data.buys[2].key, "200:0", "item key"); eq(data.buys[2].total, 900, "buyout price"); eq(data.buys[2].name, "Junk Sword", "name from the link")
StaticPopup_Show("BID_AUCTION", nil, nil, { auctionID = 8, bid = 500 })
fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 8)
eq(#data.buys, 2, "a bid isn't a purchase")
fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 7)
eq(#data.buys, 2, "the same buyout isn't counted twice")

-- mail: a sale invoice, cost first in, first out
now = start
local mails = {}
GetInboxNumItems = function() return #mails end
GetInboxHeaderInfo = function(i)
  local m = mails[i]
  return nil, nil, "Auction House", m.subject, m.money or 0, 0, m.daysLeft, m.items and #m.items or 0,
    nil, nil, nil, nil, nil, m.items and m.items[1] and m.items[1].count, m.items and m.items[1] and m.items[1].link
end
GetInboxInvoiceInfo = function(i)
  local m = mails[i]
  if not m.invoice then return end
  local v = m.invoice
  return v.type, v.name, "Buyer", v.bid, 0, v.deposit or 0, v.cut, 0, 0, 0, v.count
end
GetInboxItem = function(i, j) local it = mails[i].items and mails[i].items[j]; if it then return it.name, it.id, 0, it.count end end
GetInboxItemLink = function(i, j) local it = mails[i].items and mails[i].items[j]; return it and it.link end
mails = {
  { subject = "Auction successful: Cloth", daysLeft = 29.5,
    invoice = { type = "seller", name = "Cloth", bid = 300, cut = 15, count = 30 } },
  { subject = "Sale Pending: Cloth", daysLeft = 29.9,
    invoice = { type = "seller_temp_invoice", name = "Cloth", bid = 100, cut = 5, count = 10 } },
  { subject = "Auction expired: Junk Sword", daysLeft = 29,
    items = { { name = "Junk Sword", id = 200, count = 1, link = ITEMS[200][2] } } },
  { subject = "Auction cancelled: Cloth", daysLeft = 28,
    items = { { name = "Cloth", id = 100, count = 5, link = ITEMS[100][2] }, { name = "Cloth", id = 100, count = 3, link = ITEMS[100][2] } } },
  { subject = "Hello", daysLeft = 20 },
}
fire("MAIL_INBOX_UPDATE")
eq(#data.sales, 1, "one sale (a pending sale isn't one yet)")
local s1 = data.sales[1]
eq(s1.key, "100:0", "invoice's item name -> key (from a purchase)")
eq(s1.count, 30, "count"); eq(s1.gross, 300, "price"); eq(s1.cut, 15, "cut")
eq(s1.t, now - DAY / 2, "sold when the mail arrived (30 days minus days left)")
eq(s1.matched, 20, "20 of 30 bought before"); eq(s1.cost, 100, "their cost")
eq(data.buys[1].left, 0, "the purchase is used up")
local net, cost, profit = L.SaleResult(s1)
eq(net, 285, "net after the cut"); near(profit, 285 * 20 / 30 - 100, "profit on the 20 bought")
eq(#data.expired, 2, "expired and cancelled")
eq(data.expired[1].key, "200:0", "expired: key from the returned item"); eq(data.expired[1].kind, "expired", "kind")
eq(data.expired[2].count, 8, "cancelled: all returned stacks"); eq(data.expired[2].kind, "cancelled", "cancelled kind")
-- the mailbox again (later, fewer days left): nothing new
now = now + 3600
for _, m in ipairs(mails) do m.daysLeft = m.daysLeft - 3600 / DAY end
fire("MAIL_INBOX_UPDATE")
eq(#data.sales, 1, "same sale mail: not again"); eq(#data.expired, 2, "same expired mails: not again")
-- two identical sale mails: two sales
mails[#mails + 1] = { subject = "x", daysLeft = 29.5, invoice = { type = "seller", name = "Junk Sword", bid = 1500, cut = 75, count = 1 } }
mails[#mails + 1] = { subject = "x", daysLeft = 29.5, invoice = { type = "seller", name = "Junk Sword", bid = 1500, cut = 75, count = 1 } }
fire("MAIL_INBOX_UPDATE")
eq(#data.sales, 3, "two identical sales: both")
fire("MAIL_INBOX_UPDATE")
eq(#data.sales, 3, "and not again")
eq(data.sales[2].cost, 900, "first sword sale: the bought sword's cost")
eq(data.sales[3].matched, 0, "second: no purchase left")
eq(select(3, L.SaleResult(data.sales[3])), nil, "no cost: no profit")

-- names -> keys from the market data (suffixed items have their full name)
ns.Market.Data().items["300:5"] = { s = {}, d = {}, n = "Green Chest of the Eagle", nk = true }
eq(L.KeyForName("Green Chest of the Eagle"), "300:5", "full suffixed name")
eq(L.KeyForName("Nothing"), nil, "unknown name")

-- totals and the tab's lists
local T = L.Totals(now - 30 * DAY)
eq(T.sales, 3, "3 sales"); eq(T.buys, 2, "2 purchases"); eq(T.spent, 1000, "spent")
near(T.sold, 285 + 1425 * 2, "sold after the cut"); near(T.profit, 90 + 525, "profit where a cost is known")
eq(T.stockUnits, 0, "nothing unsold")
local LT = ns.LedgerTab
local sales = LT.Sales()
eq(#sales, 3, "sales rows"); eq(sales[1].t >= sales[3].t, true, "newest first")
eq(sales[3].unmatched, 10, "oldest sale: 10 without a purchase")
local summary = LT.Summary(now)
eq(summary:find("sold 3135c after the cut (3 sales)", 1, true) ~= nil, true, "summary: " .. summary)
eq(summary:find("spent 1000c (2 purchases)", 1, true) ~= nil, true, "summary spent")
-- stock: an unsold purchase, worth at today's market value after the cut
L.AddPurchase("100:0", 10, 60)
ns.History.Value = function() return 10 end
local stock = LT.Stock()
eq(#stock, 1, "one unsold lot"); eq(stock[1].count, 10, "10 left"); eq(stock[1].cost, 60, "cost")
near(stock[1].worth, 95, "worth 10 x 10c after the 5% cut"); near(stock[1].change, 35, "worth vs. cost")
eq(LT.Summary(now):find("Unsold: 60c at cost.", 1, true) ~= nil, true, "unsold in the summary")
local purchases = LT.Purchases()
eq(#purchases, 3, "purchase rows"); eq(purchases[1].each, 6, "paid each")
local expired = LT.Expired()
eq(#expired, 2, "expired rows"); eq(expired[1].deposit, nil, "no deposit estimate without the Market tab")
eq(LT.Ago(now - 7200), "2 h ago", "ago"); eq(LT.Ago(now - DAY), "1 day ago", "one day")

-- pruning: 90 days
now = now + 91 * DAY
L.Prune()
eq(#data.sales, 0, "old sales dropped"); eq(#data.expired, 0, "old expired dropped"); eq(#data.buys, 0, "old purchases dropped")
eq(#timers > 0, true, "changes queue a redraw")

io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
