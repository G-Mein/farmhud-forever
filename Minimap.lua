local _, ns = ...

local Core = ns.Core

local MinimapMod = {}
ns.Minimap = MinimapMod

local BUTTON_NAME = "FarmRadar3DMinimapButton"
local RADIUS_PADDING = 5
local CORNER_INSET = 10

local MINIMAP_SHAPES = {
	["ROUND"]                 = { true,  true,  true,  true  },
	["SQUARE"]                = { false, false, false, false },
	["CORNER-TOPLEFT"]        = { false, false, false, true  },
	["CORNER-TOPRIGHT"]       = { false, false, true,  false },
	["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
	["CORNER-BOTTOMRIGHT"]    = { true,  false, false, false },
	["SIDE-LEFT"]             = { false, true,  false, true  },
	["SIDE-RIGHT"]            = { true,  false, true,  false },
	["SIDE-TOP"]              = { false, false, true,  true  },
	["SIDE-BOTTOM"]           = { true,  true,  false, false },
	["TRICORNER-TOPLEFT"]     = { false, true,  true,  true  },
	["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true  },
	["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true  },
	["TRICORNER-BOTTOMRIGHT"] = { true,  true,  true,  false },
}

local button = nil
local cachedHome = {
	relX = 0,
	relY = -10,
	halfW = 75,
	halfH = 75,
	shape = "ROUND",
}

local function GetSavedAngle()
	local opts = Core.GetOptions()
	if Core.IsFiniteNumber(opts.minimapAngle) then
		return opts.minimapAngle % 360
	end
	return ns.DEFAULTS.minimapAngle
end

local function ShouldShow()
	local opts = Core.GetOptions()
	return opts.showMinimapButton ~= false
end

function MinimapMod.CaptureHomeBounds()
	if Core.hudShown or not Minimap then
		return
	end
	local parent = MinimapCluster or UIParent
	local rawW = Minimap.GetWidth and Minimap:GetWidth() or 140
	local rawH = Minimap.GetHeight and Minimap:GetHeight() or 140
	if Core.IsFiniteNumber(rawW) and rawW > 40 and rawW <= 360 and Core.IsFiniteNumber(rawH) and rawH > 40 and rawH <= 360 then
		cachedHome.halfW = rawW / 2 + RADIUS_PADDING
		cachedHome.halfH = rawH / 2 + RADIUS_PADDING
	end
	local mx, my = Minimap:GetCenter()
	local px, py = parent:GetCenter()
	if Core.IsFiniteNumber(mx) and Core.IsFiniteNumber(my) and Core.IsFiniteNumber(px) and Core.IsFiniteNumber(py) then
		cachedHome.relX = mx - px
		cachedHome.relY = my - py
	end
	if type(GetMinimapShape) == "function" then
		cachedHome.shape = GetMinimapShape() or "ROUND"
	end
end

local function PlaceAtAngle(target, angle)
	if not target then
		return
	end
	MinimapMod.CaptureHomeBounds()

	local rad = math.rad(angle)
	local x = math.cos(rad)
	local y = math.sin(rad)

	local q = 1
	if x < 0 then
		q = q + 1
	end
	if y > 0 then
		q = q + 2
	end

	local quadTable = MINIMAP_SHAPES[cachedHome.shape] or MINIMAP_SHAPES["ROUND"]
	local halfW = cachedHome.halfW
	local halfH = cachedHome.halfH

	if quadTable[q] then
		x = x * halfW
		y = y * halfH
	else
		local diagW = math.sqrt(2 * halfW * halfW) - CORNER_INSET
		local diagH = math.sqrt(2 * halfH * halfH) - CORNER_INSET
		x = math.max(-halfW, math.min(x * diagW, halfW))
		y = math.max(-halfH, math.min(y * diagH, halfH))
	end

	local anchorParent = MinimapCluster or UIParent
	target:ClearAllPoints()
	target:SetPoint("CENTER", anchorParent, "CENTER", cachedHome.relX + x, cachedHome.relY + y)
end

local function FollowCursor(self)
	local anchorParent = MinimapCluster or UIParent
	local centerX, centerY = anchorParent:GetCenter()
	local scale = anchorParent:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	if not (
		Core.IsFiniteNumber(centerX)
		and Core.IsFiniteNumber(centerY)
		and Core.IsFiniteNumber(scale)
		and scale > 0
		and Core.IsFiniteNumber(cursorX)
		and Core.IsFiniteNumber(cursorY)
	) then
		return
	end

	local targetX = centerX + cachedHome.relX
	local targetY = centerY + cachedHome.relY
	local angle = math.deg(math.atan2(cursorY / scale - targetY, cursorX / scale - targetX)) % 360
	if Core.IsFiniteNumber(angle) then
		self.dragAngle = angle
		PlaceAtAngle(self, angle)
	end
end

local function Press(self)
	if not self.isDown and self.Icon then
		self.isDown = true
		self.Icon:AdjustPointsOffset(1, -1)
	end
end

local function Release(self)
	if self.isDown and self.Icon then
		self.isDown = false
		self.Icon:AdjustPointsOffset(-1, 1)
	end
end

local function StopDrag(self)
	local wasDragging = self.dragging and true or false
	self:SetScript("OnUpdate", nil)
	self:UnlockHighlight()
	self.dragging = false
	self.dragAngle = nil
	return wasDragging
end

local function ShowTooltip(owner, canDrag)
	if not (GameTooltip and owner) then
		return
	end
	local skinText = (ns.Sources and ns.Sources.GetSkinningStatusText and ns.Sources.GetSkinningStatusText()) or ""
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText("|cff33ff99Farm|rRadar3D", 1, 1, 1)
	GameTooltip:AddLine(string.format("|cffffffffRadar-HUD:|r %s", Core.hudShown and "|cff33ff99AKTIV|r" or "|cffff6666AUS|r"))
	if skinText ~= "" then
		GameTooltip:AddLine("|cffffffffKürschnerei:|r " .. skinText)
	end
	GameTooltip:AddLine("|cffaaaaaaLinksklick: Radar-HUD ein-/ausschalten|r")
	GameTooltip:AddLine("|cffaaaaaaRechtsklick: Einstellungen öffnen|r")
	GameTooltip:AddLine("|cffaaaaaaMittelklick: HUD verschieben entsperren|r")
	if canDrag then
		GameTooltip:AddLine("|cffaaaaaaLinksklick ziehen: Button verschieben|r")
	end
	GameTooltip:Show()
end

local function HandleClick(mouseButton)
	local btn = (type(mouseButton) == "table" and mouseButton.buttonName) or mouseButton
	if btn == "RightButton" then
		if ns.Options and ns.Options.Open then
			ns.Options.Open()
		end
	elseif btn == "MiddleButton" then
		if ns.Hud and ns.Hud.ToggleDragMode then
			ns.Hud.ToggleDragMode()
		end
	else
		if ns.Hud and ns.Hud.Toggle then
			ns.Hud.Toggle()
		end
	end
end

function MinimapMod.UpdatePosition()
	if button and not button.dragging then
		PlaceAtAngle(button, GetSavedAngle())
	end
end

function MinimapMod.Refresh()
	if button then
		MinimapMod.UpdatePosition()
		if button.ActiveGlow then
			button.ActiveGlow:SetShown(Core.hudShown == true)
		end
		button:SetShown(ShouldShow())
	end
end

function MinimapMod.Init()
	if button then
		return
	end
	local parentFrame = MinimapCluster or UIParent

	local btn = CreateFrame("Button", BUTTON_NAME, parentFrame)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFixedFrameStrata(true)
	btn:SetFrameLevel(10)
	btn:SetFixedFrameLevel(true)
	btn:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	btn:RegisterForDrag("LeftButton")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(24, 24)
	bg:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
	bg:SetPoint("CENTER")
	btn.Background = bg

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexture(ns.TEX_LOGO)
	icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
	btn.Icon = icon

	local glow = btn:CreateTexture(nil, "OVERLAY")
	glow:SetSize(33, 33)
	glow:SetPoint("CENTER")
	glow:SetTexture(ns.TEX_RING)
	glow:SetVertexColor(0.25, 1.0, 0.55, 0.95)
	glow:Hide()
	btn.ActiveGlow = glow

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
	border:SetPoint("TOPLEFT", btn, "TOPLEFT")
	btn.Border = border

	btn:SetScript("OnClick", function(_, mouseButton)
		HandleClick(mouseButton)
	end)
	btn:SetScript("OnMouseDown", Press)
	btn:SetScript("OnMouseUp", Release)
	btn:SetScript("OnHide", function(self)
		if StopDrag(self) then
			MinimapMod.UpdatePosition()
		end
		Release(self)
	end)
	btn:SetScript("OnEnter", function(self)
		if not self.dragging then
			ShowTooltip(self, true)
		end
	end)
	btn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	btn:SetScript("OnDragStart", function(self)
		MinimapMod.CaptureHomeBounds()
		self.dragging = true
		self.dragAngle = GetSavedAngle()
		self:LockHighlight()
		if GameTooltip then
			GameTooltip:Hide()
		end
		self:SetScript("OnUpdate", FollowCursor)
	end)
	btn:SetScript("OnDragStop", function(self)
		local finalAngle = self.dragAngle
		StopDrag(self)
		if Core.IsFiniteNumber(finalAngle) then
			Core.GetOptions().minimapAngle = finalAngle % 360
		end
		MinimapMod.UpdatePosition()
	end)

	if Minimap and Minimap.HookScript then
		Minimap:HookScript("OnSizeChanged", function()
			if not Core.hudShown then
				MinimapMod.UpdatePosition()
			end
		end)
	end

	button = btn
	MinimapMod.Refresh()
end

function FarmRadar3D_OnAddonCompartmentClick(_, mouseButton)
	HandleClick(mouseButton)
end

function FarmRadar3D_OnAddonCompartmentEnter(_, menuButton)
	ShowTooltip(menuButton, false)
end

function FarmRadar3D_OnAddonCompartmentLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end
