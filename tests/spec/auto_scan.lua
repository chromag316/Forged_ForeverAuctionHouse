local now = 1700000000
time = function(t) if t then return os.time(t) end return now end
date = function(f) return os.date(f, now) end
local clock = 0
GetTime = function() return clock end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
geterrorhandler = function() return error end
SlashCmdList = {}
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Alliance" end
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Item = { GetItemInfo = function() end }
local printed = {}
print = function(s) printed[#printed + 1] = s end
GameTooltip_Hide = function() end
GameTooltip = {}

-- timers run when we call tick()
local timers = {}
C_Timer = { After = function(sec, fn) timers[#timers + 1] = { at = clock + sec, fn = fn } end }
local function tick(sec)
  clock = clock + sec
  local due = {}
  for i = #timers, 1, -1 do if timers[i].at <= clock then table.insert(due, 1, table.remove(timers, i)) end end
  for _, t in ipairs(due) do t.fn() end
end

hooksecurefunc = function(a, b, c)
  local t, name, fn = a, b, c
  if type(a) == "string" then t, name, fn = _G, a, b end
  local orig = t[name]
  t[name] = function(...) local r = orig(...); fn(...); return r end
end

-- frames
local eventFrame
local function newFrame()
  local f = { scripts = {}, shown = true, text = "" }
  function f:RegisterEvent() end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:SetSize() end
  function f:SetText(t) self.text = t end
  function f:SetJustifyH(j) self.justify = j end
  function f:SetWordWrap() end
  function f:SetPoint(p, rel, rp, x, y) self.points = self.points or {}; self.points[#self.points + 1] = { p, rel, rp, x, y } end
  function f:SetShown(v) self.shown = v end
  function f:SetChecked(v) self.checked = v and true or false end
  function f:GetChecked() return self.checked end
  function f:SetHitRectInsets(...) self.hitRect = { ... } end
  function f:ClearAllPoints() self.points = {} end
  function f:SetFontObject(o) self.font = o end
  function f:GetStringWidth() return 50 end
  function f:CreateFontString() local fs = newFrame(); self.createdFont = fs; return fs end
  return f
end
local created = {}
CreateFrame = function(ftype, name, parent, template)
  local f = newFrame(); f.ftype, f.parent, f.template = ftype, parent, template
  if template == "UICheckButtonTemplate" then f.Text = newFrame() end
  created[#created + 1] = f; if not eventFrame then eventFrame = f end; return f
end
local function lastOfType(t) for i = #created, 1, -1 do if created[i].ftype == t then return created[i] end end end

-- auction house
local TOTAL_PAGES, served, ready = 3, 0, true
local sent = {}
Enum = { AuctionHouseSortOrder = { Price = 0, Name = 1 } }
local function fire(e, ...) eventFrame.scripts.OnEvent(eventFrame, e, ...) end
local function page(n) local t = {}; for i = 1, 100 do t[i] = { itemKey = { itemID = n * 1000 + i }, minPrice = 10 + i } end; return t end
local all = {}
C_AuctionHouse = {
  IsThrottledMessageSystemReady = function() return ready end,
  SendBrowseQuery = function(q) sent[#sent + 1] = q; served = 0 end,
  RequestMoreBrowseResults = function() sent[#sent + 1] = "more" end,
  HasFullBrowseResults = function() return served >= TOTAL_PAGES end,
  GetBrowseResults = function() return all end,
  SearchForFavorites = function() end,
}
local function serveFirst() served = 1; all = page(1); fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end
local function serveMore() served = served + 1; local p = page(served); for _, r in ipairs(p) do all[#all + 1] = r end; fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", p) end

AuctionHouseFrameDisplayMode = { Buy = {}, ItemBuy = {} }
local mode = AuctionHouseFrameDisplayMode.Buy
AuctionHouseFrame = { IsShown = function() return true end, GetDisplayMode = function() return mode end,
  SetDisplayMode = function(self, m) mode = m end }

local ns = {}
for _, f in ipairs({"Core.lua", "History.lua", "FullScan.lua"}) do assert(loadfile(DIR .. "/" .. f))("Forged_ForeverAuctionHouse", ns) end
local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1; io.write("FAIL " .. msg .. ": got " .. tostring(a) .. " want " .. tostring(b) .. "\n") end end
local function sends() local n = 0; for _, q in ipairs(sent) do if type(q) == "table" then n = n + 1 end end; return n end
local function ready_tick() ready = true; tick(0.6) end
local Buy, ItemBuy = AuctionHouseFrameDisplayMode.Buy, AuctionHouseFrameDisplayMode.ItemBuy
local function open() fire("AUCTION_HOUSE_SHOW"); AuctionHouseFrame:SetDisplayMode(Buy) end
local function finishScan() serveFirst(); serveMore(); serveMore() end

fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")
AuctionHouseFrame.MoneyFrameBorder = { name = "money" }
fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
local button = lastOfType("Button")
eq(ns.db.autoscan, true, "auto scan on by default")

-- 1. opens: Blizzard's favorites request first doesn't count; auto scan starts after the delay
sent = {}
open()
C_AuctionHouse.SearchForFavorites()
eq(ns.FullScan.IsScanning(), false, "not started immediately")
ready_tick()
eq(ns.FullScan.IsScanning(), true, "auto scan started after delay")
eq(sends(), 1, "one browse query sent")
finishScan()
eq(ns.FullScan.IsScanning(), false, "auto scan finished")
eq(printed[#printed]:match("Scan complete: 300 items %(%d+s%)$") ~= nil, true, "auto scan end message: " .. tostring(printed[#printed]))
-- completed: no restart on returning to Buy
AuctionHouseFrame:SetDisplayMode(ItemBuy); AuctionHouseFrame:SetDisplayMode(Buy); tick(1)
eq(ns.FullScan.IsScanning(), false, "no second auto scan after completing")
fire("AUCTION_HOUSE_CLOSED")

-- 2. pause on item view, resume (start over) on Buy view
sent = {}
open(); ready_tick()
serveFirst()
AuctionHouseFrame:SetDisplayMode(ItemBuy)
eq(ns.FullScan.IsScanning(), false, "paused in item view")
tick(1)
eq(ns.FullScan.IsScanning(), false, "stays paused while away")
AuctionHouseFrame:SetDisplayMode(Buy)
ready_tick()
eq(ns.FullScan.IsScanning(), true, "resumed on Buy view")
eq(sends(), 2, "started over with a new query")
fire("AUCTION_HOUSE_CLOSED")
eq(ns.FullScan.IsScanning(), false, "closing stops")

-- 3. your own search ends auto scanning for the visit
sent = {}
open(); ready_tick()
C_AuctionHouse.SendBrowseQuery({ searchString = "linen" })
eq(ns.FullScan.IsScanning(), false, "own search stops the auto scan")
AuctionHouseFrame:SetDisplayMode(ItemBuy); AuctionHouseFrame:SetDisplayMode(Buy); ready_tick()
eq(ns.FullScan.IsScanning(), false, "no resume after your own search")
fire("AUCTION_HOUSE_CLOSED")

-- 4. own search while paused (e.g. after Sell) also ends it
open(); ready_tick()
AuctionHouseFrame:SetDisplayMode(ItemBuy)
C_AuctionHouse.SendBrowseQuery({ searchString = "ore" })
AuctionHouseFrame:SetDisplayMode(Buy); ready_tick()
eq(ns.FullScan.IsScanning(), false, "search while paused ends auto scanning")
fire("AUCTION_HOUSE_CLOSED")

-- 5. Stop button ends auto scanning for the visit
open(); ready_tick()
button.scripts.OnClick()
eq(ns.FullScan.IsScanning(), false, "stopped by user")
AuctionHouseFrame:SetDisplayMode(ItemBuy); AuctionHouseFrame:SetDisplayMode(Buy); ready_tick()
eq(ns.FullScan.IsScanning(), false, "no resume after Stop")
-- manual scan still works, says Full scan, and doesn't resume after leaving
button.scripts.OnClick(); ready_tick()
eq(ns.FullScan.IsScanning(), true, "manual scan starts")
AuctionHouseFrame:SetDisplayMode(ItemBuy); AuctionHouseFrame:SetDisplayMode(Buy); ready_tick()
eq(ns.FullScan.IsScanning(), false, "manual scan doesn't resume")
eq(printed[#printed]:match("Stopped: Left the Buy view$") ~= nil, true, "manual scan left the Buy view: " .. tostring(printed[#printed]))
fire("AUCTION_HOUSE_CLOSED")

-- 6. timeout ends auto scanning for the visit
open(); ready_tick()
tick(21)
eq(ns.FullScan.IsScanning(), false, "timeout stops")
AuctionHouseFrame:SetDisplayMode(ItemBuy); AuctionHouseFrame:SetDisplayMode(Buy); ready_tick()
eq(ns.FullScan.IsScanning(), false, "no resume after timeout")
fire("AUCTION_HOUSE_CLOSED")

-- 7. setting off: no auto scan
ns.db.autoscan = false
open(); ready_tick()
eq(ns.FullScan.IsScanning(), false, "auto scan off")
fire("AUCTION_HOUSE_CLOSED")
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
-- status text placement: left of the strip, next to the money display
local st = button.createdFont
eq(st ~= nil, true, "status font string created")
eq(st.points[1][1], "LEFT", "status starts at its left")
eq(st.points[1][2], AuctionHouseFrame.MoneyFrameBorder, "right after the money display")
eq(st.points[2][2], button, "right edge kept clear of the button area")
eq(st.points[2][4], -140, "room for the checkbox")
eq(st.justify, "LEFT", "left-aligned")

-- messages and estimate
local FS = ns.FullScan
eq(FS.Count(4210), "4,210", "thousands separator")
eq(FS.Count(1234567), "1,234,567", "millions")
eq(FS.Count(53), "53", "small number")
eq(FS.Estimate(), 300, "completed scan saved as estimate (300 items)")
eq(FS.ProgressText(53), "Scanning... (53 of ~300 items)", "progress with estimate")
eq(FS.ProgressText(450), "Scanning... (450 of ~450 items)", "estimate raised when passed")
eq(FS.ProgressText(1180), "Scanning... (1,180 of ~1,180 items)", "separators in progress")
ns.db.scan_estimate = {}
eq(FS.ProgressText(1180), "Scanning... (1,180 items)", "progress without estimate")
eq(FS.END_TEXT.user:format(FS.Count(1180), 30), "Stopped by user: 1,180 items (30s)", "stopped by user format")
eq(FS.END_TEXT.done:format(FS.Count(4210), 95), "Full scan complete: 4,210 items (95s)", "full scan format")
eq(FS.END_TEXT.done_auto:format(FS.Count(4210), 95), "Scan complete: 4,210 items (95s)", "auto scan format")
eq(FS.END_TEXT.timeout, "Stopped: Server timeout", "timeout text")
eq(FS.END_TEXT.error, "Stopped: Server error", "error text")

-- live: waiting text stays until the first page, then progress
ns.db.autoscan = true
ns.db.scan_estimate = {}
fire("AUCTION_HOUSE_CLOSED")
ready = false
button.scripts.OnClick()
eq(st.text, "Rate limited. Waiting before starting...", "rate limited before the first query")
ready_tick()
eq(st.text, "Waiting for server response...", "waiting for the first page")
serveFirst()
eq(st.text, "Scanning... (100 items)", "progress after first page (no estimate yet)")
serveMore(); serveMore()
eq(tostring(st.text):match("^Full scan complete: 300 items %(%d+s%)$") ~= nil, true, "status shows end message: " .. tostring(st.text))
button.scripts.OnClick(); ready_tick(); serveFirst()
eq(st.text, "Scanning... (100 of ~300 items)", "next scan uses the estimate")
button.scripts.OnClick()
eq(tostring(st.text):match("^Stopped by user: 100 items %(%d+s%)$") ~= nil, true, "stop message in status: " .. tostring(st.text))
eq(FS.Estimate(), 300, "a stopped scan doesn't change the estimate")
-- server error
button.scripts.OnClick(); ready_tick(); fire("AUCTION_HOUSE_BROWSE_FAILURE")
eq(st.text, "Stopped: Server error", "server error message")
-- auto pause: no message
fire("AUCTION_HOUSE_CLOSED")
open(); ready_tick()
local before = #printed
AuctionHouseFrame:SetDisplayMode(ItemBuy)
eq(#printed, before, "auto pause prints nothing")
eq(st.text, "", "auto pause leaves no stop message")
io.write(fails == 0 and "ALL PASS (with status)\n" or (fails .. " FAILURES\n"))

-- 1.4 checkbox
local check = lastOfType("CheckButton")
eq(check ~= nil, true, "checkbox created")
eq(check.template, "UICheckButtonTemplate", "Blizzard checkbox template")
eq(check.parent, button, "parented to the button (Buy view only)")
eq(check.Text.text, "Auto scan", "label")
eq(check.points[1][2], button, "left of the Full Scan button")
eq(check.points[1][4], -60, "room for the label (50 + 10)")
eq(check.hitRect[2], -50, "label is clickable")
eq(type(check.scripts.OnClick), "function", "click handler")

-- unchecking stops a running auto scan and saves the setting
ns.db.autoscan = true
fire("AUCTION_HOUSE_CLOSED")
open(); ready_tick()
eq(ns.FullScan.IsScanning(), true, "auto scan running")
check:SetChecked(false); check.scripts.OnClick(check)
eq(ns.db.autoscan, false, "setting saved off")
eq(ns.FullScan.IsScanning(), false, "unchecking stops the auto scan")
eq(tostring(st.text):match("^Stopped by user") ~= nil, true, "stop message: " .. tostring(st.text))
AuctionHouseFrame:SetDisplayMode(ItemBuy); AuctionHouseFrame:SetDisplayMode(Buy); ready_tick()
eq(ns.FullScan.IsScanning(), false, "no resume after unchecking")
-- unchecking doesn't stop a manual Full Scan
button.scripts.OnClick(); ready_tick()
check:SetChecked(false); check.scripts.OnClick(check)
eq(ns.FullScan.IsScanning(), true, "manual scan keeps going")
button.scripts.OnClick()
-- checking: saved, takes effect next open (no scan now)
check:SetChecked(true); check.scripts.OnClick(check)
eq(ns.db.autoscan, true, "setting saved on")
ready_tick()
eq(ns.FullScan.IsScanning(), false, "checking doesn't start a scan now")
fire("AUCTION_HOUSE_CLOSED")
open(); ready_tick()
eq(ns.FullScan.IsScanning(), true, "auto scan on the next open")
fire("AUCTION_HOUSE_CLOSED")
io.write(fails == 0 and "ALL PASS (checkbox)\n" or (fails .. " FAILURES\n"))
