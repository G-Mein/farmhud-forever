local _, ns = ...

local Core = ns.Core

local Hud = {}
ns.Hud = Hud

local MASK_SQUARE = "Interface\\BUTTONS\\WHITE8X8"
local MASK_ROUND_DEFAULT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local hostFrame = nil
local backdropDisc = nil
local dragBorder = nil
local controlBar = nil
local controlButtons = {}

local snapshot = nil
local pendingHudState = nil
local pendingRotateRestore = nil
local suspendedByInstance = false

local function IsWidgetProtectedInCombat(widget)
	if not (widget and InCombatLockdown and InCombatLockdown()) then
		return false
	end
	if widget.IsProtected and widget:IsProtected() then
		return true
	end
	return false
end

local function ReadBoolMethod(obj, methodName, defaultVal)
	local fn = obj and obj[methodName]
	if type(fn) == "function" then
		local ok, val = pcall(fn, obj)
		if ok and type(val) == "boolean" then
			return val
		end
	end
	return defaultVal
end

local function CollectChromeTargets()
	local targets = {}
	local added = {}

	local function AddTarget(obj)
		if type(obj) == "table" and not added[obj] then
			added[obj] = true
			targets[#targets + 1] = obj
		end
	end

	local namedChrome = {
		"MinimapBackdrop",
		"MinimapCompassTexture",
		"MinimapBorder",
		"MinimapBorderTop",
		"MinimapZoomIn",
		"MinimapZoomOut",
		"MinimapZoneTextButton",
		"MiniMapTracking",
		"MiniMapTrackingButton",
		"MiniMapMailFrame",
		"MiniMapBattlefieldFrame",
		"MiniMapWorldMapButton",
		"GameTimeFrame",
		"TimeManagerClockButton",
		"EQOLBORDER",
		"EQOLMINIMAPBACKGROUND",
		"EQOLMINIMAPBACKGROUNDBORDER",
	}
	for _, globalName in ipairs(namedChrome) do
		local obj = rawget(_G, globalName)
		if obj then
			AddTarget(obj)
		end
	end

	if Minimap and Minimap.GetChildren then
		local ok, children = pcall(function()
			return { Minimap:GetChildren() }
		end)
		if ok and type(children) == "table" then
			for _, child in ipairs(children) do
				if type(child) == "table" and child ~= hostFrame then
					local objType = child.GetObjectType and child:GetObjectType() or ""
					local name = child.GetName and child:GetName() or ""
					local isChromeName = type(name) == "string" and (
						name:find("Button", 1, true)
						or name:find("Border", 1, true)
						or name:find("Backdrop", 1, true)
						or name:find("Compass", 1, true)
						or name:find("SexyMap", 1, true)
						or name:find("LibDBIcon", 1, true)
						or name:find("Clock", 1, true)
					)
					if objType == "Button" or isChromeName then
						AddTarget(child)
					end
				end
			end
		end
	end

	return targets
end

local function CaptureSnapshot()
	if snapshot or not Minimap then
		return
	end

	local points = {}
	local numPoints = Minimap.GetNumPoints and Minimap:GetNumPoints() or 0
	for i = 1, numPoints do
		local point, relTo, relPoint, xOfs, yOfs = Minimap:GetPoint(i)
		if point then
			points[#points + 1] = { point, relTo, relPoint, xOfs or 0, yOfs or 0 }
		end
	end

	local hiddenList = {}
	for _, target in ipairs(CollectChromeTargets()) do
		if target.IsShown and target.Hide then
			hiddenList[#hiddenList + 1] = {
				widget = target,
				wasShown = target:IsShown() == true,
			}
		end
	end

	local rotateVal = pendingRotateRestore
	pendingRotateRestore = nil
	if rotateVal == nil and type(GetCVar) == "function" then
		rotateVal = GetCVar("rotateMinimap")
	end

	snapshot = {
		parent = Minimap:GetParent() or UIParent,
		points = points,
		width = (Minimap.GetWidth and Minimap:GetWidth()) or 140,
		height = (Minimap.GetHeight and Minimap:GetHeight()) or 140,
		scale = (Minimap.GetScale and Minimap:GetScale()) or 1,
		alpha = (Minimap.GetAlpha and Minimap:GetAlpha()) or 1,
		strata = (Minimap.GetFrameStrata and Minimap:GetFrameStrata()) or "BACKGROUND",
		level = (Minimap.GetFrameLevel and Minimap:GetFrameLevel()) or 1,
		mouseEnabled = ReadBoolMethod(Minimap, "IsMouseEnabled", true),
		mouseClickEnabled = ReadBoolMethod(Minimap, "IsMouseClickEnabled", true),
		mouseMotionEnabled = ReadBoolMethod(Minimap, "IsMouseMotionEnabled", true),
		wasSquare = (type(GetMinimapShape) == "function" and GetMinimapShape() == "SQUARE") or false,
		rotateMinimap = rotateVal,
		hiddenList = hiddenList,
	}
end

local function RestoreFromSnapshot()
	if not (snapshot and Minimap) then
		return true
	end
	if IsWidgetProtectedInCombat(Minimap) then
		return false
	end

	local snap = snapshot
	Minimap:SetParent(snap.parent or UIParent)
	Minimap:ClearAllPoints()
	if #snap.points > 0 then
		for _, p in ipairs(snap.points) do
			Minimap:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
	else
		Minimap:SetPoint("TOPRIGHT", MinimapCluster or UIParent, "TOPRIGHT", -10, -25)
	end

	if snap.scale and Minimap.SetScale then
		Minimap:SetScale(snap.scale)
	end
	if snap.width and snap.height and Minimap.SetSize then
		Minimap:SetSize(snap.width, snap.height)
	end
	if Minimap.SetAlpha then
		Minimap:SetAlpha(snap.alpha or 1)
	end
	if Minimap.SetFrameStrata and snap.strata then
		Minimap:SetFrameStrata(snap.strata)
	end
	if Minimap.SetFrameLevel and snap.level then
		Minimap:SetFrameLevel(snap.level)
	end
	if Minimap.EnableMouse then
		Minimap:EnableMouse(snap.mouseEnabled)
	end
	if Minimap.SetMouseClickEnabled then
		Minimap:SetMouseClickEnabled(snap.mouseClickEnabled)
	end
	if Minimap.SetMouseMotionEnabled then
		Minimap:SetMouseMotionEnabled(snap.mouseMotionEnabled)
	end
	if Minimap.SetMaskTexture then
		Minimap:SetMaskTexture(snap.wasSquare and MASK_SQUARE or MASK_ROUND_DEFAULT)
	end

	for _, item in ipairs(snap.hiddenList) do
		local w = item.widget
		if w and w.SetShown and not IsWidgetProtectedInCombat(w) then
			pcall(w.SetShown, w, item.wasShown)
		end
	end

	if snap.rotateMinimap ~= nil and type(SetCVar) == "function" then
		if InCombatLockdown and InCombatLockdown() then
			pendingRotateRestore = snap.rotateMinimap
		elseif GetCVar("rotateMinimap") ~= snap.rotateMinimap then
			pcall(SetCVar, "rotateMinimap", snap.rotateMinimap)
			pendingRotateRestore = nil
		else
			pendingRotateRestore = nil
		end
	end

	snapshot = nil
	return true
end

local function UpdateControlBarVisuals()
	local opts = Core.GetOptions()
	if controlBar then
		controlBar:SetShown(Core.hudShown and opts.showControlBar)
	end
	if controlButtons.drag then
		controlButtons.drag:SetText(opts.dragUnlocked and "|cffffd200Sperren|r" or "Schieben")
	end
	if controlButtons.bg then
		controlButtons.bg:SetText(opts.bgFade >= 95 and "BG: Aus" or ("BG: " .. tostring(100 - opts.bgFade) .. "%"))
	end
end

local function EnsureHostFrame()
	if hostFrame then
		return hostFrame
	end

	local host = CreateFrame("Frame", "FarmRadar3DHost", UIParent)
	host:SetSize(420, 420)
	host:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	host:SetFrameStrata("LOW")
	host:SetFrameLevel(2)
	host:SetClampedToScreen(true)
	host:SetMovable(true)
	host:RegisterForDrag("LeftButton")
	host:EnableMouse(false)
	host:Hide()

	local disc = host:CreateTexture(nil, "BACKGROUND")
	disc:SetAllPoints(host)
	disc:SetTexture(ns.TEX_DISC)
	disc:SetVertexColor(0.03, 0.05, 0.06, 0.28)
	backdropDisc = disc

	local border = CreateFrame("Frame", nil, host, "BackdropTemplate")
	border:SetAllPoints(host)
	border:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 2,
	})
	border:SetBackdropBorderColor(1.0, 0.82, 0.15, 0.9)
	border:Hide()
	dragBorder = border

	local hint = border:CreateFontString(nil, "OVERLAY")
	hint:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	hint:SetPoint("TOP", border, "BOTTOM", 0, -6)
	hint:SetTextColor(1.0, 0.85, 0.20, 1.0)
	hint:SetText("FarmRadar3D: Ziehen zum Verschieben")

	host:SetScript("OnHide", function(self)
		self:StopMovingOrSizing()
	end)

	host:SetScript("OnDragStart", function(self)
		local opts = Core.GetOptions()
		if opts.dragUnlocked and not (InCombatLockdown and InCombatLockdown() and Minimap and Minimap.IsProtected and Minimap:IsProtected()) then
			self:StartMoving()
		end
	end)

	host:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local cx, cy = self:GetCenter()
		local ux, uy = UIParent:GetCenter()
		if cx and cy and ux and uy then
			local opts = Core.GetOptions()
			local bX = ns.OPTION_BOUNDS.offsetX
			local bY = ns.OPTION_BOUNDS.offsetY
			opts.offsetX = math.floor(Core.Clamp(cx - ux, bX[1], bX[2]) + 0.5)
			opts.offsetY = math.floor(Core.Clamp(cy - uy, bY[1], bY[2]) + 0.5)
			Hud.ApplyLayout()
			if ns.Options and ns.Options.NotifyPosition then
				ns.Options.NotifyPosition()
			end
		end
	end)

	-- Kompakte Steuerleiste oberhalb des Radar-Kreises
	local bar = CreateFrame("Frame", "FarmRadar3DControlBar", host, "BackdropTemplate")
	bar:SetSize(284, 24)
	bar:SetPoint("BOTTOM", host, "TOP", 0, 8)
	bar:SetFrameStrata("MEDIUM")
	bar:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	bar:SetBackdropColor(0.05, 0.08, 0.09, 0.78)
	bar:SetBackdropBorderColor(0.22, 0.65, 0.45, 0.75)

	local function MakeBarBtn(key, label, width, xOffset, onClick, tooltipText)
		local btn = CreateFrame("Button", nil, bar, "BackdropTemplate")
		btn:SetSize(width, 18)
		btn:SetPoint("LEFT", bar, "LEFT", xOffset, 0)
		btn:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		btn:SetBackdropColor(0.11, 0.16, 0.18, 0.90)
		btn:SetBackdropBorderColor(0.32, 0.50, 0.42, 0.85)
		local fs = btn:CreateFontString(nil, "OVERLAY")
		fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		fs:SetPoint("CENTER")
		fs:SetText(label)
		btn.fs = fs
		function btn:SetText(text)
			self.fs:SetText(text)
		end
		btn:SetScript("OnClick", onClick)
		btn:SetScript("OnEnter", function(self)
			self:SetBackdropBorderColor(0.35, 0.95, 0.65, 1.0)
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(tooltipText, 1, 1, 1)
				GameTooltip:Show()
			end
		end)
		btn:SetScript("OnLeave", function(self)
			self:SetBackdropBorderColor(0.32, 0.50, 0.42, 0.85)
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
		controlButtons[key] = btn
	end

	MakeBarBtn("close", "|cffff6666Aus|r", 44, 4, function()
		Hud.SetShown(false)
	end, "Radar-HUD ausschalten & normale Minimap wiederherstellen")

	MakeBarBtn("drag", "Schieben", 72, 52, function()
		Hud.ToggleDragMode()
	end, "HUD-Position entsperren oder sperren")

	MakeBarBtn("bg", "BG", 76, 128, function()
		Hud.ToggleBackground()
	end, "Minimap-Terrain zwischen transparent und sichtbar umschalten")

	MakeBarBtn("opt", "Optionen", 72, 208, function()
		if ns.Options and ns.Options.Open then
			ns.Options.Open()
		end
	end, "FarmRadar3D-Einstellungen öffnen")

	controlBar = bar
	hostFrame = host
	if ns.Overlay and ns.Overlay.Init then
		ns.Overlay.Init(host)
	end
	return host
end

function Hud.ApplyLayout()
	if not Core.hudShown then
		return
	end
	local host = EnsureHostFrame()
	local opts = Core.GetOptions()

	local hudSize = Core.Clamp(opts.hudSize, ns.OPTION_BOUNDS.hudSize[1], ns.OPTION_BOUNDS.hudSize[2])
	local dotScale = Core.Clamp(opts.dotScale, ns.OPTION_BOUNDS.dotScale[1], ns.OPTION_BOUNDS.dotScale[2])
	local bgAlpha = 1.0 - (Core.Clamp(opts.bgFade, 0, 100) / 100)
	local discAlpha = Core.Clamp(opts.backdropAlpha, 0, 85) / 100

	local minimapProtected = IsWidgetProtectedInCombat(Minimap)
	if not minimapProtected then
		host:SetSize(hudSize, hudSize)
		host:ClearAllPoints()
		host:SetPoint("CENTER", UIParent, "CENTER", opts.offsetX or 0, opts.offsetY or 0)
	end

	if backdropDisc then
		backdropDisc:SetVertexColor(0.02, 0.04, 0.05, discAlpha)
	end

	local unlockDrag = opts.dragUnlocked == true
	host:EnableMouse(unlockDrag)
	if dragBorder then
		dragBorder:SetShown(unlockDrag)
	end

	if Minimap then
		if not minimapProtected then
			if Minimap.SetParent and Minimap:GetParent() ~= host then
				Minimap:SetParent(host)
			end
			Minimap:ClearAllPoints()
			Minimap:SetPoint("CENTER", host, "CENTER", 0, 0)
			Minimap:SetScale(dotScale)
			Minimap:SetSize(hudSize / dotScale, hudSize / dotScale)
			Minimap:SetFrameStrata("LOW")
			Minimap:SetFrameLevel(host:GetFrameLevel() + 1)

			local interactive = (not unlockDrag) and (not opts.clickThrough)
			if Minimap.EnableMouse then
				Minimap:EnableMouse(interactive)
			end
			if Minimap.SetMouseClickEnabled then
				Minimap:SetMouseClickEnabled(interactive)
			end
			if Minimap.SetMouseMotionEnabled then
				Minimap:SetMouseMotionEnabled(interactive)
			end
		end

		if Minimap.SetAlpha then
			Minimap:SetAlpha(bgAlpha)
		end

		if not (InCombatLockdown and InCombatLockdown()) and type(SetCVar) == "function" then
			pendingRotateRestore = nil
			local wantRotate = opts.autoRotate and "1" or "0"
			if GetCVar("rotateMinimap") ~= wantRotate then
				pcall(SetCVar, "rotateMinimap", wantRotate)
			end
		end
	end

	UpdateControlBarVisuals()
	if ns.Overlay and ns.Overlay.ApplyStyle then
		ns.Overlay.ApplyStyle()
	end
end

function Hud.SetShown(show, silent)
	local want = show and true or false
	local opts = Core.GetOptions()

	if want == Core.hudShown then
		pendingHudState = nil
		if not want then
			opts.hudActive = false
		end
		return
	end

	if IsWidgetProtectedInCombat(Minimap) then
		pendingHudState = want
		if not silent then
			Core.Print("Minimap kann im Kampf nicht umgeschaltet werden – wird nach Kampfende automatisch ausgeführt.", true)
		end
		if ns.Options and ns.Options.NotifyHUDState then
			ns.Options.NotifyHUDState()
		end
		return
	end

	if want then
		if opts.hideInInstance and IsInInstance and select(1, IsInInstance()) then
			suspendedByInstance = true
			if not silent then
				Core.Print("Radar-HUD pausiert in Instanzen (in Einstellungen änderbar).", true)
			end
			if ns.Options and ns.Options.NotifyHUDState then
				ns.Options.NotifyHUDState()
			end
			return
		end
		suspendedByInstance = false
		if ns.Minimap and ns.Minimap.CaptureHomeBounds then
			ns.Minimap.CaptureHomeBounds()
		end
		local host = EnsureHostFrame()
		CaptureSnapshot()
		if snapshot then
			for _, item in ipairs(snapshot.hiddenList) do
				local w = item.widget
				if w and w.Hide and not IsWidgetProtectedInCombat(w) then
					pcall(w.Hide, w)
				end
			end
		end
		if Minimap and Minimap.SetMaskTexture then
			Minimap:SetMaskTexture(ns.TEX_MASK)
		end
		pendingHudState = nil
		Core.hudShown = true
		opts.hudActive = true
		host:Show()
		Hud.ApplyLayout()
		if ns.Overlay and ns.Overlay.SetActive then
			ns.Overlay.SetActive(true)
		end
	else
		suspendedByInstance = false
		pendingHudState = nil
		if ns.Overlay and ns.Overlay.SetActive then
			ns.Overlay.SetActive(false)
		end
		Core.hudShown = false
		opts.hudActive = false
		if RestoreFromSnapshot() then
			if hostFrame then
				hostFrame:Hide()
			end
		else
			pendingHudState = false
			Core.hudShown = true
			if ns.Options and ns.Options.NotifyHUDState then
				ns.Options.NotifyHUDState()
			end
			return
		end
	end

	if ns.Minimap and ns.Minimap.Refresh then
		ns.Minimap.Refresh()
	end
	if ns.Options and ns.Options.NotifyHUDState then
		ns.Options.NotifyHUDState()
	end
end

function Hud.Toggle()
	local effective = (pendingHudState ~= nil) and pendingHudState or Core.hudShown
	Hud.SetShown(not effective)
end

function Hud.ToggleBackground()
	local opts = Core.GetOptions()
	if opts.bgFade >= 95 then
		opts.bgFade = 55
	elseif opts.bgFade >= 40 then
		opts.bgFade = 0
	else
		opts.bgFade = 100
	end
	Hud.ApplyLayout()
	if ns.Options and ns.Options.NotifyAll then
		ns.Options.NotifyAll()
	end
	Core.Print("Minimap-Hintergrund-Ausblendung: " .. tostring(opts.bgFade) .. "%.")
end

function Hud.ToggleDragMode()
	local opts = Core.GetOptions()
	opts.dragUnlocked = not opts.dragUnlocked
	if opts.dragUnlocked and not Core.hudShown then
		Hud.SetShown(true)
	else
		Hud.ApplyLayout()
	end
	if ns.Options and ns.Options.NotifyAll then
		ns.Options.NotifyAll()
	end
	Core.Print(opts.dragUnlocked and "HUD entsperrt: Mit linker Maustaste verschieben." or "HUD-Position gesperrt.")
end

function Hud.CenterPosition()
	local opts = Core.GetOptions()
	opts.offsetX = 0
	opts.offsetY = 0
	Hud.ApplyLayout()
	if ns.Options and ns.Options.NotifyPosition then
		ns.Options.NotifyPosition()
	end
	Core.Print("Radar-HUD wieder mittig um den Charakter zentriert.")
end

function Hud.OnRegenEnabled()
	if pendingHudState ~= nil then
		local nextState = pendingHudState
		pendingHudState = nil
		Hud.SetShown(nextState, true)
	end
	if pendingRotateRestore ~= nil and (not Core.hudShown) and type(SetCVar) == "function" then
		local val = pendingRotateRestore
		pendingRotateRestore = nil
		if GetCVar("rotateMinimap") ~= val then
			pcall(SetCVar, "rotateMinimap", val)
		end
	end
end

function Hud.ResetInstanceSuspension()
	suspendedByInstance = false
end

function Hud.CheckInstanceState()
	local opts = Core.GetOptions()
	if not opts.hideInInstance then
		suspendedByInstance = false
		return
	end
	local inInst = IsInInstance and select(1, IsInInstance()) or false
	if inInst and Core.hudShown then
		Hud.SetShown(false, true)
		suspendedByInstance = true
	elseif (not inInst) and suspendedByInstance then
		suspendedByInstance = false
		Hud.SetShown(true, true)
	end
end
