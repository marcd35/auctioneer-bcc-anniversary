--[[
	Auctioneer - Search UI - Filter BuyBidDelta
	
	This is a plugin module for the SearchUI that assists in searching by refined paramaters
--]]
-- Create a new instance of our lib with our parent
if not AucSearchUI then return end
local lib, parent, private = AucSearchUI.NewFilter("BuyBidDelta")
if not lib then return end
local print,decode,_,_,replicate,empty,_,_,_,debugPrint,fill = AucAdvanced.GetModuleLocals()
local get,set,default,Const = AucSearchUI.GetSearchLocals()
lib.tabname = "BuyBidDelta"
-- Set our defaults
default("ignorebuybiddelta.enable", false)
default("ignorebuybiddelta.excludenobuyout", true)
default("ignorebuybiddelta.mindelta", 25)
default("ignorebuybiddelta.maxdelta.enable", false)
default("ignorebuybiddelta.maxdelta", 99)

-- This function is automatically called when we need to create our search parameters
function lib:MakeGuiConfig(gui)
	-- Get our tab and populate it with our controls
	local id = gui:AddTab(lib.tabname, "Filters")
	gui:MakeScrollable(id)

	-- Add the help
	gui:AddSearcher("Buy/Bid Delta", "Filter out items based on the percentage difference between buyout and bid", 600)
	gui:AddHelp(id, "buybiddelta filter",
		"What does this filter do?",
		"This filter provides the ability to filter out items that do not meet a minimum percentage difference between their buyout price and current bid price. It can selectively apply its filters only for certain types of searches.")

	gui:AddControl(id, "Header",     0,      "Buy/Bid Delta Filter Criteria")

	local last = gui:GetLast(id)
	gui:AddControl(id, "Checkbox",    0, 1,  "ignorebuybiddelta.enable", "Enable Buy/Bid Delta filtering")
	gui:AddControl(id, "Checkbox",    0, 2,  "ignorebuybiddelta.excludenobuyout", "Exclude auctions with no buyout")
	
	gui:AddControl(id, "Slider",      0, 2,  "ignorebuybiddelta.mindelta", 0, 100, 1, "Min Δ Pct: %s%%")
	gui:AddControl(id, "Checkbox",    0, 2,  "ignorebuybiddelta.maxdelta.enable", "Enable maximum Δ Pct")
	gui:AddControl(id, "Slider",      0, 3,  "ignorebuybiddelta.maxdelta", 0, 100, 1, "Max Δ Pct: %s%%")
	gui:AddTip(id, "Filter out items whose bid/buyout delta is higher than this percentage. Disabled by default.")

	gui:SetLast(id, last)
	gui:AddControl(id, "Subhead",     .5, "Filter for:")
	for name, searcher in pairs(AucSearchUI.Searchers) do
		if searcher and searcher.Search then
			local setting = "ignorebuybiddelta.filter."..name
			default(setting, false)
			gui:AddControl(id, "Checkbox", 0.5, 1, setting, name)
			gui:AddTip(id, "Filter Buy/Bid Delta when searching with "..name)
		end
	end
end

--lib.Filter(item, searcher)
--This function will return true if the item is to be filtered
--Item is the itemtable, and searcher is the name of the searcher being called. If searcher is not given, it will assume you want it active.
function lib.Filter(item, searcher)
	if (not get("ignorebuybiddelta.enable"))
			or (searcher and (not get("ignorebuybiddelta.filter."..searcher))) then
		return
	end
	
	local excludenobuyout = get("ignorebuybiddelta.excludenobuyout")
	local mindelta = get("ignorebuybiddelta.mindelta") or 0
	
	local buy = item[Const.BUYOUT] or 0
	local price = item[Const.PRICE] or 0
	
	if buy == 0 then
		if excludenobuyout then
			return true, "No buyout price"
		else
			return false
		end
	end
	
	if price == 0 then
		-- if price is 0, then mathematically the delta is 100% from buyout, unless buyout is 0
		if mindelta > 0 then
			return false -- delta is 100%, meets any minimum
		end
	end
	
	local deltapct = math.floor((buy - price) / buy * 100)

	if deltapct < mindelta then
		return true, "Delta percentage too low"
	end

	if get("ignorebuybiddelta.maxdelta.enable") then
		local maxdelta = get("ignorebuybiddelta.maxdelta") or 99
		if deltapct > maxdelta then
			return true, "Delta percentage too high"
		end
	end

	return false
end

--PostFilter is only needed when we're restricting to bids
function lib.PostFilter(item, searcher, buyorbid)
	-- No additional post filtering needed based on bid/buy mode
	return false
end

AucAdvanced.RegisterRevision("$URL: Auc-Advanced/Modules/Auc-Util-SearchUI/FilterBuyBidDelta.lua $", "$Rev: 6750 $")
