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
--
-- Auto scan (on by default, ns.db.autoscan):
--   A scan starts by itself shortly after the auction house opens on the Buy
--   view (after Blizzard's own favorites request). Opening an item or going
--   to Sell/Auctions pauses it; back on the Buy view it starts over (the
--   server can't continue a replaced list; prices already recorded are kept).
--   Your own search, Stop, a server error or timeout, or one completed auto
--   scan end auto scanning until the auction house is opened again.

local FullScan = {}
ns.FullScan = FullScan

local THROTTLE_POLL = 0.25 -- seconds between "is the server ready?" checks
local PAGE_TIMEOUT = 20    -- seconds to wait for a page before giving up

local AUTO_START_DELAY = 0.5 -- seconds after opening / returning to the Buy view

ns.DEFAULTS.autoscan = true
-- Item count of the last completed scan per realm/faction, used as the
-- progress estimate (the server doesn't say how many items a search returns).
ns.DEFAULTS.scan_estimate = {}

local scan       -- { pages, items, started, waiting, token, auto } while scanning
local ownQuery   -- true while we call SendBrowseQuery ourselves
local button, status

-- Auto scan state for the current auction house visit.
local autoVisit = false   -- auto scanning may still (re)start this visit
local autoStarted = false -- an auto scan has been started this visit

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

-- 4210 -> "4,210"
local function Count(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    local s = tostring(n)
    local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (result:gsub("^,", ""))
end
FullScan.Count = Count

local function EstimateKey()
    return ns.RealmFactionKey()
end

function FullScan.Estimate()
    return ns.db and ns.db.scan_estimate[EstimateKey()]
end

local RATE_LIMITED_TEXT = "Rate limited. Waiting before starting..."
local WAITING_TEXT = "Waiting for server response..."

-- "Scanning... (1,180 of ~1,830 items)" (estimate from the last completed
-- scan, raised if this scan passes it), or "Scanning... (1,180 items)"
-- without one.
local function ProgressText(items)
    local estimate = FullScan.Estimate()
    if estimate then
        return ("Scanning... (%s of ~%s items)"):format(Count(items), Count(math.max(estimate, items)))
    end
    return ("Scanning... (%s items)"):format(Count(items))
end
FullScan.ProgressText = ProgressText

local function UpdateButton()
    if not button then return end
    if scan then
        button:SetText("Stop Scan")
        -- The waiting texts stay until the first page arrives.
        if scan.pages > 0 then status:SetText(ProgressText(scan.items)) end
    else
        button:SetText("Full Scan")
    end
end

-- End messages by outcome. "%s" = item count, "%d" = seconds.
local END_TEXT = {
    done_auto = "Scan complete: %s items (%ds)",
    done = "Full scan complete: %s items (%ds)",
    user = "Stopped by user: %s items (%ds)",
    search = "Stopped: New search started",
    timeout = "Stopped: Server timeout",
    error = "Stopped: Server error",
    left = "Stopped: Left the Buy view",
}

-- `outcome`: "done", "user", "left" (left the Buy view), "search", "timeout",
-- "error" or "closed". An auto scan that left the Buy view is paused (it
-- starts over on return, no message); any other end stops auto scanning for
-- this visit. A completed scan's item count becomes the next estimate.
local function Finish(outcome)
    if not scan then return end
    local s = scan
    scan = nil
    ns:Fire("SCAN_FINISHED", outcome, s.auto) -- Market.lua stores what was seen
    if s.auto and outcome ~= "left" then autoVisit = false end
    if outcome == "done" then
        ns.db.scan_estimate[EstimateKey()] = s.items
    end
    local key = (outcome == "done" and s.auto) and "done_auto" or outcome
    local format = END_TEXT[key]
    local text = ""
    if format and not (s.auto and outcome == "left") then
        local seconds = math.floor(GetTime() - s.started + .5)
        text = format:format(Count(s.items), seconds)
        ns:Print(text)
    end
    if status then status:SetText(text) end
    UpdateButton()
end
FullScan.END_TEXT = END_TEXT

function FullScan.Stop()
    Finish("user")
end

-- The "Auto scan" checkbox. On: from the next time the auction house opens
-- (so it doesn't replace what you're looking at). Off: also stops a running
-- auto scan; a Full Scan started with the button keeps going.
function FullScan.SetAutoScan(on)
    ns.db.autoscan = on and true or false
    if not ns.db.autoscan then
        autoVisit = false
        if scan and scan.auto then Finish("user") end
    end
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
            Finish("timeout")
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
            Finish("done")
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

function FullScan.Start(auto)
    if scan or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end
    local s = { pages = 0, items = 0, started = GetTime(), auto = auto or nil }
    scan = s
    ns:Fire("SCAN_STARTED", s.auto) -- Market.lua starts collecting
    if auto then autoStarted = true end
    if status then status:SetText(WAITING_TEXT) end
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
            if status then status:SetText(RATE_LIMITED_TEXT) end
            C_Timer.After(THROTTLE_POLL, send)
            return
        end
        if status then status:SetText(WAITING_TEXT) end
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
    Finish("error")
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
    if scan then Finish("closed") end
    autoVisit, autoStarted = false, false
    if status then status:SetText("") end
end)

-- Any browse search we didn't send (your own search, a category, favorites)
-- replaces the list, so a scan ends there, and auto scanning stops for this
-- visit so your results stay. Blizzard's own favorites request when the
-- window opens comes before the first auto scan and doesn't count.
local function OtherSearch()
    if scan then
        Finish("search")
    end
    if autoStarted then autoVisit = false end
end
hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function()
    if not ownQuery then OtherSearch() end
end)
if C_AuctionHouse.SearchForFavorites then
    hooksecurefunc(C_AuctionHouse, "SearchForFavorites", OtherSearch)
end

------------------------------------------------------------------------
-- Button in Blizzard's window
------------------------------------------------------------------------

local function IsBuyView(frame)
    return AuctionHouseFrameDisplayMode and frame:GetDisplayMode() == AuctionHouseFrameDisplayMode.Buy
end

-- Starts an auto scan if this visit still allows one and you're on the Buy view.
local function TryAutoScan()
    local frame = AuctionHouseFrame
    if not ns.db.autoscan or not autoVisit or scan then return end
    if not frame or not frame:IsShown() or not IsBuyView(frame) then return end
    FullScan.Start(true)
end

local function ScheduleAutoScan()
    C_Timer.After(AUTO_START_DELAY, TryAutoScan)
end
FullScan.TryAutoScan = TryAutoScan

ns:On("AUCTION_HOUSE_SHOW", function()
    autoVisit, autoStarted = ns.db.autoscan and true or false, false
    ScheduleAutoScan()
end)

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
        GameTooltip:AddLine("An auto scan also starts when the auction house opens.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    -- Status text at the left of the bottom strip, right after Blizzard's money
    -- display, leaving room left of the button for the auto scan checkbox.
    -- Parented to the button so it's only shown on the Buy view.
    status = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local money = frame.MoneyFrameBorder or frame.MoneyFrameInset
    if money then
        status:SetPoint("LEFT", money, "RIGHT", 12, 0)
    else
        status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 180, 10)
    end
    status:SetPoint("RIGHT", button, "LEFT", -140, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)

    -- "Auto scan" checkbox left of the button (Blizzard's checkbox template),
    -- parented to the button so it's only shown on the Buy view. The label
    -- sits between the box and the button and is clickable too.
    local check = CreateFrame("CheckButton", nil, button, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    local label = check.Text or check.text or check:CreateFontString(nil, "OVERLAY")
    label:SetFontObject("GameFontNormalSmall")
    label:ClearAllPoints()
    label:SetPoint("LEFT", check, "RIGHT", 1, 0)
    label:SetText("Auto scan")
    local labelWidth = math.ceil(label:GetStringWidth())
    check:SetPoint("RIGHT", button, "LEFT", -(labelWidth + 10), 0)
    check:SetHitRectInsets(0, -labelWidth, 0, 0)
    check:SetChecked(ns.db.autoscan)
    check:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if SOUNDKIT then
            PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
        FullScan.SetAutoScan(on)
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Auto scan")
        GameTooltip:AddLine("Scan the whole auction house automatically when it opens.", 1, 1, 1, true)
        GameTooltip:AddLine("Turning it on takes effect the next time you open the auction house. Turning it off stops a running auto scan.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    FullScan.checkbox = check

    local function Refresh()
        local buyView = IsBuyView(frame)
        button:SetShown(buyView)
        if scan and not buyView then
            Finish("left")
        elseif buyView and autoVisit and not scan then
            ScheduleAutoScan() -- resume a paused auto scan
        end
    end
    hooksecurefunc(frame, "SetDisplayMode", Refresh)
    Refresh()
end)
