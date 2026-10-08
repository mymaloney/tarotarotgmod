-- Tarotarot Tabletop: configuration.
-- Table-local coordinates: origin is the centre of the table on the floor,
-- +X runs along the long edge, seat 1 is on the -Y side, seat 2 on +Y.

TT.Config = {
	-- Card size in world units (3:5, matching the card art). Width runs along the card's local X.
	CardW = 24,
	CardH = 40,
	CardThick = 0.4,      -- height of each card in a pile
	RowStep = 0.15,       -- height step between overlapping cards in a row
	SurfaceOffset = 0.5,  -- how far cards sit above the table top
	HoldHeight = 4,       -- how far a held card floats above the table
	Reach = 400,          -- max distance you can interact with a table from

	-- Table dimensions
	TableW = 360,
	TableD = 290,
	TableHeight = 34,
	TableColor = Color(92, 60, 38),
	LegColor = Color(60, 38, 24),
	FeltColor = Color(28, 84, 52),

	-- Spacing between slots in grid zones
	SlotX = 30,
	SlotY = 46,

	MaxCounter = 99,
	DefaultDeck = "tarotarot",
}

-- Counter types that can be placed on cards (one NetworkVar each).
-- Shift+LMB / Shift+RMB add the first / second; Alt removes them.
TT.CounterTypes = {
	{ name = "Generic", color = Color(240, 200, 40) },
	{ name = "Silence", color = Color(150, 150, 175) },
}

-- Fixed zones on the table.
--   kind = "grid": cols x rows slots, one card per slot (Past/Present/Future).
--   kind = "pile": cards stack on one spot. faceDown turns cards placed there
--                  face down. E shuffles it.
--   kind = "row":  any number of cards fanned out left to right; every card
--                  can be picked up. width sets how much table it may use.
--   kind = "hand": drop target for a seat's hidden hand. The cards themselves
--                  only exist on their owner's screen.
--   yaw:        cards in this zone face that seat's player (0 = seat 1, 180 = seat 2).
--   startDeck:  deck spawned (face down, shuffled) into this zone on setup.
--   labelInside: draw the zone name inside the zone instead of beside it.
local function seatZones(seat)
	local m = seat == 1 and 1 or -1 -- seat 2 is seat 1 mirrored through the centre
	local yaw = seat == 1 and 0 or 180
	local function at(x, y) return Vector(x * m, y * m, 0) end
	local p = "p" .. seat .. "_"
	return {
		{ id = p .. "past",    name = "Past",    kind = "grid", cols = 1, rows = 1, pos = at(-35, -48), yaw = yaw, seat = seat },
		{ id = p .. "present", name = "Present", kind = "grid", cols = 1, rows = 1, pos = at(0, -48),   yaw = yaw, seat = seat },
		{ id = p .. "future",  name = "Future",  kind = "grid", cols = 1, rows = 1, pos = at(35, -48),  yaw = yaw, seat = seat },
		{ id = p .. "deck",    name = "Deck",    kind = "pile", faceDown = true, pos = at(85, -48), yaw = yaw, seat = seat,
		  startDeck = TT.Config.DefaultDeck },
		{ id = p .. "memory",  name = "Memory",  kind = "row", width = 110, pos = at(-115, -48), yaw = yaw, seat = seat },
		{ id = p .. "hand",    name = "Hand",    kind = "hand", width = 200, pos = at(0, -105),  yaw = yaw, seat = seat },
	}
end

TT.Zones = {}
for seat = 1, 2 do
	for _, zone in ipairs(seatZones(seat)) do TT.Zones[#TT.Zones + 1] = zone end
end
TT.Zones[#TT.Zones + 1] = { id = "out", name = "Out of Game", kind = "row", width = 200, pos = Vector(0, 0, 0), yaw = 0, labelInside = true }
