-- Tarotarot Tabletop: the local player's hidden hand (contents arrive only
-- for the seat you own), selection with the mouse wheel, and its HUD strip.

TT.Hand = TT.Hand or { cards = {} }
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
	TT.Hand = { table = tbl, seat = seat, cards = cards }
	TT.HandSel = math.Clamp(TT.HandSel, 1, math.max(n, 1))
	sendSelection()
end)

-- My hand at this table (empty if I have no seat there).
function TT.MyHand(tbl)
	if IsValid(tbl) and TT.Hand.table == tbl and TT.Hand.seat > 0 then return TT.Hand.cards end
	return {}
end

function TT.HandCardData(entry)
	local deck = TT.Decks[entry.deck]
	return deck, deck and deck.cards[entry.id]
end

-- Mouse wheel picks a hand card while the Card Hand is out and you hold cards.
hook.Add("PlayerBindPress", "TT_HandSelect", function(ply, bind, pressed)
	if not pressed then return end
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "tt_cardtool" then return end
	local n = #TT.Hand.cards
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
	local cards = IsValid(TT.Hand.table) and TT.Hand.cards or {}
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
	draw.SimpleTextOutlined(sel .. " / " .. n, "TT_HUD", x + w / 2, y - 8, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
end
