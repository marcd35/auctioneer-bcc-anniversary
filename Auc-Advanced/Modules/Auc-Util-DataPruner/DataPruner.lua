--[[
	Auctioneer - DataPruner Utility Module
	Version: 2.5.6779 (Crusade)
	Revision: $Id: DataPruner.lua 6779 2026-08-09 18:58:00Z none $
	URL: http://auctioneeraddon.com/

	This AddOn provides retroactive database pruning functionality for Auctioneer,
	allowing users to set lower/upper cutoff thresholds to purge outlier price
	data from existing SavedVariables databases, scan databases in dry-run mode,
	select target databases via a dropdown menu, and target individual items via
	a square drop-in item slot or Alt-Click with real-time preview evaluation.

	License: GNU General Public License v2 or later
--]]
if not AucAdvanced then return end

local libType, libName = "Util", "DataPruner"
local lib, parent, private = AucAdvanced.NewModule(libType, libName)
if not lib then return end

local aucPrint, decode, _, _, replicate, empty, get, set, default, debugPrint, fill = AucAdvanced.GetModuleLocals()
local Resources = AucAdvanced.Resources
local ResolveServerKey = AucAdvanced.ResolveServerKey
local GetStoreKey = AucAdvanced.API.GetStoreKeyFromLinkB

local pairs, ipairs, tonumber, tostring, type = pairs, ipairs, tonumber, tostring, type
local math_floor, math_ceil = math.floor, math.ceil
local strsplit, tconcat, tinsert, strmatch = strsplit, table.concat, table.insert, string.match
local unpack = unpack

private.ScanResults = {
	scanned = false,
	outlierCount = 0,
	itemHits = 0,
	serverKey = nil,
	upperPct = 0,
	lowerPct = 0,
	targetdb = "simple",
}

private.StagedItemLink = nil

StaticPopupDialogs["DATAPRUNER_WARN_NO_SCAN"] = {
	text = "You have not run a dry-run scan yet!\n\nIt is strongly recommended to click '1. Scan Database (Dry Run)' first to review how many records will be removed before pruning.",
	button1 = "Go Back",
	button2 = "Proceed Anyway",
	OnCancel = function()
		-- Go Back selected
	end,
	OnAccept = function(self, data)
		-- User chose to proceed anyway without dry-run scan
		StaticPopup_Show("DATAPRUNER_CONFIRM_PRUNE", "0", "0", data)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["DATAPRUNER_CONFIRM_PRUNE"] = {
	text = "Dry-Run Scan Results:\nFound %s outlier records across %s items violating cutoffs.\n\nAre you sure you want to permanently prune these records from your SavedVariables database?",
	button1 = "Confirm Prune",
	button2 = "Cancel",
	OnAccept = function(self, data)
		lib.PruneData(data, true)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["DATAPRUNER_SINGLE_ITEM_CONFIRM"] = {
	text = "Targeted Pruning for %s:\n\nPreview: Found %s.\n\nSelect an option below to prune outliers or wipe all saved history for this item.",
	button1 = "Prune Outliers",
	button2 = "Wipe History",
	button3 = "Cancel",
	OnAccept = function(self, data)
		lib.PruneItem(data, "threshold")
	end,
	OnCancel = function(self, data, reason)
		if reason == "clicked" then
			StaticPopup_Show("DATAPRUNER_CONFIRM_WIPE_ITEM", data, nil, data)
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["DATAPRUNER_CONFIRM_WIPE_ITEM"] = {
	text = "WIPE ITEM HISTORY WARNING:\n\nAre you sure you want to COMPLETELY WIPE all historical price data for %s?\n\nThis action cannot be undone!",
	button1 = "Wipe History",
	button2 = "Cancel",
	OnAccept = function(self, data)
		lib.PruneItem(data, "wipe")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

lib.Processors = {
	config = function(callbackType, gui)
		private.SetupConfigGui(gui)
	end,
	configchanged = function(callbackType, setting, value)
		if setting == "util.datapruner.uppercutoff" or setting == "util.datapruner.lowercutoff" or setting == "util.datapruner.targetdb" then
			private.ScanResults.scanned = false
			if private.StagedItemLink then
				lib.SetWorkingItem(private.StagedItemLink)
			end
		end
	end,
}

function lib.CommandHandler(command, ...)
	local serverKey = Resources.ServerKey
	local keyText = AucAdvanced.GetServerKeyText(serverKey)
	if command == "help" then
		aucPrint("Help for Auctioneer - DataPruner:")
		local line = AucAdvanced.Config.GetCommandLead(libType, libName)
		aucPrint(line, "help}} - Show DataPruner slash help")
		aucPrint(line, "scan [serverKey]}} - Run a dry-run scan for {{serverKey}}")
		aucPrint(line, "prune [serverKey]}} - Execute retroactive data prune for {{serverKey}}")
		aucPrint(line, "item [link]}} - Target single item for pruning or wiping")
	elseif command == "scan" then
		local arg1 = ...
		lib.ScanData(arg1 or serverKey)
	elseif command == "prune" then
		local arg1 = ...
		private.OnPruneButtonClick(arg1 or serverKey)
	elseif command == "item" then
		local link = ...
		if link then
			private.HandleAltClickItem(link)
		else
			aucPrint("DataPruner: Usage /auc util datapruner item [ItemLink]")
		end
	end
end

function lib.OnLoad()
	default("util.datapruner.enable", true)
	default("util.datapruner.uppercutoff", 300)
	default("util.datapruner.lowercutoff", 15)
	default("util.datapruner.targetdb", "simple")

	-- Hook Alt-Click on container item buttons for quick target pruning
	if ContainerFrameItemButton_OnModifiedClick then
		hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
			if IsAltKeyDown() then
				local bag = self:GetParent():GetID()
				local slot = self:GetID()
				local link
				if C_Container and C_Container.GetContainerItemLink then
					link = C_Container.GetContainerItemLink(bag, slot)
				elseif GetContainerItemLink then
					link = GetContainerItemLink(bag, slot)
				end
				if link then
					private.HandleAltClickItem(link)
				end
			end
		end)
	end
end

-- Real-time dry-run evaluation for a single item
function lib.EvaluateItemOutliers(link)
	if not link then return 0, 0 end
	local serverKey = Resources.ServerKey
	local rKey = ResolveServerKey(serverKey)
	if not rKey or not AucAdvancedStatSimpleData or not AucAdvancedStatSimpleData.RealmData then
		return 0, 0
	end

	local realmdata = AucAdvancedStatSimpleData.RealmData[rKey]
	if not realmdata or not realmdata.means then
		return 0, 0
	end

	local storeID = GetStoreKey(link)
	if not storeID or not realmdata.means[storeID] then
		return 0, 0
	end

	local upperPct = get("util.datapruner.uppercutoff") or 300
	local lowerPct = get("util.datapruner.lowercutoff") or 15
	local upperFactor = upperPct / 100
	local lowerFactor = lowerPct / 100

	local itemstring = realmdata.means[storeID]
	local itemstoremeans = {strsplit("_", itemstring)}
	local totalProps = #itemstoremeans
	local outlierCount = 0

	local baselinePrice = 0
	local validCount = 0
	for _, propStr in ipairs(itemstoremeans) do
		local prop, dataStr = strsplit("@", propStr)
		if dataStr then
			local fields = {strsplit(";", dataStr)}
			local ema3 = tonumber(fields[3]) or 0
			if ema3 > 0 then
				baselinePrice = baselinePrice + ema3
				validCount = validCount + 1
			end
		end
	end

	if validCount > 0 then
		baselinePrice = baselinePrice / validCount
	end

	if baselinePrice > 0 then
		local minBound = baselinePrice * lowerFactor
		local maxBound = baselinePrice * upperFactor

		for _, propStr in ipairs(itemstoremeans) do
			local prop, dataStr = strsplit("@", propStr)
			if dataStr then
				local fields = {strsplit(";", dataStr)}
				local ema3 = tonumber(fields[3]) or 0
				local ema7 = tonumber(fields[4]) or 0
				local ema14 = tonumber(fields[5]) or 0
				local avgmbo = tonumber(fields[6]) or 0

				if (ema3 > 0 and (ema3 < minBound or ema3 > maxBound)) or
				   (ema7 > 0 and (ema7 < minBound or ema7 > maxBound)) or
				   (ema14 > 0 and (ema14 < minBound or ema14 > maxBound)) or
				   (avgmbo > 0 and (avgmbo < minBound or avgmbo > maxBound)) then
					outlierCount = outlierCount + 1
				end
			end
		end
	end

	return outlierCount, totalProps
end

function lib.SetWorkingItem(link)
	private.StagedItemLink = link
	if not private.frame then return end
	local frame = private.frame

	if not link then
		frame.name:SetText("Insert or Alt-Click Item to target")
		frame.name:SetTextColor(0.5, 0.5, 0.7)
		if frame.infoText then frame.infoText:SetText("") end
		if frame.icon then frame.icon:ClearNormalTexture() end
		frame.link = nil
		return
	end

	local itemID, property, linktype = GetStoreKey(link, 10)
	local texture
	if linktype == "item" or not linktype then
		texture = GetItemIcon(link)
	elseif linktype == "battlepet" then
		local speciesID = tonumber(strmatch(link, "battlepet:(%d+)"))
		if speciesID and C_PetJournal then
			local _, t = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
			texture = t
		end
	end

	frame.name:SetText(link)
	frame.link = link
	if texture and frame.icon then
		frame.icon:SetNormalTexture(texture)
	elseif frame.icon then
		frame.icon:ClearNormalTexture()
	end

	-- Evaluate dry-run preview for single item
	local outlierCount, totalProps = lib.EvaluateItemOutliers(link)
	local upperPct = get("util.datapruner.uppercutoff") or 300
	local lowerPct = get("util.datapruner.lowercutoff") or 15

	if frame.infoText then
		if outlierCount > 0 then
			frame.infoText:SetText(("|cffffd100Preview:|r |cffff3f3f%d|r of %d records violate cutoffs [%d%%, %d%%]"):format(outlierCount, totalProps, lowerPct, upperPct))
		else
			frame.infoText:SetText(("|cffffd100Preview:|r |cff3fff3fNo outlier records found|r with cutoffs [%d%%, %d%%] (%d total properties)"):format(lowerPct, upperPct, totalProps))
		end
	end
end

function private.HandleAltClickItem(itemLink)
	if not itemLink then return end
	lib.SetWorkingItem(itemLink)

	local upperPct = get("util.datapruner.uppercutoff") or 300
	local lowerPct = get("util.datapruner.lowercutoff") or 15
	local outlierCount, totalProps = lib.EvaluateItemOutliers(itemLink)
	local previewText = ("%d outlier record(s) violating cutoffs [%d%%, %d%%]"):format(outlierCount, lowerPct, upperPct)

	StaticPopup_Show("DATAPRUNER_SINGLE_ITEM_CONFIRM", itemLink, previewText, itemLink)
end

function private.GetTargetDatabases()
	local dbs = {
		{"all", "All"}
	}
	local algoList = AucAdvanced.API.GetAlgorithms()
	for i, name in ipairs(algoList) do
		tinsert(dbs, {name:lower(), name})
	end
	return dbs
end

function private.SetupConfigGui(gui)
	local id = gui:AddTab(libName, "Data Maintenance")

	gui:AddHelp(id, "what is datapruner",
		"What is Retroactive Data Pruning?",
		"DataPruner cleans historical auction data already stored in your SavedVariables databases.\n"..
		"Unlike scan-time filters that only operate on new auctions, DataPruner scans existing records and removes outlier pricing that skews averages.\n\n"..
		"WARNING: Retroactive pruning permanently modifies your SavedVariables. It is strongly recommended to back up your WTF/SavedVariables folder before running a batch prune!")

	gui:AddHelp(id, "how to use cutoffs",
		"How do Cutoff Thresholds work?",
		"Cutoff thresholds define acceptable boundaries relative to estimated market value:\n"..
		"• Upper Cutoff (e.g. 300%): Removes historical records priced significantly higher than baseline (e.g. 9,999g bait auctions).\n"..
		"• Lower Cutoff (e.g. 15%): Removes abnormally low listing spikes (e.g. 1-copper accidental dumps).\n"..
		"Records outside the specified [Lower Cutoff, Upper Cutoff] range are purged from historical data.")

	gui:AddControl(id, "Header",     0,    libName.." Options & Data Sanitization")
	gui:AddControl(id, "Note",       0, 1, nil, nil, " ")

	gui:AddControl(id, "WideSlider", 0, 1, "util.datapruner.uppercutoff", 120, 1000, 10, "Upper Cutoff Threshold: %d%%")
	gui:AddTip(id, "Maximum allowable multiplier above market average (e.g. 300% means prices above 3x baseline will be pruned).")

	gui:AddControl(id, "WideSlider", 0, 1, "util.datapruner.lowercutoff", 1, 50, 1, "Lower Cutoff Threshold: %d%%")
	gui:AddTip(id, "Minimum allowable floor percentage relative to market average (e.g. 15% means prices below 0.15x baseline will be pruned).")

	gui:AddControl(id, "Subhead",    0,    "Prune target database:")
	gui:AddControl(id, "Selectbox",  0, 1, private.GetTargetDatabases, "util.datapruner.targetdb")
	gui:AddTip(id, "Select which pricing database store to analyze and prune.")

	gui:AddControl(id, "Note",       0, 1, nil, nil, " ")
	gui:AddControl(id, "Subhead",    0,    "Database Scan & Prune Controls:")

	local scanButton = gui:AddControl(id, "Button", 0, 1, "util.datapruner.scan", "1. Scan Database (Dry Run)")
	scanButton:SetScript("OnClick", function() lib.ScanData() end)
	gui:AddTip(id, "Scans the database and counts matching outlier records WITHOUT modifying SavedVariables.")

	local pruneButton = gui:AddControl(id, "Button", 0, 1, "util.datapruner.prune", "2. Prune Data")
	pruneButton:SetScript("OnClick", function() private.OnPruneButtonClick() end)
	gui:AddTip(id, "Opens confirmation dialog to prune historical outlier records from SavedVariables.")

	gui:AddControl(id, "Note",       0, 1, nil, nil, " ")
	local singleItemHeading = gui:AddControl(id, "Subhead", 0, "Single-Item Target Pruning:")

	-- Exact Square Drop-in Slot UI matching StatHistogram
	local frame = gui.tabs[id].content
	private.frame = frame

	frame.slot = frame:CreateTexture(nil, "BORDER")
	frame.slot:SetDrawLayer("Artwork")
	frame.slot:SetPoint("TOPLEFT", singleItemHeading, "BOTTOMLEFT", 15, -8)
	frame.slot:SetWidth(45)
	frame.slot:SetHeight(45)
	frame.slot:SetTexCoord(0.17, 0.83, 0.17, 0.83)
	frame.slot:SetTexture("Interface\\Buttons\\UI-EmptySlot")

	function frame.IconClicked()
		local objtype, _, link = GetCursorInfo()
		ClearCursor()
		if objtype == "item" or objtype == "battlepet" then
			lib.SetWorkingItem(link)
		else
			lib.SetWorkingItem()
		end
	end

	function frame.ClickHook(link)
		if not frame.slot or not frame.slot:IsVisible() then return end
		lib.SetWorkingItem(link)
	end

	if not private.hookedModifiedClick then
		hooksecurefunc("HandleModifiedItemClick", frame.ClickHook)
		private.hookedModifiedClick = true
	end

	frame.icon = CreateFrame("Button", nil, frame)
	frame.icon:SetPoint("TOPLEFT", frame.slot, "TOPLEFT", 2, -2)
	frame.icon:SetPoint("BOTTOMRIGHT", frame.slot, "BOTTOMRIGHT", -2, 2)
	frame.icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square.blp")
	frame.icon:SetScript("OnClick", frame.IconClicked)
	frame.icon:SetScript("OnReceiveDrag", frame.IconClicked)
	frame.icon:SetScript("OnEnter", function()
		if not frame.link then return end
		GameTooltip:SetOwner(frame.icon, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetHyperlink(frame.link)
	end)
	frame.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

	frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.name:SetPoint("TOPLEFT", frame.slot, "TOPRIGHT", 10, -2)
	frame.name:SetPoint("RIGHT", frame, "RIGHT", -15)
	frame.name:SetHeight(20)
	frame.name:SetJustifyH("LEFT")
	frame.name:SetJustifyV("TOP")
	frame.name:SetText("Insert or Alt-Click Item to target")
	frame.name:SetTextColor(0.5, 0.5, 0.7)

	frame.infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.infoText:SetPoint("TOPLEFT", frame.slot, "TOPRIGHT", 10, -22)
	frame.infoText:SetPoint("RIGHT", frame, "RIGHT", -15)
	frame.infoText:SetHeight(16)
	frame.infoText:SetJustifyH("LEFT")
	frame.infoText:SetJustifyV("TOP")
	frame.infoText:SetText("")

	frame.pruneBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.pruneBtn:SetPoint("TOPLEFT", frame.slot, "TOPRIGHT", 10, -40)
	frame.pruneBtn:SetSize(140, 22)
	frame.pruneBtn:SetText("Prune Item Outliers")
	frame.pruneBtn:SetScript("OnClick", function()
		if frame.link then
			lib.PruneItem(frame.link, "threshold")
		else
			aucPrint("DataPruner: Please insert an item first.")
		end
	end)

	frame.wipeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.wipeBtn:SetPoint("LEFT", frame.pruneBtn, "RIGHT", 10, 0)
	frame.wipeBtn:SetSize(150, 22)
	frame.wipeBtn:SetText("Wipe All Item History")
	frame.wipeBtn:SetScript("OnClick", function()
		if frame.link then
			StaticPopup_Show("DATAPRUNER_CONFIRM_WIPE_ITEM", frame.link, nil, frame.link)
		else
			aucPrint("DataPruner: Please insert an item first.")
		end
	end)

	if private.StagedItemLink then
		lib.SetWorkingItem(private.StagedItemLink)
	end
end

-- Dry-Run Scan Function (Non-destructive)
function lib.ScanData(serverKey)
	serverKey = serverKey or Resources.ServerKey
	local upperPct = get("util.datapruner.uppercutoff") or 300
	local lowerPct = get("util.datapruner.lowercutoff") or 15
	local upperFactor = upperPct / 100
	local lowerFactor = lowerPct / 100
	local targetDB = get("util.datapruner.targetdb") or "simple"

	if targetDB ~= "simple" and targetDB ~= "all" then
		aucPrint("DataPruner: Threshold scanning/pruning is currently optimized only for Stat-Simple data structures. Your target is set to [" .. targetDB .. "].")
		return
	end

	if not AucAdvancedStatSimpleData or not AucAdvancedStatSimpleData.RealmData then
		aucPrint("DataPruner: Stat database is empty or not selected.")
		return
	end

	local SSRealmData = AucAdvancedStatSimpleData.RealmData
	local realmsToProcess = {}

	if serverKey and AucAdvanced.API.IsKeyword(serverKey, "ALL") then
		for rKey in pairs(SSRealmData) do
			tinsert(realmsToProcess, rKey)
		end
	else
		local rKey = ResolveServerKey(serverKey)
		if rKey and SSRealmData[rKey] then
			tinsert(realmsToProcess, rKey)
		end
	end

	aucPrint(("DataPruner: Starting dry-run scan on [%s] [Lower: %d%%, Upper: %d%%]..."):format(targetDB, lowerPct, upperPct))

	local totalItemsChecked = 0
	local totalOutliersFound = 0
	local itemsAffected = 0

	for _, rKey in ipairs(realmsToProcess) do
		local realmdata = SSRealmData[rKey]
		local daily = realmdata.daily
		local means = realmdata.means

		if means then
			for storeID, itemstring in pairs(means) do
				totalItemsChecked = totalItemsChecked + 1
				local itemstoremeans = {strsplit("_", itemstring)}
				local itemHasOutlier = false

				local baselinePrice = 0
				local validCount = 0

				for _, propStr in ipairs(itemstoremeans) do
					local prop, dataStr = strsplit("@", propStr)
					if dataStr then
						local fields = {strsplit(";", dataStr)}
						local ema3 = tonumber(fields[3]) or 0
						if ema3 > 0 then
							baselinePrice = baselinePrice + ema3
							validCount = validCount + 1
						end
					end
				end

				if validCount > 0 then
					baselinePrice = baselinePrice / validCount
				end

				if baselinePrice > 0 then
					local minBound = baselinePrice * lowerFactor
					local maxBound = baselinePrice * upperFactor

					for _, propStr in ipairs(itemstoremeans) do
						local prop, dataStr = strsplit("@", propStr)
						if dataStr then
							local fields = {strsplit(";", dataStr)}
							local ema3 = tonumber(fields[3]) or 0
							local ema7 = tonumber(fields[4]) or 0
							local ema14 = tonumber(fields[5]) or 0
							local avgmbo = tonumber(fields[6]) or 0

							if (ema3 > 0 and (ema3 < minBound or ema3 > maxBound)) or
							   (ema7 > 0 and (ema7 < minBound or ema7 > maxBound)) or
							   (ema14 > 0 and (ema14 < minBound or ema14 > maxBound)) or
							   (avgmbo > 0 and (avgmbo < minBound or avgmbo > maxBound)) then
								totalOutliersFound = totalOutliersFound + 1
								itemHasOutlier = true
							end
						end
					end
				end

				if itemHasOutlier then
					itemsAffected = itemsAffected + 1
				end
			end
		end
	end

	private.ScanResults.scanned = true
	private.ScanResults.outlierCount = totalOutliersFound
	private.ScanResults.itemHits = itemsAffected
	private.ScanResults.serverKey = serverKey
	private.ScanResults.upperPct = upperPct
	private.ScanResults.lowerPct = lowerPct
	private.ScanResults.targetdb = targetDB

	aucPrint(("DataPruner Scan Complete: Found %d outlier records across %d items in [%s] violating cutoffs [Lower: %d%%, Upper: %d%%]."):format(totalOutliersFound, itemsAffected, targetDB, lowerPct, upperPct))
end

-- Handles Prune Button Click with Scan Validation
function private.OnPruneButtonClick(serverKey)
	serverKey = serverKey or Resources.ServerKey

	if not private.ScanResults.scanned or private.ScanResults.serverKey ~= serverKey then
		-- No dry-run scan executed yet: show warning dialog
		StaticPopup_Show("DATAPRUNER_WARN_NO_SCAN", nil, nil, serverKey)
	else
		-- Scan was executed: show scan summary confirmation dialog
		StaticPopup_Show("DATAPRUNER_CONFIRM_PRUNE", tostring(private.ScanResults.outlierCount), tostring(private.ScanResults.itemHits), serverKey)
	end
end

-- Core Function: Prune existing stored databases
function lib.PruneData(serverKey, confirmed)
	if not confirmed then
		private.OnPruneButtonClick(serverKey)
		return
	end

	serverKey = serverKey or Resources.ServerKey
	local upperPct = get("util.datapruner.uppercutoff") or 300
	local lowerPct = get("util.datapruner.lowercutoff") or 15
	local upperFactor = upperPct / 100
	local lowerFactor = lowerPct / 100
	local targetDB = get("util.datapruner.targetdb") or "simple"

	if targetDB ~= "simple" and targetDB ~= "all" then
		aucPrint("DataPruner: Threshold batch pruning is currently optimized only for Stat-Simple data structures. Change target database or use 'Wipe All Item History' for single items.")
		return
	end

	if not AucAdvancedStatSimpleData or not AucAdvancedStatSimpleData.RealmData then
		aucPrint("DataPruner: Stat-Simple database is empty or not loaded.")
		return
	end

	local SSRealmData = AucAdvancedStatSimpleData.RealmData
	local realmsToProcess = {}

	if serverKey and AucAdvanced.API.IsKeyword(serverKey, "ALL") then
		for rKey in pairs(SSRealmData) do
			tinsert(realmsToProcess, rKey)
		end
	else
		local rKey = ResolveServerKey(serverKey)
		if rKey and SSRealmData[rKey] then
			tinsert(realmsToProcess, rKey)
		end
	end

	aucPrint(("DataPruner: Executing retroactive prune on [%s] [Lower: %d%%, Upper: %d%%]..."):format(targetDB, lowerPct, upperPct))

	local totalItemsChecked = 0
	local totalRecordsPruned = 0

	for _, rKey in ipairs(realmsToProcess) do
		local keyText = AucAdvanced.GetServerKeyText(rKey)
		local realmdata = SSRealmData[rKey]
		local daily = realmdata.daily
		local means = realmdata.means
		local realmPrunedCount = 0

		if means then
			for storeID, itemstring in pairs(means) do
				totalItemsChecked = totalItemsChecked + 1
				local itemstoremeans = {strsplit("_", itemstring)}
				local cleanedProps = {}
				local modified = false

				local baselinePrice = 0
				local validCount = 0

				for _, propStr in ipairs(itemstoremeans) do
					local prop, dataStr = strsplit("@", propStr)
					if dataStr then
						local fields = {strsplit(";", dataStr)}
						local ema3 = tonumber(fields[3]) or 0
						if ema3 > 0 then
							baselinePrice = baselinePrice + ema3
							validCount = validCount + 1
						end
					end
				end

				if validCount > 0 then
					baselinePrice = baselinePrice / validCount
				end

				if baselinePrice > 0 then
					local minBound = baselinePrice * lowerFactor
					local maxBound = baselinePrice * upperFactor

					for _, propStr in ipairs(itemstoremeans) do
						local prop, dataStr = strsplit("@", propStr)
						local isOutlier = false
						if dataStr then
							local fields = {strsplit(";", dataStr)}
							local ema3 = tonumber(fields[3]) or 0
							local ema7 = tonumber(fields[4]) or 0
							local ema14 = tonumber(fields[5]) or 0
							local avgmbo = tonumber(fields[6]) or 0

							if (ema3 > 0 and (ema3 < minBound or ema3 > maxBound)) or
							   (ema7 > 0 and (ema7 < minBound or ema7 > maxBound)) or
							   (ema14 > 0 and (ema14 < minBound or ema14 > maxBound)) or
							   (avgmbo > 0 and (avgmbo < minBound or avgmbo > maxBound)) then
								isOutlier = true
							end
						end

						if isOutlier then
							modified = true
							realmPrunedCount = realmPrunedCount + 1
						else
							tinsert(cleanedProps, propStr)
						end
					end

					if modified then
						if #cleanedProps > 0 then
							means[storeID] = tconcat(cleanedProps, "_")
						else
							means[storeID] = nil
						end
					end
				end
			end
		end

		totalRecordsPruned = totalRecordsPruned + realmPrunedCount
		aucPrint(("DataPruner: Realm [%s] finished. Checked %d entries, pruned %d outlier records."):format(keyText, totalItemsChecked, realmPrunedCount))
	end

	private.ScanResults.scanned = false -- Reset scan state after commit
	aucPrint(("DataPruner: Retroactive prune complete. Total pruned: %d records across scanned realm(s)."):format(totalRecordsPruned))
end

-- Handles Single-Item Pruning (Dual Mode: "threshold" vs "wipe")
function lib.PruneItem(itemLink, mode)
	if not itemLink then return end
	local serverKey = Resources.ServerKey
	local rKey = ResolveServerKey(serverKey)
	local targetDB = get("util.datapruner.targetdb") or "simple"

	if mode == "wipe" then
		local wipedCount = 0
		local algoList = AucAdvanced.API.GetAlgorithms()
		for i, algo in ipairs(algoList) do
			if targetDB == "all" or targetDB == algo:lower() then
				local module = AucAdvanced.GetModule(algo)
				if module and module.ClearItem then
					module.ClearItem(itemLink, serverKey)
					wipedCount = wipedCount + 1
				end
			end
		end
		
		if wipedCount > 0 then
			aucPrint("DataPruner: Completely wiped historical price data for " .. itemLink .. " in target database(s) (" .. targetDB .. ").")
		else
			aucPrint("DataPruner: No valid databases found to wipe for target: " .. targetDB)
		end
	elseif mode == "threshold" then
		if not rKey or not AucAdvancedStatSimpleData or not AucAdvancedStatSimpleData.RealmData then return end
		local realmdata = AucAdvancedStatSimpleData.RealmData[rKey]
		if not realmdata then return end
		local storeID = GetStoreKey(itemLink)
		if not storeID then return end

		local upperPct = get("util.datapruner.uppercutoff") or 300
		local lowerPct = get("util.datapruner.lowercutoff") or 15
		local upperFactor = upperPct / 100
		local lowerFactor = lowerPct / 100

		local prunedCount = 0
		if realmdata.means and realmdata.means[storeID] then
			local itemstring = realmdata.means[storeID]
			local itemstoremeans = {strsplit("_", itemstring)}
			local cleanedProps = {}

			local baselinePrice = 0
			local validCount = 0
			for _, propStr in ipairs(itemstoremeans) do
				local prop, dataStr = strsplit("@", propStr)
				if dataStr then
					local fields = {strsplit(";", dataStr)}
					local ema3 = tonumber(fields[3]) or 0
					if ema3 > 0 then
						baselinePrice = baselinePrice + ema3
						validCount = validCount + 1
					end
				end
			end
			if validCount > 0 then baselinePrice = baselinePrice / validCount end

			if baselinePrice > 0 then
				local minBound = baselinePrice * lowerFactor
				local maxBound = baselinePrice * upperFactor
				for _, propStr in ipairs(itemstoremeans) do
					local prop, dataStr = strsplit("@", propStr)
					local isOutlier = false
					if dataStr then
						local fields = {strsplit(";", dataStr)}
						local ema3 = tonumber(fields[3]) or 0
						if ema3 > 0 and (ema3 < minBound or ema3 > maxBound) then
							isOutlier = true
						end
					end
					if isOutlier then
						prunedCount = prunedCount + 1
					else
						tinsert(cleanedProps, propStr)
					end
				end
				if #cleanedProps > 0 then
					realmdata.means[storeID] = tconcat(cleanedProps, "_")
				else
					realmdata.means[storeID] = nil
				end
			end
		end
		aucPrint(("DataPruner: Finished targeted threshold prune for %s. Pruned %d outlier records."):format(itemLink, prunedCount))
	end

	-- Re-evaluate preview state for item after pruning/wiping
	lib.SetWorkingItem(itemLink)
end

AucAdvanced.RegisterRevision("$URL: Auc-Advanced/Modules/Auc-Util-DataPruner/DataPruner.lua $", "$Rev: 6779 $")
