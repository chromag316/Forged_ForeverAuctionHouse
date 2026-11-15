local _, ns = ...

-- Sell view additions (Blizzard's item and commodity sell forms)
--
--   % of value   right of the Unit Price input: the price you entered as a
--                % of the item's market value, colored like the lists' %
--   Vendor       right of the Total Price: what a vendor pays for the same
--                quantity, green when that beats the auction house (the
--                revenue if it sells)
--   Revenue      a row below the Create Auction button, aligned with
--                Blizzard's rows: what you get if it sells (the total price
--                minus the 5% auction house cut; the deposit is refunded on
--                a sale), and what you lose if it doesn't (the deposit)
--
-- Nothing is added to Blizzard's sell forms: they post auctions (a
-- restricted call), so our text lives on our own frame (a child of the
-- auction house window, shown while a sell form is), anchored to
-- Blizzard's rows, and only reads what the form shows: the unit price
-- input, the quantity input, the deposit and total price displays, and the
-- item. Updated a few times a second while the form is shown.

local SellInfo = {}
ns.SellInfo = SellInfo

local UPDATE_INTERVAL = 0.15
-- Blizzard's form rows are 30 high with 15 between them; the Create
-- Auction button (22 high) follows Total Price. The Revenue row goes one
-- row below the button: 15 + 22 + 15 + 15 (half a row) below the Total
-- Price row's middle, plus its own half: 82.
local REVENUE_OFFSET = -82
-- Right of the unit price input. There are only ~48 px left to the panel's
-- edge; Blizzard's price error icon (10 right of the input, shown only for
-- an invalid price) may overlap it then.
local PERCENT_OFFSET = 8
-- Vendor comparison: right of the Total Price amount, which starts 18 right
-- of its label; room for a ~130 px amount.
local VENDOR_X = 18 + 130

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local function Money(c)
    if c < 0 then return "|cffff5050-" .. ns.FormatMoney(-c) .. "|r" end
    return ns.FormatMoney(c)
end

-- If it sells: the total minus the cut (deposit refunded); if it doesn't:
-- minus the deposit.
function SellInfo.Revenue(total, deposit)
    local cut = (ns.Strategy and ns.Strategy.AH_CUT) or 0.05
    return math.floor(total * (1 - cut)), -(deposit or 0)
end

-- "Vendor: 6c", green when a vendor pays at least what the auction house
-- does if it sells; "Vendor: none" for items vendors don't buy.
function SellInfo.VendorText(vendorEach, quantity, total)
    if not quantity or quantity <= 0 or not total or total <= 0 then return "" end
    if not vendorEach or vendorEach <= 0 then return "Vendor: none" end
    local vendor = vendorEach * quantity
    local sold = SellInfo.Revenue(total, 0)
    local color = vendor >= sold and "|cff40c040" or "|cffffffff"
    return ("%sVendor:|r %s"):format(color, ns.FormatMoney(vendor))
end

function SellInfo.RevenueText(total, deposit)
    if not total or total <= 0 then return "" end
    local sold, unsold = SellInfo.Revenue(total, deposit)
    return ("%s if it sells, %s if not"):format(Money(sold), Money(unsold))
end

------------------------------------------------------------------------
-- Reading the form (read only)
------------------------------------------------------------------------

local function Call(obj, method)
    if type(obj) ~= "table" or type(obj[method]) ~= "function" then return end
    local ok, value = pcall(obj[method], obj)
    if ok then return value end
end

-- unit price, total price, deposit, history key of the item, quantity,
-- item link; nil if empty
function SellInfo.Read(form)
    local unitPrice = Call(form.PriceInput, "GetAmount")
    local total = Call(form.TotalPrice and form.TotalPrice.MoneyDisplayFrame, "GetAmount")
    local deposit = Call(form.Deposit and form.Deposit.MoneyDisplayFrame, "GetAmount")
    local location = Call(form, "GetItem")
    local link
    if type(location) == "table" and Call(location, "IsValid") and C_Item and C_Item.GetItemLink then
        local ok, l = pcall(C_Item.GetItemLink, location)
        if ok then link = l end
    end
    local quantity = Call(form.QuantityInput, "GetQuantity")
    if type(quantity) ~= "number" or quantity <= 0 then
        -- Item form without a quantity input: from total and unit price.
        quantity = (unitPrice and unitPrice > 0 and total) and math.floor(total / unitPrice + .5) or 1
    end
    return unitPrice, total, deposit, link and ns.History.KeyFromLink(link), quantity, link
end

------------------------------------------------------------------------
-- Our text next to a form
------------------------------------------------------------------------

local function Attach(frame, form)
    if type(form) ~= "table" or not form.PriceInput or not form.TotalPrice then return end
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(form)
    holder:SetFrameLevel((form:GetFrameLevel() or 0) + 10)
    holder:Hide()

    local price = form.PriceInput.MoneyInputFrame or form.PriceInput
    holder.percent = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holder.percent:SetPoint("LEFT", price, "RIGHT", PERCENT_OFFSET, 0)

    -- Label like Blizzard's (gold GameFontNormal, right-aligned, 93 wide),
    -- right edge on Total Price's label; value 18 right of it.
    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    holder.label:SetWidth(93)
    holder.label:SetJustifyH("RIGHT")
    holder.label:SetText("Revenue")
    local totalLabel = form.TotalPrice.Label or form.TotalPrice
    holder.label:SetPoint("RIGHT", totalLabel, "RIGHT", 0, REVENUE_OFFSET)
    holder.vendor = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.vendor:SetPoint("LEFT", totalLabel, "RIGHT", VENDOR_X, 0)
    holder.value = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holder.value:SetJustifyH("LEFT")
    holder.value:SetPoint("LEFT", holder.label, "RIGHT", 18, 0)

    function holder.Update()
        local unitPrice, total, deposit, key, quantity, link = SellInfo.Read(form)
        local vendorEach = link and select(11, GetItemInfo(link))
        holder.vendor:SetText(link and SellInfo.VendorText(vendorEach, quantity, total) or "")
        local value = key and ns.History.Value(key)
        holder.percent:SetText(ns.PercentText and ns.PercentText(unitPrice, value) or "")
        holder.value:SetText(SellInfo.RevenueText(total, deposit))
        holder.label:SetShown(total ~= nil and total > 0)
    end

    local elapsed = 0
    holder:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0
        holder.Update()
    end)
    holder:SetScript("OnShow", function() holder.Update() end)
    form:HookScript("OnShow", function() holder:Show() end)
    form:HookScript("OnHide", function() holder:Hide() end)
    if form:IsShown() then holder:Show() end
    return holder
end

SellInfo.holders = {}

ns:Listen("AUCTION_UI_LOADED", function(frame)
    for _, name in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
        local ok, holder = pcall(Attach, frame, frame[name])
        if not ok then
            geterrorhandler()(holder)
        elseif holder then
            SellInfo.holders[name] = holder
        end
    end
end)
