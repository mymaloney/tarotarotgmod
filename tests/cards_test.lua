-- Tests for the card scripts (lua/tarotarot_engine/cards.lua), using the
-- real card list from data_static/tarotarot/cards.csv. Run from the repo
-- root with any Lua 5.1+ or LuaJIT:   lua tests/cards_test.lua

dofile("lua/tarotarot_engine/init.lua")
TTE.Load(function(f) dofile("lua/tarotarot_engine/" .. f) end)

-- Load the deck the way the addon does (with just enough of the GMod API)
TT = {}
string.Trim = string.Trim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
ErrorNoHalt = function(m) error(m) end
file = { Read = function(p, where)
	if where ~= "GAME" then return nil end
	local f = io.open(p, "rb"); if not f then return nil end
	local t = f:read("*a"); f:close(); return t
end }
dofile("lua/tabletop/sh_atlas.lua")
dofile("lua/tabletop/sh_decks.lua")
local CARDS = TT.Decks.tarotarot.cards
assert(#CARDS == 78, "78 cards")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function ok(v, msg) if not v then error(msg or "expected true", 2) end end

local function countCards(g)
	local n = #g.out + #g.unused
	for _, p in ipairs(g.players) do n = n + #p.deck + #p.hand + #p.memory + #g:spreadCards(p.id) end
	return n
end

-- Park-Miller (exact in double-precision Lua)
local function rng(seed)
	local r = (seed * 7919) % 2147483647
	if r == 0 then r = 1 end
	return function(k) r = r * 48271 % 2147483647; return r % k + 1 end
end

-- Answer every decision at random.
local function randomPolicy(rand)
	return function(g, d)
		if d.kind == "manual" then return { action = "done" } end
		if d.kind == "may_draw" then return rand(2) == 1 and "draw" or "skip" end
		return d.options[rand(#d.options)].id
	end
end

local function drive(g, policy, stop, limit)
	local n = 0
	while g.pending and not g.over and not (stop and stop(g)) do
		n = n + 1
		if n > (limit or 20000) then error("runaway: " .. table.concat(g.log, "\n", math.max(1, #g.log - 15))) end
		local d = g.pending
		local good, err = g:answer(d.player, policy(g, d))
		assert(good, "answer rejected: " .. tostring(err) .. " (" .. d.kind .. ")")
	end
	return n
end

local function newGame(players, seed)
	local names = { "Ann", "Bo", "Cy", "Di" }
	local list = {}
	for i = 1, players do list[i] = names[i] end
	return TTE.new({ players = list, cards = CARDS, seed = seed, first = 1 })
end

---------------------------------------------------------------------------
-- Every card has both sides scripted
---------------------------------------------------------------------------

test("all 78 cards are scripted on both sides", function()
	local missing = {}
	for _, c in ipairs(CARDS) do
		local s = TTE.Cards[c.name]
		if not (s and s.upright and s.reversed) then missing[#missing + 1] = c.name end
	end
	eq(#missing, 0, "unscripted: " .. table.concat(missing, ", "))
end)

---------------------------------------------------------------------------
-- Random full games with every card scripted
---------------------------------------------------------------------------

test("random full games", function()
	local turns = 0
	for seed = 1, 60 do
		local g = newGame(seed % 3 + 2, seed)
		local rand = rng(seed)
		g:start()
		local good, err = pcall(drive, g, randomPolicy(rand))
		if not good then
			error("seed " .. seed .. ": " .. tostring(err) .. "\n--- last log lines:\n" .. table.concat(g.log, "\n", math.max(1, #g.log - 12)))
		end
		ok(g.over, "seed " .. seed .. " finished")
		eq(countCards(g), 78, "seed " .. seed .. " cards conserved")
		turns = turns + g.turnNumber
	end
	print("  random games: " .. turns .. " turns")
end)

---------------------------------------------------------------------------
-- Controlled boards
---------------------------------------------------------------------------

local ID = {}
for i, c in ipairs(CARDS) do ID[c.name] = i end

-- A game in the middle of player 1's turn, with cards dealt to decks round-robin.
local function board(players, seed)
	local g = newGame(players or 3, seed or 1)
	for i = 1, 78 do g:putCard(i, (i - 1) % #g.players + 1, "deck") end
	g.active, g.turnNumber = 1, 1
	g.turn = { player = 1, step = "activate" }
	g.turnDamage, g.turnActivations = {}, {}
	return g
end

-- Put named cards somewhere: place(g, "The Fool", 2, "spread", "past", { reversed = true })
local function put(g, name, pid, zone, pos, o)
	o = o or {}
	local cid = ID[name]
	g:putCard(cid, pid, zone, pos)
	if zone == "spread" then
		g:card(cid).faceUp = not o.faceDown
		g:card(cid).reversed = o.reversed and true or false
	end
	return cid
end

-- Answer decisions from a script: each entry is a function(d) -> answer, or a
-- string matched against option labels. Then: first option / done / skip.
local function scripted(answers)
	local i = 0
	return function(g, d)
		i = i + 1
		local a = answers[i]
		if type(a) == "function" then return a(d) end
		if type(a) == "string" and d.options then
			for _, opt in ipairs(d.options) do
				if opt.label:find(a, 1, true) then return opt.id end
			end
			error("no option matching '" .. a .. "' in " .. d.kind .. ": " .. d.prompt)
		end
		if d.kind == "manual" then return { action = "done" } end
		if d.kind == "may_draw" then return "skip" end
		if d.kind == "priority" then return "pass" end
		return d.options[1].id
	end
end

-- Run fn inside the game (so it can ask), then the stack and a state check.
local function run(g, fn, policy)
	g.co = coroutine.create(function()
		fn()
		g:runStack()
		g:checkState()
	end)
	g:resume()
	drive(g, policy or scripted({}))
end

-- Activate a named card on player 1's spread and resolve it.
local function activate(g, name, policy, o)
	o = o or {}
	local cid = put(g, name, o.player or 1, "spread", o.pos or "present", o)
	run(g, function() g:activate(cid, o.player or 1) end, policy)
	return cid
end

---------------------------------------------------------------------------
-- Every card, both sides, on a busy board with random answers
---------------------------------------------------------------------------

test("every side resolves on a busy board (random answers)", function()
	local runs = 0
	for _, c in ipairs(CARDS) do
		for _, side in ipairs({ "upright", "reversed" }) do
			for seed = 1, 12 do
				local g = board(3, seed)
				local rand = rng(seed * 131 + #c.name)
				-- Busy board: full spreads (one face down), memories and hands
				local pool = {}
				for i = 1, 78 do if i ~= ID[c.name] then pool[#pool + 1] = i end end
				g:shuffle(pool)
				local k = 0
				local function nextCard() k = k + 1 return pool[k] end
				for pid = 1, 3 do
					for _, pos in ipairs(TTE.POSITIONS) do
						if not (pid == 1 and pos == "present") then
							local cid = nextCard()
							g:putCard(cid, pid, "spread", pos)
							g:card(cid).faceUp = not (pos == "future" and pid == 2)
							g:card(cid).reversed = rand(2) == 1
						end
					end
					for _ = 1, 3 do g:putCard(nextCard(), pid, "memory") end
					for _ = 1, 3 do g:putCard(nextCard(), pid, "hand") end
				end
				local cid = ID[c.name]
				g:putCard(cid, 1, "spread", "present")
				g:card(cid).faceUp, g:card(cid).reversed = true, side == "reversed"
				g.turnActivations[1] = { card = pool[1], side = "upright" }

				local good, err = pcall(run, g, function() g:activate(cid, 1) end, randomPolicy(rand))
				if not good then
					error(c.name .. " (" .. side .. "), seed " .. seed .. ": " .. tostring(err) ..
						"\n--- log:\n" .. table.concat(g.log, "\n", math.max(1, #g.log - 10)))
				end
				eq(countCards(g), 78, c.name .. " (" .. side .. ") conserves cards")
				runs = runs + 1
			end
		end
	end
	print("  busy-board activations: " .. runs)
end)

---------------------------------------------------------------------------
-- Rules checks for individual cards
---------------------------------------------------------------------------

test("The Fool reversed: 5 damage to each player", function()
	local g = board(3)
	activate(g, "The Fool", nil, { reversed = true })
	for pid = 1, 3 do eq(g.players[pid].life, 15) end
end)

test("The Fool upright: place one revealed top card, remove the rest", function()
	local g = board(2)
	local t1, t2 = g:topOfDeck(1), g:topOfDeck(2)
	activate(g, "The Fool", scripted({ g:cardLabel(t2, 1):match("^[^(]+"), "past, upright" }))
	eq(g.players[1].spread.past, t2, "placed the opponent's top card")
	eq(g:card(t1).loc.zone, "out", "the rest removed")
end)

test("The Magician reversed: win if you can't draw 3", function()
	local g = board(2)
	while #g.players[1].deck > 2 do g:putCard(g.players[1].deck[1], nil, "out") end
	activate(g, "The Magician", nil, { reversed = true })
	ok(g.over and g.winners[1] == 1)
end)

test("The High Priestess: found card and those above it go to memory", function()
	local g = board(2)
	local deck = g.players[2].deck
	local target = deck[#deck - 2] -- third from the top
	local name = g:card(target).name
	activate(g, "The High Priestess", scripted({ name, "Bo" }))
	eq(#g.players[2].memory, 3, "three revealed cards in memory")
	eq(g:card(target).loc.zone, "memory")
end)

test("The Empress: win with The Emperor on your spread", function()
	local g = board(2)
	put(g, "The Emperor", 1, "spread", "past")
	activate(g, "The Empress")
	ok(g.over and g.winners[1] == 1)
end)

test("The Hierophant: remove everything not of the chosen suit", function()
	local g = board(2)
	local w = put(g, "2 of Wands", 2, "spread", "past")
	local c = put(g, "2 of Cups", 2, "spread", "future")
	local hiero = activate(g, "The Hierophant", scripted({ "Wands" }))
	eq(g:card(w).loc.zone, "spread", "Wand stays")
	eq(g:card(c).loc.zone, "out", "Cup removed")
	eq(g:card(hiero).loc.zone, "out", "itself (a Major) removed")
end)

test("The Lovers reversed: discard or take 3", function()
	local g = board(3)
	put(g, "2 of Cups", 2, "hand")
	activate(g, "The Lovers", nil, { reversed = true })
	eq(g.players[2].life, 20, "Bo discarded")
	eq(g:card(ID["2 of Cups"]).loc.zone, "memory")
	eq(g.players[3].life, 17, "Cy couldn't")
end)

test("Strength upright: half their life, then the same to you (not below 1)", function()
	local g = board(2)
	g.players[2].life = 17
	g.players[1].life = 5
	activate(g, "Strength")
	eq(g.players[2].life, 9, "17 - 8")
	eq(g.players[1].life, 1, "5 - 8, floored at 1")
end)

test("Temperance upright: everyone down to the lowest life", function()
	local g = board(3)
	g.players[1].life, g.players[2].life, g.players[3].life = 12, 7, 20
	activate(g, "Temperance")
	for pid = 1, 3 do eq(g.players[pid].life, 7) end
end)

test("The Devil upright: 3 to each opponent, gain 1 each", function()
	local g = board(3)
	activate(g, "The Devil")
	eq(g.players[1].life, 22); eq(g.players[2].life, 17); eq(g.players[3].life, 17)
end)

test("The Devil reversed: pay 2 life to place from memory instead, for the rest of the game", function()
	local g = board(2)
	local mem = put(g, "3 of Cups", 1, "memory")
	activate(g, "The Devil", nil, { reversed = true })
	eq(#g:spreadCards(1), 0, "spread removed")
	local handCard = put(g, "4 of Cups", 1, "hand")
	run(g, function() g:placeStep(1) end, scripted({ "4 of Cups", "past, upright", "3 of Cups" }))
	eq(g.players[1].spread.past, mem, "memory card placed instead")
	eq(g:card(handCard).loc.zone, "hand", "hand card stays")
	eq(g.players[1].life, 18, "paid 2 life")
end)

test("The Star: win with 10 more life than each opponent", function()
	local g = board(3)
	g.players[1].life, g.players[2].life, g.players[3].life = 30, 20, 23
	activate(g, "The Star")
	ok(g.over and g.winners[1] == 1)
end)

test("The Star reversed: 2 to everyone, then the damage you dealt them this turn again", function()
	local g = board(2)
	run(g, function() g:damage(2, 3, 1) end)
	activate(g, "The Star", nil, { reversed = true })
	eq(g.players[1].life, 18)
	eq(g.players[2].life, 20 - 3 - 2 - 5, "3 + 2 dealt earlier, then 5 more")
end)

test("The Moon reversed: deck cards to memory for each card in hand and spread", function()
	local g = board(2)
	put(g, "2 of Cups", 2, "hand"); put(g, "3 of Cups", 2, "hand"); put(g, "4 of Cups", 2, "spread", "past")
	activate(g, "The Moon", nil, { reversed = true })
	eq(#g.players[2].memory, 3)
end)

test("Judgement upright: dismiss all; 2 damage per opponent card", function()
	local g = board(2)
	put(g, "2 of Cups", 2, "spread", "past"); put(g, "3 of Cups", 2, "spread", "future")
	activate(g, "Judgement")
	eq(#g:allSpreadCards(1), 0)
	eq(g.players[2].life, 16)
	eq(g.players[1].life, 20, "no damage for your own cards")
end)

test("The World: counters and damage; reversed adds 7 and reverses at 21", function()
	local g = board(2)
	local w = activate(g, "The World")
	run(g, function() g:activate(w, 1) end)
	eq(g:counters(w, "generic"), 2); eq(g.players[2].life, 20 - 1 - 2)
	g:card(w).reversed = true
	run(g, function() g:activate(w, 1) end) -- 9
	run(g, function() g:activate(w, 1) end) -- 16
	ok(g:card(w).reversed, "not yet")
	run(g, function() g:activate(w, 1) end) -- 23
	ok(not g:card(w).reversed, "reversed (back to upright) at 21+")
end)

test("The Hanged Man reversed: the next lethal damage leaves 1 life", function()
	local g = board(2)
	activate(g, "The Hanged Man", nil, { reversed = true })
	run(g, function() g:damage(2, 50, 1) end)
	eq(g.players[2].life, 1)
	run(g, function() g:damage(2, 5, 1) end)
	ok(g.over, "only once")
end)

test("3 of Swords reversed: prevent the next damage to you", function()
	local g = board(2)
	activate(g, "3 of Swords", nil, { reversed = true })
	run(g, function() g:damage(1, 6, 2); g:damage(1, 2, 2) end)
	eq(g.players[1].life, 18)
end)

test("2 of Wands: doubles your next damage this turn, and stacks", function()
	local g = board(2)
	activate(g, "2 of Wands")
	g:putCard(ID["2 of Wands"], 1, "memory")
	activate(g, "2 of Wands")
	run(g, function() g:damage(2, 3, 1); g:damage(2, 1, 1) end)
	eq(g.players[2].life, 20 - 12 - 1, "3 x2 x2, then 1")
end)

test("2 of Wands reversed: the next time you would place, you don't", function()
	local g = board(2)
	put(g, "3 of Cups", 1, "hand"); put(g, "4 of Cups", 1, "hand")
	activate(g, "2 of Wands", scripted({ "3 of Cups", "past, upright" }), { reversed = true })
	eq(g.players[1].spread.past, ID["3 of Cups"], "placed now")
	run(g, function() g:placeStep(1) end, scripted({ "4 of Cups", "future, upright" }))
	eq(g.players[1].spread.future, nil, "next place skipped")
end)

test("6 of Swords reversed: the named card can't be dismissed until your next turn", function()
	local g = board(2)
	local c = put(g, "2 of Cups", 2, "spread", "past")
	activate(g, "6 of Swords", scripted({ "2 of Cups" }), { reversed = true })
	run(g, function() g:dismiss(c, 1) end)
	eq(g:card(c).loc.zone, "spread")
	g:expire("start_of_turn", 1)
	run(g, function() g:dismiss(c, 1) end)
	eq(g:card(c).loc.zone, "memory")
end)

test("Queen of Swords reversed: the named card doesn't activate", function()
	local g = board(2)
	local fool = put(g, "The Fool", 2, "spread", "past", { reversed = true })
	activate(g, "Queen of Swords", scripted({ "The Fool" }), { reversed = true })
	run(g, function() g:activate(fool, 2) end)
	eq(g.players[1].life, 20, "The Fool didn't activate")
end)

test("King of Cups: drawers can't damage you or dismiss your cards", function()
	local g = board(2)
	local k = activate(g, "King of Cups", scripted({ "Don't draw", "Draw" }))
	run(g, function() g:damage(1, 5, 2); g:dismiss(k, 2); g:damage(1, 1, 1) end)
	eq(g.players[1].life, 19, "only self-damage got through")
	eq(g:card(k).loc.zone, "spread")
end)

test("9 of Cups: end the turn (no place step) and flip it face down", function()
	local g = board(2)
	local nine = put(g, "9 of Cups", 1, "spread", "past")
	g.co = coroutine.create(function() g:takeTurn(1) end)
	g:resume()
	drive(g, scripted({ "Yes" }), function(g) return g.pending and (g.pending.kind == "place_source" or g.turnNumber > 2) end)
	ok(g.turn.ended, "turn ended")
	ok(not g:card(nine).faceUp, "flipped face down")
	eq(#g.permissions, 1, "may flip it later")
end)

test("6 of Cups: restart from the Past without undoing; it's removed", function()
	local g = board(2)
	local hits = 0
	local fool = put(g, "The Fool", 1, "spread", "past", { reversed = true })
	local six = put(g, "6 of Cups", 1, "spread", "present")
	g.co = coroutine.create(function() g:takeTurn(1) end)
	g:resume()
	drive(g, scripted({}), function(g) return g.pending and g.pending.kind == "place_source" end)
	eq(g.players[2].life, 10, "The Fool activated twice")
	eq(g:card(six).loc.zone, "out")
end)

test("5 of Cups: copies an earlier effect this turn, never itself", function()
	local g = board(2)
	g.turnActivations = { { card = ID["The Fool"], side = "reversed" } }
	local five = activate(g, "5 of Cups", function(g, d)
		if d.kind == "choose" then
			for _, opt in ipairs(d.options) do ok(not opt.label:find("5 of Cups"), "itself offered") end
		end
		return d.options and d.options[1].id or { action = "done" }
	end)
	eq(g.players[2].life, 15, "copied The Fool (reversed)")
end)

test("Knight of Swords: activate and silence your next placed card", function()
	local g = board(2)
	put(g, "The Fool", 1, "hand")
	activate(g, "Knight of Swords")
	run(g, function() g:placeStep(1) end, scripted({ "The Fool", "past, reversed", "Yes" }))
	eq(g.players[2].life, 15, "activated")
	eq(g:counters(ID["The Fool"], "silence"), 1, "and silenced")
end)

test("7 of Wands: 5 damage whenever a card on your spread is dismissed", function()
	local g = board(2)
	local c = put(g, "2 of Cups", 1, "spread", "past")
	activate(g, "7 of Wands", nil, { pos = "future" })
	run(g, function() g:dismiss(c, 2) end, scripted({ "Bo" }))
	eq(g.players[2].life, 15)
end)

test("4 of Pentacles: the taken card is dismissed at the end of your next turn", function()
	local g = board(2)
	local taken = put(g, "2 of Cups", 2, "spread", "past")
	activate(g, "4 of Pentacles", scripted({ "past" })) -- (the only card to take is picked automatically)
	eq(g.players[1].spread.past, taken)
	run(g, function() g:fire({ name = "turn_end", player = 1 }) end)
	eq(g:card(taken).loc.zone, "spread", "not this turn")
	g.turnNumber = 3
	run(g, function() g:fire({ name = "turn_end", player = 1 }) end)
	eq(g:card(taken).loc.zone, "memory", "end of the next turn")
end)

test("Queen of Wands reversed: your next activation happens twice", function()
	local g = board(2)
	activate(g, "Queen of Wands", nil, { reversed = true })
	local fool = put(g, "The Fool", 1, "spread", "past", { reversed = true })
	run(g, function() g:activate(fool, 1) end)
	eq(g.players[2].life, 10)
	run(g, function() g:activate(fool, 1) end)
	eq(g.players[2].life, 5, "only the next one")
end)

test("3 of Cups: activate your other cards in the order you choose", function()
	local g = board(2)
	local order = {}
	local saved = TTE.Cards["2 of Swords"]
	put(g, "4 of Cups", 1, "spread", "past"); put(g, "5 of Swords", 1, "spread", "future")
	TTE.Cards["4 of Cups"].upright, TTE.Cards["5 of Swords"].upright = function() order[#order + 1] = "4C" end, function() order[#order + 1] = "5S" end
	activate(g, "3 of Cups", scripted({ "5 of Swords", "4 of Cups" }))
	dofile("lua/tarotarot_engine/cards.lua") -- restore the scripts we stubbed
	eq(table.concat(order, ","), "5S,4C")
end)

test("Ace of Wands: place a revealed card instead; the rest are removed", function()
	local g = board(2)
	local deck = g.players[1].deck
	local a, b, c = deck[#deck], deck[#deck - 1], deck[#deck - 2]
	put(g, "4 of Cups", 1, "hand")
	activate(g, "Ace of Wands")
	run(g, function() g:placeStep(1) end, scripted({ "4 of Cups", "past, upright", g:card(b).name }))
	eq(g.players[1].spread.past, b, "revealed card placed instead")
	eq(g:card(a).loc.zone, "out"); eq(g:card(c).loc.zone, "out")
	eq(g:card(ID["4 of Cups"]).loc.zone, "hand")
end)

test("7 of Pentacles: dismiss to set life to 7 x counters", function()
	local g = board(2)
	local seven = put(g, "7 of Pentacles", 1, "spread", "past")
	g:addCounter(seven, "generic", 2)
	run(g, function() g:activate(seven, 1) end, scripted({ "Yes" }))
	eq(g.players[1].life, 21)
	eq(g:card(seven).loc.zone, "memory")
end)

test("Wheel of Fortune reversed: doubling coin flips until the winner stops", function()
	local g = board(2, 7)
	activate(g, "The Wheel of Fortune", scripted({ "Yes", "No" }), { reversed = true }) -- (the only opponent is picked automatically)
	local total = (20 - g.players[1].life) + (20 - g.players[2].life)
	eq(total, 2 + 4, "two flips: 2 then 4 damage")
end)

test("Knight of Swords reversed: smallest number gets a card dismissed", function()
	local g = board(2)
	local c = put(g, "2 of Cups", 2, "spread", "past")
	activate(g, "Knight of Swords", scripted({ "5", "1" }), { reversed = true })
	eq(g.players[1].life, 15); eq(g.players[2].life, 19)
	eq(g:card(c).loc.zone, "memory")
end)

test("a place swapped by another effect reports the card actually placed", function()
	-- Queen of Pentacles: the next place may use a memory card instead; then the
	-- Knight of Pentacles exchanges *that* card with another
	local g = board(2)
	local mem = put(g, "3 of Cups", 1, "memory")
	put(g, "4 of Cups", 1, "hand")
	local other = put(g, "5 of Cups", 1, "spread", "past")
	activate(g, "Queen of Pentacles")
	g:putCard(ID["Queen of Pentacles"], 1, "memory")
	activate(g, "Knight of Pentacles", scripted({ "4 of Cups", "future, upright", "3 of Cups", "5 of Cups", "Neither" }))
	eq(g:card(mem).loc.pos, "past", "memory card placed, then exchanged into the Past")
	eq(g:card(other).loc.pos, "future", "the other card moved to the Future")
	eq(g:card(ID["4 of Cups"]).loc.zone, "hand", "the hand card stayed")
end)

---------------------------------------------------------------------------
-- "Can't place" from an effect: draw instead (unless the place was a "may")
---------------------------------------------------------------------------

-- Majors in every space but `except` (where the activating Major goes)
local function fillWithMajors(g, pid, except)
	for i, pos in ipairs(TTE.POSITIONS) do
		if pos ~= except then put(g, ({ "The Sun", "The Moon", "The Star" })[i], pid, "spread", pos) end
	end
end

test("a required place you can't make draws instead (The Magician, no legal space)", function()
	local g = board(2)
	fillWithMajors(g, 1, "present")
	local hand = #g.players[1].hand
	activate(g, "The Magician", nil, { pos = "present" })
	eq(#g.players[1].hand, hand + 1, "drew instead")
	ok(table.concat(g.log, "\n"):find("can't place a card, so draws"), "logged")
end)

test("10 of Pentacles with an empty memory draws instead", function()
	local g = board(2)
	local hand = #g.players[1].hand
	activate(g, "10 of Pentacles")
	eq(#g.players[1].hand, hand + 1)
end)

test("The Chariot with no card to take draws instead", function()
	local g = board(2)
	local hand = #g.players[1].hand
	activate(g, "The Chariot")
	eq(#g.players[1].hand, hand + 1)
end)

test("a 'may' place you can't make doesn't draw (The Fool, no legal space)", function()
	local g = board(2)
	fillWithMajors(g, 1, "past")
	local hand = #g.players[1].hand
	activate(g, "The Fool", nil, { pos = "past" })
	eq(#g.players[1].hand, hand, "no draw")
end)

test("a place stopped by another effect isn't 'can't place' (2 of Wands reversed, then The Magician)", function()
	local g = board(2)
	put(g, "3 of Cups", 1, "hand"); put(g, "4 of Cups", 1, "hand")
	activate(g, "2 of Wands", scripted({ "3 of Cups", "past, upright" }), { reversed = true })
	g:putCard(ID["2 of Wands"], 1, "memory")
	local hand = #g.players[1].hand
	activate(g, "The Magician", scripted({ "4 of Cups", "future, upright" }), { pos = "present" })
	eq(g.players[1].spread.future, nil, "the place was skipped")
	eq(#g.players[1].hand, hand, "and no draw")
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
