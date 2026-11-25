# FarmRadar3D (WoW Forever 1.60.1 / Interface 16001)

Live-Minimap-HUD im FarmHud-Stil fuer WoW Forever mit stufenloser Terrain-Ausblendung, Dot-Vergroesserung, freier Positionierung und eigenem Radar-Overlay.

## Hauptfunktionen
- Live-Minimap-HUD: Verschiebt Blizzard-Minimap nahtlos als Radar um den Charakter oder frei neben ihn und stellt beim Ausschalten die originale Minimap exakt wieder her.
- Hintergrund & Dots: Minimap-Terrain stufenlos 0..100% ausblendbar (gelbe Live-Dots bleiben voll sichtbar), Kontrast-Scheibe (0..85%), Dot-Scale (1.0..2.4x), Entfernungsringe (1..3), rotierender Kompass (N/O/S/W) und Fadenkreuz.
- Overlay-Filter: Quest-Items und aktive Quest-Ziele (Questie + Blizzard-Fallback), Kuerschnerei-Layer (automatisch nur aktiv bei erlerntem Beruf: Leichen-Timer nach Loot/Tod mit Auto-Clear nach Kuerschnern + gelernte Spots), aktive Minimap-Dienste (Reparatur, Briefkasten, Bank, Auktionshaus, Flugmeister, Gastwirt, Lehrer, Haendler) und optionale QuestieDB Herb-/Ore-Spawns inkl. Auto-Lernen und Cooldown-Abdunklung.
- Bedienung: Stationaerer Minimap-Button (Linksklick HUD, Rechtsklick Settings, Mittelklick Verschieben, Drag zum Positionieren), Addon Compartment, Keybinds (Bindings.xml), Steuerleiste und native deutsche Blizzard Settings.

## Slash-Befehle (/fr3d, /farmradar, /farmradar3d)
- `/fr3d` -> HUD ein-/ausschalten
- `/fr3d config` -> Einstellungen oeffnen
- `/fr3d bg [0..100]` -> Hintergrund umschalten oder Prozent setzen
- `/fr3d scale <1.0-2.4>` -> Dot-Scale setzen
- `/fr3d size <220-760>` -> HUD-Durchmesser in Pixeln setzen
- `/fr3d move` -> HUD zum Verschieben entsperren/sperren
- `/fr3d center` -> HUD mittig um Charakter zentrieren
- `/fr3d status` -> Status, Berufserkennung und Tracking im Chat ausgeben
- `/fr3d reset` -> Einstellungen auf Standardwerte zuruecksetzen
