local _, ns = ...

-- Sell view addition (Blizzard's item and commodity sell forms): right of
-- the Unit Price input, the price you entered as a % of the item's market
-- value, colored like the lists' %.
--
-- Nothing is added to Blizzard's sell forms: they post auctions (a
-- restricted call), so our text lives on our own frame (a child of the
-- auction house window, shown while a sell form is), anchored to the price
-- input, and only reads what the form shows: the unit price input and the
-- item. Updated a few times a second while the form is shown.

local SellInfo = {}
ns.SellInfo = SellInfo

local UPDATE_INTERVAL = 0.15
-- Right of the unit price input. There are only ~48 px left to the panel's
-- edge; Blizzard's price error icon (10 right of the input, shown only for
-- an invalid price) may overlap it then.
local PERCENT_OFFSET = 8

------------------------------------------------------------------------
-- Reading the form (read only)
------------------------------------------------------------------------

local function Call(obj, method)
    if type(obj) ~= "table" or type(obj[method]) ~= "function" then return end
    local ok, value = pcall(obj[method], obj)
    if ok then return value end
end

-- unit price, history key of the item; nil if empty
function SellInfo.Read(form)
    local unitPrice = Call(form.PriceInput, "GetAmount")
    local location = Call(form, "GetItem")
    local link
    if type(location) == "table" and Call(location, "IsValid") and C_Item and C_Item.GetItemLink then
        local ok, l = pcall(C_Item.GetItemLink, location)
        if ok then link = l end
    end
    return unitPrice, link and ns.History.KeyFromLink(link)
end

------------------------------------------------------------------------
-- Our text next to a form
------------------------------------------------------------------------

local function Attach(frame, form)
    if type(form) ~= "table" or not form.PriceInput then return end
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(form)
    holder:SetFrameLevel((form:GetFrameLevel() or 0) + 10)
    holder:Hide()

    local price = form.PriceInput.MoneyInputFrame or form.PriceInput
    holder.percent = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holder.percent:SetPoint("LEFT", price, "RIGHT", PERCENT_OFFSET, 0)

    function holder.Update()
        local unitPrice, key = SellInfo.Read(form)
        local value = key and ns.History.Value(key)
        holder.percent:SetText(ns.PercentText and ns.PercentText(unitPrice, value) or "")
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
