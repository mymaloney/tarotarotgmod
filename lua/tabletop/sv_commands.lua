-- Tarotarot Tabletop: networking and console commands.

util.AddNetworkString("tt_hand")    -- server -> seat owner: their hand contents
util.AddNetworkString("tt_peek")    -- server -> player: identity of a face-down card they may see
util.AddNetworkString("tt_handsel") -- client -> server: which hand card is selected

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
	local zone = tbl and TT.ZoneAt(hit)
	if not zone or zone.kind ~= "pile" then
		ply:ChatPrint("Look at a Deck zone on a card table first.")
		return
	end
	tbl:SpawnDeck(zone.id, deckName)
end)

-- tt_reset: clear the table you're looking at and deal fresh decks.
concommand.Add("tt_reset", function(ply)
	if not IsValid(ply) then return end
	local tbl = TT.FindTable(ply)
	if tbl then tbl:ResetGame() else ply:ChatPrint("Look at a card table first.") end
end)

-- tt_leave: give up your seat (and hand) at the table you're looking at.
-- The hand stays with the seat for the next player who sits there.
concommand.Add("tt_leave", function(ply)
	if not IsValid(ply) then return end
	local tbl = TT.FindTable(ply)
	if tbl and tbl:SeatOf(ply) then
		tbl:LeaveSeat(ply)
		ply:ChatPrint("You left your seat.")
	else
		ply:ChatPrint("Look at a card table where you have a seat.")
	end
end)
