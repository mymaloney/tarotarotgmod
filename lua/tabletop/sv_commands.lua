-- Tarotarot Tabletop: console commands.

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
		ply:ChatPrint("Look at a Deck or Discard zone on a card table first.")
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
