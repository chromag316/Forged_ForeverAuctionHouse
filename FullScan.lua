local _, ns = ...

-- Full scan
--
-- A "Full Scan" button at the bottom right of Blizzard's auction house window
-- (Buy view only). It sends an empty browse search, which covers the whole
-- auction house, and requests every further page until the list is complete.
-- History.lua records each page's prices from the same browse events, and
-- Blizzard's own results list shows the pages as they arrive.
--
-- The scan only calls C_AuctionHouse directly; it never calls Blizzard's
-- frame methods, so Blizzard's buy/post buttons stay untainted.
--
-- It stops when:
--   the list is complete, Stop is clicked, the window leaves the Buy view
--   (e.g. you open an item), any other browse search is sent (your own
--   search), the server reports a failure, no page arrives for a while,
--   or the auction house closes.
--
-- ReplicateItems() would be the "get all" call, but it does nothing on
-- Forever (tested in game), so this pages the browse search instead.

local FullScan = {}
ns.FullScan = FullScan

local THROTTLE_POLL = 0.25 -- seconds between "is the server ready?" checks
local PAGE_TIMEOUT = 20    -- seconds to wait for a page before giving up

local scan       -- { pages, items, started, waiting, token } while scanning
local ownQuery   -- true while we call SendBrowseQuery ourselves
local button, status

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local function UpdateButton()
    if not button then return end
    if scan then
        button:SetText("Stop Scan")
        status:SetText(("Scanning... page %d, %d items"):format(scan.pages, scan.items))
    else
        button:SetText("Full Scan")
    end
end

local function Finish(message)
    if not scan then return end
    local s = scan
    scan = nil
    local seconds = math.floor(GetTime() - s.started + .5)
    local text = ("%s %d items, %d pages, %ds."):format(message, s.items, s.pages, seconds)
    ns:Print("Full scan: " .. text)
    if status then status:SetText(text) end
    UpdateButton()
end

function FullScan.Stop()
    Finish("stopped after")
end

function FullScan.IsScanning()
    return scan ~= nil
end

-- Fails the scan if no page arrives within PAGE_TIMEOUT seconds of `token`.
local function ArmTimeout(s)
    s.token = (s.token or 0) + 1
    local token = s.token
    C_Timer.After(PAGE_TIMEOUT, function()
        if scan == s and s.token == token then
            Finish("no response from the server; stopped after")
        end
    end)
end

-- Requests the next page as soon as the server's throttle allows it.
local function RequestNextPage(s)
    if scan ~= s or s.waiting then return end
    s.waiting = true
    local function try()
        if scan ~= s then return end
        if C_AuctionHouse.HasFullBrowseResults() then
            s.waiting = false
            Finish("done:")
            return
        end
        if C_AuctionHouse.IsThrottledMessageSystemReady() then
            s.waiting = false
            ArmTimeout(s)
            C_AuctionHouse.RequestMoreBrowseResults()
        else
            C_Timer.After(THROTTLE_POLL, try)
        end
    end
    try()
end

function FullScan.Start()
    if scan or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end
    local s = { pages = 0, items = 0, started = GetTime() }
    scan = s
    status:SetText("Waiting for the server...")
    UpdateButton()
    local query = {
        searchString = "",
        sorts = {
            { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
            { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
        },
        filters = {},
        itemClassFilters = {},
    }
    local function send()
        if scan ~= s then return end
        if not C_AuctionHouse.IsThrottledMessageSystemReady() then
            C_Timer.After(THROTTLE_POLL, send)
            return
        end
        ArmTimeout(s)
        ownQuery = true
        C_AuctionHouse.SendBrowseQuery(query)
        ownQuery = false
    end
    send()
end

------------------------------------------------------------------------
-- Browse events
------------------------------------------------------------------------

-- First page of our search: the full list so far.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    local s = scan
    if not s then return end
    s.pages = 1
    s.items = #(C_AuctionHouse.GetBrowseResults() or {})
    UpdateButton()
    RequestNextPage(s)
end)

-- Later pages: only the added rows.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
    local s = scan
    if not s then return end
    s.pages = s.pages + 1
    s.items = s.items + #(added or {})
    UpdateButton()
    RequestNextPage(s)
end)

ns:On("AUCTION_HOUSE_BROWSE_FAILURE", function()
    Finish("the server reported a failure; stopped after")
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
    if scan then Finish("auction house closed; stopped after") end
    if status then status:SetText("") end
end)

-- Any browse search we didn't send (your own search, a category, favorites)
-- replaces the list, so the scan ends there.
hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function()
    if scan and not ownQuery then
        Finish("another search started; stopped after")
    end
end)
if C_AuctionHouse.SearchForFavorites then
    hooksecurefunc(C_AuctionHouse, "SearchForFavorites", function()
        if scan then Finish("another search started; stopped after") end
    end)
end

------------------------------------------------------------------------
-- Button in Blizzard's window
------------------------------------------------------------------------

local function IsBuyView(frame)
    return AuctionHouseFrameDisplayMode and frame:GetDisplayMode() == AuctionHouseFrameDisplayMode.Buy
end

ns:Listen("AUCTION_UI_LOADED", function(frame)
    button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 4)
    button:SetText("Full Scan")
    button:SetScript("OnClick", function()
        if scan then FullScan.Stop() else FullScan.Start() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Full Scan")
        GameTooltip:AddLine("Search the whole auction house and record the lowest price of every item.", 1, 1, 1, true)
        GameTooltip:AddLine("Stops if you open an item, search, or change tabs.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    status = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("RIGHT", button, "LEFT", -8, 0)
    status:SetJustifyH("RIGHT")

    local function Refresh()
        local buyView = IsBuyView(frame)
        button:SetShown(buyView)
        if scan and not buyView then
            Finish("left the Buy view; stopped after")
        end
    end
    hooksecurefunc(frame, "SetDisplayMode", Refresh)
    Refresh()
end)
