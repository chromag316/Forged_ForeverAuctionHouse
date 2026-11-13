local _, ns = ...

-- Disenchant outcomes for level 1-60 items (tables from the 1.12 addon).

local Disenchant = {}
ns.Disenchant = Disenchant

local UNCOMMON, RARE, EPIC = 2, 3, 4

local ARMOR = {
    INVTYPE_HEAD = true, INVTYPE_NECK = true, INVTYPE_SHOULDER = true, INVTYPE_BODY = true,
    INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true,
    INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true, INVTYPE_CLOAK = true, INVTYPE_HOLDABLE = true,
}

local WEAPON = {
    INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPON = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
}

-- Items that look disenchantable but aren't.
local EXCLUDED = {
    [20406] = true, [20407] = true, [20408] = true,                 -- Twilight Cultist set
    [11287] = true, [11288] = true, [11289] = true, [11290] = true, -- enchanting wands
}

local function E(itemID, minQuantity, maxQuantity, probability)
    return { itemID = itemID, min = minQuantity, max = maxQuantity, probability = probability }
end

-- List of { itemID, min, max, probability }; empty if not disenchantable.
-- equipLoc, quality and itemLevel come from C_Item.GetItemInfo.
function Disenchant.Distribution(equipLoc, quality, itemLevel, itemID)
    if (not ARMOR[equipLoc] and not WEAPON[equipLoc]) or not itemLevel or itemLevel == 0 or EXCLUDED[itemID] then
        return {}
    end
    local function p(armor, weapon)
        if ARMOR[equipLoc] then return armor end
        return weapon
    end
    local level = itemLevel

    if quality == UNCOMMON then
        if level <= 10 then
            return { E(10940, 1, 2, p(.8, .2)), E(10938, 1, 2, p(.2, .8)) }
        elseif level <= 15 then
            return { E(10940, 2, 3, p(.75, .2)), E(10939, 1, 2, p(.2, .75)), E(10978, 1, 1, .05) }
        elseif level <= 20 then
            return { E(10940, 4, 6, p(.75, .15)), E(10998, 1, 2, p(.15, .75)), E(10978, 1, 1, .10) }
        elseif level <= 25 then
            return { E(11083, 1, 2, p(.75, .2)), E(11082, 1, 2, p(.2, .75)), E(11084, 1, 1, .05) }
        elseif level <= 30 then
            return { E(11083, 2, 5, p(.75, .2)), E(11134, 1, 2, p(.2, .75)), E(11138, 1, 1, .05) }
        elseif level <= 35 then
            return { E(11137, 1, 2, p(.75, .2)), E(11135, 1, 2, p(.2, .75)), E(11139, 1, 1, .05) }
        elseif level <= 40 then
            return { E(11137, 2, 5, p(.75, .2)), E(11174, 1, 2, p(.2, .75)), E(11177, 1, 1, .05) }
        elseif level <= 45 then
            return { E(11176, 1, 2, p(.75, .2)), E(11175, 1, 2, p(.2, .75)), E(11178, 1, 1, .05) }
        elseif level <= 50 then
            return { E(11176, 2, 5, p(.75, .22)), E(16202, 1, 2, p(.2, .75)), E(14343, 1, 1, p(.05, .03)) }
        elseif level <= 55 then
            return { E(16204, 1, 2, p(.75, .22)), E(16203, 1, 2, p(.2, .75)), E(14344, 1, 1, p(.05, .03)) }
        elseif level <= 60 then
            return { E(16204, 2, 5, p(.75, .22)), E(16203, 2, 3, p(.2, .75)), E(14344, 1, 1, p(.05, .03)) }
        end
    elseif quality == RARE then
        if level <= 20 then return { E(10978, 1, 1, 1) }
        elseif level <= 25 then return { E(11084, 1, 1, 1) }
        elseif level <= 30 then return { E(11138, 1, 1, 1) }
        elseif level <= 35 then return { E(11139, 1, 1, 1) }
        elseif level <= 40 then return { E(11177, 1, 1, 1) }
        elseif level <= 45 then return { E(11178, 1, 1, 1) }
        elseif level <= 50 then return { E(14343, 1, 1, 1) }
        elseif level <= 60 then return { E(14344, 1, 1, .995), E(20725, 1, 1, .005) }
        end
    elseif quality == EPIC then
        if level <= 40 then return { E(11177, 2, 4, 1) }
        elseif level <= 45 then return { E(11178, 2, 4, 1) }
        elseif level <= 50 then return { E(14343, 2, 4, 1) }
        elseif level <= 55 then return { E(20725, 1, 1, 1) }
        elseif level <= 60 then return { E(20725, 1, 2, 1) }
        end
    end
    return {}
end

-- Expected value of disenchanting, or nil if any outcome has no price yet.
-- Each outcome is priced at the lower of its value and today's minimum.
function Disenchant.Value(equipLoc, quality, itemLevel, itemID)
    local expectation
    for _, e in ipairs(Disenchant.Distribution(equipLoc, quality, itemLevel, itemID)) do
        local key = e.itemID .. ":0"
        local value = ns.History.Value(key)
        if not value then return end
        local today = ns.History.MarketValue(key)
        if today then value = math.min(value, today) end
        expectation = (expectation or 0) + e.probability * (e.min + e.max) / 2 * value
    end
    return expectation
end
