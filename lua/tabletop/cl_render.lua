-- Tarotarot Tabletop: client-side card rendering and hover detection.

local cfg = TT.Config
local CS = 0.1 -- 3D2D scale for cards (10 px per unit)
local PW, PH = cfg.CardW / CS, cfg.CardH / CS -- card size in pixels (240 x 400)

surface.CreateFont("TT_CardTitle", { font = "Roboto", size = 30, weight = 800 })
surface.CreateFont("TT_Counter",   { font = "Roboto", size = 30, weight = 900 })
surface.CreateFont("TT_Zone",      { font = "Roboto", size = 32, weight = 700 })
surface.CreateFont("TT_HUD",       { font = "Roboto", size = 18, weight = 600 })
surface.CreateFont("TT_HUDTitle",  { font = "Roboto", size = 22, weight = 800 })
surface.CreateFont("TT_HUDText",   { font = "Roboto", size = 20, weight = 500 })

local WHITE = Color(255, 255, 255)
local HIGHLIGHT = Color(255, 220, 60)
local PLACEHOLDER = Color(60, 60, 70)

local wrapCache = {}
function TT.WrapText(text, font, maxW)
	local key = font .. "\0" .. maxW .. "\0" .. text
	if wrapCache[key] then return wrapCache[key] end

	surface.SetFont(font)
	local lines, cur = {}, ""
	for word in string.gmatch(text, "%S+") do
		local try = cur == "" and word or (cur .. " " .. word)
		if cur ~= "" and surface.GetTextSize(try) > maxW then
			lines[#lines + 1] = cur
			cur = word
		else
			cur = try
		end
	end
	if cur ~= "" then lines[#lines + 1] = cur end
	wrapCache[key] = lines
	return lines
end

local sheets = {}
local function sheetMaterial(i)
	sheets[i] = sheets[i] or Material(TT.Atlas.sheets[i])
	return sheets[i]
end

-- Draw an image from the atlas into a w x h rectangle, turned 180 degrees if
-- flip is set. Returns false if the image isn't in the atlas.
local function drawAtlasImage(image, x, y, w, h, flip)
	local cell = image and TT.Atlas.cells[image]
	if not cell then return false end

	local a = TT.Atlas
	local col, row = cell[2] % a.cols, math.floor(cell[2] / a.cols)
	local u0 = (col * a.cellW + (a.cellW - a.imgW) / 2) / a.sheetSize
	local v0 = (row * a.cellH + (a.cellH - a.imgH) / 2) / a.sheetSize
	surface.SetMaterial(sheetMaterial(cell[1]))
	surface.SetDrawColor(255, 255, 255)
	local u1, v1 = u0 + a.imgW / a.sheetSize, v0 + a.imgH / a.sheetSize
	if flip then u0, v0, u1, v1 = u1, v1, u0, v0 end
	surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)
	return true
end

-- Face-down cards this player is allowed to see, by card serial -> card index.
TT.Peeks = TT.Peeks or {}

net.Receive("tt_peek", function()
	local serial, id = net.ReadUInt(32), net.ReadUInt(16)
	TT.Peeks[serial] = id > 0 and id or nil
end)

-- deck, card data (nil if hidden), and whether it's only visible via a peek.
-- Peeks are only used when allowPeek is set (the HUD, never the shared world).
function TT.GetCardData(card, allowPeek)
	local deck = TT.Decks[card:GetDeckName()]
	if not deck then return end
	if card:IsFaceUp() then return deck, deck.cards[card:GetFaceId()], false end
	local peek = allowPeek and TT.Peeks[card:GetSerial()]
	if peek then return deck, deck.cards[peek], true end
	return deck, nil, false
end

-- Fallback for cards without art: a plain card with the name on it.
local function drawPlaceholder(text, x, y, w, h)
	draw.RoundedBox(12, x, y, w, h, PLACEHOLDER)
	local lines = TT.WrapText(text, "TT_CardTitle", w - 30)
	for i, line in ipairs(lines) do
		draw.SimpleText(line, "TT_CardTitle", x + w / 2, y + h / 2 + (i - (#lines + 1) / 2) * 30, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

-- Draw a card face from deck data, or the deck's back if data is nil.
function TT.DrawCardFace(deck, data, x, y, w, h, flip)
	if data then
		if not drawAtlasImage(data.image, x, y, w, h, flip) then drawPlaceholder(data.name, x, y, w, h) end
	elseif not drawAtlasImage(deck and deck.back, x, y, w, h, flip) then
		drawPlaceholder("", x, y, w, h)
	end
end

local COUNTER_BG = Color(0, 0, 0, 200)

-- Counter chips down the card's left edge (as seen by the card's owner).
local function drawCounters(card, x, y, scale)
	local size = math.floor(52 * scale)
	local cy = y + 18 * scale
	for i, kind in ipairs(TT.CounterTypes) do
		local n = card:GetCounter(i)
		if n > 0 then
			draw.RoundedBox(size / 2, x + 16 * scale, cy, size, size, COUNTER_BG)
			draw.RoundedBox(size / 2 - 3, x + 16 * scale + 3, cy + 3, size - 6, size - 6, kind.color)
			draw.SimpleTextOutlined(n, "TT_Counter", x + 16 * scale + size / 2, cy + size / 2, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
			cy = cy + size + 6 * scale
		end
	end
end

-- Draw a card at x, y (in pixels), PW x PH unless a size is given. A reversed
-- card's art is drawn upside down; counters always stay upright.
function TT.DrawCardSurface(card, x, y, highlight, w, h, allowPeek)
	w, h = w or PW, h or PH
	local deck, data, peeked = TT.GetCardData(card, allowPeek)
	TT.DrawCardFace(deck, data, x, y, w, h, card:GetReversed())
	if peeked then
		-- Dim it so it's obvious other players see the back
		surface.SetDrawColor(0, 0, 40, 110)
		surface.DrawRect(x, y, w, h)
	end
	drawCounters(card, x, y, w / PW)
	if highlight then
		surface.SetDrawColor(HIGHLIGHT)
		surface.DrawOutlinedRect(x - 4, y - 4, w + 8, h + 8, 6)
	end
end

function TT.DrawCard3D(card)
	-- Draw in the owner's upright frame; the art is flipped when reversed
	local ang = card:GetAngles()
	if card:GetReversed() then ang:RotateAroundAxis(ang:Up(), 180) end
	cam.Start3D2D(card:GetPos() + ang:Up() * 0.05, ang, CS)
		TT.DrawCardSurface(card, -PW / 2, -PH / 2, TT.HoverCard == card or IsValid(card:GetHolder()))
	cam.End3D2D()
end

TT.CardPixelSize = { PW, PH }

-- Work out what the local player is pointing at while holding the card hand.
hook.Add("Think", "TT_Hover", function()
	TT.HoverCard, TT.HoverTable, TT.HoverZone = nil, nil, nil

	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "tt_cardtool" then return end

	local tbl, hit = TT.FindTable(ply)
	if not tbl then return end
	local zone = TT.ZoneAt(hit)
	TT.HoverTable, TT.HoverZone = tbl, zone and zone.id
	if not IsValid(wep:GetHeldCard()) then
		TT.HoverCard = TT.TraceCard(tbl, ply)
	end
end)
