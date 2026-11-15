local _, ns = ...

-- Ledger: your own auction house results
--
-- Recorded per realm and faction, for all your characters there:
--   purchases  when a purchase goes through in Blizzard's buy views:
--              stackable items (commodities) when the server confirms
--              (COMMODITY_PURCHASE_SUCCEEDED; item and quantity from
--              Blizzard's buy dialog, the price from the server's last quote,
--              COMMODITY_PRICE_UPDATED); other items when a buyout completes
--              (AUCTION_HOUSE_PURCHASE_COMPLETED for the auction Blizzard's
--              buyout confirmation was shown for; bids aren't purchases)
--   sales      from the "Auction successful" mails' invoices, when the
--              mailbox is open: item name, count, price, the auction house
--              cut; a sale you never open the mailbox for isn't seen
--   expired    "Auction expired" and "Auction cancelled" mails (item and
--              quantity from the returned item)
--
-- Only reads: nothing here buys, posts or takes mail. Purchases are watched
-- through events and a hook on StaticPopup_Show (after it runs).
--
-- Cost of a sale: first in, first out. A sale uses up your oldest purchases
-- of the item made before it; the part with no purchase behind it (farmed,
-- crafted, bought before the ledger) has no cost and no profit.
--
--   ForgedForeverAuctionHouseDB.ledger["Realm|Faction"] = {
--     buys    = { { t, key, name, qty, total, left, char }, ... },
--     sales   = { { t, key, name, count, gross, cut, cost, matched, char }, ... },
--     expired = { { t, key, name, count, kind = "expired"|"cancelled", char }, ... },
--   }
-- (named fields.) Kept 90 days; purchases nobody sold within 90 days are
-- dropped too (most likely used, vendored or destroyed).
--
-- The internal message LEDGER_CHANGED says something was recorded.

local Ledger = {}
ns.Ledger = Ledger

local DAY = 24 * 60 * 60
local KEEP_DAYS = 90
local MAIL_DAYS = 30           -- auction house mails last 30 days
local MAIL_MATCH = 2 * 3600    -- the same mail seen again: arrival within 2 h

ns.DEFAULTS.ledger = {}

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local data

local function Char()
    return UnitName and UnitName("player") or nil
end

ns:Listen("LOGIN", function()
    local key = ns.RealmFactionKey()
    ns.db.ledger[key] = ns.db.ledger[key] or {}
    data = ns.db.ledger[key]
    data.buys = data.buys or {}
    data.sales = data.sales or {}
    data.expired = data.expired or {}
    Ledger.Prune()
end)

function Ledger.Data()
    return data
end

function Ledger.Prune(now)
    if not data then return end
    local cutoff = (now or time()) - KEEP_DAYS * DAY
    for _, list in pairs({ data.buys, data.sales, data.expired }) do
        local keep = {}
        for _, e in ipairs(list) do
            if e.t >= cutoff then keep[#keep + 1] = e end
        end
        wipe(list)
        for i, e in ipairs(keep) do list[i] = e end
    end
end

local function ItemID(key)
    return key and tonumber(key:match("^(%d+)"))
end

-- A name for a key: the market data's (full, with a random suffix), else
-- the client's item info.
local function NameOf(key, link)
    if link then
        local name = GetItemInfo(link)
        if name then return name end
    end
    local name = key and ns.Market.Name(key)
    if name then return name end
    local itemID = ItemID(key)
    return itemID and GetItemInfo(itemID) or nil
end

-- The history key for an item name (mail invoices only name the item): a
-- purchase of it, else the market data (the unsuffixed variant first).
function Ledger.KeyForName(name)
    if not name then return end
    if data then
        for i = #data.buys, 1, -1 do
            if data.buys[i].name == name then return data.buys[i].key end
        end
    end
    local market = ns.Market.Data()
    local found
    for key, item in pairs(market and market.items or {}) do
        if item.n == name then
            if key:match(":0$") then return key end
            found = found or key
        end
    end
    if found then return found end
    for key in pairs(market and market.items or {}) do
        if key:match(":0$") and not ns.Market.Suffixed(key) and GetItemInfo(ItemID(key)) == name then return key end
    end
end

------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------

function Ledger.AddPurchase(key, qty, total, link, t)
    if not data or not key or not qty or qty <= 0 or not total then return end
    local buy = { t = t or time(), key = key, name = NameOf(key, link), qty = qty, total = total,
                  left = qty, char = Char() }
    data.buys[#data.buys + 1] = buy
    ns:Fire("LEDGER_CHANGED")
    return buy
end

-- Uses up the oldest purchases of the item made before the sale (first in,
-- first out): returns their cost and how many of the sold units they cover.
local function Consume(key, count, t)
    local cost, matched = 0, 0
    if not key then return cost, matched end
    for _, buy in ipairs(data.buys) do
        if matched >= count then break end
        if buy.key == key and buy.left > 0 and buy.t <= t then
            local take = math.min(buy.left, count - matched)
            cost = cost + buy.total / buy.qty * take
            buy.left = buy.left - take
            matched = matched + take
        end
    end
    return cost, matched
end

function Ledger.AddSale(name, count, gross, cut, t, key)
    if not data or not count or count <= 0 or not gross then return end
    key = key or Ledger.KeyForName(name)
    local cost, matched = Consume(key, count, t)
    local sale = { t = t, key = key, name = name, count = count, gross = gross, cut = cut or 0,
                   cost = cost, matched = matched, char = Char() }
    data.sales[#data.sales + 1] = sale
    ns:Fire("LEDGER_CHANGED")
    return sale
end

function Ledger.AddExpired(key, name, count, kind, t)
    if not data then return end
    local e = { t = t, key = key, name = name or NameOf(key), count = count or 1, kind = kind, char = Char() }
    data.expired[#data.expired + 1] = e
    ns:Fire("LEDGER_CHANGED")
    return e
end

-- Purchases: stackable items. Blizzard's buy dialog (AuctionHouseFrame.
-- BuyDialog, read only) knows the item and quantity; the server's last
-- quote the price.
local quote
ns:On("COMMODITY_PRICE_UPDATED", function(unitPrice, totalPrice)
    quote = { unit = unitPrice, total = totalPrice }
end)

ns:On("COMMODITY_PURCHASE_SUCCEEDED", function()
    local dialog = AuctionHouseFrame and AuctionHouseFrame.BuyDialog
    local itemID = dialog and dialog.itemID
    local qty = dialog and dialog.quantity
    local total = quote and quote.total
    if not total and dialog and type(dialog.PriceFrame) == "table" and dialog.PriceFrame.GetAmount then
        local ok, amount = pcall(dialog.PriceFrame.GetAmount, dialog.PriceFrame)
        if ok then total = amount end
    end
    quote = nil
    if itemID and qty then Ledger.AddPurchase(itemID .. ":0", qty, total) end
end)

-- Purchases: other items. Their search results give each auction's item
-- and quantity; Blizzard's buyout confirmation (StaticPopup
-- "BUYOUT_AUCTION", data = { auctionID, buyout }) says it's a buyout, not a
-- bid.
local auctions = {} -- [auctionID] = { key, qty, link }, this session
local buyout        -- { auctionID, buyout } of the last buyout confirmation

local function CacheAuctions(itemKey)
    if not itemKey then return end
    local key = ns.History.KeyFromItemKey(itemKey)
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.auctionID then
            auctions[r.auctionID] = { key = key, qty = math.max(1, r.quantity or 1), link = r.itemLink }
        end
    end
end
ns:On("ITEM_SEARCH_RESULTS_UPDATED", CacheAuctions)
ns:On("ITEM_SEARCH_RESULTS_ADDED", CacheAuctions)

if hooksecurefunc and StaticPopup_Show then
    hooksecurefunc("StaticPopup_Show", function(which, _, _, popupData)
        if which == "BUYOUT_AUCTION" and type(popupData) == "table" then
            buyout = { auctionID = popupData.auctionID, buyout = popupData.buyout }
        end
    end)
end

function Ledger.OnPurchaseCompleted(auctionID)
    if not (buyout and buyout.auctionID == auctionID and buyout.buyout) then return end
    local a, amount = auctions[auctionID], buyout.buyout
    buyout = nil
    if a then Ledger.AddPurchase(a.key, a.qty, amount, a.link) end
end
ns:On("AUCTION_HOUSE_PURCHASE_COMPLETED", Ledger.OnPurchaseCompleted)

------------------------------------------------------------------------
-- Mail: sales, expired and cancelled auctions
------------------------------------------------------------------------

-- "Auction expired: %s" -> "^Auction expired: (.+)$"
local function SubjectPattern(format, fallback)
    format = type(format) == "string" and format or fallback
    local escaped = format:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

-- An already recorded entry for the same mail (seen in an earlier visit):
-- same item, count and amount, arrived within 2 hours; each entry stands
-- for one mail per visit (`used`).
local function Recorded(list, used, t, name, count, amount, field)
    for _, e in ipairs(list) do
        if not used[e] and e.name == name and e.count == count and (not field or e[field] == amount)
            and math.abs(e.t - t) <= MAIL_MATCH then
            used[e] = true
            return true
        end
    end
end

local function MailItems(index)
    local count, link = 0, nil
    if GetInboxItem then
        for j = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
            local _, _, _, n = GetInboxItem(index, j)
            if n then
                count = count + n
                link = link or (GetInboxItemLink and GetInboxItemLink(index, j))
            end
        end
    end
    return count, link
end

function Ledger.ScanMail(now)
    if not data or not GetInboxNumItems then return end
    now = now or time()
    local expiredPattern = SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s")
    local cancelledPattern = SubjectPattern(AUCTION_REMOVED_MAIL_SUBJECT, "Auction cancelled: %s")
    local usedSales, usedExpired = {}, {}
    for i = 1, GetInboxNumItems() do
        local _, _, _, subject, _, _, daysLeft, _, _, _, _, _, _, firstQuantity, firstLink = GetInboxHeaderInfo(i)
        local t = math.floor(now - (MAIL_DAYS - (daysLeft or MAIL_DAYS)) * DAY)
        local invoiceType, itemName, bid, consignment, count, _
        if GetInboxInvoiceInfo then
            invoiceType, itemName, _, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
        end
        if invoiceType == "seller" and itemName and bid then
            count = count or 1
            if not Recorded(data.sales, usedSales, t, itemName, count, bid, "gross") then
                local sale = Ledger.AddSale(itemName, count, bid, consignment, t)
                if sale then usedSales[sale] = true end -- an identical mail after it is another sale
            end
        elseif type(subject) == "string" then
            local name, kind = subject:match(expiredPattern), "expired"
            if not name then name, kind = subject:match(cancelledPattern), "cancelled" end
            if name then
                local qty, link = MailItems(i)
                link = link or firstLink
                if qty == 0 then qty = firstQuantity or 1 end
                local key = link and ns.History.KeyFromLink(link) or Ledger.KeyForName(name)
                if not Recorded(data.expired, usedExpired, t, name, qty) then
                    local e = Ledger.AddExpired(key, name, qty, kind, t)
                    if e then usedExpired[e] = true end
                end
            end
        end
    end
end

ns:On("MAIL_INBOX_UPDATE", function() Ledger.ScanMail() end)

------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------

-- A sale's figures: net (after the cut), cost of the units with a
-- purchase behind them, profit on those (nil if none).
function Ledger.SaleResult(sale)
    local net = sale.gross - (sale.cut or 0)
    local profit
    if sale.matched and sale.matched > 0 then
        profit = net * sale.matched / sale.count - sale.cost
    end
    return net, sale.cost, profit
end

-- Totals since `since` (time): sold (net), spent, profit, number of sales
-- and purchases; and the unsold stock now (cost, units).
function Ledger.Totals(since)
    local t = { sold = 0, spent = 0, profit = 0, sales = 0, buys = 0, stock = 0, stockUnits = 0 }
    if not data then return t end
    for _, sale in ipairs(data.sales) do
        if sale.t >= since then
            local net, _, profit = Ledger.SaleResult(sale)
            t.sold, t.sales = t.sold + net, t.sales + 1
            if profit then t.profit = t.profit + profit end
        end
    end
    for _, buy in ipairs(data.buys) do
        if buy.t >= since then t.spent, t.buys = t.spent + buy.total, t.buys + 1 end
        if buy.left > 0 then
            t.stock = t.stock + buy.total / buy.qty * buy.left
            t.stockUnits = t.stockUnits + buy.left
        end
    end
    return t
end
