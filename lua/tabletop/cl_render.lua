-- Tarotarot Tabletop: client-side card rendering and hover detection.

local cfg = TT.Config
local CS = 0.1 -- 3D2D scale for cards (10 px per unit)
local PW, PH = cfg.CardW / CS, cfg.CardH / CS -- card size in pixels (240 x 360)

surface.CreateFont("TT_CardNum",   { font = "Roboto", size = 44, weight = 900 })
surface.CreateFont("TT_CardTitle", { font = "Roboto", size = 30, weight = 800 })
surface.CreateFont("TT_CardBack",  { font = "Roboto", size = 40, weight = 900 })
surface.CreateFont("TT_Counter",   { font = "Roboto", size = 30, weight = 900 })
surface.CreateFont("TT_Zone",      { font = "Roboto", size = 32, weight = 700 })
surface.CreateFont("TT_HUD",       { font = "Roboto", size = 18, weight = 600 })
surface.CreateFont("TT_HUDTitle",  { font = "Roboto", size = 22, weight = 800 })

local EDGE = Color(240, 234, 216)
local SHADE = Color(0, 0, 0, 160)
local WHITE = Color(255, 255, 255)
local HIGHLIGHT = Color(255, 220, 60)
local FALLBACK_DECK = { faceColor = Color(60, 60, 70), backColor = Color(30, 30, 40), accent = WHITE, backText = "", cards = {} }

local materials = {}
local function getMaterial(path)
	materials[path] = materials[path] or Material(path, "smooth mips")
	return materials[path]
end

local wrapCache = {}
local function wrapText(text, font, maxW)
	local key = font .. "\0" .. text
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

function TT.GetCardData(card)
	local deck = TT.Decks[card:GetDeckName()] or FALLBACK_DECK
	return deck, card:IsFaceUp() and deck.cards[card:GetFaceId()] or nil
end

local function drawFace(deck, data, x, y)
	draw.RoundedBox(18, x, y, PW, PH, EDGE)
	draw.RoundedBox(12, x + 10, y + 10, PW - 20, PH - 20, data.color or deck.faceColor)

	if data.material then
		surface.SetMaterial(getMaterial(data.material))
		surface.SetDrawColor(255, 255, 255)
		surface.DrawTexturedRect(x + 10, y + 10, PW - 20, PH - 20)
	else
		surface.SetDrawColor(deck.accent)
		surface.DrawOutlinedRect(x + 20, y + 20, PW - 40, PH - 40, 3)
		draw.RoundedBox(50, x + PW / 2 - 50, y + PH / 2 - 80, 100, 100, Color(255, 255, 255, 35))
		if data.num then
			draw.SimpleText(data.num, "TT_CardNum", x + PW / 2, y + 60, deck.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	-- Title band
	local lines = wrapText(data.name or "?", "TT_CardTitle", PW - 40)
	local bandH = 20 + #lines * 30
	draw.RoundedBox(0, x + 10, y + PH - 30 - bandH, PW - 20, bandH, SHADE)
	for i, line in ipairs(lines) do
		draw.SimpleText(line, "TT_CardTitle", x + PW / 2, y + PH - 30 - bandH + 10 + (i - 1) * 30, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end

local function drawBack(deck, x, y)
	draw.RoundedBox(18, x, y, PW, PH, EDGE)
	draw.RoundedBox(12, x + 10, y + 10, PW - 20, PH - 20, deck.backColor)
	surface.SetDrawColor(deck.accent)
	surface.DrawOutlinedRect(x + 22, y + 22, PW - 44, PH - 44, 3)
	surface.DrawOutlinedRect(x + 34, y + 34, PW - 68, PH - 68, 1)
	draw.SimpleText(deck.backText, "TT_CardBack", x + PW / 2, y + PH / 2, deck.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function drawCounters(card, x, y)
	local cy = y + 18
	for i, kind in ipairs(TT.CounterTypes) do
		local n = card:GetCounter(i)
		if n > 0 then
			draw.RoundedBox(26, x + 16, cy, 52, 52, Color(0, 0, 0, 200))
			draw.RoundedBox(23, x + 19, cy + 3, 46, 46, kind.color)
			draw.SimpleTextOutlined(n, "TT_Counter", x + 42, cy + 26, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
			cy = cy + 58
		end
	end
end

-- Draw a card with its top-left corner at x, y (in pixels).
function TT.DrawCardSurface(card, x, y, highlight)
	local deck, data = TT.GetCardData(card)
	if data then drawFace(deck, data, x, y) else drawBack(deck, x, y) end
	drawCounters(card, x, y)
	if highlight then
		surface.SetDrawColor(HIGHLIGHT)
		surface.DrawOutlinedRect(x - 4, y - 4, PW + 8, PH + 8, 6)
	end
end

function TT.DrawCard3D(card)
	local ang = card:GetAngles()
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
