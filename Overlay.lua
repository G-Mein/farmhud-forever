local _, ns = ...

local Core = ns.Core
local Sources = ns.Sources

local Overlay = {}
ns.Overlay = Overlay

local COLLECT_INTERVAL = 0.18
local PROJECT_INTERVAL = 0.033

local overlayFrame = nil
local rings = {}
local compassLabels = {}
local crossH = nil
local crossV = nil
local pinFrames = {}
local pinBuffer = {}

local active = false
local collectElapsed = 0
local projectElapsed = 0
local cachedViewRadius = 150

local CARDINALS = {
	{ text = "N", dx = 0, dy = -1, color = { 1.00, 0.84, 0.18, 0.96 } },
	{ text = "O", dx = 1, dy = 0, color = { 0.86, 0.94, 0.88, 0.88 } },
	{ text = "S", dx = 0, dy = 1, color = { 0.86, 0.94, 0.88, 0.88 } },
	{ text = "W", dx = -1, dy = 0, color = { 0.86, 0.94, 0.88, 0.88 } },
}

local function AcquirePinFrame(idx)
	local pf = pinFrames[idx]
	if pf then
		return pf
	end

	pf = CreateFrame("Frame", nil, overlayFrame)
	pf:SetSize(18, 18)
	pf:EnableMouse(false)

	local halo = pf:CreateTexture(nil, "BACKGROUND")
	halo:SetTexture(ns.TEX_DOT)
	halo:SetAllPoints(pf)
	pf.halo = halo

	local icon = pf:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER", pf, "CENTER", 0, 0)
	icon:SetSize(13, 13)
	pf.icon = icon

	local timerText = pf:CreateFontString(nil, "OVERLAY")
	timerText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	timerText:SetPoint("TOP", pf, "BOTTOM", 0, -1)
	timerText:SetTextColor(1.0, 0.65, 0.25, 0.95)
	timerText:Hide()
	pf.timerText = timerText

	pf:Hide()
	pinFrames[idx] = pf
	return pf
end

local function HideAllPins()
	for i = 1, #pinFrames do
		pinFrames[i]:Hide()
	end
end

local function UpdateFrame(collectNow)
	if not (active and overlayFrame and overlayFrame:IsShown()) then
		return
	end

	local opts = Core.GetOptions()
	local hudSize = Core.Clamp(opts.hudSize, ns.OPTION_BOUNDS.hudSize[1], ns.OPTION_BOUNDS.hudSize[2])
	local hudRadius = hudSize / 2
	local viewRadius = Sources.GetCurrentViewRadius() or cachedViewRadius
	cachedViewRadius = viewRadius

	local rotate = false
	if type(GetCVarBool) == "function" then
		local okR, val = pcall(GetCVarBool, "rotateMinimap")
		rotate = okR and Core.CanInspectValue(val) and val == true
	elseif type(GetCVar) == "function" then
		rotate = GetCVar("rotateMinimap") == "1"
	end

	local sinF, cosF = 0, 1
	if rotate and type(GetPlayerFacing) == "function" then
		local okF, facing = pcall(GetPlayerFacing)
		facing = okF and Core.SafeNumber(facing) or nil
		if facing then
			sinF = math.sin(facing)
			cosF = math.cos(facing)
		end
	end

	-- Kompassbuchstaben immer aktuell halten (auch in Instanzen bei hideInInstance == false)
	if opts.showCompass then
		local compassRadius = hudRadius + 11
		for i = 1, #CARDINALS do
			local c = CARDINALS[i]
			local fs = compassLabels[i]
			if fs then
				local rx = c.dx * cosF - c.dy * sinF
				local ry = c.dx * sinF + c.dy * cosF
				fs:ClearAllPoints()
				fs:SetPoint("CENTER", overlayFrame, "CENTER", rx * compassRadius, -ry * compassRadius)
				fs:Show()
			end
		end
	end

	if IsInInstance and select(1, IsInInstance()) then
		HideAllPins()
		return
	end

	local px, py, playerInst = Sources.GetPlayerWorldPos()
	if not (px and py and playerInst) then
		HideAllPins()
		return
	end

	if collectNow then
		local uiMapID = Sources.GetPlayerZonePos()
		Sources.CollectVisiblePins(uiMapID, px, py, playerInst, viewRadius * 1.15, pinBuffer)
	end

	local pinScale = Core.Clamp(opts.pinScale, ns.OPTION_BOUNDS.pinScale[1], ns.OPTION_BOUNDS.pinScale[2])
	local baseAlpha = Core.Clamp(opts.pinAlpha, ns.OPTION_BOUNDS.pinAlpha[1], ns.OPTION_BOUNDS.pinAlpha[2]) / 100
	local usedCount = 0

	for i = 1, math.min(#pinBuffer, ns.MAX_PINS) do
		local pin = pinBuffer[i]
		local xDist = px - pin.wx
		local yDist = py - pin.wy
		if rotate then
			local dx, dy = xDist, yDist
			xDist = dx * cosF - dy * sinF
			yDist = dx * sinF + dy * cosF
		end

		local diffX = xDist / viewRadius
		local diffY = yDist / viewRadius
		local normSq = diffX * diffX + diffY * diffY
		if normSq <= 0.90 then
			usedCount = usedCount + 1
			local pf = AcquirePinFrame(usedCount)
			local isCorpse = (pin.category == "skin_corpse")
			local isQuestItem = (pin.category == "quest_item")
			local frameSize = (isCorpse and 22 or (isQuestItem and 20 or 16)) * pinScale
			local iconSize = frameSize * 0.72

			pf:SetSize(frameSize, frameSize)
			pf.icon:SetSize(iconSize, iconSize)
			local tex = pin.icon or ns.TEX_DOT
			pf.icon:SetTexture(tex)
			if tex == ns.TEX_DOT then
				pf.icon:SetTexCoord(0, 1, 0, 1)
			else
				pf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end

			local col = pin.color or ns.PIN_COLORS.service
			pf.halo:SetVertexColor(col[1], col[2], col[3], 0.9)
			pf:SetAlpha(Core.Clamp(baseAlpha * (pin.alphaFactor or 1), 0.1, 1.0))

			if isCorpse and pin.countdown then
				pf.timerText:SetText(tostring(math.max(1, pin.countdown)) .. "s")
				pf.timerText:Show()
			else
				pf.timerText:Hide()
			end

			pf:ClearAllPoints()
			pf:SetPoint("CENTER", overlayFrame, "CENTER", diffX * hudRadius, -diffY * hudRadius)
			pf:Show()
		end
	end

	for i = usedCount + 1, #pinFrames do
		pinFrames[i]:Hide()
	end
end

function Overlay.Init(host)
	if overlayFrame or not host then
		return
	end

	local frame = CreateFrame("Frame", "FarmRadar3DOverlay", host)
	frame:SetAllPoints(host)
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(host:GetFrameLevel() + 8)
	if frame.SetIgnoreParentAlpha then
		frame:SetIgnoreParentAlpha(true)
	end
	frame:EnableMouse(false)

	for i = 1, 3 do
		local ring = frame:CreateTexture(nil, "BORDER")
		ring:SetPoint("CENTER", frame, "CENTER", 0, 0)
		ring:SetTexture(ns.TEX_RING)
		rings[i] = ring
	end

	for i = 1, #CARDINALS do
		local c = CARDINALS[i]
		local fs = frame:CreateFontString(nil, "OVERLAY")
		fs:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
		fs:SetTextColor(c.color[1], c.color[2], c.color[3], c.color[4])
		fs:SetText(c.text)
		compassLabels[i] = fs
	end

	local ch = frame:CreateTexture(nil, "ARTWORK")
	ch:SetPoint("CENTER", frame, "CENTER", 0, 0)
	ch:SetSize(14, 1)
	ch:SetColorTexture(0.78, 0.96, 0.86, 0.55)
	crossH = ch

	local cv = frame:CreateTexture(nil, "ARTWORK")
	cv:SetPoint("CENTER", frame, "CENTER", 0, 0)
	cv:SetSize(1, 14)
	cv:SetColorTexture(0.78, 0.96, 0.86, 0.55)
	crossV = cv

	frame:SetScript("OnUpdate", function(_, elapsed)
		if not active then
			return
		end
		collectElapsed = collectElapsed + elapsed
		projectElapsed = projectElapsed + elapsed
		local doCollect = collectElapsed >= COLLECT_INTERVAL
		if doCollect then
			collectElapsed = 0
		end
		if doCollect or projectElapsed >= PROJECT_INTERVAL then
			projectElapsed = 0
			UpdateFrame(doCollect)
		end
	end)

	overlayFrame = frame
	Overlay.ApplyStyle()
end

function Overlay.ApplyStyle()
	if not overlayFrame then
		return
	end
	local opts = Core.GetOptions()
	local hudSize = Core.Clamp(opts.hudSize, ns.OPTION_BOUNDS.hudSize[1], ns.OPTION_BOUNDS.hudSize[2])
	local count = math.floor(Core.Clamp(opts.ringCount, 1, 3))

	for i = 1, 3 do
		local r = rings[i]
		if opts.showRings and i <= count then
			local frac = i / count
			local sz = hudSize * frac
			r:SetSize(sz, sz)
			if i == count then
				r:SetVertexColor(0.30, 0.85, 0.58, 0.48)
			else
				r:SetVertexColor(0.65, 0.90, 0.78, 0.24)
			end
			r:Show()
		else
			r:Hide()
		end
	end

	for i = 1, #compassLabels do
		compassLabels[i]:SetShown(opts.showCompass == true)
	end

	if crossH then
		crossH:SetShown(opts.showCrosshair == true)
	end
	if crossV then
		crossV:SetShown(opts.showCrosshair == true)
	end

	if active then
		collectElapsed = COLLECT_INTERVAL
		UpdateFrame(true)
	end
end

function Overlay.SetActive(state)
	active = state and true or false
	collectElapsed = COLLECT_INTERVAL
	projectElapsed = PROJECT_INTERVAL
	if active then
		Overlay.ApplyStyle()
	else
		HideAllPins()
	end
end

function Overlay.ForceRefresh()
	if active then
		collectElapsed = COLLECT_INTERVAL
		UpdateFrame(true)
	end
end
