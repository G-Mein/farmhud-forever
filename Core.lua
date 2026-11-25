local _, ns = ...

local Core = {}
ns.Core = Core

local CHAT_PREFIX = "|cff33ff99Farm|rRadar3D: "

Core.hudShown = false

BINDING_HEADER_FARMRADAR3D = "FarmRadar3D"
BINDING_NAME_FARMRADAR3D_TOGGLE_HUD = "Radar-HUD ein-/ausschalten"
BINDING_NAME_FARMRADAR3D_TOGGLE_BG = "Minimap-Hintergrund umschalten"
BINDING_NAME_FARMRADAR3D_TOGGLE_DRAG = "HUD-Position entsperren/sperren"
BINDING_NAME_FARMRADAR3D_OPEN_OPTIONS = "FarmRadar3D-Einstellungen öffnen"

function Core.IsFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Core.Clamp(value, minVal, maxVal)
	if not Core.IsFiniteNumber(value) then
		return minVal
	end
	if value < minVal then
		return minVal
	end
	if value > maxVal then
		return maxVal
	end
	return value
end

function Core.CanInspectValue(value)
	if issecretvalue then
		local ok, secret = pcall(issecretvalue, value)
		if not ok or secret then
			return false
		end
	end
	if canaccessvalue then
		local ok, accessible = pcall(canaccessvalue, value)
		if not ok or accessible == false then
			return false
		end
	end
	return true
end

function Core.SafeNumber(value)
	if not Core.CanInspectValue(value) then
		return nil
	end
	local num = tonumber(value)
	if Core.IsFiniteNumber(num) then
		return num
	end
	return nil
end

function Core.SafeString(value)
	if not Core.CanInspectValue(value) or value == nil then
		return nil
	end
	if type(value) == "string" then
		return value
	end
	local ok, text = pcall(tostring, value)
	if ok and type(text) == "string" then
		return text
	end
	return nil
end

function Core.SafeNonEmptyString(value)
	local text = Core.SafeString(value)
	if not text then
		return nil
	end
	if text:match("^%s*$") then
		return nil
	end
	return text
end

function Core.SafeBool(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, val = pcall(fn, ...)
	if not ok or not Core.CanInspectValue(val) or type(val) ~= "boolean" then
		return nil
	end
	return val
end

function Core.IsActionRestricted()
	if not (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) then
		return false
	end
	if not (Enum and Enum.AddOnRestrictionType) then
		return false
	end
	local checkKeys = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }
	for _, key in ipairs(checkKeys) do
		local rType = Enum.AddOnRestrictionType[key]
		if rType ~= nil and Core.CanInspectValue(rType) then
			local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, rType)
			if not ok or not Core.CanInspectValue(active) or type(active) ~= "boolean" or active then
				return true
			end
		end
	end
	return false
end

function Core.Print(msg, isWarning)
	if not DEFAULT_CHAT_FRAME or not DEFAULT_CHAT_FRAME.AddMessage then
		return
	end
	local color = isWarning and "|cffff9933" or "|cffffffff"
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. color .. tostring(msg) .. "|r")
end

local function SanitizeOptions(opts)
	for key, defaultVal in pairs(ns.DEFAULTS) do
		if opts[key] == nil or type(opts[key]) ~= type(defaultVal) then
			opts[key] = defaultVal
		end
	end

	for key, bounds in pairs(ns.OPTION_BOUNDS) do
		if type(opts[key]) == "number" and Core.IsFiniteNumber(opts[key]) then
			opts[key] = Core.Clamp(opts[key], bounds[1], bounds[2])
		else
			opts[key] = ns.DEFAULTS[key]
		end
	end

	if Core.IsFiniteNumber(opts.minimapAngle) then
		opts.minimapAngle = opts.minimapAngle % 360
	else
		opts.minimapAngle = ns.DEFAULTS.minimapAngle
	end
end

local function SanitizeLearnedZoneTable(mapTable, maxPerZone)
	if type(mapTable) ~= "table" then
		return {}
	end
	local badZones = {}
	for mapId, list in pairs(mapTable) do
		if type(mapId) ~= "number" or not Core.IsFiniteNumber(mapId) or mapId <= 0 or type(list) ~= "table" then
			badZones[#badZones + 1] = mapId
		else
			local cleanList = {}
			for i = 1, #list do
				local entry = list[i]
				if type(entry) == "table"
					and Core.IsFiniteNumber(entry.x) and entry.x >= 0 and entry.x <= 1
					and Core.IsFiniteNumber(entry.y) and entry.y >= 0 and entry.y <= 1 then
					local nameStr = Core.SafeNonEmptyString(entry.name)
					cleanList[#cleanList + 1] = {
						x = entry.x,
						y = entry.y,
						name = nameStr,
					}
				end
			end
			while #cleanList > maxPerZone do
				table.remove(cleanList, 1)
			end
			mapTable[mapId] = cleanList
		end
	end
	for _, badKey in ipairs(badZones) do
		mapTable[badKey] = nil
	end
	return mapTable
end

function Core.InitDB()
	if type(FarmRadar3DDB) ~= "table" then
		FarmRadar3DDB = {}
	end
	if type(FarmRadar3DDB.options) ~= "table" then
		FarmRadar3DDB.options = {}
	end
	if type(FarmRadar3DDB.learnedNodes) ~= "table" then
		FarmRadar3DDB.learnedNodes = {}
	end

	SanitizeOptions(FarmRadar3DDB.options)
	FarmRadar3DDB.learnedNodes.herb = SanitizeLearnedZoneTable(FarmRadar3DDB.learnedNodes.herb, 400)
	FarmRadar3DDB.learnedNodes.ore = SanitizeLearnedZoneTable(FarmRadar3DDB.learnedNodes.ore, 400)
	FarmRadar3DDB.learnedSkinning = SanitizeLearnedZoneTable(FarmRadar3DDB.learnedSkinning, 250)

	Core.db = FarmRadar3DDB
	if not Core.db.options.restoreOnLogin then
		Core.db.options.hudActive = false
	end
	Core.hudShown = false
end

function Core.GetOptions()
	if not Core.db then
		Core.InitDB()
	end
	return Core.db.options
end

function Core.ResetOptions()
	local opts = Core.GetOptions()
	for key, val in pairs(ns.DEFAULTS) do
		opts[key] = val
	end
	opts.hudActive = Core.hudShown
	if ns.Hud and ns.Hud.ResetInstanceSuspension then
		ns.Hud.ResetInstanceSuspension()
	end
	if Core.hudShown and ns.Hud and ns.Hud.ApplyLayout then
		ns.Hud.ApplyLayout()
	elseif ns.Overlay and ns.Overlay.ApplyStyle then
		ns.Overlay.ApplyStyle()
	end
	if ns.Minimap and ns.Minimap.Refresh then
		ns.Minimap.Refresh()
	end
	if ns.Options and ns.Options.NotifyAll then
		ns.Options.NotifyAll()
	end
	Core.Print("Alle FarmRadar3D-Einstellungen wurden auf Standardwerte zurückgesetzt (gelernte Spots blieben erhalten).")
end

function Core.PrintStatus()
	local opts = Core.GetOptions()
	local skinText = (ns.Sources and ns.Sources.GetSkinningStatusText and ns.Sources.GetSkinningStatusText()) or "unbekannt"
	local trackingCount = (ns.Sources and ns.Sources.GetActiveTrackingCount and ns.Sources.GetActiveTrackingCount()) or 0
	Core.Print(
		string.format(
			"HUD=%s | Größe=%d px | DotScale=%.2fx | BG-Ausblendung=%d%% | Kürschnerei=%s | Aktive Tracking-Filter=%d",
			Core.hudShown and "|cff33ff99AN|r" or "|cffff6666AUS|r",
			opts.hudSize,
			opts.dotScale,
			opts.bgFade,
			skinText,
			trackingCount
		)
	)
end
