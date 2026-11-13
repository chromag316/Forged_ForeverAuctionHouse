local _, ns = ...

-- Addon tabs in Blizzard's auction house window (Deals, Market)
--
-- Works like LibAHTab (the library Auctionator uses; MIT,
-- github.com/TheMouseNest/LibAHTab), which avoids taint:
--   * Tab buttons use Blizzard's tab template but are NOT added to
--     AuctionHouseFrame.Tabs or PanelTemplates_SetNumTabs (doing that taints
--     the player's bags).
--   * The first addon tab sits after Blizzard's last tab, each next one after
--     the previous addon tab.
--   * Selecting one clears Blizzard's view with SetDisplayMode({}), deselects
--     Blizzard's and the other addon tabs, hides their panels and shows its own.
--   * Any Blizzard view change (SetDisplayMode with a real mode) hides all
--     addon panels.
-- If LibAHTab is already loaded (e.g. by Auctionator), tabs are created
-- through it so all addons' tabs line up.
--
-- ns.AddAuctionTab(id, text, panel) -> select function. `panel` is the
-- caller's frame (parent, size and anchors are the caller's).

local tabs = {} -- { id, text, button, panel } in creation order
local hooked = false

local function SelectTab(frame, entry)
    frame:SetDisplayMode({})
    frame.displayMode = nil -- so clicking the previous Blizzard tab works again
    for _, tab in ipairs(frame.Tabs or {}) do
        PanelTemplates_DeselectTab(tab)
    end
    for _, other in ipairs(tabs) do
        if other ~= entry then
            other.panel:Hide()
            PanelTemplates_DeselectTab(other.button)
        end
    end
    PanelTemplates_SelectTab(entry.button)
    if frame.SetTitle then frame:SetTitle(entry.text) end
    entry.panel:Show()
end

local function HookDisplayMode(frame)
    if hooked then return end
    hooked = true
    -- A real Blizzard view (Buy, Sell, Auctions, item views) hides ours.
    hooksecurefunc(frame, "SetDisplayMode", function(_, mode)
        if type(mode) == "table" and #mode > 0 then
            for _, entry in ipairs(tabs) do
                entry.panel:Hide()
                PanelTemplates_DeselectTab(entry.button)
            end
        end
    end)
end

local function CreateOwnTab(frame, entry)
    local previous = tabs[#tabs - 1]
    local anchor = previous and previous.button or (frame.Tabs and frame.Tabs[#frame.Tabs])
    local button = CreateFrame("Button", "ForgedForeverAHTab" .. entry.id, frame, "AuctionHouseFrameDisplayModeTabTemplate")
    if anchor then
        button:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 3, 0)
    else
        button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 300, 2)
    end
    button:SetText(entry.text)
    if PanelTemplates_TabResize then PanelTemplates_TabResize(button, 20, nil, 70) end
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841)
        SelectTab(frame, entry)
    end)
    PanelTemplates_DeselectTab(button)
    entry.button = button
    HookDisplayMode(frame)
    return function() SelectTab(frame, entry) end
end

-- Adds a tab; returns a function that selects it.
function ns.AddAuctionTab(id, text, panel)
    local frame = AuctionHouseFrame
    local entry = { id = id, text = text, panel = panel }
    tabs[#tabs + 1] = entry
    panel:Hide()
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if lib then
        local libID = "ForgedForever" .. id
        lib:CreateTab(libID, panel, text)
        entry.button = lib:GetButton(libID)
        return function() lib:SetSelected(libID) end
    end
    return CreateOwnTab(frame, entry)
end

function ns.AuctionTabButton(id)
    for _, entry in ipairs(tabs) do
        if entry.id == id then return entry.button end
    end
end
