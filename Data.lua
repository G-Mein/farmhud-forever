local _, ns = ...

ns.MAX_PINS = 80

ns.DEFAULTS = {
	hudActive = false,
	restoreOnLogin = false,
	hudSize = 420,
	dotScale = 1.45,
	bgFade = 85,
	backdropAlpha = 28,
	showRings = true,
	ringCount = 3,
	showCompass = true,
	showCrosshair = true,
	showControlBar = true,
	autoRotate = true,
	clickThrough = true,
	hideInInstance = false,
	offsetX = 0,
	offsetY = 0,
	dragUnlocked = false,
	showMinimapButton = true,
	minimapAngle = 260,
	pinScale = 1.0,
	pinAlpha = 95,
	showQuestItems = true,
	showQuestObjectives = true,
	showSkinningCorpses = true,
	showLearnedSkinning = true,
	skinningCorpseDuration = 150,
	showHerbSpawns = false,
	showOreSpawns = false,
	gatherCooldown = 300,
	highlightActiveServices = true,
}

ns.OPTION_BOUNDS = {
	hudSize = { 220, 760 },
	dotScale = { 1.0, 2.4 },
	bgFade = { 0, 100 },
	backdropAlpha = { 0, 85 },
	ringCount = { 1, 3 },
	offsetX = { -600, 600 },
	offsetY = { -400, 400 },
	pinScale = { 0.6, 1.8 },
	pinAlpha = { 20, 100 },
	skinningCorpseDuration = { 60, 300 },
	gatherCooldown = { 60, 600 },
}

-- Fallback-Zoomdurchmesser (in Yards) aus HereBeDragons Classic/Forever,
-- falls C_Minimap.GetViewRadius() nicht verfuegbar ist.
ns.MINIMAP_ZOOM_DIAMETERS = {
	indoor = {
		[0] = 300,
		[1] = 240,
		[2] = 180,
		[3] = 120,
		[4] = 80,
		[5] = 50,
	},
	outdoor = {
		[0] = 466 + 2 / 3,
		[1] = 400,
		[2] = 333 + 1 / 3,
		[3] = 266 + 2 / 3,
		[4] = 200,
		[5] = 133 + 1 / 3,
	},
}

ns.PIN_COLORS = {
	quest_item = { 1.00, 0.86, 0.18 },
	quest_obj = { 0.98, 0.62, 0.16 },
	skin_corpse = { 1.00, 0.42, 0.20 },
	skin_spot = { 0.86, 0.68, 0.42 },
	herb = { 0.25, 0.94, 0.48 },
	ore = { 0.35, 0.82, 1.00 },
	service = { 0.50, 0.85, 1.00 },
}

ns.TEX_DOT = "Interface\\AddOns\\FarmRadar3D\\Textures\\dot"
ns.TEX_DISC = "Interface\\AddOns\\FarmRadar3D\\Textures\\disc"
ns.TEX_RING = "Interface\\AddOns\\FarmRadar3D\\Textures\\ring"
ns.TEX_MASK = "Interface\\AddOns\\FarmRadar3D\\Textures\\circle_mask"
ns.TEX_LOGO = "Interface\\AddOns\\FarmRadar3D\\logo"

ns.ICON_SKINNING = "Interface\\Icons\\inv_misc_pelt_wolf_01"
ns.ICON_HERB = "Interface\\Icons\\trade_herbalism"
ns.ICON_ORE = "Interface\\Icons\\trade_mining"

-- Verifizierte Classic- & Forever-Kraeuter-Objekt-IDs aus QuestieDB_Forever.toc.
ns.HERB_OBJECT_IDS = {
	1617, 1618, 1619, 1620, 1621, 1622, 1623, 1624, 1628,
	2041, 2042, 2043, 2044, 2045, 2046, 2866,
	3724, 3725, 3726, 3727, 3729, 3730,
	142140, 142141, 142142, 142143, 142144, 142145,
	176583, 176584, 176586, 176587, 176588, 176589,
	176636, 176637, 176638, 176639, 176640, 176641, 176642,
	180164, 180165, 180166, 180167, 180168, 183046,
	656160, 656161, 657380, 657382, 657383, 657384, 657385,
	657386, 657387, 657388, 657389, 657390, 657391, 657392,
	657393, 657394, 657395, 657396, 657397, 657398, 657399,
	657400, 657401, 657402, 657403, 657404, 657405, 657406,
	657408, 657409, 657455, 657456, 657457, 657458, 657459,
	657460, 657461, 657462, 657463, 657464, 657465, 657466,
	657467, 657468,
}

-- Verifizierte Classic- & Forever-Erz-Objekt-IDs aus QuestieDB_Forever.toc.
ns.ORE_OBJECT_IDS = {
	324, 1610, 1667, 1731, 1732, 1733, 1734, 1735,
	2040, 2047, 2054, 2055, 2653, 3763, 3764, 19903,
	73939, 73940, 73941, 103711, 103713, 105569,
	123309, 123310, 123848, 150079, 150080, 150081, 150082,
	165658, 175404, 176643, 176645, 177388, 180215,
	181068, 181069, 181108, 181109, 181248, 181249,
	422911, 439558, 439628, 439778, 562111, 566779, 613761, 613764,
}

-- Verifizierte Briefkasten-Objekt-IDs aus Questie Townsfolk Mailboxes (Classic/Forever).
ns.MAILBOX_OBJECT_IDS = {
	32349, 142075, 142089, 142093, 142094, 142095, 142102, 142103, 142109, 142110,
	142111, 142117, 142119, 143981, 143982, 143983, 143984, 143985, 143986, 143987,
	143988, 143989, 143990, 144011, 144112, 144125, 144126, 144127, 144128, 144129,
	144131, 153578, 153716, 157637, 163313, 163645, 164618, 164840, 171556, 171699,
	171752, 173047, 173221, 176319, 176324, 176404, 177044, 178864, 179895, 179896,
	180451, 181236, 181639, 187260, 188123,
}

ns.SERVICE_TRACKING = {
	{
		key = "REPAIR",
		globalKey = "MINIMAP_TRACKING_REPAIR",
		label = "Reparatur",
		npcFlagKey = "REPAIR",
		townsfolkKey = "Repair",
		color = { 0.35, 0.80, 1.00 },
		icon = "Interface\\Minimap\\tracking\\repair",
		keywords = { "repair", "reparat" },
	},
	{
		key = "MAILBOX",
		globalKey = "MINIMAP_TRACKING_MAILBOX",
		label = "Briefkasten",
		isMailbox = true,
		townsfolkKey = "Mailbox",
		color = { 0.96, 0.82, 0.24 },
		icon = "Interface\\Minimap\\tracking\\mailbox",
		keywords = { "mail", "briefkasten", "post" },
	},
	{
		key = "BANKER",
		globalKey = "MINIMAP_TRACKING_BANKER",
		label = "Bankier",
		npcFlagKey = "BANKER",
		townsfolkKey = "Banker",
		color = { 1.00, 0.84, 0.20 },
		icon = "Interface\\Minimap\\tracking\\banker",
		keywords = { "bank" },
	},
	{
		key = "AUCTIONEER",
		globalKey = "MINIMAP_TRACKING_AUCTIONEER",
		label = "Auktionshaus",
		npcFlagKey = "AUCTIONEER",
		townsfolkKey = "Auctioneer",
		color = { 0.95, 0.72, 0.18 },
		icon = "Interface\\Minimap\\tracking\\auctioneer",
		keywords = { "auction", "auktion" },
	},
	{
		key = "FLIGHTMASTER",
		globalKey = "MINIMAP_TRACKING_FLIGHTMASTER",
		label = "Flugmeister",
		npcFlagKey = "FLIGHT_MASTER",
		townsfolkKey = "Flight Master",
		color = { 0.40, 0.92, 0.96 },
		icon = "Interface\\Minimap\\tracking\\flightmaster",
		keywords = { "flight", "flug" },
	},
	{
		key = "INNKEEPER",
		globalKey = "MINIMAP_TRACKING_INNKEEPER",
		label = "Gastwirt",
		npcFlagKey = "INNKEEPER",
		townsfolkKey = "Innkeeper",
		color = { 0.55, 0.92, 0.55 },
		icon = "Interface\\Minimap\\tracking\\innkeeper",
		keywords = { "innkeeper", "gastwirt" },
	},
	{
		key = "STABLEMASTER",
		globalKey = "MINIMAP_TRACKING_STABLEMASTER",
		label = "Stallmeister",
		npcFlagKey = "STABLEMASTER",
		townsfolkKey = "Stable Master",
		color = { 0.85, 0.72, 0.50 },
		icon = "Interface\\Minimap\\tracking\\stablemaster",
		keywords = { "stable", "stall" },
	},
	{
		key = "BATTLEMASTER",
		globalKey = "MINIMAP_TRACKING_BATTLEMASTER",
		label = "Kampfmeister",
		npcFlagKey = "BATTLEMASTER",
		townsfolkKey = "Battlemaster",
		color = { 0.95, 0.42, 0.42 },
		icon = "Interface\\Minimap\\tracking\\battlemaster",
		keywords = { "battle", "kampfmeister" },
	},
	{
		key = "TRAINER_CLASS",
		globalKey = "MINIMAP_TRACKING_TRAINER_CLASS",
		label = "Klassenlehrer",
		npcFlagKey = "TRAINER",
		townsfolkKey = "Class Trainer",
		color = { 0.72, 0.65, 1.00 },
		icon = "Interface\\Minimap\\tracking\\class",
		keywords = { "class trainer", "klassenlehrer" },
	},
	{
		key = "TRAINER_PROFESSION",
		globalKey = "MINIMAP_TRACKING_TRAINER_PROFESSION",
		label = "Berufslehrer",
		npcFlagKey = "TRAINER",
		townsfolkKey = "Profession Trainers",
		color = { 0.65, 0.80, 1.00 },
		icon = "Interface\\Minimap\\tracking\\profession",
		keywords = { "profession", "berufslehrer" },
	},
	{
		key = "VENDOR_REAGENT",
		globalKey = "MINIMAP_TRACKING_VENDOR_REAGENT",
		label = "Reagenzienhändler",
		npcFlagKey = "VENDOR",
		townsfolkKey = "Reagents",
		color = { 0.78, 0.65, 0.98 },
		icon = "Interface\\Minimap\\tracking\\reagents",
		keywords = { "reagent", "reagenz" },
	},
	{
		key = "VENDOR_FOOD",
		globalKey = "MINIMAP_TRACKING_VENDOR_FOOD",
		label = "Nahrung & Getränke",
		npcFlagKey = "VENDOR",
		townsfolkKey = "Food",
		color = { 0.75, 0.90, 0.55 },
		icon = "Interface\\Minimap\\tracking\\food",
		keywords = { "food", "drink", "speis", "getränk" },
	},
	{
		key = "VENDOR_POISON",
		globalKey = "MINIMAP_TRACKING_VENDOR_POISON",
		label = "Gifthändler",
		npcFlagKey = "VENDOR",
		townsfolkKey = "Poisons",
		color = { 0.50, 0.95, 0.35 },
		icon = "Interface\\Minimap\\tracking\\poisons",
		keywords = { "poison", "gift" },
	},
	{
		key = "VENDOR_AMMO",
		globalKey = "MINIMAP_TRACKING_VENDOR_AMMO",
		label = "Munitionshändler",
		npcFlagKey = "VENDOR",
		townsfolkKey = "Ammo",
		color = { 0.90, 0.75, 0.45 },
		icon = "Interface\\Minimap\\tracking\\ammunition",
		keywords = { "ammo", "ammunition", "munition" },
	},
	{
		key = "BARBER",
		globalKey = "MINIMAP_TRACKING_BARBER",
		label = "Friseur",
		npcFlagKey = "BARBER",
		townsfolkKey = "Barber",
		color = { 0.98, 0.72, 0.85 },
		icon = "Interface\\Minimap\\tracking\\barbershop",
		keywords = { "barber", "friseur" },
	},
	{
		key = "TRANSMOGRIFIER",
		globalKey = "MINIMAP_TRACKING_TRANSMOGRIFIER",
		label = "Transmogrifizierer",
		npcFlagKey = "TRANSMOGRIFIER",
		townsfolkKey = "Transmogrifier",
		color = { 0.85, 0.55, 1.00 },
		icon = "Interface\\Minimap\\tracking\\transmogrifier",
		keywords = { "transmog" },
	},
}

ns.SERVICE_BY_KEY = {}
for _, def in ipairs(ns.SERVICE_TRACKING) do
	ns.SERVICE_BY_KEY[def.key] = def
end

ns.GATHER_SPELLS = {
	SKINNING = {
		[8613] = true,
		[8617] = true,
		[8618] = true,
		[10768] = true,
		[32678] = true,
		[50305] = true,
		[74522] = true,
	},
	HERB = {
		[2366] = true,
		[2368] = true,
		[3570] = true,
		[11993] = true,
		[28695] = true,
		[50300] = true,
		[74519] = true,
	},
	MINING = {
		[2575] = true,
		[2576] = true,
		[3564] = true,
		[10248] = true,
		[29354] = true,
		[50310] = true,
		[74517] = true,
	},
}

ns.SKINNING_NAMES = {
	["skinning"] = true,
	["kürschnerei"] = true,
	["kuerschnerei"] = true,
	["kürschnern"] = true,
	["dépeçage"] = true,
	["desuello"] = true,
	["esfolamento"] = true,
	["scuoiatura"] = true,
	["снятие шкур"] = true,
	["무두질"] = true,
	["剥皮"] = true,
	["剝皮"] = true,
}

ns.HERB_SPELL_KEYWORDS = { "herb", "kräut", "kraeut", "cueillette", "herbor", "erbor", "трав", "약초", "草" }
ns.ORE_SPELL_KEYWORDS = { "mining", "bergbau", "minage", "minería", "minera", "горн", "채광", "采矿", "採礦" }

ns.SKINNABLE_CREATURE_TYPES = {
	["beast"] = true,
	["wildtier"] = true,
	["bête"] = true,
	["bestia"] = true,
	["fera"] = true,
	["животное"] = true,
	["야수"] = true,
	["野兽"] = true,
	["野獸"] = true,
	["dragonkin"] = true,
	["drachkin"] = true,
	["draconien"] = true,
	["dragón"] = true,
	["draconiano"] = true,
	["дракон"] = true,
	["용족"] = true,
	["龙类"] = true,
	["龍類"] = true,
}
