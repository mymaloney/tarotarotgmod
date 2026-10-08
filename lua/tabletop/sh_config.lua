-- Tarotarot Tabletop: configuration.
-- Table-local coordinates: origin is the centre of the table on the floor,
-- +X runs along the long edge, Player 1 sits on the -Y side, Player 2 on +Y.

TT.Config = {
	-- Card size in world units (2:3 ratio). Width runs along the card's local X.
	CardW = 24,
	CardH = 36,
	CardThick = 0.4,      -- height of each card in a pile
	SurfaceOffset = 0.5,  -- how far cards sit above the table top
	HoldHeight = 4,       -- how far a held card floats above the table
	Reach = 400,          -- max distance you can interact with a table from

	-- Table dimensions
	TableW = 360,
	TableD = 230,
	TableHeight = 34,
	TableColor = Color(92, 60, 38),
	LegColor = Color(60, 38, 24),
	FeltColor = Color(28, 84, 52),

	-- Spacing between slots in grid zones (wide enough for a rotated card)
	SlotX = 40,
	SlotY = 42,

	MaxCounter = 99,
	DefaultDeck = "tarot_major",
}

-- Counter types that can be placed on cards (max 4, one NetworkVar each).
TT.CounterTypes = {
	{ name = "Generic", color = Color(240, 200, 40) },
	{ name = "Damage",  color = Color(220, 50, 50) },
	{ name = "Shield",  color = Color(60, 140, 240) },
	{ name = "Charge",  color = Color(170, 80, 220) },
}

-- Fixed zones on the table.
--   kind = "pile": cards stack on one spot (deck, discard). E shuffles it.
--   kind = "grid": cols x rows slots, one card per slot.
--   yaw:       cards in this zone face the owner (0 = P1, 180 = P2).
--   startDeck: deck spawned (face down, shuffled) into this zone on setup.
TT.Zones = {
	{ id = "p1_field",   name = "Field",   kind = "grid", pos = Vector(-30, -55, 0), yaw = 0, cols = 5, rows = 2 },
	{ id = "p1_deck",    name = "Deck",    kind = "pile", pos = Vector(100, -55, 0), yaw = 0, startDeck = TT.Config.DefaultDeck },
	{ id = "p1_discard", name = "Discard", kind = "pile", pos = Vector(140, -55, 0), yaw = 0 },

	{ id = "p2_field",   name = "Field",   kind = "grid", pos = Vector(30, 55, 0),    yaw = 180, cols = 5, rows = 2 },
	{ id = "p2_deck",    name = "Deck",    kind = "pile", pos = Vector(-100, 55, 0),  yaw = 180, startDeck = TT.Config.DefaultDeck },
	{ id = "p2_discard", name = "Discard", kind = "pile", pos = Vector(-140, 55, 0),  yaw = 180 },
}
