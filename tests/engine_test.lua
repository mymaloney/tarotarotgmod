-- Tests for the Tarotarot rules engine. Run from the repo root with any
-- Lua 5.1+ or LuaJIT:   lua tests/engine_test.lua

dofile("lua/tarotarot_engine/init.lua")
TTE.Load(function(f) dofile("lua/tarotarot_engine/" .. f) end)

---------------------------------------------------------------------------
-- Tiny test harness
---------------------------------------------------------------------------

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function ok(v, msg) if not v then error(msg or "expected true", 2) end end

-- A 78-card deck: 22 Majors and 56 Minors (names only matter for scripts)
local function deck()
	local cards = {}
	for i = 1, 22 do cards[#cards + 1] = { name = "Major " .. i, suit = "Major", upright = "M" .. i .. " up", reversed = "M" .. i .. " rev" } end
	for _, suit in ipairs({ "Pentacles", "Swords", "Wands", "Cups" }) do
		for r = 1, 14 do cards[#cards + 1] = { name = r .. " of " .. suit, suit = suit, upright = "up", reversed = "rev" } end
	end
	return cards
end

local function newGame(n, opts)
	opts = opts or {}
	local names = { "Ann", "Bo", "Cy", "Di" }
	local players = {}
	for i = 1, n do players[i] = names[i] end
	return TTE.new({ players = players, cards = deck(), seed = opts.seed or 42, first = opts.first or 1, effects = opts.effects or {} })
end

-- Answer decisions with simple defaults until `stop(g)` is true or the game ends.
local function auto(g, stop, policy)
	local guard = 0
	while g.pending and not g.over and not (stop and stop(g)) do
		guard = guard + 1
		assert(guard < 10000, "runaway game")
		local d = g.pending
		local answer = policy and policy(g, d)
		if answer == nil then
			if d.kind == "manual" then answer = { action = "done" }
			elseif d.kind == "may_draw" then answer = "skip"
			elseif d.kind == "priority" then answer = "pass"
			else answer = d.options[1].id end
		end
		local good, err = g:answer(d.player, answer)
		assert(good, "answer rejected: " .. tostring(err) .. " for " .. d.kind)
	end
end

local function countCards(g)
	local n = #g.out + #g.unused
	for _, p in ipairs(g.players) do
		n = n + #p.deck + #p.hand + #p.memory + #g:spreadCards(p.id)
	end
	return n
end

local function untilTurn(n) return function(g) return g.turnNumber >= n end end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

for _, case in ipairs({ { 2, 39 }, { 3, 26 }, { 4, 19 } }) do
	test("setup deals " .. case[2] .. " each to " .. case[1] .. " players", function()
		local g = newGame(case[1])
		g:start()
		eq(g.pending.kind, "survey_past", "first decision")
		auto(g, function(g) return g.pending and g.pending.kind == "manual" end)
		for _, p in ipairs(g.players) do
			eq(#p.deck + #p.hand + #g:spreadCards(p.id), case[2], "cards per player")
			eq(#p.hand, 3, "starting hand")
			eq(p.life, 20, "starting life")
			ok(p.spread.past and g:card(p.spread.past).faceUp, "past is face up")
		end
		eq(#g.unused, 78 - case[1] * case[2], "leftovers")
		eq(countCards(g), 78, "no cards lost")
	end)
end

test("survey the past respects the chosen orientation", function()
	local g = newGame(2)
	g:start()
	g:answer(1, "reversed")
	g:answer(2, "upright")
	ok(g:card(g.players[1].spread.past).reversed, "p1 reversed")
	ok(not g:card(g.players[2].spread.past).reversed, "p2 upright")
end)

---------------------------------------------------------------------------
-- Turn structure
---------------------------------------------------------------------------

test("activation goes Past, Present, Future and uses the side facing its player", function()
	local seen = {}
	local effects = setmetatable({}, { __index = function(_, name)
		return {
			upright = function(g, ctx) if ctx.controller == 1 then seen[#seen + 1] = g:card(ctx.card).loc.pos .. ":upright" end end,
			reversed = function(g, ctx) if ctx.controller == 1 then seen[#seen + 1] = g:card(ctx.card).loc.pos .. ":reversed" end end,
		}
	end })
	local g = newGame(2, { effects = effects })
	g:start()
	auto(g, untilTurn(1))
	-- Fill player 1's spread directly, then run their next turn
	local p = g.players[1]
	g:putCard(p.deck[1], 1, "spread", "present"); g:card(p.spread.present).faceUp = true; g:card(p.spread.present).reversed = true
	g:putCard(p.deck[1], 1, "spread", "future"); g:card(p.spread.future).faceUp = true
	seen = {}
	auto(g, function(g) return g.pending and g.pending.kind == "place_source" and g.pending.player == 1 and g.turnNumber == 3 end)
	eq(table.concat(seen, ","), "past:upright,present:reversed,future:upright", "order")
end)

test("face-down cards don't activate; silenced cards lose a counter instead", function()
	local count = 0
	local effects = setmetatable({}, { __index = function() return { upright = function() count = count + 1 end, reversed = function() count = count + 1 end } end })
	local g = newGame(2, { effects = effects })
	g:start()
	auto(g, untilTurn(2))
	local p = g.players[1]
	g:putCard(p.deck[1], 1, "spread", "present") -- face down
	g:silence(p.spread.past); g:silence(p.spread.past)
	count = 0
	auto(g, untilTurn(3))
	auto(g, function(g) return g.pending.kind == "place_source" end)
	eq(count, 0, "nothing activated")
	eq(g:counters(p.spread.past, "silence"), 1, "one silence counter used up")
end)

test("placing: legal spaces skip Majors, a replaced Minor goes to memory", function()
	local g = newGame(2)
	g:start()
	auto(g, function(g) return g.pending.kind == "place_source" end)
	local p = g.players[1]
	-- Past holds whatever was surveyed; force a Major in Present and a Minor in Future
	g:putCard(23, 1, "spread", "future"); g:card(23).faceUp = true -- "1 of Pentacles"
	local major
	for _, cid in ipairs(p.deck) do if g:card(cid).major then major = cid break end end
	if p.spread.present then g:putCard(p.spread.present, 1, "memory") end
	g:putCard(major, 1, "spread", "present")
	local spaces = table.concat(g:legalSpaces(1), ",")
	ok(not spaces:find("present"), "Major space not legal: " .. spaces)
	ok(spaces:find("future"), "Minor space legal")
	local hand1 = p.hand[1]
	g:answer(1, "hand:" .. hand1)
	g:answer(1, "future:reversed")
	eq(p.spread.future, hand1, "placed")
	ok(g:card(hand1).reversed, "reversed")
	eq(g:card(23).loc.zone, "memory", "replaced Minor to memory")
	eq(countCards(g), 78, "no cards lost")
end)

test("placing from the deck shows the card to its player first", function()
	local g = newGame(2)
	g:start()
	auto(g, function(g) return g.pending.kind == "place_source" end)
	local top = g:topOfDeck(1)
	g:answer(1, "deck")
	eq(g.pending.kind, "place_target")
	eq(g.pending.card, top, "revealed card")
	ok(g.pending.private, "private to the placer")
end)

test("can't place: draw instead (no legal space)", function()
	local g = newGame(2)
	g:start()
	auto(g, function(g) return g.pending.kind == "may_draw" and g.pending.player == 1 end)
	-- Before player 2's turn, fill their spread with face-down Majors (face down so they don't activate)
	local p = g.players[2]
	for _, pos in ipairs(TTE.POSITIONS) do if p.spread[pos] then g:putCard(p.spread[pos], 2, "memory") end end
	local placed = 0
	for cid = 1, 22 do
		if placed < 3 and g:card(cid).loc.zone ~= "spread" then
			placed = placed + 1
			g:putCard(cid, 2, "spread", TTE.POSITIONS[placed])
			g:card(cid).faceUp = false
		end
	end
	ok(not g:canPlace(2), "no legal space")
	local before = #p.hand
	g:answer(1, "skip")
	eq(g.turnNumber, 2)
	eq(g.pending.kind, "may_draw", "place step skipped")
	eq(#p.hand, before + 1, "drew instead")
	ok(table.concat(g.log, "\n"):find("can't place a card, so draws"), "logged")
end)

test("drawing from an empty deck removes you; last player standing wins", function()
	local g = newGame(2)
	g:start()
	auto(g, function(g) return g.pending.kind == "may_draw" end)
	local p = g.players[g.pending.player]
	while #p.deck > 0 do g:putCard(p.deck[1], nil, "out") end
	g:answer(p.id, "draw")
	ok(g.over, "game over")
	eq(#g.winners, 1)
	ok(g.winners[1] ~= p.id, "the other player wins")
	eq(countCards(g), 78, "no cards lost")
end)

test("simultaneous lethal damage: nobody wins", function()
	local effects = { ["Major 1"] = { upright = function(g) for _, pid in ipairs(g:living()) do g:damage(pid, 25) end end } }
	local g = newGame(2, { effects = effects })
	g:start()
	auto(g, function(g) return g.pending.kind == "place_source" end)
	g:answer(1, "hand:" .. g.players[1].hand[1]) -- any
	-- put Major 1 in player 2's spread so it activates on their turn
	auto(g, untilTurn(2))
	local p2 = g.players[2]
	if g:card(1).loc.zone == "spread" then g:putCard(1, nil, "out") end
	if p2.spread.future then g:putCard(p2.spread.future, 2, "memory") end
	g:putCard(1, 2, "spread", "future"); g:card(1).faceUp = true
	auto(g, untilTurn(4))
	ok(g.over, "game over")
	eq(#g.winners, 0, "nobody wins")
end)

test("eliminated players lose all their cards", function()
	local g = newGame(3)
	g:start()
	auto(g, function(g) return g.pending.kind == "place_source" end)
	g.players[2].life = 0
	g:checkState()
	ok(g.players[2].eliminated)
	eq(#g.players[2].deck + #g.players[2].hand + #g.players[2].memory + #g:spreadCards(2), 0)
	eq(countCards(g), 78)
	eq(g:nextPlayer(1), 3, "turn order skips eliminated players")
end)

test("you win the game", function()
	local g = newGame(3, { effects = { ["Major 1"] = { upright = function(g, ctx) g:win(ctx.controller) end } } })
	g:start()
	auto(g, untilTurn(1))
	auto(g, function(g) return g.pending.kind == "place_source" end)
	local p = g.players[1]
	g:putCard(1, 1, "spread", "future"); g:card(1).faceUp = true
	auto(g)
	ok(g.over); eq(g.winners[1], 1)
end)

---------------------------------------------------------------------------
-- Stack, priority, replacements, lasting effects
---------------------------------------------------------------------------

test("flip permission: offered only when the stack is empty; activates and silences", function()
	local activated = 0
	local effects = setmetatable({}, { __index = function() return { upright = function() activated = activated + 1 end, reversed = function() activated = activated + 1 end } end })
	local g = newGame(2, { effects = effects })
	g:start()
	auto(g, function(g) return g.pending.kind == "place_source" end)
	-- Player 2 has a face-down card on their spread and permission to flip it
	local p2 = g.players[2]
	local cid = p2.deck[1]
	if p2.spread.present then g:putCard(p2.spread.present, 2, "memory") end
	g:putCard(cid, 2, "spread", "present")
	g:addPermission({ player = 2, kind = "flip", card = cid, uses = 1 })
	activated = 0
	g:answer(1, g.pending.options[1].id) -- choose a source
	g:answer(1, g.pending.options[1].id) -- and a space; then the stack is empty: priority
	auto(g, function(g) return g.pending.kind == "priority" end)
	eq(g.pending.player, 2, "player 2 gets priority")
	g:answer(2, g.pending.options[1].id)
	ok(g:card(cid).faceUp, "flipped")
	eq(g:counters(cid, "silence"), 1, "silenced")
	auto(g, function(g) return g.pending.kind == "may_draw" end)
	eq(activated, 1, "activated once")
	eq(#g.permissions, 0, "permission used up")
end)

test("replacement effects: the affected player picks the order; uses run out", function()
	local g = newGame(2)
	g:start()
	auto(g, function(g) return g.pending.kind == "manual" or g.pending.kind == "place_source" end)
	local double = g:addModifier({ event = "damage", desc = "double", uses = 1,
		replace = function(_, ev) ev.amount = ev.amount * 2 return ev end })
	local minus = g:addModifier({ event = "damage", desc = "minus 1",
		applies = function(_, ev) return ev.player == 2 end,
		replace = function(_, ev) ev.amount = ev.amount - 1 return ev end })
	local co = coroutine.create(function() g:damage(2, 3) end)
	g.co = co
	g:resume()
	eq(g.pending.kind, "order_replacements")
	eq(g.pending.player, 2, "affected player chooses")
	g:answer(2, tostring(minus.id)) -- (3 - 1) * 2 = 4
	eq(g.players[2].life, 16)
	-- "double" was used up; "minus 1" stays
	g.co = coroutine.create(function() g:damage(2, 3) end)
	g:resume()
	eq(g.players[2].life, 14)
end)

test("a replacement can cancel an event (prevention)", function()
	local g = newGame(2)
	g:addModifier({ event = "damage", uses = 1, replace = function() return nil end })
	g.co = coroutine.create(function() g:damage(1, 5); g:damage(1, 5) end)
	g:resume()
	eq(g.players[1].life, 15, "first prevented")
end)

test("lasting effects expire at end of turn / start of your next turn", function()
	local g = newGame(2)
	g:start()
	auto(g, function(g) return g.pending.kind == "place_source" end)
	g:addModifier({ event = "damage", ["until"] = "end_of_turn", replace = function() return nil end })
	g:addModifier({ event = "draw", ["until"] = { turnOf = 1 }, replace = function(_, ev) return ev end })
	eq(#g.modifiers, 2)
	auto(g, untilTurn(2))
	eq(#g.modifiers, 1, "end of turn expired")
	auto(g, untilTurn(3))
	eq(#g.modifiers, 0, "start of player 1's turn expired")
end)

test("triggers go on the stack after the event", function()
	local g = newGame(2)
	g:start()
	auto(g, function(g) return g.pending.kind == "place_source" end)
	local hits = 0
	g:addTrigger({ event = "place", controller = 1, applies = function(_, ev) return ev.player == 1 end,
		run = function() hits = hits + 1 end, ["until"] = "end_of_turn" })
	g:answer(1, g.pending.options[1].id)
	g:answer(1, g.pending.options[1].id)
	auto(g, function(g) return g.pending.kind == "may_draw" end)
	eq(hits, 1)
end)

test("restart from the Past re-runs activation without undoing", function()
	local log, restarted = {}, false
	local effects = setmetatable({}, { __index = function(_, name)
		return { upright = function(g, ctx)
			log[#log + 1] = g:card(ctx.card).loc.pos
			if g:card(ctx.card).loc.pos == "present" and not restarted then
				restarted = true
				g:restartFromPast()
			end
		end, reversed = function(g, ctx) log[#log + 1] = g:card(ctx.card).loc.pos end }
	end })
	local g = newGame(2, { effects = effects })
	g:start()
	auto(g, untilTurn(2))
	local p = g.players[1]
	g:putCard(p.deck[1], 1, "spread", "present"); g:card(p.spread.present).faceUp = true
	log = {}
	auto(g, function(g) return g.turnNumber == 3 and g.pending.kind == "place_source" end)
	eq(table.concat(log, ","), "past,present,past,present", "restarted once")
end)

---------------------------------------------------------------------------
-- Manual resolution
---------------------------------------------------------------------------

test("manual resolution: keyword actions, illegal ones rejected, eliminations wait for done", function()
	local g = newGame(2)
	g:start()
	auto(g, function(g) return g.pending.kind == "manual" end)
	local d = g.pending
	local me, other = d.player, d.player == 1 and 2 or 1
	ok(not g:answer(me, { action = "damage", player = 9, amount = 1 }), "bad player rejected")
	ok(not g:answer(me, { action = "fly" }), "unknown action rejected")
	ok(g:answer(me, { action = "damage", player = other, amount = 30 }))
	ok(g:answer(me, { action = "damage", player = me, amount = 30 }))
	ok(not g.over, "no eliminations mid-effect")
	g:answer(me, { action = "done" })
	ok(g.over, "both out after the effect"); eq(#g.winners, 0)
end)

test("manual place follows the place rules (no replacing Majors)", function()
	local g = newGame(2)
	g:start()
	auto(g, function(g) return g.pending.kind == "manual" end)
	local me = g.pending.player
	local p = g.players[me]
	for _, pos in ipairs(TTE.POSITIONS) do if p.spread[pos] then g:putCard(p.spread[pos], me, "memory") end end
	g:putCard(1, me, "spread", "past") -- a Major
	ok(not g:answer(me, { action = "place", player = me, card = p.hand[1], pos = "past" }), "can't replace a Major")
	ok(g:answer(me, { action = "place", player = me, card = p.hand[1], pos = "present", reversed = true }))
	ok(g:card(p.spread.present).reversed)
end)

---------------------------------------------------------------------------
-- Random games: every card resolved manually with random keyword actions
---------------------------------------------------------------------------

STATS = { turns = 0, flips = 0 }
test("200 random games end cleanly with no cards lost", function()
	local actions = { "damage", "gain_life", "draw", "discard", "dismiss", "reverse", "flip", "silence", "shuffle", "to_hand", "remove", "permit_flip" }
	for seed = 1, 200 do
		local n = seed % 3 + 2
		local g = newGame(n, { seed = seed, first = seed % n + 1 })
		-- Park-Miller: stays exact in double-precision Lua (LuaJIT / 5.1)
		local r = seed * 7919 % 2147483647
		local function rand(k) r = r * 48271 % 2147483647; return r % k + 1 end
		local budget = {}
		g:start()
		auto(g, nil, function(g, d)
			if d.kind == "may_draw" then return rand(2) == 1 and "draw" or "skip" end
			if d.kind == "priority" then return d.options[rand(#d.options)].id end
			if d.kind ~= "manual" then return d.options[rand(#d.options)].id end
			-- (each ask is a new decision table, so count per activation)
			local k2 = g.turnNumber .. ":" .. d.card
			budget[k2] = (budget[k2] or 0) + 1
			if budget[k2] > 4 then return { action = "done" } end
			local p = g.players[d.player]
			local a = { action = actions[rand(#actions)], player = g:living()[rand(#g:living())], amount = rand(6) }
			local spread = g:allSpreadCards(1)
			if a.action == "discard" then a.card = p.hand[1]
			elseif a.action == "remove" then a.card = spread[1]
			else a.card = spread[rand(math.max(#spread, 1))] end
			if a.action == "permit_flip" then a.card = nil end
			if not TTE.MANUAL_ACTIONS[a.action].check(g, a) then return { action = "done" } end
			return a
		end)
		ok(g.over, "seed " .. seed .. " finished")
		STATS.turns = STATS.turns + g.turnNumber
		for _, line in ipairs(g.log) do
			if line:find("flips .* face up") then STATS.flips = STATS.flips + 1 end
		end
		eq(countCards(g), 78, "seed " .. seed .. " cards")
		ok(#g.winners <= 1, "seed " .. seed .. " winners")
	end
end)

ok(STATS.flips > 0) -- (sanity: the random games exercised instant-speed flips)
print(string.format("%d passed, %d failed  (random games: %d turns, %d instant flips)", passed, failed, STATS.turns, STATS.flips))
if failed > 0 then os.exit(1) end
