-- Tarotarot Tabletop: networking and console commands.

util.AddNetworkString("tt_hand")    -- server -> seat owner: their hand contents
util.AddNetworkString("tt_peek")    -- server -> player: identity of a face-down card they may see
util.AddNetworkString("tt_handsel") -- client -> server: which hand card is selected
util.AddNetworkString("tt_decision")  -- server -> seated players: the rules engine's current decision
util.AddNetworkString("tt_answer")    -- client -> server: answer to that decision
util.AddNetworkString("tt_openpanel") -- server -> client: show my decision's options (Shift+R)
util.AddNetworkString("tt_log")       -- server -> everyone: game log lines

net.Receive("tt_answer", function(_, ply)
	local tbl, answer = net.ReadEntity(), net.ReadString()
	if not IsValid(tbl) or tbl:GetClass() ~= "tt_table" or not tbl.Engine then return end
	local ok, why = tbl:EngineAnswer(ply, answer)
	if not ok and why then ply:PrintMessage(HUD_PRINTCENTER, why) end
end)

net.Receive("tt_handsel", function(_, ply)
	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and wep:GetClass() == "tt_cardtool" then
		wep:SetHandIndex(net.ReadUInt(8))
	end
end)

concommand.Add("tt_decks", function(ply)
	local say = IsValid(ply) and function(s) ply:ChatPrint(s) end or print
	for name, deck in SortedPairs(TT.Decks) do
		say(string.format("%s - %s (%d cards)", name, deck.title, #deck.cards))
	end
end)

-- tt_spawndeck <deck>: add a deck to the pile you're looking at.
concommand.Add("tt_spawndeck", function(ply, _, args)
	if not IsValid(ply) then return end
	local deckName = args[1] or TT.Config.DefaultDeck
	if not TT.Decks[deckName] then
		ply:ChatPrint("Unknown deck '" .. deckName .. "'. Type tt_decks to list them.")
		return
	end

	local tbl, hit = TT.FindTable(ply)
	if tbl and tbl.Engine then
		ply:ChatPrint("A rules-engine game is running on that table (tt_endgame stops it).")
		return
	end
	local zone = tbl and TT.ZoneAt(hit)
	if not zone or zone.kind ~= "pile" then
		ply:ChatPrint("Look at a Deck zone on a card table first.")
		return
	end
	tbl:SpawnDeck(zone.id, deckName)
end)

-- tt_newgame (or "!deal" in chat): start a game at the table you're looking
-- at, for everyone sitting there, run by the rules engine.
--   "free": just deal and leave the rules to the players.
--   "solo [n]": play n seats (default 2) yourself, for trying things out alone.
--               You take the seat opposite yours (then any others).
local function newGame(ply, mode, count)
	local tbl = TT.FindTable(ply)
	if not tbl then
		ply:ChatPrint("Look at a card table first.")
		return
	end
	tbl:StopEngineGame()

	if mode == "solo" then
		local mine = tbl:SeatOf(ply)
		if not mine then
			ply:ChatPrint("Sit down first (E on a seat's zones), then !deal solo.")
			return
		end
		local want = math.Clamp(tonumber(count) or 2, 2, TT.MaxSeats)
		local have = #tbl:SeatedSeats()
		-- Opposite seat first, then the rest clockwise
		for _, k in ipairs({ 2, 1, 3 }) do
			local seat = (mine - 1 + k) % TT.MaxSeats + 1
			if have < want and not IsValid(tbl:SeatOwner(seat)) and tbl:ClaimSeat(seat, ply, true) then
				have = have + 1
			end
		end
	end

	local ok, why
	if mode == "free" then ok, why = tbl:NewGame() else ok, why = tbl:StartEngineGame() end
	if not ok then ply:ChatPrint(why) end
end

for _, cmd in ipairs({ "tt_newgame", "tt_reset" }) do
	concommand.Add(cmd, function(ply, _, args)
		if IsValid(ply) then newGame(ply, args[1], args[2]) end
	end)
end

-- tt_endgame: stop the rules engine; the cards stay where they are (free play).
concommand.Add("tt_endgame", function(ply)
	if not IsValid(ply) then return end
	local tbl = TT.FindTable(ply)
	if tbl and tbl.Engine then
		tbl:StopEngineGame()
		PrintMessage(HUD_PRINTTALK, "[Tarotarot] " .. ply:Nick() .. " ended the game. The table is in free play.")
	else
		ply:ChatPrint("Look at a card table with a game running.")
	end
end)

hook.Add("PlayerSay", "TT_Deal", function(ply, text)
	local words = string.Explode(" ", string.Trim(text):lower())
	if words[1] == "!deal" then
		newGame(ply, words[2], words[3])
		return ""
	end
end)

-- tt_leave: give up your seat (and hand) at the table you're looking at.
-- The hand stays with the seat for the next player who sits there.
concommand.Add("tt_leave", function(ply)
	if not IsValid(ply) then return end
	local tbl = TT.FindTable(ply)
	if tbl and tbl:SeatOf(ply) then
		local ok, why = tbl:LeaveSeat(ply)
		ply:ChatPrint(ok and "You left your seat." or why)
	else
		ply:ChatPrint("Look at a card table where you have a seat.")
	end
end)
