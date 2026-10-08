-- Tarotarot Tabletop: the local player's hidden hand (contents arrive only
-- for seats you own), selection with the mouse wheel, and its HUD strip.
-- In solo games you own several seats; the strip shows the hand zone you're
-- pointing at, or the seat whose decision it is.

TT.Hand = TT.Hand or { bySeat = {} } -- { table = ent, bySeat = { [seat] = cards } }
TT.HandSel = TT.HandSel or 1

local function sendSelection()
	net.Start("tt_handsel")
	net.WriteUInt(TT.HandSel, 8)
	net.SendToServer()
end

net.Receive("tt_hand", function()
	local tbl, seat, n = net.ReadEntity(), net.ReadUInt(3), net.ReadUInt(8)
	local cards = {}
	for i = 1, n do
		cards[i] = { deck = net.ReadString(), id = net.ReadUInt(16) }
	end
	if TT.Hand.table ~= tbl then TT.Hand = { table = tbl, bySeat = {} } end
	if seat == 0 then
		TT.Hand.bySeat = {} -- left the table
	else
		TT.Hand.bySeat[seat] = cards
	end
	TT.HandSel = math.Clamp(TT.HandSel, 1, math.max(#TT.ActiveHand(), 1))
	sendSelection()
end)

-- The cards in one of my seats' hands at this table (empty if not mine).
function TT.HandCards(tbl, seat)
	if IsValid(tbl) and TT.Hand.table == tbl then return TT.Hand.bySeat[seat] or {} end
	return {}
end

-- Which of my seats the hand strip shows: the hand zone I'm pointing at (the
-- one a click takes from), else the seat whose decision it is, else my first seat.
function TT.ActiveHandSeat()
	local bySeat = TT.Hand.bySeat
	local zone = TT.GetZone(TT.HoverZone)
	if zone and zone.kind == "hand" and bySeat[zone.seat] then return zone.seat end
	local d = TT.Decision
	if d and d.table == TT.Hand.table and bySeat[d.seat] then return d.seat end
	local first
	for seat in pairs(bySeat) do
		if not first or seat < first then first = seat end
	end
	return first
end

function TT.ActiveHand()
	local seat = TT.ActiveHandSeat()
	return seat and TT.Hand.bySeat[seat] or {}, seat
end

local lastSeat
hook.Add("Think", "TT_HandSeat", function()
	-- Keep the selection in range when the strip switches seats
	local cards, seat = TT.ActiveHand()
	if seat ~= lastSeat then
		lastSeat = seat
		TT.HandSel = math.Clamp(TT.HandSel, 1, math.max(#cards, 1))
		if IsValid(TT.Hand.table) then sendSelection() end
	end
end)

function TT.HandCardData(entry)
	local deck = TT.Decks[entry.deck]
	return deck, deck and deck.cards[entry.id]
end

-- Mouse wheel picks a hand card while the Card Hand is out and you hold cards.
hook.Add("PlayerBindPress", "TT_HandSelect", function(ply, bind, pressed)
	if not pressed then return end
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "tt_cardtool" then return end
	local n = #TT.ActiveHand()
	if n == 0 or not IsValid(TT.Hand.table) then return end

	local dir = bind:find("invnext", 1, true) and 1 or bind:find("invprev", 1, true) and -1
	if not dir then return end
	TT.HandSel = (TT.HandSel - 1 + dir) % n + 1
	sendSelection()
	return true
end)

local SELECTED = Color(255, 220, 60)

-- Your hand along the bottom of the screen; the selected card is raised.
function TT.DrawHand()
	local cards, seat = TT.ActiveHand()
	if not IsValid(TT.Hand.table) then return end
	local n = #cards
	if n == 0 then return end

	local h = math.floor(ScrH() * 0.2)
	local w = math.floor(h * TT.Config.CardW / TT.Config.CardH)
	local maxW = ScrW() * 0.5
	local step = n > 1 and math.min(w + 8, (maxW - w) / (n - 1)) or 0
	local total = w + step * (n - 1)
	local x0, y0 = (ScrW() - total) / 2, ScrH() - h * 0.75

	local sel = math.Clamp(TT.HandSel, 1, n)
	for i, entry in ipairs(cards) do
		if i ~= sel then
			local deck, data = TT.HandCardData(entry)
			TT.DrawCardFace(deck, data, x0 + (i - 1) * step, y0, w, h)
		end
	end
	-- Selected card last so it sits on top of its neighbours
	local x, y = x0 + (sel - 1) * step, y0 - h * 0.2
	local deck, data = TT.HandCardData(cards[sel])
	TT.DrawCardFace(deck, data, x, y, w, h)
	surface.SetDrawColor(SELECTED)
	surface.DrawOutlinedRect(x - 3, y - 3, w + 6, h + 6, 3)
	local mySeats = 0
	for _ in pairs(TT.Hand.bySeat) do mySeats = mySeats + 1 end
	local label = sel .. " / " .. n .. (mySeats > 1 and ("   (seat " .. seat .. ")") or "")
	draw.SimpleTextOutlined(label, "TT_HUD", x + w / 2, y - 8, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
end
