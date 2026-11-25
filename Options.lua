local _, ns = ...

local Core = ns.Core
local Sources = ns.Sources

local Options = {}
ns.Options = Options

local registeredVars = {}
local trackingVars = {}

local function NotifySetting(varName)
	if varName and Settings and Settings.NotifyUpdate then
		pcall(Settings.NotifyUpdate, varName)
	end
end

local function NotifySettingNextFrame(varName)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			NotifySetting(varName)
		end)
	else
		NotifySetting(varName)
	end
end

local function AddSectionHeader(layout, title)
	if layout and CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
	end
end

local function AddButtonRow(layout, label, buttonText, onClick, tooltip)
	if layout and CreateSettingsButtonInitializer then
		-- 5. Argument zwingend false: verhindert Taint in Blizzards Optionssuche.
		layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, false))
	end
end

local function RegisterBool(category, varName, optKey, label, tooltip, onAfterSet)
	local opts = Core.GetOptions()
	local defaultVal = ns.DEFAULTS[optKey] and true or false
	local setting = Settings.RegisterProxySetting(
		category,
		varName,
		Settings.VarType.Boolean,
		label,
		defaultVal,
		function()
			return opts[optKey] == true
		end,
		function(val)
			opts[optKey] = val and true or false
			if onAfterSet then
				onAfterSet(opts[optKey])
			end
		end
	)
	Settings.CreateCheckbox(category, setting, tooltip)
	registeredVars[#registeredVars + 1] = varName
end

local function RegisterSlider(category, varName, optKey, label, minVal, maxVal, step, formatter, tooltip, onAfterSet)
	local opts = Core.GetOptions()
	local defaultVal = ns.DEFAULTS[optKey]
	local setting = Settings.RegisterProxySetting(
		category,
		varName,
		Settings.VarType.Number,
		label,
		defaultVal,
		function()
			return tonumber(opts[optKey]) or defaultVal
		end,
		function(val)
			local num = tonumber(val) or defaultVal
			opts[optKey] = Core.Clamp(num, minVal, maxVal)
			if onAfterSet then
				onAfterSet(opts[optKey])
			end
		end
	)
	local sliderOpts = Settings.CreateSliderOptions(minVal, maxVal, step)
	if formatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		sliderOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
	end
	Settings.CreateSlider(category, setting, sliderOpts, tooltip)
	registeredVars[#registeredVars + 1] = varName
end

local function ApplyHudChange()
	if ns.Hud and ns.Hud.ApplyLayout then
		ns.Hud.ApplyLayout()
	end
end

local function ApplyOverlayChange()
	if ns.Overlay and ns.Overlay.ForceRefresh then
		ns.Overlay.ForceRefresh()
	end
end

function Options.Init()
	if Options.initialized then
		return
	end
	if not (
		Settings
		and Settings.RegisterVerticalLayoutCategory
		and Settings.RegisterAddOnCategory
		and Settings.RegisterProxySetting
		and Settings.CreateCheckbox
		and Settings.CreateSlider
		and Settings.CreateSliderOptions
	) then
		return
	end

	local mainCat, mainLayout = Settings.RegisterVerticalLayoutCategory("FarmRadar3D")
	Options.mainCategory = mainCat

	-- Hauptseite: Schnellsteuerung
	AddSectionHeader(mainLayout, "Schnellsteuerung & HUD-Modus")

	local hudSetting = Settings.RegisterProxySetting(
		mainCat,
		"FARMRADAR3D_OPT_HUD_ACTIVE",
		Settings.VarType.Boolean,
		"Radar-HUD aktivieren",
		false,
		function()
			return Core.hudShown == true
		end,
		function(val)
			if ns.Hud and ns.Hud.SetShown then
				ns.Hud.SetShown(val)
			end
			if Core.hudShown ~= (val and true or false) then
				NotifySettingNextFrame("FARMRADAR3D_OPT_HUD_ACTIVE")
			end
		end
	)
	Settings.CreateCheckbox(
		mainCat,
		hudSetting,
		"Blendet die echte Minimap als großes transparentes Radar um deinen Charakter (oder frei positioniert) ein. Ausschalten stellt die normale Minimap exakt wieder her."
	)
	registeredVars[#registeredVars + 1] = "FARMRADAR3D_OPT_HUD_ACTIVE"

	AddButtonRow(
		mainLayout,
		"HUD schnell umschalten",
		"Ein / Aus",
		function()
			if ns.Hud and ns.Hud.Toggle then
				ns.Hud.Toggle()
			end
		end,
		"Alternativ über Minimap-Button, /fr3d oder eigene Tastaturbelegung umschaltbar."
	)

	RegisterBool(
		mainCat,
		"FARMRADAR3D_OPT_DRAG_UNLOCKED",
		"dragUnlocked",
		"HUD-Position entsperren (mit Maus verschieben)",
		"Zeigt einen goldenen Rahmen um das HUD, damit du das Radar beliebig um oder neben deinen Charakter ziehen kannst.",
		function(enabled)
			if enabled and not Core.hudShown and ns.Hud and ns.Hud.SetShown then
				ns.Hud.SetShown(true)
			else
				ApplyHudChange()
			end
		end
	)

	AddButtonRow(
		mainLayout,
		"Position zurücksetzen",
		"Zentrieren (0, 0)",
		function()
			if ns.Hud and ns.Hud.CenterPosition then
				ns.Hud.CenterPosition()
			end
		end,
		"Setzt das Radar-HUD wieder exakt mittig um deinen Charakter."
	)

	AddButtonRow(
		mainLayout,
		"Minimap-Hintergrund schnell wechseln",
		"Hintergrund umschalten",
		function()
			if ns.Hud and ns.Hud.ToggleBackground then
				ns.Hud.ToggleBackground()
			end
		end,
		"Wechselt schnell zwischen komplett ausgeblendetem Terrain (100%), halbtransparent (55%) und voller Karte (0%)."
	)

	AddSectionHeader(mainLayout, "Bedienung & Status")

	RegisterBool(
		mainCat,
		"FARMRADAR3D_OPT_SHOW_MINIMAP_BTN",
		"showMinimapButton",
		"Minimap-Symbol anzeigen",
		"Zeigt das verschiebbare FarmRadar3D-Medaillon an der normalen Minimap-Ecke (bleibt auch bei aktivem HUD dort).",
		function()
			if ns.Minimap and ns.Minimap.Refresh then
				ns.Minimap.Refresh()
			end
		end
	)

	RegisterBool(
		mainCat,
		"FARMRADAR3D_OPT_SHOW_CONTROL_BAR",
		"showControlBar",
		"Kompakte HUD-Steuerleiste anzeigen",
		"Zeigt bei aktivem HUD eine kleine Leiste über dem Radar (Aus / Schieben / BG / Optionen).",
		ApplyHudChange
	)

	AddButtonRow(
		mainLayout,
		"Status im Chat anzeigen",
		"Status ausgeben",
		function()
			Core.PrintStatus()
		end,
		"Gibt aktuellen HUD-Status, Kürschnerei-Erkennung und aktive Minimap-Tracking-Filter im Chat aus."
	)

	AddButtonRow(
		mainLayout,
		"Alle Einstellungen zurücksetzen",
		"Standardwerte laden",
		function()
			Core.ResetOptions()
		end,
		"Setzt alle Regler und Filter auf Standardwerte zurück (gelernte Spots bleiben erhalten)."
	)

	Settings.RegisterAddOnCategory(mainCat)

	-- Unterkategorien
	if Settings.RegisterVerticalLayoutSubcategory then
		-- 1. HUD & Darstellung
		local hudCat, hudLayout = Settings.RegisterVerticalLayoutSubcategory(mainCat, "HUD & Darstellung")
		Options.hudCategory = hudCat

		AddSectionHeader(hudLayout, "Größe, Punkte & Transparenz")
		RegisterSlider(
			hudCat, "FARMRADAR3D_OPT_HUD_SIZE", "hudSize", "Radar-Durchmesser (Pixel)",
			220, 760, 10, function(v) return string.format("%d px", v) end,
			"Bestimmt den sichtbaren Durchmesser des Radar-HUDs auf dem Bildschirm.",
			ApplyHudChange
		)
		RegisterSlider(
			hudCat, "FARMRADAR3D_OPT_DOT_SCALE", "dotScale", "Größe der gelben Dots (Dot-Scale)",
			1.0, 2.4, 0.05, function(v) return string.format("%.2fx", v) end,
			"Vergrößert die nativen gelben Minimap-Tracking-Dots stufenlos per Minimap-Skalierung bei gleichbleibender HUD-Größe.",
			ApplyHudChange
		)
		RegisterSlider(
			hudCat, "FARMRADAR3D_OPT_BG_FADE", "bgFade", "Minimap-Hintergrund ausblenden (%)",
			0, 100, 5, function(v) return string.format("%d%%", v) end,
			"Blendet nur die Minimap-Terrain-Karte bis 100% aus – gelbe Kräuter-, Erz- und Tracking-Dots bleiben voll sichtbar!",
			ApplyHudChange
		)
		RegisterSlider(
			hudCat, "FARMRADAR3D_OPT_DISC_ALPHA", "backdropAlpha", "Dunkle Kontrast-Scheibe (%)",
			0, 85, 5, function(v) return string.format("%d%%", v) end,
			"Legt einen dezenten dunklen Hintergrund unter die Dots, damit sie über hellem Schnee oder Wüste besser hervorstechen.",
			ApplyHudChange
		)

		AddSectionHeader(hudLayout, "Position auf dem Bildschirm")
		RegisterSlider(
			hudCat, "FARMRADAR3D_OPT_OFFSET_X", "offsetX", "Horizontale Position (X)",
			-600, 600, 5, function(v) return string.format("%d px", v) end,
			"0 = exakt mittig um deinen Charakter; negative Werte verschieben nach links, positive nach rechts.",
			ApplyHudChange
		)
		RegisterSlider(
			hudCat, "FARMRADAR3D_OPT_OFFSET_Y", "offsetY", "Vertikale Position (Y)",
			-400, 400, 5, function(v) return string.format("%d px", v) end,
			"0 = exakt mittig um deinen Charakter; negative Werte verschieben nach unten, positive nach oben.",
			ApplyHudChange
		)

		AddSectionHeader(hudLayout, "Hilfslinien & Verhalten")
		RegisterBool(
			hudCat, "FARMRADAR3D_OPT_SHOW_RINGS", "showRings", "Entfernungsringe anzeigen",
			"Zeichnet feine konzentrische Ringe über das Radar zur besseren Entfernungsabschätzung.",
			ApplyHudChange
		)
		RegisterSlider(
			hudCat, "FARMRADAR3D_OPT_RING_COUNT", "ringCount", "Anzahl der Ringe",
			1, 3, 1, function(v) return string.format("%d", v) end,
			"Legt fest, wie viele konzentrische Ringe gezeichnet werden (1 bis 3).",
			ApplyHudChange
		)
		RegisterBool(
			hudCat, "FARMRADAR3D_OPT_SHOW_COMPASS", "showCompass", "Kompass (N / O / S / W) anzeigen",
			"Zeigt die Himmelsrichtungen am äußeren Radar-Rand (dreht sich mit, wenn Minimap-Rotation aktiv ist).",
			ApplyHudChange
		)
		RegisterBool(
			hudCat, "FARMRADAR3D_OPT_SHOW_CROSSHAIR", "showCrosshair", "Fadenkreuz in der Mitte anzeigen",
			"Zeigt ein dezentes Fadenkreuz exakt auf der Spielerposition.",
			ApplyHudChange
		)
		RegisterBool(
			hudCat, "FARMRADAR3D_OPT_AUTO_ROTATE", "autoRotate", "Minimap-Rotation erzwingen",
			"Dreht das Radar automatisch mit der Blickrichtung deines Charakters (oben = Blickrichtung).",
			ApplyHudChange
		)
		RegisterBool(
			hudCat, "FARMRADAR3D_OPT_CLICK_THROUGH", "clickThrough", "Mausklicks durchlassen (Click-Through)",
			"Wenn aktiv, blockiert das Radar weder Kameradrehung noch das Anklicken von Gegnern, Loot oder Knoten in der 3D-Welt.",
			ApplyHudChange
		)
		RegisterBool(
			hudCat, "FARMRADAR3D_OPT_HIDE_INSTANCE", "hideInInstance", "In Instanzen automatisch ausblenden",
			"Pausiert das Radar-HUD automatisch in Dungeons/Schlachtzügen (dort sperrt WoW die genaue Spieler-Koordinatenabfrage).",
			function()
				if ns.Hud and ns.Hud.CheckInstanceState then
					ns.Hud.CheckInstanceState()
				end
			end
		)
		RegisterBool(
			hudCat, "FARMRADAR3D_OPT_RESTORE_LOGIN", "restoreOnLogin", "HUD-Status nach Reload/Login beibehalten",
			"Wenn aktiv, schaltet sich das HUD beim Einloggen automatisch wieder ein, sofern es zuletzt aktiv war.",
			nil
		)

		-- 2. Radar-Filter & Pins
		local filterCat, filterLayout = Settings.RegisterVerticalLayoutSubcategory(mainCat, "Radar-Filter & Pins")
		Options.filterCategory = filterCat

		AddSectionHeader(filterLayout, "Overlay-Darstellung")
		RegisterSlider(
			filterCat, "FARMRADAR3D_OPT_PIN_SCALE", "pinScale", "Overlay-Pin-Größe",
			0.6, 1.8, 0.1, function(v) return string.format("%.1fx", v) end,
			"Skaliert die zusätzlichen Overlay-Icons (Quests, Kürschnern, Dienste, Datenbank-Spawns).",
			ApplyOverlayChange
		)
		RegisterSlider(
			filterCat, "FARMRADAR3D_OPT_PIN_ALPHA", "pinAlpha", "Overlay-Pin-Deckkraft (%)",
			20, 100, 5, function(v) return string.format("%d%%", v) end,
			"Transparenz der Overlay-Icons auf dem Radar.",
			ApplyOverlayChange
		)

		AddSectionHeader(filterLayout, "Quest-Items & Quest-Ziele")
		RegisterBool(
			filterCat, "FARMRADAR3D_OPT_QUEST_ITEMS", "showQuestItems", "Quest-Items & Quest-Objekte hervorheben",
			"Zeigt Quest-Gegenstände, Sammelobjekte und Interaktionsziele aus Questie deutlich auf dem Radar.",
			ApplyOverlayChange
		)
		RegisterBool(
			filterCat, "FARMRADAR3D_OPT_QUEST_OBJ", "showQuestObjectives", "Übrige aktive Quest-Ziele anzeigen",
			"Zeigt Gegner- und Abgabeziele aktiver Quests (Questie + Blizzard-Fallback).",
			ApplyOverlayChange
		)

		AddSectionHeader(filterLayout, "Kürschnerei / Leder (nur mit Beruf aktiv)")
		RegisterBool(
			filterCat, "FARMRADAR3D_OPT_SKIN_CORPSES", "showSkinningCorpses", "Kürschner-Leichen-Marker mit Timer",
			"Aktiviert sich automatisch NUR wenn dieser Charakter Kürschnerei beherrscht: Markiert gelootete kürschnerbare Wildtiere/Drachkin per Countdown (nützlich bei Multi-Pulls) und löscht den Marker automatisch nach dem Kürschnern.",
			ApplyOverlayChange
		)
		RegisterSlider(
			filterCat, "FARMRADAR3D_OPT_SKIN_DURATION", "skinningCorpseDuration", "Leichen-Marker Laufzeit (Sekunden)",
			60, 300, 15, function(v) return string.format("%ds", v) end,
			"Wie lange ungekürschnerte Leichen-Marker sichtbar bleiben.",
			nil
		)
		RegisterBool(
			filterCat, "FARMRADAR3D_OPT_SKIN_LEARNED", "showLearnedSkinning", "Gelernte Kürschner-Spots anzeigen",
			"Speichert beim Kürschnern automatisch den Fundort und zeigt bewährte Spot-Positionen dezent auf dem Radar.",
			ApplyOverlayChange
		)
		AddButtonRow(
			filterLayout,
			"Aktive Leichen-Marker entfernen",
			"Marker leeren",
			function()
				Sources.ClearAllSkinningCorpses()
				ApplyOverlayChange()
				Core.Print("Alle aktiven Kürschner-Leichen-Marker wurden gelöscht.")
			end,
			"Entfernt sofort alle laufenden Leichen-Timer."
		)

		AddSectionHeader(filterLayout, "Kräuter & Erze (Zusatz-Spawns)")
		RegisterBool(
			filterCat, "FARMRADAR3D_OPT_HERB_SPAWNS", "showHerbSpawns", "Bekannte Kräuter-Spawns überlagern (QuestieDB)",
			"Hinweis: Echte gespawnte Kräuter siehst du über die gelben Live-Dots der Minimap. Diese Option blendet zusätzlich alle bekannten Spawnpunkte aus QuestieDB + selbst gesammelte Nodes (inkl. Cooldown-Abdunklung) ein.",
			ApplyOverlayChange
		)
		RegisterBool(
			filterCat, "FARMRADAR3D_OPT_ORE_SPAWNS", "showOreSpawns", "Bekannte Erz-Spawns überlagern (QuestieDB)",
			"Hinweis: Echte gespawnte Erzadern siehst du über die gelben Live-Dots der Minimap. Diese Option blendet zusätzlich alle bekannten Spawnpunkte aus QuestieDB + selbst abgebaute Nodes ein.",
			ApplyOverlayChange
		)
		RegisterSlider(
			filterCat, "FARMRADAR3D_OPT_GATHER_CD", "gatherCooldown", "Abgebaut-Cooldown-Ausblendung (Sekunden)",
			60, 600, 30, function(v) return string.format("%ds", v) end,
			"Dunkelt bekannte Kräuter-/Erz-Spawns nach dem Sammeln vorübergehend ab.",
			nil
		)

		AddSectionHeader(filterLayout, "Minimap-Dienste (Rep / Mail / Bank / Lehrer)")
		RegisterBool(
			filterCat, "FARMRADAR3D_OPT_HIGHLIGHT_SERVICES", "highlightActiveServices", "Aktive Minimap-Dienste klar hervorheben",
			"Zeigt NPCs und Briefkästen für deine aktuell in der Minimap angehakten Tracking-Dienste zusätzlich mit deutlichen Icons auf dem HUD.",
			ApplyOverlayChange
		)

		-- 3. Minimap-Tracking (Live-Sync)
		local trackCat, trackLayout = Settings.RegisterVerticalLayoutSubcategory(mainCat, "Minimap-Tracking")
		Options.trackingCategory = trackCat

		AddSectionHeader(trackLayout, "Live-Synchronisation mit Blizzard-Minimap-Tracking")
		for _, def in ipairs(ns.SERVICE_TRACKING) do
			local varName = "FARMRADAR3D_TRACK_" .. def.key
			local setting = Settings.RegisterProxySetting(
				trackCat,
				varName,
				Settings.VarType.Boolean,
				def.label,
				false,
				function()
					return Sources.IsServiceTrackingActive(def.key)
				end,
				function(val)
					local changed = Sources.SetTrackingActive(def.key, val)
					if not changed then
						NotifySettingNextFrame(varName)
					else
						ApplyOverlayChange()
					end
				end
			)
			Settings.CreateCheckbox(
				trackCat,
				setting,
				"Schaltet den Minimap-Tracking-Filter '" .. def.label .. "' direkt im Spiel um und synchronisiert das Radar-Overlay."
			)
			trackingVars[#trackingVars + 1] = varName
		end

		AddButtonRow(
			trackLayout,
			"Tracking-Status aktualisieren",
			"Neu einlesen",
			function()
				Sources.RefreshTracking()
				Options.NotifyTracking()
				Core.Print("Blizzard Minimap-Tracking neu eingelesen.")
			end,
			"Liest alle aktiven Haken der Minimap neu aus."
		)
	end

	Options.initialized = true
end

function Options.NotifyHUDState()
	NotifySetting("FARMRADAR3D_OPT_HUD_ACTIVE")
	NotifySetting("FARMRADAR3D_OPT_DRAG_UNLOCKED")
end

function Options.NotifyPosition()
	NotifySetting("FARMRADAR3D_OPT_OFFSET_X")
	NotifySetting("FARMRADAR3D_OPT_OFFSET_Y")
	NotifySetting("FARMRADAR3D_OPT_DRAG_UNLOCKED")
end

function Options.NotifyTracking()
	for _, varName in ipairs(trackingVars) do
		NotifySetting(varName)
	end
end

function Options.NotifyAll()
	for _, varName in ipairs(registeredVars) do
		NotifySetting(varName)
	end
	Options.NotifyTracking()
end

function Options.OpenCategory(cat)
	if InCombatLockdown and InCombatLockdown() then
		Core.Print("Einstellungsfenster kann im Kampf nicht geöffnet werden (/fr3d, /fr3d bg, /fr3d move funktionieren weiter).", true)
		return
	end
	local target = cat or Options.mainCategory
	if not (target and Settings and Settings.OpenToCategory) then
		Core.Print("Blizzard Settings-Menü ist in diesem Client nicht verfügbar.", true)
		return
	end
	local id = target:GetID()
	pcall(Settings.OpenToCategory, id)
	pcall(Settings.OpenToCategory, id)
end

function Options.Open()
	Options.OpenCategory(Options.mainCategory)
end
