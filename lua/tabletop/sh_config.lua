-- Tarotarot Tabletop: configuration.
-- Table-local coordinates: origin is the centre of the table on the floor.
-- The table is square with one seat per side. Seat 1 is on the -Y side and
-- seats go clockwise (seen from above): 1 south, 2 west, 3 north, 4 east.

TT.Config = {
	-- Card size in world units (3:5, matching the card art). Width runs along the card's local X.
	CardW = 21,
	CardH = 35,
	CardThick = 0.4,      -- height of each card in a pile
	RowStep = 0.15,       -- height step between overlapping cards in a row
	SurfaceOffset = 0.5,  -- how far cards sit above the table top
	HoldHeight = 4,       -- how far a held card floats above the table
	Reach = 600,          -- max distance you can interact with a table from

	-- Table size (TableW/TableD) is worked out below from the zone layout
	TableHeight = 34,
	TableColor = Color(92, 60, 38),
	LegColor = Color(60, 38, 24),
	FeltColor = Color(28, 84, 52),

	MaxCounter = 99,
	DefaultDeck = "tarotarot",

	-- Game setup (see docs/RULES.md)
	StartLife = 20,
	StartHand = 3,
}

-- Spacing between slots in grid zones: a card plus a small margin
TT.Config.SlotX = TT.Config.CardW + 6
TT.Config.SlotY = TT.Config.CardH + 6

-- Counter types that can be placed on cards (one NetworkVar each).
-- Shift+LMB / Shift+RMB add the first / second; Alt removes them.
TT.CounterTypes = {
	{ name = "Generic", color = Color(240, 200, 40) },
	{ name = "Silence", color = Color(150, 150, 175) },
}

TT.MaxSeats = 4

-- Fixed zones on the table.
--   kind = "grid": cols x rows slots, one card per slot (Past/Present/Future).
--   kind = "pile": cards stack on one spot. faceDown turns cards placed there
--                  face down. E draws from your own deck, Shift+E shuffles.
--   kind = "row":  any number of cards fanned out left to right; every card
--                  can be picked up. width sets how much table it may use.
--   kind = "hand": drop target for a seat's hidden hand. The cards themselves
--                  only exist on their owner's screen.
--   kind = "life": shows the seat's life total; click to change it.
--   yaw:        which way the zone faces (0 = towards seat 1's player).
--   seat:       the seat a zone belongs to (nil for shared zones).
--   labelInside: draw the zone name inside the zone instead of beside it.
--
-- Each seat, left to right from its player's view (as in the rulebook):
--   Life | Deck | Past | Present | Future | Memory, with the Hand at the edge.
do
	local cfg = TT.Config
	local zoneH = cfg.CardH + 6
	local slotW = cfg.CardW + 6
	local GAP, LABEL, EDGE = 4, 9, 5

	local row = {
		{ key = "life",    name = "Life",    kind = "life", w = slotW },
		{ key = "deck",    name = "Deck",    kind = "pile", w = slotW, faceDown = true },
		{ key = "past",    name = "Past",    kind = "grid", w = slotW, cols = 1, rows = 1 },
		{ key = "present", name = "Present", kind = "grid", w = slotW, cols = 1, rows = 1 },
		{ key = "future",  name = "Future",  kind = "grid", w = slotW, cols = 1, rows = 1 },
		{ key = "memory",  name = "Memory",  kind = "row",  w = 4 * cfg.CardW + 6 },
	}
	local rowW = -GAP
	for _, z in ipairs(row) do rowW = rowW + z.w + GAP end

	-- From the table edge inwards: hand label, hand, spread labels, spread
	local depth = EDGE + LABEL + zoneH + LABEL + GAP + zoneH
	local size = rowW + 2 * depth + 2 * GAP -- seats on adjacent sides just clear each other
	cfg.TableW, cfg.TableD = size, size

	local handY = -size / 2 + EDGE + LABEL + zoneH / 2
	local spreadY = -size / 2 + depth - zoneH / 2

	TT.Zones = {}
	for seat = 1, TT.MaxSeats do
		local yaw = ({ 0, 270, 180, 90 })[seat]
		local function at(x, y)
			local v = Vector(x, y, 0)
			v:Rotate(Angle(0, yaw, 0))
			return Vector(math.Round(v.x, 3), math.Round(v.y, 3), 0)
		end
		local p = "p" .. seat .. "_"

		local x = -rowW / 2
		for _, z in ipairs(row) do
			TT.Zones[#TT.Zones + 1] = {
				id = p .. z.key, name = z.name, kind = z.kind, seat = seat, yaw = yaw,
				pos = at(x + z.w / 2, spreadY), width = z.w, cols = z.cols, rows = z.rows,
				faceDown = z.faceDown,
			}
			x = x + z.w + GAP
		end
		TT.Zones[#TT.Zones + 1] = { id = p .. "hand", name = "Hand", kind = "hand", seat = seat, yaw = yaw,
			pos = at(0, handY), width = rowW }
	end

	TT.Zones[#TT.Zones + 1] = { id = "out", name = "Out of Game", kind = "row", yaw = 0, labelInside = true,
		pos = Vector(0, 0, 0), width = rowW - 2 * zoneH }
end
