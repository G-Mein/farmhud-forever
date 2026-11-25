# CHANGELOG - FarmRadar3D

## [1.0.0] - 2026-11-24
### Added
- Erstveroeffentlichung fuer WoW Forever 1.60.1.71037 (Interface 16001) als eigenstaendiges Live-Minimap-HUD im FarmHud-Stil.
- Minimap-HUD-Engine (Hud.lua) mit einmaligem Voll-Snapshot/Restore, stufenloser Hintergrund-Ausblendung (bgFade 0..100%), Dot-Skalierung (dotScale 1.0..2.4x) bei kompensierter Groesse, Click-Through, Maus-Drag + X/Y-Versatz, Instanz-Auto-Pause, Steuerleiste und Combat-Lockdown-Queue.
- Sibling-Overlay-Engine (Overlay.lua) mit HBD-genauer Welt-zu-Radar-Projektion, rotierendem N/O/S/W-Kompass, Entfernungsringen, Fadenkreuz und 80 gepoolten Pin-Frames.
- Datenquellen-Adapter (Sources.lua, Data.lua) fuer Questie/Blizzard-Questziele, berufsgesteuerte Kuerschner-Leichenmarker (GetProfessions/GetProfessionInfo + Loot/Spell-Events + gelernte Spots), C_Minimap-Tracking-Live-Sync + Dienste-Hervorhebung (Questie Townsfolk / LibQuestieDB NpcDB + Mailboxes) sowie optionale verifizierte Classic/Forever Herb-/Ore-Spawns aus LibQuestieDB inkl. Auto-Lernen und Cooldown-Fade.
- Native Blizzard Settings (Options.lua), Tastaturbelegung (Bindings.xml), Slash-Befehle (/fr3d, /farmradar), Addon Compartment, stationaerer Minimap-Button an MinimapCluster (Winkel 260) und Custom-Artwork (FarmRadar3D.png, logo.tga, disc.tga, ring.tga, circle_mask.tga, dot.tga).
