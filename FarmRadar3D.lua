local ADDON_NAME, ns = ...

local Core = ns.Core
local Sources = ns.Sources
local Hud = ns.Hud
local Overlay = ns.Overlay
local Options = ns.Options
local MinimapMod = ns.Minimap

local loginRestoreApplied = false

-- Globale Keybind-Einstiegspunkte fuer Bindings.xml
function FarmRadar3D_ToggleHUD()
	Hud.Toggle()
end

function FarmRadar3D_ToggleBackground()
	Hud.ToggleBackground()
end

function FarmRadar3D_ToggleDragMode()
	Hud.ToggleDragMode()
end

function FarmRadar3D_OpenOptions()
	Options.Open()
end

local function PrintHelp()
	Core.Print("Befehle: /fr3d (oder /farmradar)")
	Core.Print("  /fr3d              -> Radar-HUD ein-/ausschalten")
	Core.Print("  /fr3d config       -> Einstellungen öffnen")
	Core.Print("  /fr3d bg [0..100]  -> Minimap-Hintergrund umschalten oder % Ausblendung setzen")
	Core.Print("  /fr3d scale <1-2.4>-> Dot-Größe setzen (z.B. /fr3d scale 1.6)")
	Core.Print("  /fr3d size <px>    -> Radar-Durchmesser in Pixeln setzen (220..760)")
	Core.Print("  /fr3d move         -> Position entsperren/sperren")
	Core.Print("  /fr3d center       -> Radar wieder mittig um Charakter zentrieren")
	Core.Print("  /fr3d status       -> Status und erkannte Berufe/Tracking anzeigen")
	Core.Print("  /fr3d reset        -> Einstellungen zurücksetzen")
end

local function HandleSlashCommand(input)
	local text = tostring(input or ""):match("^%s*(.-)%s*$")
	if text == "" or text == "toggle" then
		Hud.Toggle()
		return
	end

	local cmd, rest = text:match("^(%S+)%s*(.-)%s*$")
	cmd = string.lower(cmd or "")

	if cmd == "config" or cmd == "options" or cmd == "opt" then
		Options.Open()
	elseif cmd == "bg" or cmd == "fade" then
		if rest ~= "" then
			local num = tonumber(rest)
			if num then
				Core.GetOptions().bgFade = Core.Clamp(math.floor(num + 0.5), 0, 100)
				Hud.ApplyLayout()
				Options.NotifyAll()
				Core.Print("Minimap-Hintergrund-Ausblendung auf " .. tostring(Core.GetOptions().bgFade) .. "% gesetzt.")
				return
			end
		end
		Hud.ToggleBackground()
	elseif cmd == "scale" then
		local num = tonumber(rest)
		if num then
			Core.GetOptions().dotScale = Core.Clamp(num, ns.OPTION_BOUNDS.dotScale[1], ns.OPTION_BOUNDS.dotScale[2])
			Hud.ApplyLayout()
			Options.NotifyAll()
			Core.Print(string.format("Dot-Scale auf %.2fx gesetzt.", Core.GetOptions().dotScale))
		else
			Core.Print("Verwendung: /fr3d scale 1.0 bis 2.4", true)
		end
	elseif cmd == "size" then
		local num = tonumber(rest)
		if num then
			Core.GetOptions().hudSize = Core.Clamp(math.floor(num + 0.5), ns.OPTION_BOUNDS.hudSize[1], ns.OPTION_BOUNDS.hudSize[2])
			Hud.ApplyLayout()
			Options.NotifyAll()
			Core.Print("Radar-Größe auf " .. tostring(Core.GetOptions().hudSize) .. " px gesetzt.")
		else
			Core.Print("Verwendung: /fr3d size 220 bis 760", true)
		end
	elseif cmd == "move" or cmd == "drag" or cmd == "lock" then
		Hud.ToggleDragMode()
	elseif cmd == "center" or cmd == "mitte" then
		Hud.CenterPosition()
	elseif cmd == "status" then
		Core.PrintStatus()
	elseif cmd == "reset" then
		Core.ResetOptions()
	else
		PrintHelp()
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local optionalEvents = {
	"MINIMAP_UPDATE_TRACKING",
	"MINIMAP_UPDATE_ZOOM",
	"ZONE_CHANGED_NEW_AREA",
	"ZONE_CHANGED_INDOORS",
	"SKILL_LINES_CHANGED",
	"SPELLS_CHANGED",
	"LEARNED_SPELL_IN_TAB",
	"QUEST_LOG_UPDATE",
	"LOOT_OPENED",
	"LOOT_READY",
	"LOOT_CLOSED",
	"PLAYER_TARGET_CHANGED",
	"UPDATE_MOUSEOVER_UNIT",
	"UNIT_SPELLCAST_SENT",
	"UNIT_SPELLCAST_SUCCEEDED",
}
for _, ev in ipairs(optionalEvents) do
	pcall(eventFrame.RegisterEvent, eventFrame, ev)
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			self:UnregisterEvent("ADDON_LOADED")
			Core.InitDB()

			SLASH_FARMRADAR3D1 = "/fr3d"
			SLASH_FARMRADAR3D2 = "/farmradar"
			SLASH_FARMRADAR3D3 = "/farmradar3d"
			SlashCmdList["FARMRADAR3D"] = HandleSlashCommand
		end
	elseif event == "PLAYER_LOGIN" then
		Sources.InitZoneMaps()
		Sources.RefreshProfessions()
		Sources.RefreshTracking()
		Options.Init()
		MinimapMod.Init()
	elseif event == "PLAYER_ENTERING_WORLD" then
		Sources.RefreshProfessions()
		Sources.RefreshTracking()
		Sources.InvalidateQuestCache()
		MinimapMod.UpdatePosition()
		if not loginRestoreApplied then
			loginRestoreApplied = true
			local opts = Core.GetOptions()
			if opts.restoreOnLogin and opts.hudActive then
				Hud.SetShown(true, true)
			end
		end
		Hud.CheckInstanceState()
		Overlay.ForceRefresh()
		Options.NotifyTracking()
	elseif event == "PLAYER_REGEN_ENABLED" then
		Hud.OnRegenEnabled()
	elseif event == "MINIMAP_UPDATE_TRACKING" then
		Sources.RefreshTracking()
		Overlay.ForceRefresh()
		Options.NotifyTracking()
	elseif event == "MINIMAP_UPDATE_ZOOM" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
		Sources.InvalidateQuestCache()
		Overlay.ForceRefresh()
	elseif event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
		Sources.RefreshProfessions()
		Overlay.ForceRefresh()
	elseif event == "QUEST_LOG_UPDATE" then
		Sources.InvalidateQuestCache()
		Overlay.ForceRefresh()
	elseif event == "PLAYER_TARGET_CHANGED" then
		Sources.ObserveUnit("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		Sources.ObserveUnit("mouseover")
	elseif event == "LOOT_OPENED" or event == "LOOT_READY" or event == "LOOT_CLOSED" then
		Sources.OnLootEvent(event)
		if event ~= "LOOT_CLOSED" then
			Overlay.ForceRefresh()
		end
	elseif event == "UNIT_SPELLCAST_SENT" then
		Sources.OnSpellCastSent(arg1, arg2, arg3, arg4)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if Sources.OnSpellCastSucceeded(arg1, arg2, arg3) and Core.hudShown then
			Overlay.ForceRefresh()
		end
	end
end)
