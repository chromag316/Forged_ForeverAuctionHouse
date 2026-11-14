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
  function f:CreateFontString() local fs = newFrame(); return fs end
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

fire("ADDON_LOADED", "Forged_ForeverAuctionHouse")
fire("PLAYER_LOGIN")
fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
local button = lastOfType("Button")
eq(button.shown, true, "button shown in Buy view")
eq(button.text, "Full Scan", "button label")

-- 1. complete scan with throttle waits
ready = false
button.scripts.OnClick()
eq(#sent, 0, "waits for throttle before sending")
ready = true; tick(0.25)
eq(type(sent[1]), "table", "sent browse query")
eq(sent[1].searchString, "", "empty search")
eq(button.text, "Stop Scan", "label while scanning")
serveFirst()
eq(sent[2], "more", "requests page 2")
ready = false
serveMore()
eq(#sent, 2, "no request while throttled")
ready = true; tick(0.25)
eq(sent[3], "more", "requests page 3 after throttle")
serveMore()
eq(ns.FullScan.IsScanning(), false, "finished after last page")
eq(printed[#printed]:match("Full scan complete: 300 items %(%d+s%)$") ~= nil, true, "summary printed: " .. tostring(printed[#printed]))
eq(button.text, "Full Scan", "label reset")
eq(ns.History.MarketValue("3001:0"), 11, "page 3 prices recorded")

-- 2. stop button
sent = {}
button.scripts.OnClick(); serveFirst()
button.scripts.OnClick()
eq(ns.FullScan.IsScanning(), false, "stop button")
-- 3. user's own search stops it
button.scripts.OnClick()
C_AuctionHouse.SendBrowseQuery({ searchString = "linen" })
eq(ns.FullScan.IsScanning(), false, "own search stops scan")
eq(printed[#printed]:match("Stopped: New search started$") ~= nil, true, "reason printed: " .. tostring(printed[#printed]))
-- 4. leaving Buy view stops it and hides button
button.scripts.OnClick()
AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.ItemBuy)
eq(ns.FullScan.IsScanning(), false, "leaving Buy stops scan")
eq(button.shown, false, "button hidden outside Buy")
AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
-- 5. timeout
button.scripts.OnClick()
tick(21)
eq(ns.FullScan.IsScanning(), false, "timeout stops scan")
-- 6. AH closed
button.scripts.OnClick()
fire("AUCTION_HOUSE_CLOSED")
eq(ns.FullScan.IsScanning(), false, "closing stops scan")
io.write(fails == 0 and "ALL PASS\n" or (fails .. " FAILURES\n"))
