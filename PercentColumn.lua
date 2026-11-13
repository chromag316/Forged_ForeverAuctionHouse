local _, ns = ...

-- EXPERIMENTAL: a sortable "%" column in Blizzard's browse results
--
-- Off by default; /fah percent column toggles it (takes effect after /reload).
--
-- Unlike the inline % (ValuePercent.lua), this writes into Blizzard's own
-- data: it appends a column to the browse list's table builder and, when
-- the "%" header is clicked, reorders BrowseResultsFrame.browseResults
-- (the server can't sort by %). Blizzard then reads addon-written data when
-- it fills rows, which can make the client block buying ("Interface action
-- failed because of an AddOn"). If that happens, turn the column off.
--
--   Column: fixed width, right after Price, cells from
--           ForgedForeverAHPercentCellTemplate (PercentColumn.xml).
--   Sort:   header click cycles low->high, high->low, server order.
--           Pages added later are sorted in; a new search or a click on a
--           Blizzard header ends the % sort.

local PercentColumn = {}
ns.PercentColumn = PercentColumn

ns.DEFAULTS.percent_column = false

local COLUMN_WIDTH = 50

local active = false        -- column added this session
local sortState = nil       -- nil, "asc", "desc"
local serverOrder = nil     -- copy of browseResults in server order while sorted
local browseFrame, header

function ns.PercentColumnActive()
    return active and ns.db and ns.db.percent ~= false
end

------------------------------------------------------------------------
-- Cell (mixin used by PercentColumn.xml's template)
------------------------------------------------------------------------

ForgedForeverAHPercentCellMixin = {}

function ForgedForeverAHPercentCellMixin:Init(owner)
    self.owner = owner
end

function ForgedForeverAHPercentCellMixin:Populate(rowData)
    local pct = ns.BrowsePercent(rowData)
    if pct and ns.db.percent ~= false then
        self.Text:SetText(ns.PercentText(pct, 100))
    else
        self.Text:SetText("")
    end
end

------------------------------------------------------------------------
-- Sorting
------------------------------------------------------------------------

local function UpdateArrow()
    if not header or not header.Arrow then return end
    if sortState == "asc" then
        header.Arrow:SetTexCoord(0, 1, 1, 0)
        header.Arrow:Show()
    elseif sortState == "desc" then
        header.Arrow:SetTexCoord(0, 1, 0, 1)
        header.Arrow:Show()
    else
        header.Arrow:Hide()
    end
end

-- Items without a market value go last in both directions.
local function Compare(a, b)
    local pa, pb = ns.BrowsePercent(a), ns.BrowsePercent(b)
    if pa == nil then return false end
    if pb == nil then return true end
    if sortState == "desc" then return pa > pb end
    return pa < pb
end

local function ApplySort()
    local results = browseFrame and browseFrame.browseResults
    if type(results) ~= "table" then return end
    if sortState then
        table.sort(results, Compare)
    elseif serverOrder then
        for i = 1, #serverOrder do results[i] = serverOrder[i] end
        for i = #serverOrder + 1, #results do results[i] = nil end
    end
    browseFrame.ItemList:DirtyScrollFrame()
end

function PercentColumn.CycleSort()
    local results = browseFrame and browseFrame.browseResults
    if type(results) ~= "table" then return end
    if sortState == nil then
        serverOrder = {}
        for i, r in ipairs(results) do serverOrder[i] = r end
        sortState = "asc"
    elseif sortState == "asc" then
        sortState = "desc"
    else
        sortState = nil
    end
    ApplySort()
    if not sortState then serverOrder = nil end
    UpdateArrow()
end

local function EndSort()
    sortState, serverOrder = nil, nil
    UpdateArrow()
end

------------------------------------------------------------------------
-- Adding the column after Blizzard builds the browse layout
------------------------------------------------------------------------

local function Columns(tableBuilder)
    if tableBuilder.GetColumns then return tableBuilder:GetColumns() end
    return tableBuilder.columns
end

local function AddColumn(itemList)
    local tableBuilder = itemList.tableBuilder
    if not tableBuilder or not tableBuilder.AddUnsortableFixedWidthColumn then return end
    local column = tableBuilder:AddUnsortableFixedWidthColumn(browseFrame, 0, COLUMN_WIDTH, 0, 10, "%",
        "ForgedForeverAHPercentCellTemplate")
    -- Move it right after Price (the first column) when the column list is reachable.
    local columns = Columns(tableBuilder)
    if type(columns) == "table" and columns[#columns] == column and #columns > 2 then
        table.remove(columns)
        table.insert(columns, 2, column)
    end
    tableBuilder:Arrange()
    header = column.GetHeaderFrame and column:GetHeaderFrame()
    if header then
        header:SetEnabled(true)
        header:SetScript("OnClick", PercentColumn.CycleSort)
        UpdateArrow()
    end
    active = true
end

ns:Listen("AUCTION_UI_LOADED", function(frame)
    if not ns.db.percent_column then return end
    browseFrame = frame.BrowseResultsFrame
    local itemList = browseFrame and browseFrame.ItemList
    if not itemList then return end

    -- Copy the base cell methods our mixin lacks (frames get the mixin's
    -- functions when created, which is after this).
    for k, v in pairs(AuctionHouseTableCellMixin or {}) do
        if ForgedForeverAHPercentCellMixin[k] == nil then ForgedForeverAHPercentCellMixin[k] = v end
    end

    -- Blizzard sets a layout (marking it dirty) and applies it in
    -- UpdateTableBuilderLayout (Reset + layout + Arrange). Add our column
    -- each time a new layout has just been applied. The first layout was set
    -- in OnLoad, before this hook.
    local pending = true
    local function AddIfApplied(self)
        if pending and not self.tableBuilderLayoutDirty and self.tableBuilder then
            pending = false
            local ok, err = pcall(AddColumn, self)
            if not ok then geterrorhandler()(err) end
        end
    end
    -- SetTableBuilderLayout applies the layout itself when the list is shown
    -- (before this post-hook runs), otherwise it's applied on the next show.
    hooksecurefunc(itemList, "SetTableBuilderLayout", function(self)
        pending = true
        AddIfApplied(self)
    end)
    hooksecurefunc(itemList, "UpdateTableBuilderLayout", AddIfApplied)

    -- New search (first page) is in server order again; added pages get
    -- sorted in while a % sort is on.
    hooksecurefunc(browseFrame, "UpdateBrowseResults", function(_, added)
        if not sortState then return end
        if added then
            if serverOrder then
                for _, r in ipairs(added) do serverOrder[#serverOrder + 1] = r end
            end
            ApplySort()
        else
            EndSort()
        end
    end)
    -- Clicking one of Blizzard's headers sorts on the server instead.
    hooksecurefunc(browseFrame, "SetSortOrder", EndSort)
end)

------------------------------------------------------------------------
-- /fah percent column
------------------------------------------------------------------------

function PercentColumn.Toggle()
    ns.db.percent_column = not ns.db.percent_column
    ns:Print("% column in the browse results (experimental): "
        .. (ns.db.percent_column and "|cff16ff16on|r" or "|cffff0000off|r")
        .. ". Takes effect after /reload.")
    if ns.db.percent_column then
        ns:Print("If buying shows \"Interface action failed because of an AddOn\", turn it off again.")
    end
end
