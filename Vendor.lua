local _, ns = ...

-- Vendor buy prices
--
-- Buy price: learned whenever a merchant window is open, per unit, with
-- whether the merchant's stock is limited. Saved account-wide in
-- ForgedForeverAuctionHouseDB.vendor_buy[itemID] = { price, limited }.

local Vendor = {}
ns.Vendor = Vendor

ns.DEFAULTS.vendor_buy = {}

-- Vendor buy price per unit (copper) and whether stock is limited, or nil.
function Vendor.BuyPrice(itemID)
    local entry = ns.db and ns.db.vendor_buy[itemID]
    if entry then return entry.price, entry.limited end
end

-- price, stack size, number available (-1 = unlimited), has extended cost
local function MerchantItem(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then
            return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
        end
    elseif GetMerchantItemInfo then
        local _, _, price, stackCount, numAvailable, _, _, extendedCost = GetMerchantItemInfo(index)
        return price, stackCount, numAvailable, extendedCost
    end
end

local function ScanMerchant()
    if not ns.db then return end
    for i = 1, GetMerchantNumItems() do
        local link = GetMerchantItemLink(i)
        local itemID = link and tonumber(link:match("item:(%d+)"))
        local price, stackCount, numAvailable, extendedCost = MerchantItem(i)
        -- Items bought with tokens/currency have no gold price to learn.
        if itemID and price and price > 0 and not extendedCost then
            ns.db.vendor_buy[itemID] = {
                price = price / math.max(1, stackCount or 1),
                limited = numAvailable ~= nil and numAvailable >= 0,
            }
        end
    end
end

ns:On("MERCHANT_SHOW", ScanMerchant)
ns:On("MERCHANT_UPDATE", ScanMerchant)
