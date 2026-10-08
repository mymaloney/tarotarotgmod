-- Tarotarot Tabletop: client side of rules-engine games. Your current
-- decision (with a pop-up of buttons, or a hint when it's made on the table),
-- the game status line and the game log.

TT.Decision = TT.Decision or nil -- { table, kind, seat, prompt, serial, popup, card, options }
TT.GameLog = TT.GameLog or {}
local LOG_LINES = 8

local frame

local function closePopup()
	if IsValid(frame) then frame:Remove() end
	frame = nil
end

local function sendAnswer(id)
	local d = TT.Decision
	if not d or not IsValid(d.table) then return end
	net.Start("tt_answer")
	net.WriteEntity(d.table)
	net.WriteString(id)
	net.SendToServer()
	closePopup()
end

local function openPopup()
	local d = TT.Decision
	closePopup()
	if not d then return end

	local hasCard = d.card > 0
	local w = hasCard and 700 or 520
	frame = vgui.Create("DFrame")
	frame:SetTitle("Tarotarot")
	frame:SetSize(w, 200)
	frame.Serial = d.serial

	local body = vgui.Create("DPanel", frame)
	body:Dock(FILL)
	body:SetPaintBackground(false)

	if hasCard then
		local preview = vgui.Create("DPanel", body)
		preview:Dock(LEFT)
		preview:SetWide(200)
		preview:DockMargin(0, 0, 10, 0)
		preview.Paint = function(_, pw)
			local deck = TT.Decks[TT.Config.DefaultDeck]
			local cw = pw - 10
			TT.DrawCardFace(deck, deck and deck.cards[d.card], 0, 0, cw, cw * TT.Config.CardH / TT.Config.CardW)
		end
	end

	local right = vgui.Create("DScrollPanel", body)
	right:Dock(FILL)

	local label = vgui.Create("DLabel", right)
	label:Dock(TOP)
	label:SetFont("TT_HUDText")
	label:SetWrap(true)
	label:SetAutoStretchVertical(true)
	label:SetText(d.prompt)
	label:DockMargin(0, 0, 0, 8)

	if d.kind == "manual" or d.kind == "place_source" or d.kind == "place_target" or d.kind == "survey_past" then
		local hint = vgui.Create("DLabel", right)
		hint:Dock(TOP)
		hint:SetWrap(true)
		hint:SetAutoStretchVertical(true)
		hint:SetTextColor(Color(200, 200, 200))
		hint:SetText(d.kind == "manual"
			and "Carry this out on the table with the Card Hand (move, flip, reverse, counters, life, E to draw), then press Done."
			or d.kind == "survey_past"
			and "On the table: pick up the top card of your deck, put it in your Past, press R to turn it, then confirm here. Or just choose below."
			or "Or drag the card onto your spread on the table (R sets its orientation).")
		hint:DockMargin(0, 0, 0, 8)
	end

	for _, opt in ipairs(d.options) do
		local b = vgui.Create("DButton", right)
		b:Dock(TOP)
		b:DockMargin(0, 0, 0, 4)
		b:SetWrap(true)
		b:SetTall(#opt.label > 60 and 52 or 28) -- long labels (copied card text) wrap
		b:SetText(opt.label)
		b.DoClick = function() sendAnswer(opt.id) end
	end

	local height = 70
	for _, opt in ipairs(d.options) do height = height + (#opt.label > 60 and 56 or 32) end
	frame:SetTall(math.Clamp(math.max(height + 80, hasCard and 400 or 0), 200, ScrH() * 0.8))
	frame:Center()
	frame:MakePopup()
end

net.Receive("tt_decision", function()
	local tbl, kind = net.ReadEntity(), net.ReadString()
	if kind == "" then
		if TT.Decision and TT.Decision.table == tbl then
			TT.Decision = nil
			closePopup()
		end
		return
	end
	local d = { table = tbl, kind = kind, seat = net.ReadUInt(3), prompt = net.ReadString(), serial = net.ReadUInt(32),
		popup = net.ReadBool(), card = net.ReadUInt(16), options = {} }
	for i = 1, net.ReadUInt(8) do
		d.options[i] = { id = net.ReadString(), label = net.ReadString() }
	end
	local isNew = not TT.Decision or TT.Decision.serial ~= d.serial
	TT.Decision = d
	if not isNew and IsValid(frame) then
		openPopup() -- same decision, new options (e.g. the survey's Confirm button)
	elseif isNew then
		closePopup()
		if d.popup then openPopup() end
		surface.PlaySound("buttons/button17.wav")
	end
end)

net.Receive("tt_openpanel", function()
	if TT.Decision then openPopup() end
end)

net.Receive("tt_log", function()
	local tbl, line = net.ReadEntity(), net.ReadString()
	TT.GameTable = tbl
	table.insert(TT.GameLog, line)
	while #TT.GameLog > 50 do table.remove(TT.GameLog, 1) end
end)

---------------------------------------------------------------------------
-- HUD: status line, your decision hint, recent log
---------------------------------------------------------------------------

local BG = Color(0, 0, 0, 170)
local GOLD = Color(255, 220, 60)
local DIM = Color(190, 190, 190)

local function gameTable()
	local tbl = IsValid(TT.HoverTable) and TT.HoverTable or TT.GameTable
	if IsValid(tbl) and tbl:GetEngineOn() then return tbl end
end

hook.Add("HUDPaint", "TT_EngineHUD", function()
	local tbl = gameTable()
	if not tbl or LocalPlayer():GetPos():DistToSqr(tbl:GetPos()) > 1500 * 1500 then return end

	-- Status line
	local turnSeat = tbl:GetTurnSeat()
	local turnPly = turnSeat > 0 and tbl:SeatOwner(turnSeat) or NULL
	local status = string.format("Turn %d  -  %s's turn  -  %s", tbl:GetTurnNumber(),
		IsValid(turnPly) and turnPly:Nick() or "?", tbl:GetStatus())
	surface.SetFont("TT_HUDTitle")
	local tw = surface.GetTextSize(status)
	draw.RoundedBox(8, ScrW() / 2 - tw / 2 - 14, 12, tw + 28, 34, BG)
	draw.SimpleText(status, "TT_HUDTitle", ScrW() / 2, 29, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	-- My decision, when it's made on the table
	local d = TT.Decision
	if d and d.table == tbl and not IsValid(frame) then
		local hint = d.kind == "manual" and "Resolve the card on the table, then Shift+R > Done"
			or d.kind == "survey_past" and "Survey the Past: put the top card of your deck in your Past (R turns it), then Shift+R > Confirm"
			or (d.kind == "place_source" or d.kind == "place_target") and "Your move: drag a card from your hand or deck onto your spread (Shift+R for a list)"
			or "Your decision: Shift+R to choose"
		draw.SimpleTextOutlined(hint, "TT_HUDTitle", ScrW() / 2, 56, GOLD, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
		if d.kind == "manual" then
			for i, line in ipairs(TT.WrapText(d.prompt, "TT_HUDText", 700)) do
				draw.SimpleTextOutlined(line, "TT_HUDText", ScrW() / 2, 60 + i * 24, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
			end
		end
	end

	-- Recent log, top right
	local n = #TT.GameLog
	if n == 0 then return end
	local first = math.max(1, n - LOG_LINES + 1)
	local x, y, w = ScrW() - 440, 12, 420
	draw.RoundedBox(8, x, y, w, (n - first + 1) * 20 + 12, BG)
	for i = first, n do
		draw.SimpleText(TT.GameLog[i], "TT_HUD", x + 10, y + 6 + (i - first) * 20, i == n and color_white or DIM)
	end
end)
