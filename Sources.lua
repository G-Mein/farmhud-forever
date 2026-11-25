local _, ns = ...

local Core = ns.Core

local Sources = {}
ns.Sources = Sources

local uiMapToArea = {}
local zoneMapsInitialized = false
local mapBoundsCache = {}

local professionsChecked = false
local hasSkinning = false

local questCache = {}
local questCacheTime = -1
local questCacheMapId = nil
local questCacheDirty = true

local gatherCache = {} -- [uiMapID] = list | { retryAt = t }
local nodeCooldowns = {} -- [coordKey] = expiresAt (GetTime)

local skinningCorpses = {} -- array of { wx, wy, instance, guid, name, expiresAt, ... }
local recentSkinnableGuids = {} -- [guid] = { name, seenAt }
local skinnedGuids = {} -- [guid] = skinnedAt
local lastSkinnableMob = nil -- { guid, name, seenAt }
local suppressLootUntil = 0

local trackingEntries = {}
local trackingByKey = {}
local trackingChecked = false
local activeTrackingCount = 0

local serviceCache = {} -- [uiMapID] = { [serviceKey] = list | { retryAt = t } }
local mailboxCache = {} -- [uiMapID] = list | { retryAt = t }
local npcScanState = nil

local scanTooltip = nil
local reusableSortTemp = {}
local lastCastTargetName = nil

local function MakeVector(x, y)
	if type(CreateVector2D) == "function" then
		return CreateVector2D(x, y)
	end
	return {
		x = x,
		y = y,
		GetXY = function(self)
			return self.x, self.y
		end,
	}
end

local function ExtractXY(pos)
	if type(pos) ~= "table" then
		return nil, nil
	end
	if type(pos.GetXY) == "function" then
		local ok, x, y = pcall(pos.GetXY, pos)
		if ok then
			return Core.SafeNumber(x), Core.SafeNumber(y)
		end
	end
	return Core.SafeNumber(pos.x), Core.SafeNumber(pos.y)
end

local function MakeCoordKey(kind, wx, wy)
	return string.format("%s:%.1f:%.1f", kind, wx, wy)
end

local function IsCacheRetryPending(entry, now)
	return type(entry) == "table" and entry.retryAt ~= nil and now < entry.retryAt
end

local function DecodeQuestieTableString(chunkStr, target)
	if type(chunkStr) ~= "string" or chunkStr == "" then
		return
	end
	local loader = rawget(_G, "loadstring") or rawget(_G, "load")
	if type(loader) ~= "function" then
		return
	end
	local okCompile, fn = pcall(loader, chunkStr)
	if not okCompile or type(fn) ~= "function" then
		return
	end
	local okRun, tbl = pcall(fn)
	if okRun and type(tbl) == "table" then
		for k, v in pairs(tbl) do
			target[k] = v
		end
	end
end

function Sources.InitZoneMaps()
	if zoneMapsInitialized then
		return
	end
	zoneMapsInitialized = true

	local areaToUiTemp = {}
	local qdb = rawget(_G, "LibQuestieDB")
	if type(qdb) == "table" and qdb.Support and type(qdb.Support.Get) == "function" then
		local ok, zData = pcall(qdb.Support.Get, "ZoneDB")
		if ok and type(zData) == "table" and type(zData.private) == "table" then
			local priv = zData.private
			DecodeQuestieTableString(priv.uiMapIdToAreaId, uiMapToArea)
			DecodeQuestieTableString(priv.uiMapIdToAreaIdOverride, uiMapToArea)
			DecodeQuestieTableString(priv.areaIdToUiMapId, areaToUiTemp)
			DecodeQuestieTableString(priv.areaIdToUiMapIdOverride, areaToUiTemp)
		end
	end

	for areaId, mapId in pairs(areaToUiTemp) do
		if type(mapId) == "number" and mapId > 0 and type(areaId) == "number" and areaId > 0 and not uiMapToArea[mapId] then
			uiMapToArea[mapId] = areaId
		end
	end
end

function Sources.GetAreaIdByUiMapId(uiMapID)
	if type(uiMapID) ~= "number" or uiMapID <= 0 then
		return nil
	end
	Sources.InitZoneMaps()
	if uiMapToArea[uiMapID] then
		return uiMapToArea[uiMapID]
	end
	if QuestieLoader and type(QuestieLoader.ImportModule) == "function" then
		local okMod, zdb = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
		if okMod and type(zdb) == "table" and type(zdb.GetAreaIdByUiMapId) == "function" then
			local okId, aid = pcall(zdb.GetAreaIdByUiMapId, zdb, uiMapID)
			if okId and type(aid) == "number" and aid > 0 then
				uiMapToArea[uiMapID] = aid
				return aid
			end
		end
	end
	if C_Map and C_Map.GetMapInfo then
		local okInfo, info = pcall(C_Map.GetMapInfo, uiMapID)
		if okInfo and type(info) == "table" and info.parentMapID and info.parentMapID > 0 then
			return uiMapToArea[info.parentMapID]
		end
	end
	return nil
end

function Sources.GetMapBounds(uiMapID)
	if type(uiMapID) ~= "number" or uiMapID <= 0 then
		return nil
	end
	local now = GetTime()
	local cached = mapBoundsCache[uiMapID]
	if type(cached) == "table" and cached.width then
		return cached
	end
	if IsCacheRetryPending(cached, now) then
		return nil
	end
	if not (C_Map and C_Map.GetWorldPosFromMapPos) then
		mapBoundsCache[uiMapID] = { retryAt = now + 2.0 }
		return nil
	end

	local okCenter, instance, center = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, MakeVector(0.5, 0.5))
	if not okCenter or not Core.CanInspectValue(instance) or type(instance) ~= "number" or not center then
		mapBoundsCache[uiMapID] = { retryAt = now + 2.0 }
		return nil
	end

	local cTop, cLeft = ExtractXY(center)
	if not (cTop and cLeft) then
		mapBoundsCache[uiMapID] = { retryAt = now + 2.0 }
		return nil
	end

	local width, height
	if C_Map.GetMapWorldSize then
		local okSize, w, h = pcall(C_Map.GetMapWorldSize, uiMapID)
		if okSize then
			width = Core.SafeNumber(w)
			height = Core.SafeNumber(h)
		end
	end
	if not (width and height and width > 0 and height > 0) then
		local okTL, _, topLeft = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, MakeVector(0, 0))
		if okTL and topLeft then
			local tlTop, tlLeft = ExtractXY(topLeft)
			if tlTop and tlLeft then
				width = math.abs(tlLeft - cLeft) * 2
				height = math.abs(tlTop - cTop) * 2
			end
		end
	end

	if not (width and height and width > 0 and height > 0) then
		mapBoundsCache[uiMapID] = { retryAt = now + 2.0 }
		return nil
	end

	local bounds = {
		width = width,
		height = height,
		left = cLeft + (width / 2),
		top = cTop + (height / 2),
		instance = instance,
	}
	mapBoundsCache[uiMapID] = bounds
	return bounds
end

-- HBD-konforme Umrechnung: (uiMapID, x in 0..1, y in 0..1) -> (worldX, worldY, instanceID)
function Sources.ZoneToWorld(uiMapID, x01, y01)
	local b = Sources.GetMapBounds(uiMapID)
	if not b then
		return nil, nil, nil
	end
	if not (Core.IsFiniteNumber(x01) and Core.IsFiniteNumber(y01)) then
		return nil, nil, nil
	end
	return b.left - b.width * x01, b.top - b.height * y01, b.instance
end

function Sources.GetPlayerWorldPos()
	if type(UnitPosition) ~= "function" then
		return nil, nil, nil
	end
	local ok, rawY, rawX, _, rawInstance = pcall(UnitPosition, "player")
	if not ok then
		return nil, nil, nil
	end
	local py = Core.SafeNumber(rawY)
	local px = Core.SafeNumber(rawX)
	local instance = Core.SafeNumber(rawInstance)
	if not (px and py and instance) then
		return nil, nil, nil
	end
	return px, py, instance
end

function Sources.GetPlayerZonePos()
	if not (C_Map and C_Map.GetBestMapForUnit) then
		return nil, nil, nil
	end
	local okMap, uiMapID = pcall(C_Map.GetBestMapForUnit, "player")
	uiMapID = okMap and Core.SafeNumber(uiMapID) or nil
	if not uiMapID or uiMapID <= 0 then
		return nil, nil, nil
	end
	if C_Map.GetPlayerMapPosition then
		local okPos, pos = pcall(C_Map.GetPlayerMapPosition, uiMapID, "player")
		if okPos and pos then
			local mx, my = ExtractXY(pos)
			if mx and my then
				return uiMapID, mx, my
			end
		end
	end
	return uiMapID, nil, nil
end

function Sources.GetCurrentViewRadius()
	if C_Minimap and C_Minimap.GetViewRadius then
		local ok, radius = pcall(C_Minimap.GetViewRadius)
		radius = ok and Core.SafeNumber(radius) or nil
		if radius and radius > 5 then
			return radius
		end
	end

	local zoom = (Minimap and Minimap.GetZoom) and Core.SafeNumber(Minimap:GetZoom()) or 0
	zoom = math.floor(Core.Clamp(zoom or 0, 0, 5))
	local indoor = Core.SafeBool(IsIndoors) == true
	local tableSet = indoor and ns.MINIMAP_ZOOM_DIAMETERS.indoor or ns.MINIMAP_ZOOM_DIAMETERS.outdoor
	local diameter = tableSet[zoom] or tableSet[0]
	return diameter / 2
end

-- ---------------------------------------------------------------------------
-- Berufserkennung (Primaer: GetProfessions + GetProfessionInfo fuer Forever 16001)
-- ---------------------------------------------------------------------------

local function IsSkinningSlot(name, icon, skillLine)
	local line = Core.SafeNumber(skillLine)
	if line == 393 then
		return true
	end
	local safeName = Core.SafeNonEmptyString(name)
	if safeName and ns.SKINNING_NAMES[string.lower(safeName)] then
		return true
	end
	local iconNum = Core.SafeNumber(icon)
	if iconNum == 134366 then
		return true
	end
	local iconStr = Core.SafeNonEmptyString(icon)
	if iconStr and string.lower(iconStr):find("inv_misc_pelt_wolf_01", 1, true) then
		return true
	end
	return false
end

local function ProbePositiveSkinningSpell()
	for spellID in pairs(ns.GATHER_SPELLS.SKINNING) do
		if C_SpellBook and C_SpellBook.IsSpellKnown then
			if Core.SafeBool(C_SpellBook.IsSpellKnown, spellID) == true then
				return true
			end
		end
		if type(IsSpellKnown) == "function" then
			if Core.SafeBool(IsSpellKnown, spellID) == true then
				return true
			end
		end
		if type(IsPlayerSpell) == "function" then
			if Core.SafeBool(IsPlayerSpell, spellID) == true then
				return true
			end
		end
	end
	return false
end

function Sources.RefreshProfessions()
	local prevSkinning = hasSkinning
	local detectedSkinning = false
	local gotPrimaryRows = false

	-- Primaerer Pfad auf WoW Forever 16001: GetProfessions + GetProfessionInfo
	if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
		local ok, p1, p2, arch, fish, cook, firstAid = pcall(GetProfessions)
		if ok then
			local slots = { p1, p2, arch, fish, cook, firstAid }
			for _, idx in pairs(slots) do
				local slotIdx = Core.SafeNumber(idx)
				if slotIdx then
					local okInfo, name, icon, _, _, _, _, skillLine = pcall(GetProfessionInfo, slotIdx)
					if okInfo and Core.SafeNonEmptyString(name) then
						gotPrimaryRows = true
						if IsSkinningSlot(name, icon, skillLine) then
							detectedSkinning = true
							break
						end
					end
				end
			end
		end
	end

	-- Sekundaerer Pfad ueber C_SkillInfo oder Legacy-GetSkillLineInfo
	if not detectedSkinning then
		if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
			local okN, count = pcall(C_SkillInfo.GetNumSkillLines)
			count = okN and Core.SafeNumber(count) or 0
			for i = 1, math.min(count, 40) do
				local okS, info = pcall(C_SkillInfo.GetSkillLineInfo, i)
				if okS and type(info) == "table" and Core.CanInspectValue(info.isHeader) and not info.isHeader then
					if Core.SafeNonEmptyString(info.name) then
						gotPrimaryRows = true
					end
					if IsSkinningSlot(info.name, nil, info.skillID) then
						detectedSkinning = true
						break
					end
				end
			end
		elseif type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
			local okN, count = pcall(GetNumSkillLines)
			count = okN and Core.SafeNumber(count) or 0
			for i = 1, math.min(count, 40) do
				local okS, name, isHeader = pcall(GetSkillLineInfo, i)
				if okS and Core.CanInspectValue(isHeader) and not isHeader then
					if Core.SafeNonEmptyString(name) then
						gotPrimaryRows = true
					end
					if IsSkinningSlot(name, nil, nil) then
						detectedSkinning = true
						break
					end
				end
			end
		end
	end

	-- Spell-Fallback nur falls primaere Berufsabfrage noch gar keine Zeilen geliefert hat
	if (not gotPrimaryRows) and (not detectedSkinning) and ProbePositiveSkinningSpell() then
		detectedSkinning = true
	end

	professionsChecked = true
	hasSkinning = detectedSkinning

	if prevSkinning and not hasSkinning then
		Sources.ClearAllSkinningCorpses()
		lastSkinnableMob = nil
		recentSkinnableGuids = {}
		skinnedGuids = {}
	end

	if prevSkinning ~= hasSkinning and ns.Options and ns.Options.NotifyAll then
		ns.Options.NotifyAll()
	end
end

function Sources.HasSkinning()
	if not professionsChecked then
		Sources.RefreshProfessions()
	end
	return hasSkinning
end

function Sources.GetSkinningStatusText()
	if Sources.HasSkinning() then
		return "|cff33ff99gelernt (aktiv)|r"
	end
	return "|cff999999nicht gelernt (ausgeblendet)|r"
end

-- ---------------------------------------------------------------------------
-- Quest-Items & Quest-Ziele (Questie + C_QuestLog/C_SuperTrack/C_AreaPoiInfo)
-- ---------------------------------------------------------------------------

function Sources.InvalidateQuestCache()
	questCacheDirty = true
end

local function ClassifyQuestIconType(iconType, dataType)
	local q = rawget(_G, "Questie")
	if q then
		if iconType == q.ICON_TYPE_LOOT or iconType == q.ICON_TYPE_OBJECT
			or iconType == q.ICON_TYPE_INTERACT or iconType == q.ICON_TYPE_CHEST then
			return "quest_item"
		end
		if iconType == q.ICON_TYPE_AVAILABLE or iconType == q.ICON_TYPE_AVAILABLE_GRAY
			or iconType == q.ICON_TYPE_REPEATABLE or iconType == q.ICON_TYPE_EVENTQUEST
			or iconType == q.ICON_TYPE_PVPQUEST then
			return nil
		end
		if iconType == q.ICON_TYPE_SLAY or iconType == q.ICON_TYPE_EVENT
			or iconType == q.ICON_TYPE_TALK or iconType == q.ICON_TYPE_COMPLETE
			or iconType == q.ICON_TYPE_INCOMPLETE or iconType == q.ICON_TYPE_REPEATABLE_COMPLETE
			or iconType == q.ICON_TYPE_EVENTQUEST_COMPLETE or iconType == q.ICON_TYPE_PVPQUEST_COMPLETE
			or iconType == q.ICON_TYPE_SODRUNE then
			return "quest_obj"
		end
	end
	if dataType == "object" or dataType == "item" then
		return "quest_item"
	end
	if dataType == "monster" or dataType == "event" or dataType == "complete" then
		return "quest_obj"
	end
	return nil
end

local function AddFallbackQuestPin(seenCoords, uiMapID, mx, my, playerInstance, category, name)
	local wx, wy, inst = Sources.ZoneToWorld(uiMapID, mx, my)
	if wx and wy and inst == playerInstance then
		local dedupKey = MakeCoordKey(category, wx, wy)
		if not seenCoords[dedupKey] then
			seenCoords[dedupKey] = true
			questCache[#questCache + 1] = {
				wx = wx,
				wy = wy,
				instance = inst,
				category = category,
				icon = ns.TEX_DOT,
				color = ns.PIN_COLORS[category],
				name = name,
			}
		end
	end
end

local function RebuildQuestCache(uiMapID, playerInstance)
	questCache = {}
	questCacheTime = GetTime()
	questCacheMapId = uiMapID
	questCacheDirty = false

	local q = rawget(_G, "Questie")
	local qm = rawget(_G, "QuestieMap")
	if not qm and rawget(_G, "QuestieLoader") and type(QuestieLoader.ImportModule) == "function" then
		local okM, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieMap")
		if okM and type(mod) == "table" then
			qm = mod
		end
	end

	local seenCoords = {}
	if qm and type(qm.questIdFrames) == "table" then
		for _, frameList in pairs(qm.questIdFrames) do
			if type(frameList) == "table" then
				for _, frameName in pairs(frameList) do
					local frame = type(frameName) == "string" and _G[frameName] or frameName
					if type(frame) == "table" and not frame.miniMapIcon and not frame.hidden and frame.data then
						local fMapId = Core.SafeNumber(frame.UiMapID)
						local fx = Core.SafeNumber(frame.x)
						local fy = Core.SafeNumber(frame.y)
						if fMapId and fx and fy then
							local category = ClassifyQuestIconType(frame.data.Icon, frame.data.Type)
							if category then
								local wx, wy, inst = Sources.ZoneToWorld(fMapId, fx / 100, fy / 100)
								if wx and wy and inst == playerInstance then
									local dedupKey = MakeCoordKey(category, wx, wy)
									if not seenCoords[dedupKey] then
										seenCoords[dedupKey] = true
										local tex = (q and q.usedIcons and frame.data.Icon and q.usedIcons[frame.data.Icon])
											or ns.TEX_DOT
										questCache[#questCache + 1] = {
											wx = wx,
											wy = wy,
											instance = inst,
											category = category,
											icon = tex,
											color = ns.PIN_COLORS[category],
											name = Core.SafeNonEmptyString(frame.data.Name) or "Questziel",
										}
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Blizzard-Fallbacks (C_QuestLog, C_SuperTrack, C_AreaPoiInfo), wenn Questie nicht aktiv ist
	if #questCache == 0 and uiMapID then
		if C_QuestLog and C_QuestLog.GetQuestsOnMap then
			local okQ, mapQuests = pcall(C_QuestLog.GetQuestsOnMap, uiMapID)
			if okQ and type(mapQuests) == "table" then
				for _, info in ipairs(mapQuests) do
					if type(info) == "table" then
						local mx = Core.SafeNumber(info.x)
						local my = Core.SafeNumber(info.y)
						if mx and my then
							AddFallbackQuestPin(seenCoords, uiMapID, mx, my, playerInstance, "quest_obj", "Quest")
						end
					end
				end
			end
		end

		if C_SuperTrack and C_SuperTrack.GetNextWaypointForMap then
			local okW, wx01, wy01, desc = pcall(C_SuperTrack.GetNextWaypointForMap, uiMapID)
			if okW then
				local mx = Core.SafeNumber(wx01)
				local my = Core.SafeNumber(wy01)
				if mx and my then
					AddFallbackQuestPin(
						seenCoords,
						uiMapID,
						mx,
						my,
						playerInstance,
						"quest_obj",
						Core.SafeNonEmptyString(desc) or "Quest-Wegpunkt"
					)
				end
			end
		end

		if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap and C_AreaPoiInfo.GetAreaPOIInfo then
			local okIds, poiIds = pcall(C_AreaPoiInfo.GetAreaPOIForMap, uiMapID)
			if okIds and type(poiIds) == "table" then
				for _, poiId in ipairs(poiIds) do
					local okPoi, poiInfo = pcall(C_AreaPoiInfo.GetAreaPOIInfo, uiMapID, poiId)
					if okPoi and type(poiInfo) == "table" and poiInfo.position then
						local mx, my = ExtractXY(poiInfo.position)
						if mx and my then
							AddFallbackQuestPin(
								seenCoords,
								uiMapID,
								mx,
								my,
								playerInstance,
								"quest_obj",
								Core.SafeNonEmptyString(poiInfo.name) or "POI"
							)
						end
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Kuerschnerei-Leichen-Tracker + Gelernte Kuerschner-Spots
-- ---------------------------------------------------------------------------

local function EnsureScanTooltip()
	if scanTooltip then
		return scanTooltip
	end
	if type(CreateFrame) ~= "function" then
		return nil
	end
	local ok, tt = pcall(CreateFrame, "GameTooltip", "FarmRadar3DScanTooltip", nil, "GameTooltipTemplate")
	if ok and tt then
		scanTooltip = tt
	end
	return scanTooltip
end

local function CheckTooltipSkinnable(unit)
	local skinConst = rawget(_G, "UNIT_SKINNABLE_LEATHER")
	if type(skinConst) ~= "string" or skinConst == "" then
		return false
	end
	local tt = EnsureScanTooltip()
	if not (tt and tt.SetOwner and tt.SetUnit) then
		return false
	end
	local ok = pcall(function()
		tt:SetOwner(WorldFrame, "ANCHOR_NONE")
		tt:SetUnit(unit)
	end)
	if not ok then
		return false
	end
	local lowerTarget = string.lower(skinConst)
	local numLines = Core.SafeNumber(tt.NumLines and tt:NumLines() or 0) or 0
	for i = 1, math.min(numLines, 12) do
		local lineFS = _G["FarmRadar3DScanTooltipTextLeft" .. i]
		if lineFS and lineFS.GetText then
			local txt = Core.SafeNonEmptyString(lineFS:GetText())
			if txt and string.lower(txt):find(lowerTarget, 1, true) then
				tt:Hide()
				return true
			end
		end
	end
	tt:Hide()
	return false
end

local function IsUnitPotentiallySkinnable(unit)
	if not Sources.HasSkinning() then
		return false, nil, nil
	end
	if Core.SafeBool(UnitExists, unit) ~= true then
		return false, nil, nil
	end
	if Core.SafeBool(UnitIsDead, unit) ~= true then
		return false, nil, nil
	end
	if Core.SafeBool(UnitIsPlayer, unit) == true then
		return false, nil, nil
	end
	if Core.SafeBool(UnitIsFriend, "player", unit) == true then
		return false, nil, nil
	end

	local cType = UnitCreatureType and Core.SafeNonEmptyString(UnitCreatureType(unit)) or nil
	local skinnable = false
	if cType and ns.SKINNABLE_CREATURE_TYPES[string.lower(cType)] then
		skinnable = true
	elseif CheckTooltipSkinnable(unit) then
		skinnable = true
	end
	if not skinnable then
		return false, nil, nil
	end
	local uName = UnitName and Core.SafeNonEmptyString(UnitName(unit)) or "Kürschnerbar"
	local guid = UnitGUID and Core.SafeNonEmptyString(UnitGUID(unit)) or nil
	return true, uName, guid
end

local function PruneOldGuidMaps(now)
	for guid, entry in pairs(recentSkinnableGuids) do
		if (now - entry.seenAt) > 120 then
			recentSkinnableGuids[guid] = nil
		end
	end
	for guid, ts in pairs(skinnedGuids) do
		if (now - ts) > 60 then
			skinnedGuids[guid] = nil
		end
	end
end

function Sources.ObserveUnit(unit)
	if not Sources.HasSkinning() then
		return
	end
	local ok, name, guid = IsUnitPotentiallySkinnable(unit)
	if ok then
		local now = GetTime()
		PruneOldGuidMaps(now)
		lastSkinnableMob = {
			name = name or "Kürschnerbar",
			guid = guid,
			seenAt = now,
		}
		if guid then
			recentSkinnableGuids[guid] = {
				name = name or "Kürschnerbar",
				seenAt = now,
			}
		end
	end
end

local function PruneExpiredCorpses(now)
	for i = #skinningCorpses, 1, -1 do
		if skinningCorpses[i].expiresAt <= now then
			table.remove(skinningCorpses, i)
		end
	end
end

local function InspectLootCreatureSources()
	if type(GetNumLootItems) ~= "function" or type(GetLootSourceInfo) ~= "function" then
		return false, {}
	end
	local okN, numItems = pcall(GetNumLootItems)
	numItems = okN and Core.SafeNumber(numItems) or 0
	if numItems <= 0 then
		return false, {}
	end
	local creatureGuids = {}
	local sawAnyGuid = false
	for slot = 1, math.min(numItems, 32) do
		local res = { pcall(GetLootSourceInfo, slot) }
		if res[1] then
			for idx = 2, #res, 2 do
				local guid = Core.SafeNonEmptyString(res[idx])
				if guid then
					sawAnyGuid = true
					if guid:sub(1, 9) == "Creature-" then
						creatureGuids[guid] = true
					end
				end
			end
		end
	end
	return sawAnyGuid, creatureGuids
end

function Sources.OnLootEvent(event)
	if not Sources.HasSkinning() then
		return
	end
	if event == "LOOT_CLOSED" then
		lastSkinnableMob = nil
		return
	end
	local opts = Core.GetOptions()
	if not opts.showSkinningCorpses then
		return
	end

	local now = GetTime()
	if now < suppressLootUntil then
		-- Unterdrueckt eigenes Leder-Lootfenster unmittelbar nach Kuerschner-Zauber
		return
	end
	PruneOldGuidMaps(now)

	local px, py, inst = Sources.GetPlayerWorldPos()
	if not (px and py and inst) then
		return
	end

	local sawGuid, creatureGuids = InspectLootCreatureSources()
	if sawGuid and not next(creatureGuids) then
		-- Loot stammt nur von Truhe / Objekt / Beutel -> kein Kuerschner-Marker
		return
	end

	local chosenGuid = nil
	local chosenName = nil

	if next(creatureGuids) then
		for guid in pairs(creatureGuids) do
			if not skinnedGuids[guid] then
				local seen = recentSkinnableGuids[guid]
				if seen then
					chosenGuid = guid
					chosenName = seen.name
					break
				end
			end
		end
	end

	if not chosenName then
		local tSkin, tName, tGuid = IsUnitPotentiallySkinnable("target")
		if not tSkin then
			tSkin, tName, tGuid = IsUnitPotentiallySkinnable("mouseover")
		end
		if tSkin then
			if (not sawGuid) or (tGuid and creatureGuids[tGuid] and not skinnedGuids[tGuid]) then
				chosenGuid = tGuid
				chosenName = tName
			end
		end
	end

	if not chosenName then
		return
	end

	PruneExpiredCorpses(now)
	for _, c in ipairs(skinningCorpses) do
		if (chosenGuid and c.guid == chosenGuid)
			or (c.instance == inst and ((c.wx - px) ^ 2 + (c.wy - py) ^ 2) <= 25) then
			c.expiresAt = now + opts.skinningCorpseDuration
			c.name = chosenName or c.name
			c.guid = c.guid or chosenGuid
			return
		end
	end

	skinningCorpses[#skinningCorpses + 1] = {
		wx = px,
		wy = py,
		instance = inst,
		guid = chosenGuid,
		category = "skin_corpse",
		icon = ns.ICON_SKINNING,
		color = ns.PIN_COLORS.skin_corpse,
		name = chosenName or "Kürschner-Leiche",
		expiresAt = now + opts.skinningCorpseDuration,
	}
end

local function SaveLearnedSpot(storageTable, uiMapID, x01, y01, name, maxPerZone)
	if not (uiMapID and x01 and y01) then
		return
	end
	storageTable[uiMapID] = storageTable[uiMapID] or {}
	local list = storageTable[uiMapID]
	local b = Sources.GetMapBounds(uiMapID)
	local wx, wy = nil, nil
	if b then
		wx = b.left - b.width * x01
		wy = b.top - b.height * y01
	end
	for _, entry in ipairs(list) do
		if wx and wy and b then
			local ex = b.left - b.width * entry.x
			local ey = b.top - b.height * entry.y
			local dx, dy = ex - wx, ey - wy
			if (dx * dx + dy * dy) <= 144 then
				return
			end
		elseif math.abs(entry.x - x01) < 0.008 and math.abs(entry.y - y01) < 0.008 then
			return
		end
	end
	if #list >= maxPerZone then
		table.remove(list, 1)
	end
	list[#list + 1] = {
		x = math.floor(x01 * 10000 + 0.5) / 10000,
		y = math.floor(y01 * 10000 + 0.5) / 10000,
		name = Core.SafeNonEmptyString(name),
	}
end

function Sources.ClearAllSkinningCorpses()
	skinningCorpses = {}
end

-- ---------------------------------------------------------------------------
-- Herb/Ore Spawns (QuestieDB + Auto-Lernen + Cooldown) & Zauber-Ereignisse
-- ---------------------------------------------------------------------------

local function EnsureGatherZoneCache(uiMapID)
	local now = GetTime()
	local existing = gatherCache[uiMapID]
	if type(existing) == "table" and not existing.retryAt then
		return existing
	end
	if IsCacheRetryPending(existing, now) then
		return nil
	end

	local areaID = Sources.GetAreaIdByUiMapId(uiMapID)
	local qdb = rawget(_G, "LibQuestieDB")
	local objDB = (type(qdb) == "table" and qdb.Object) or rawget(_G, "ObjectDB")
	if not (areaID and objDB and type(objDB.Get) == "function") then
		gatherCache[uiMapID] = { retryAt = now + 2.0 }
		return nil
	end

	local bounds = Sources.GetMapBounds(uiMapID)
	if not bounds then
		gatherCache[uiMapID] = { retryAt = now + 2.0 }
		return nil
	end

	local list = {}
	local seen = {}

	local function AddObjectList(idList, kind, defaultIcon)
		for _, oid in ipairs(idList) do
			local spawns = objDB.Get(oid, "spawns")
			local zoneSpawns = type(spawns) == "table" and spawns[areaID] or nil
			if type(zoneSpawns) == "table" then
				local objName = Core.SafeNonEmptyString(objDB.Get(oid, "name")) or (kind == "herb" and "Kraut" or "Erz")
				for _, coord in ipairs(zoneSpawns) do
					if type(coord) == "table" and type(coord[1]) == "number" and type(coord[2]) == "number" then
						local wx = bounds.left - bounds.width * (coord[1] / 100)
						local wy = bounds.top - bounds.height * (coord[2] / 100)
						local key = MakeCoordKey(kind, wx, wy)
						if not seen[key] then
							seen[key] = true
							list[#list + 1] = {
								id = oid,
								key = key,
								kind = kind,
								category = kind,
								name = objName,
								wx = wx,
								wy = wy,
								instance = bounds.instance,
								icon = defaultIcon,
								color = ns.PIN_COLORS[kind],
							}
						end
					end
				end
			end
		end
	end

	AddObjectList(ns.HERB_OBJECT_IDS, "herb", ns.ICON_HERB)
	AddObjectList(ns.ORE_OBJECT_IDS, "ore", ns.ICON_ORE)

	gatherCache[uiMapID] = list
	return list
end

local function PruneExpiredCooldowns(now)
	for key, entry in pairs(nodeCooldowns) do
		if type(entry) ~= "table" or entry.expiresAt <= now then
			nodeCooldowns[key] = nil
		end
	end
end

local function MarkNearestGatherCooldown(kind, labelName)
	local opts = Core.GetOptions()
	local px, py, inst = Sources.GetPlayerWorldPos()
	local uiMapID, mx, my = Sources.GetPlayerZonePos()
	if not (px and py and inst) then
		return
	end

	local now = GetTime()
	PruneExpiredCooldowns(now)
	local bestNode = nil
	local nodes = uiMapID and EnsureGatherZoneCache(uiMapID) or nil
	if type(nodes) == "table" then
		local bestDistSq = 324 -- 18 Yards
		for _, node in ipairs(nodes) do
			if node.kind == kind and node.instance == inst then
				local dx, dy = node.wx - px, node.wy - py
				local dSq = dx * dx + dy * dy
				if dSq <= bestDistSq then
					bestDistSq = dSq
					bestNode = node
				end
			end
		end
	end

	local cdWx, cdWy = px, py
	if bestNode then
		cdWx, cdWy = bestNode.wx, bestNode.wy
	elseif uiMapID and mx and my then
		local lx, ly = Sources.ZoneToWorld(uiMapID, mx, my)
		if lx and ly then
			cdWx, cdWy = lx, ly
		end
	end

	local cdKey = MakeCoordKey(kind, cdWx, cdWy)
	nodeCooldowns[cdKey] = {
		kind = kind,
		wx = cdWx,
		wy = cdWy,
		instance = inst,
		expiresAt = now + opts.gatherCooldown,
	}

	if uiMapID and mx and my and Core.db then
		local learned = Core.db.learnedNodes
		learned[kind] = learned[kind] or {}
		local cleanLabel = Core.SafeNonEmptyString(labelName) or (kind == "herb" and "Kraut" or "Erz")
		SaveLearnedSpot(learned[kind], uiMapID, mx, my, cleanLabel, 400)
	end
end

local function ClassifySpellAction(spellID)
	if type(spellID) ~= "number" then
		return nil
	end
	if ns.GATHER_SPELLS.SKINNING[spellID] then
		return "skinning"
	end
	if ns.GATHER_SPELLS.HERB[spellID] then
		return "herb"
	end
	if ns.GATHER_SPELLS.MINING[spellID] then
		return "ore"
	end

	local spellName = nil
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
		if ok and type(info) == "table" then
			spellName = Core.SafeNonEmptyString(info.name)
		end
	elseif type(GetSpellInfo) == "function" then
		local ok, name = pcall(GetSpellInfo, spellID)
		if ok then
			spellName = Core.SafeNonEmptyString(name)
		end
	end

	if not spellName then
		return nil
	end
	local lower = string.lower(spellName)
	if ns.SKINNING_NAMES[lower] or lower:find("kürsch", 1, true) or lower:find("skinning", 1, true) then
		return "skinning"
	end
	for _, kw in ipairs(ns.HERB_SPELL_KEYWORDS) do
		if lower:find(kw, 1, true) then
			return "herb"
		end
	end
	for _, kw in ipairs(ns.ORE_SPELL_KEYWORDS) do
		if lower:find(kw, 1, true) then
			return "ore"
		end
	end
	return nil
end

function Sources.OnSpellCastSent(unit, target, _, spellID)
	if Core.SafeString(unit) ~= "player" then
		return
	end
	lastCastTargetName = Core.SafeNonEmptyString(target)
	local safeSpellId = Core.SafeNumber(spellID)
	if ClassifySpellAction(safeSpellId) == "skinning" then
		suppressLootUntil = 0
	end
end

function Sources.OnSpellCastSucceeded(unit, _, spellID)
	if Core.SafeString(unit) ~= "player" then
		return false
	end
	local safeSpellId = Core.SafeNumber(spellID)
	local kind = ClassifySpellAction(safeSpellId)
	if not kind then
		return false
	end

	if kind == "skinning" then
		if not Sources.HasSkinning() then
			return false
		end
		local now = GetTime()
		suppressLootUntil = now + 2.5
		lastSkinnableMob = nil

		local px, py, inst = Sources.GetPlayerWorldPos()
		if px and py and inst then
			local bestIdx = nil
			local bestDistSq = 196 -- 14 Yards
			for i, corpse in ipairs(skinningCorpses) do
				if corpse.instance == inst then
					local dx, dy = corpse.wx - px, corpse.wy - py
					local dSq = dx * dx + dy * dy
					if dSq <= bestDistSq then
						bestDistSq = dSq
						bestIdx = i
					end
				end
			end
			if bestIdx then
				local removed = table.remove(skinningCorpses, bestIdx)
				if removed and removed.guid then
					skinnedGuids[removed.guid] = now
				end
			end
		end
		local uiMapID, mx, my = Sources.GetPlayerZonePos()
		if Core.db and uiMapID and mx and my then
			SaveLearnedSpot(Core.db.learnedSkinning, uiMapID, mx, my, lastCastTargetName or "Kürschner-Spot", 250)
		end
		return true
	elseif kind == "herb" or kind == "ore" then
		MarkNearestGatherCooldown(kind, lastCastTargetName)
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Minimap Tracking Live-Sync & Dienste-Hervorhebung
-- ---------------------------------------------------------------------------

local function MatchTrackingService(infoName)
	local lower = infoName and string.lower(infoName) or ""
	for _, def in ipairs(ns.SERVICE_TRACKING) do
		local globalName = def.globalKey and rawget(_G, def.globalKey)
		if type(globalName) == "string" and globalName ~= "" and infoName == globalName then
			return def
		end
	end
	if lower ~= "" then
		for _, def in ipairs(ns.SERVICE_TRACKING) do
			if def.keywords then
				for _, kw in ipairs(def.keywords) do
					if lower:find(kw, 1, true) then
						return def
					end
				end
			end
		end
	end
	return nil
end

function Sources.RefreshTracking()
	trackingEntries = {}
	trackingByKey = {}
	activeTrackingCount = 0
	trackingChecked = true

	local count = 0
	if C_Minimap and C_Minimap.GetNumTrackingTypes then
		local okC, n = pcall(C_Minimap.GetNumTrackingTypes)
		count = okC and Core.SafeNumber(n) or 0
	elseif type(GetNumTrackingTypes) == "function" then
		local okC, n = pcall(GetNumTrackingTypes)
		count = okC and Core.SafeNumber(n) or 0
	end

	for idx = 1, math.min(count, 80) do
		local name, texture, active, category
		if C_Minimap and C_Minimap.GetTrackingInfo then
			local okT, info = pcall(C_Minimap.GetTrackingInfo, idx)
			if okT and type(info) == "table" then
				name = Core.SafeNonEmptyString(info.name)
				texture = info.texture
				active = Core.CanInspectValue(info.active) and type(info.active) == "boolean" and info.active == true
				category = Core.SafeNonEmptyString(info.type)
			elseif okT and Core.CanInspectValue(info) and type(info) == "string" then
				local _, rName, rTex, rActive, rCat = pcall(C_Minimap.GetTrackingInfo, idx)
				name = Core.SafeNonEmptyString(rName)
				texture = rTex
				active = Core.CanInspectValue(rActive) and type(rActive) == "boolean" and rActive == true
				category = Core.SafeNonEmptyString(rCat)
			end
		elseif type(GetTrackingInfo) == "function" then
			local okT, rName, rTex, rActive, rCat = pcall(GetTrackingInfo, idx)
			if okT then
				name = Core.SafeNonEmptyString(rName)
				texture = rTex
				active = Core.CanInspectValue(rActive) and type(rActive) == "boolean" and rActive == true
				category = Core.SafeNonEmptyString(rCat)
			end
		end

		if name then
			local matchedDef = MatchTrackingService(name)
			local entry = {
				index = idx,
				key = matchedDef and matchedDef.key or ("RAW_" .. idx),
				def = matchedDef,
				name = name,
				texture = texture or (matchedDef and matchedDef.icon) or ns.TEX_DOT,
				active = active == true,
				category = category,
			}
			trackingEntries[#trackingEntries + 1] = entry
			if matchedDef and not trackingByKey[matchedDef.key] then
				trackingByKey[matchedDef.key] = entry
			end
			if active then
				activeTrackingCount = activeTrackingCount + 1
			end
		end
	end
end

function Sources.IsServiceTrackingActive(serviceKey)
	if not trackingChecked then
		Sources.RefreshTracking()
	end
	local entry = trackingByKey[serviceKey]
	return entry and entry.active == true or false
end

function Sources.GetActiveTrackingCount()
	if not trackingChecked then
		Sources.RefreshTracking()
	end
	return activeTrackingCount
end

function Sources.SetTrackingActive(indexOrKey, desiredState)
	if InCombatLockdown and InCombatLockdown() then
		Core.Print("Minimap-Tracking kann im Kampf nicht umgeschaltet werden.", true)
		return false
	end
	if Core.IsActionRestricted() then
		Core.Print("Minimap-Tracking ist momentan eingeschränkt.", true)
		return false
	end
	local entry = type(indexOrKey) == "number" and trackingEntries[indexOrKey] or trackingByKey[indexOrKey]
	local idx = type(indexOrKey) == "number" and indexOrKey or (entry and entry.index)
	if not idx then
		return false
	end
	local state = desiredState and true or false
	local ok = false
	if C_Minimap and C_Minimap.SetTracking then
		ok = pcall(C_Minimap.SetTracking, idx, state)
	elseif type(SetTracking) == "function" then
		ok = pcall(SetTracking, idx, state)
	end
	if ok then
		Sources.RefreshTracking()
	end
	return ok
end

local function IsFriendlyToPlayer(friendlyStr, playerFactionKey)
	if friendlyStr == nil or friendlyStr == "" then
		return false
	end
	if friendlyStr == "AH" or friendlyStr == "HA" then
		return true
	end
	return friendlyStr == playerFactionKey
end

local function EnsureMailboxCacheForZone(uiMapID)
	local now = GetTime()
	local existing = mailboxCache[uiMapID]
	if type(existing) == "table" and not existing.retryAt then
		return existing
	end
	if IsCacheRetryPending(existing, now) then
		return nil
	end

	local areaID = Sources.GetAreaIdByUiMapId(uiMapID)
	local qdb = rawget(_G, "LibQuestieDB")
	local objDB = (type(qdb) == "table" and qdb.Object) or rawget(_G, "ObjectDB")
	local bounds = Sources.GetMapBounds(uiMapID)
	if not (areaID and objDB and type(objDB.Get) == "function" and bounds) then
		mailboxCache[uiMapID] = { retryAt = now + 2.0 }
		return nil
	end

	local list = {}
	local mailDef = ns.SERVICE_BY_KEY["MAILBOX"]
	local mailEntry = trackingByKey["MAILBOX"]
	local icon = (mailEntry and mailEntry.texture) or mailDef.icon
	local color = mailDef.color
	for _, oid in ipairs(ns.MAILBOX_OBJECT_IDS) do
		local spawns = objDB.Get(oid, "spawns")
		local zoneSpawns = type(spawns) == "table" and spawns[areaID] or nil
		if type(zoneSpawns) == "table" then
			for _, coord in ipairs(zoneSpawns) do
				if type(coord) == "table" and type(coord[1]) == "number" and type(coord[2]) == "number" then
					list[#list + 1] = {
						wx = bounds.left - bounds.width * (coord[1] / 100),
						wy = bounds.top - bounds.height * (coord[2] / 100),
						instance = bounds.instance,
						category = "service",
						serviceKey = "MAILBOX",
						name = mailDef.label,
						icon = icon,
						color = color,
					}
				end
			end
		end
	end
	mailboxCache[uiMapID] = list
	return list
end

local function GetQuestieTownsfolkIds(townsfolkKey)
	if not (QuestieLoader and type(QuestieLoader.ImportModule) == "function") then
		return nil
	end
	local ok, tf = pcall(QuestieLoader.ImportModule, QuestieLoader, "Townsfolk")
	if not (ok and type(tf) == "table") then
		return nil
	end
	if type(tf.townsfolk) == "table" and type(tf.townsfolk[townsfolkKey]) == "table" then
		return tf.townsfolk[townsfolkKey]
	end
	if type(tf.factionSpecificTownsfolk) == "table" then
		local fac = UnitFactionGroup and Core.SafeNonEmptyString(UnitFactionGroup("player")) or nil
		if fac and type(tf.factionSpecificTownsfolk[fac]) == "table" and type(tf.factionSpecificTownsfolk[fac][townsfolkKey]) == "table" then
			return tf.factionSpecificTownsfolk[fac][townsfolkKey]
		end
	end
	if type(tf.classSpecificTownsfolk) == "table" and UnitClassBase then
		local _, cls = pcall(UnitClassBase, "player")
		cls = Core.SafeNonEmptyString(cls)
		if cls and type(tf.classSpecificTownsfolk[cls]) == "table" and type(tf.classSpecificTownsfolk[cls][townsfolkKey]) == "table" then
			return tf.classSpecificTownsfolk[cls][townsfolkKey]
		end
	end
	return nil
end

local function StartOrStepNpcFallbackScan()
	if npcScanState and npcScanState.done then
		return
	end
	local qdb = rawget(_G, "LibQuestieDB")
	local npcDB = (type(qdb) == "table" and qdb.Npc) or rawget(_G, "NpcDB")
	local flagsEnum = type(qdb) == "table" and type(qdb.Enum) == "table" and qdb.Enum.npcFlags or nil
	if not (npcDB and flagsEnum and type(npcDB.GetAllIds) == "function" and type(npcDB.Get) == "function") then
		return
	end

	if not npcScanState then
		local ids = npcDB.GetAllIds()
		if type(ids) ~= "table" then
			return
		end
		local uniqueFlags = {}
		for _, def in ipairs(ns.SERVICE_TRACKING) do
			if def.npcFlagKey and flagsEnum[def.npcFlagKey] then
				uniqueFlags[def.npcFlagKey] = flagsEnum[def.npcFlagKey]
			end
		end
		if not next(uniqueFlags) then
			return
		end

		npcScanState = {
			ids = ids,
			cursor = 1,
			uniqueFlags = uniqueFlags,
			byFlag = {},
			done = false,
		}
		local frame = CreateFrame("Frame")
		frame:SetScript("OnUpdate", function(self)
			local st = npcScanState
			if not st or st.done then
				self:Hide()
				return
			end
			local total = #st.ids
			local limit = math.min(st.cursor + 119, total)
			for i = st.cursor, limit do
				local id = st.ids[i]
				local flags = Core.SafeNumber(npcDB.Get(id, "npcFlags"))
				if flags and flags > 0 and bit and bit.band then
					for flagKey, mask in pairs(st.uniqueFlags) do
						if bit.band(flags, mask) == mask then
							st.byFlag[flagKey] = st.byFlag[flagKey] or {}
							local arr = st.byFlag[flagKey]
							arr[#arr + 1] = id
						end
					end
				end
			end
			st.cursor = limit + 1
			if st.cursor > total then
				st.done = true
				serviceCache = {}
				self:Hide()
			end
		end)
		npcScanState.frame = frame
	elseif npcScanState.frame and not npcScanState.frame:IsShown() then
		npcScanState.frame:Show()
	end
end

local function EnsureServiceCacheForZone(uiMapID, def)
	local now = GetTime()
	serviceCache[uiMapID] = serviceCache[uiMapID] or {}
	local zoneBucket = serviceCache[uiMapID]
	local existing = zoneBucket[def.key]
	if type(existing) == "table" and not existing.retryAt then
		return existing
	end
	if IsCacheRetryPending(existing, now) then
		return nil
	end

	local areaID = Sources.GetAreaIdByUiMapId(uiMapID)
	local qdb = rawget(_G, "LibQuestieDB")
	local npcDB = (type(qdb) == "table" and qdb.Npc) or rawget(_G, "NpcDB")
	local bounds = Sources.GetMapBounds(uiMapID)
	if not (areaID and npcDB and type(npcDB.Get) == "function" and bounds) then
		zoneBucket[def.key] = { retryAt = now + 2.0 }
		return nil
	end

	local npcIds = def.townsfolkKey and GetQuestieTownsfolkIds(def.townsfolkKey) or nil
	if not npcIds and def.npcFlagKey then
		if npcScanState and npcScanState.done then
			npcIds = npcScanState.byFlag[def.npcFlagKey]
		else
			StartOrStepNpcFallbackScan()
			return nil
		end
	end
	if type(npcIds) ~= "table" then
		zoneBucket[def.key] = { retryAt = now + 2.0 }
		return nil
	end

	local factionGroup = UnitFactionGroup and Core.SafeNonEmptyString(UnitFactionGroup("player")) or "Alliance"
	local facKey = (factionGroup == "Horde") and "H" or "A"
	local trackEntry = trackingByKey[def.key]
	local icon = (trackEntry and trackEntry.texture) or def.icon
	local color = def.color

	local list = {}
	local seen = {}
	for _, npcId in ipairs(npcIds) do
		local spawns = npcDB.Get(npcId, "spawns")
		local zoneSpawns = type(spawns) == "table" and spawns[areaID] or nil
		if type(zoneSpawns) == "table" then
			local friendly = Core.SafeNonEmptyString(npcDB.Get(npcId, "friendlyToFaction"))
			if IsFriendlyToPlayer(friendly, facKey) then
				local npcName = Core.SafeNonEmptyString(npcDB.Get(npcId, "name")) or def.label
				for _, coord in ipairs(zoneSpawns) do
					if type(coord) == "table" and type(coord[1]) == "number" and type(coord[2]) == "number" then
						local wx = bounds.left - bounds.width * (coord[1] / 100)
						local wy = bounds.top - bounds.height * (coord[2] / 100)
						local key = MakeCoordKey(def.key, wx, wy)
						if not seen[key] then
							seen[key] = true
							list[#list + 1] = {
								wx = wx,
								wy = wy,
								instance = bounds.instance,
								category = "service",
								serviceKey = def.key,
								name = npcName,
								icon = icon,
								color = color,
							}
						end
					end
				end
			end
		end
	end

	zoneBucket[def.key] = list
	return list
end

-- ---------------------------------------------------------------------------
-- Gesamtausgabe aller sichtbaren Overlay-Pins im aktuellen Radar-Radius
-- ---------------------------------------------------------------------------

local function HasNearbyEmittedNode(emittedNodes, wx, wy)
	if not emittedNodes then
		return false
	end
	for _, n in ipairs(emittedNodes) do
		local dx, dy = n.wx - wx, n.wy - wy
		if (dx * dx + dy * dy) <= 100 then -- 10 Yards Dedup gegen QuestieDB-Spawns
			return true
		end
	end
	return false
end

local function FindActiveCooldown(wx, wy, inst, kind, now)
	for key, cd in pairs(nodeCooldowns) do
		if type(cd) ~= "table" or cd.expiresAt <= now then
			nodeCooldowns[key] = nil
		elseif cd.kind == kind and cd.instance == inst then
			local dx, dy = cd.wx - wx, cd.wy - wy
			if (dx * dx + dy * dy) <= 225 then -- 15 Yards Toleranz ueberdeckt 4-Dezimal-Rundung & Spot-Offset
				return true
			end
		end
	end
	return false
end

local function AddLearnedEntries(storageTable, uiMapID, px, py, inst, rangeSq, category, icon, color, priority, targetList, emittedNodes, now)
	local zoneList = type(storageTable) == "table" and storageTable[uiMapID] or nil
	if type(zoneList) ~= "table" then
		return
	end
	for _, spot in ipairs(zoneList) do
		if type(spot) == "table" and Core.IsFiniteNumber(spot.x) and Core.IsFiniteNumber(spot.y) then
			local wx, wy, sInst = Sources.ZoneToWorld(uiMapID, spot.x, spot.y)
			if wx and wy and sInst == inst and not HasNearbyEmittedNode(emittedNodes, wx, wy) then
				local dx, dy = wx - px, wy - py
				local dSq = dx * dx + dy * dy
				if dSq <= rangeSq then
					local onCd = (category == "herb" or category == "ore") and FindActiveCooldown(wx, wy, inst, category, now) or false
					targetList[#targetList + 1] = {
						wx = wx,
						wy = wy,
						instance = inst,
						category = category,
						icon = icon,
						color = color,
						name = spot.name,
						distSq = dSq,
						priority = priority,
						alphaFactor = onCd and 0.25 or 0.72,
					}
				end
			end
		end
	end
end

function Sources.CollectVisiblePins(uiMapID, px, py, playerInstance, maxRangeYards, outList)
	for i = #outList, 1, -1 do
		outList[i] = nil
	end
	if not (px and py and playerInstance) then
		return
	end

	local opts = Core.GetOptions()
	local now = GetTime()
	local rangeSq = maxRangeYards * maxRangeYards
	local temp = reusableSortTemp
	for i = #temp, 1, -1 do
		temp[i] = nil
	end

	-- 1. Kuerschner-Leichen (hoechste Prioritaet, nur wenn Beruf vorhanden)
	if Sources.HasSkinning() and opts.showSkinningCorpses then
		PruneExpiredCorpses(now)
		for _, corpse in ipairs(skinningCorpses) do
			if corpse.instance == playerInstance then
				local dx, dy = corpse.wx - px, corpse.wy - py
				local dSq = dx * dx + dy * dy
				if dSq <= rangeSq then
					temp[#temp + 1] = {
						wx = corpse.wx,
						wy = corpse.wy,
						instance = playerInstance,
						category = "skin_corpse",
						icon = corpse.icon,
						color = corpse.color,
						name = corpse.name,
						distSq = dSq,
						priority = 1,
						alphaFactor = 1.0,
						countdown = math.max(1, math.ceil(corpse.expiresAt - now)),
					}
				end
			end
		end
	end

	-- 2. Quest-Items & Quest-Ziele
	if opts.showQuestItems or opts.showQuestObjectives then
		if questCacheDirty or questCacheMapId ~= uiMapID or (now - questCacheTime) >= 0.8 then
			RebuildQuestCache(uiMapID, playerInstance)
		end
		for _, qp in ipairs(questCache) do
			if qp.instance == playerInstance then
				local enabled = (qp.category == "quest_item" and opts.showQuestItems)
					or (qp.category == "quest_obj" and opts.showQuestObjectives)
				if enabled then
					local dx, dy = qp.wx - px, qp.wy - py
					local dSq = dx * dx + dy * dy
					if dSq <= rangeSq then
						temp[#temp + 1] = {
							wx = qp.wx,
							wy = qp.wy,
							instance = playerInstance,
							category = qp.category,
							icon = qp.icon,
							color = qp.color,
							name = qp.name,
							distSq = dSq,
							priority = (qp.category == "quest_item") and 2 or 3,
							alphaFactor = 1.0,
						}
					end
				end
			end
		end
	end

	-- 3. Aktivierte Minimap-Dienste (Rep, Mail, Bank, AH, Flug, Lehrer ...)
	if opts.highlightActiveServices and uiMapID then
		if Sources.IsServiceTrackingActive("MAILBOX") then
			local mailList = EnsureMailboxCacheForZone(uiMapID)
			if type(mailList) == "table" then
				for _, m in ipairs(mailList) do
					if m.instance == playerInstance then
						local dx, dy = m.wx - px, m.wy - py
						local dSq = dx * dx + dy * dy
						if dSq <= rangeSq then
							temp[#temp + 1] = {
								wx = m.wx,
								wy = m.wy,
								instance = playerInstance,
								category = "service",
								icon = m.icon,
								color = m.color,
								name = m.name,
								distSq = dSq,
								priority = 4,
								alphaFactor = 0.95,
							}
						end
					end
				end
			end
		end

		for _, def in ipairs(ns.SERVICE_TRACKING) do
			if not def.isMailbox and Sources.IsServiceTrackingActive(def.key) then
				local svcList = EnsureServiceCacheForZone(uiMapID, def)
				if type(svcList) == "table" then
					for _, sp in ipairs(svcList) do
						if sp.instance == playerInstance then
							local dx, dy = sp.wx - px, sp.wy - py
							local dSq = dx * dx + dy * dy
							if dSq <= rangeSq then
								temp[#temp + 1] = {
									wx = sp.wx,
									wy = sp.wy,
									instance = playerInstance,
									category = "service",
									icon = sp.icon,
									color = sp.color,
									name = sp.name,
									distSq = dSq,
									priority = 4,
									alphaFactor = 0.92,
								}
							end
						end
					end
				end
			end
		end
	end

	-- 4. Optionale bekannte Kraeuter-/Erz-Spawns (QuestieDB + Auto-Lernen + Cooldown)
	if (opts.showHerbSpawns or opts.showOreSpawns) and uiMapID then
		local emittedHerbs = {}
		local emittedOres = {}
		local gatherList = EnsureGatherZoneCache(uiMapID)
		if type(gatherList) == "table" then
			for _, node in ipairs(gatherList) do
				local want = (node.kind == "herb" and opts.showHerbSpawns)
					or (node.kind == "ore" and opts.showOreSpawns)
				if want and node.instance == playerInstance then
					local dx, dy = node.wx - px, node.wy - py
					local dSq = dx * dx + dy * dy
					if dSq <= rangeSq then
						local onCd = FindActiveCooldown(node.wx, node.wy, playerInstance, node.kind, now)
						local entry = {
							wx = node.wx,
							wy = node.wy,
							instance = playerInstance,
							category = node.category,
							icon = node.icon,
							color = node.color,
							name = node.name,
							distSq = dSq,
							priority = 5,
							alphaFactor = onCd and 0.25 or 0.80,
						}
						temp[#temp + 1] = entry
						if node.kind == "herb" then
							emittedHerbs[#emittedHerbs + 1] = entry
						else
							emittedOres[#emittedOres + 1] = entry
						end
					end
				end
			end
		end

		if Core.db and type(Core.db.learnedNodes) == "table" then
			if opts.showHerbSpawns then
				AddLearnedEntries(Core.db.learnedNodes.herb, uiMapID, px, py, playerInstance, rangeSq,
					"herb", ns.ICON_HERB, ns.PIN_COLORS.herb, 5, temp, emittedHerbs, now)
			end
			if opts.showOreSpawns then
				AddLearnedEntries(Core.db.learnedNodes.ore, uiMapID, px, py, playerInstance, rangeSq,
					"ore", ns.ICON_ORE, ns.PIN_COLORS.ore, 5, temp, emittedOres, now)
			end
		end
	end

	-- 5. Gelernte Kuerschner-Spots
	if Sources.HasSkinning() and opts.showLearnedSkinning and uiMapID and Core.db then
		AddLearnedEntries(Core.db.learnedSkinning, uiMapID, px, py, playerInstance, rangeSq,
			"skin_spot", ns.ICON_SKINNING, ns.PIN_COLORS.skin_spot, 6, temp, nil, now)
	end

	table.sort(temp, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.distSq < b.distSq
	end)

	local maxCount = math.min(#temp, ns.MAX_PINS)
	for i = 1, maxCount do
		outList[i] = temp[i]
	end
end
