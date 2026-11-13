local _, ns = ...

-- Tooltip lines (from the 1.12 addon's tooltip.lua)
--
-- Adds price lines to every item tooltip: label on the left, price on the
-- right, in the tooltip's standard font and Blizzard's money format. Prices
-- are for one item, also when the tooltip is for a stack.
--   Market:           historical value (price history)        on by default
--   Today:            today's lowest price and % of value      off
--   Vendor Buy:       vendor buy price (learned at merchants)  off
--   Disenchant:       expected disenchant value               off
--   Disenchants into: possible outcomes                       off
--
-- Blizzard's own "Sell Price: <money>" line (the stack's total) becomes
-- "Vendor:" with one item's price on the right, so all prices
-- line up (on by default).
-- Toggle with /fah tooltip <line>.

local History, Vendor, Disenchant = ns.History, ns.Vendor, ns.Disenchant

ns.DEFAULTS.tooltip = {
    value = true,
    daily = false,
    vendor_buy = false,
    disenchant_value = false,
    disenchant_distribution = false,
    align_sell_price = true,
}

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local UNKNOWN = "|cff808080?|r"

-- Money in the same format as Blizzard's sell price line.
local function Money(copper)
    if not copper then return UNKNOWN end
    copper = math.floor(copper + .5)
    if MoneyFormatterUtil and MoneyFormatterUtil.FormatMoney and GameTooltipMoneyFormat then
        local ok, text = pcall(MoneyFormatterUtil.FormatMoney, copper, GameTooltipMoneyFormat)
        if ok and text then return text end
    end
    return ns.FormatMoney(copper)
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

-- The left/right font strings of line n (nil for unnamed tooltips).
local function LineFonts(tooltip, n)
    local name = tooltip.GetName and tooltip:GetName()
    if not name then return end
    return _G[name .. "TextLeft" .. n], _G[name .. "TextRight" .. n]
end

-- Gives line n the tooltip's standard body font on both sides, so our lines
-- look like Blizzard's.
local function UseBodyFont(tooltip, n)
    if not GameTooltipText then return end
    local left, right = LineFonts(tooltip, n)
    if left then left:SetFontObject(GameTooltipText) end
    if right then right:SetFontObject(GameTooltipText) end
end

local VENDOR_LABEL = "Vendor:" -- replaces Blizzard's "Sell Price:"

-- "Label:" on the left, price text on the right, both white.
local function AddPriceLine(tooltip, label, text)
    tooltip:AddDoubleLine(label .. ":", text, 1, 1, 1, 1, 1, 1)
    UseBodyFont(tooltip, tooltip:NumLines())
end

local function AddTextLine(tooltip, text)
    tooltip:AddLine(text, 1, 1, 1)
    UseBodyFont(tooltip, tooltip:NumLines())
end

-- Percentage text colored like aux: blue < 50, green < 80, yellow < 110,
-- orange < 135, red above.
local function Percent(price, reference)
    if not price or not reference or reference <= 0 then return "" end
    local pct = math.floor(price / reference * 100 + .5)
    local color = pct < 50 and "2992ff" or pct < 80 and "16ff16" or pct < 110 and "ffff00"
        or pct < 135 and "ff9218" or "ff0000"
    return (" (|cff%s%d%%|r)"):format(color, pct)
end

function ns.AddTooltipLines(tooltip, link)
    local settings = ns.db and ns.db.tooltip
    if not settings or not link then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end

    local _, _, quality, itemLevel, _, _, _, _, equipLoc, _, _, _, _, bindType = GetItemInfo(link)

    -- Bind on pickup (1) and quest items (4) can't be auctioned.
    local auctionable = bindType ~= 1 and bindType ~= 4
    if auctionable and (settings.value or settings.daily) then
        local key = History.KeyFromLink(link)
        local value = History.Value(key)
        if settings.value then
            AddPriceLine(tooltip, "Market", Money(value))
        end
        if settings.daily then
            local today = History.MarketValue(key)
            AddPriceLine(tooltip, "Today", Money(today) .. Percent(today, value))
        end
    end

    if settings.vendor_buy then
        local price, limited = Vendor.BuyPrice(itemID)
        if price then
            AddPriceLine(tooltip, "Vendor Buy" .. (limited and " (limited)" or ""), Money(price))
        end
    end

    if settings.disenchant_value or settings.disenchant_distribution then
        local outcomes = Disenchant.Distribution(equipLoc, quality, itemLevel, itemID)
        if #outcomes > 0 then
            if settings.disenchant_value then
                local value = Disenchant.Value(equipLoc, quality, itemLevel, itemID)
                AddPriceLine(tooltip, "Disenchant", Money(value))
            end
            if settings.disenchant_distribution then
                AddTextLine(tooltip, "Disenchants into:")
                table.sort(outcomes, function(a, b) return a.probability > b.probability end)
                for _, e in ipairs(outcomes) do
                    local name = GetItemInfo(e.itemID) or ("item " .. e.itemID)
                    local amount = e.min == e.max and e.min or (e.min .. "-" .. e.max)
                    AddTextLine(tooltip, ("    %g%% %s (%s)"):format(e.probability * 100, name, amount))
                end
            end
        end
    end
end

local function OnItemTooltip(tooltip, data)
    if not tooltip.AddLine then return end
    local link
    if tooltip.GetItem then
        link = select(2, tooltip:GetItem())
    end
    if not link and data and data.id then
        link = select(2, GetItemInfo(data.id))
    end
    if IsSecret(link) then return end
    ns.AddTooltipLines(tooltip, link)
end

-- Blizzard adds "Sell Price: <money>" as one left-aligned line (in a line
-- post call registered before ours); its price is the whole stack's. Rewrite
-- it as "Vendor:" on the left and one item's price on the right, both white.
-- The two-line minimum/maximum variant is left as it is.
local function AlignSellPrice(tooltip, lineData)
    local settings = ns.db and ns.db.tooltip
    if not settings or not settings.align_sell_price then return end
    if tooltip.isShopping or not lineData or type(lineData.price) ~= "number" or IsSecret(lineData.price) then return end
    if lineData.maxPrice and lineData.maxPrice >= 1 then return end
    local left, right = LineFonts(tooltip, tooltip:NumLines())
    if not left or not right then return end
    local text = left:GetText()
    local prefix = (SELL_PRICE or "Sell Price") .. ":"
    if type(text) ~= "string" or IsSecret(text) or text:sub(1, #prefix) ~= prefix then return end
    -- One item's sell price from item info; the line's own price if unknown.
    local price = lineData.price
    local link = tooltip.GetItem and select(2, tooltip:GetItem())
    if type(link) == "string" and not IsSecret(link) then
        local unitPrice = select(11, GetItemInfo(link))
        if type(unitPrice) == "number" and unitPrice > 0 then price = unitPrice end
    end
    left:SetText(VENDOR_LABEL)
    left:SetTextColor(1, 1, 1)
    right:SetText(Money(price))
    right:SetTextColor(1, 1, 1)
    right:SetFontObject(left:GetFontObject())
    right:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    if TooltipDataProcessor.AddLinePostCall and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice then
        TooltipDataProcessor.AddLinePostCall(Enum.TooltipDataLineType.SellPrice, AlignSellPrice)
    end
end

------------------------------------------------------------------------
-- /fah tooltip <line>
------------------------------------------------------------------------

local OPTIONS = {
    { "market", "value", "market value (price history)" },
    { "daily", "daily", "today's lowest price" },
    { "vendor buy", "vendor_buy", "vendor buy price" },
    { "disenchant value", "disenchant_value", "disenchant value" },
    { "disenchant distribution", "disenchant_distribution", "disenchant outcomes" },
    { "sell price", "align_sell_price", "show Blizzard's sell price as a Vendor: line" },
}

local function Status(on)
    return on and "|cff16ff16on|r" or "|cffff0000off|r"
end

ns:RegisterCommand("tooltip", "<line> - toggle a tooltip line (no line: list them)", function(args)
    local settings = ns.db.tooltip
    args = args:lower()
    for _, option in ipairs(OPTIONS) do
        if args == option[1] then
            settings[option[2]] = not settings[option[2]]
            ns:Print("tooltip " .. option[1] .. ": " .. Status(settings[option[2]]))
            return
        end
    end
    ns:Print("tooltip lines (/fah tooltip <line> to toggle):")
    for _, option in ipairs(OPTIONS) do
        ns:Print(("  %s - %s [%s]"):format(option[1], option[3], Status(settings[option[2]])))
    end
end)
