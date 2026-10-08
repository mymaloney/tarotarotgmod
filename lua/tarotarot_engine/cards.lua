-- Tarotarot rules engine: card scripts, one function per side.
--
-- TTE.Cards[name] = { upright = function(g, ctx), reversed = function(g, ctx) }
--   ctx.card       "this card" (when copying: the card doing the copying)
--   ctx.controller "you"
-- "A card" means a card on any player's spread (rulebook: "If a card refers
-- to a card, assume it refers to cards on any player's spread"). Where the
-- text leaves something open, the choice made is noted (see docs/ENGINE.md).

local C = TTE.Cards
local function card(name, upright, reversed) C[name] = { upright = upright, reversed = reversed } end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function suitOf(g, cid) return g.cards[cid].def.suit end
local function onSpread(g, cid) local l = g.cards[cid].loc return l and l.zone == "spread" end
local function posOf(g, cid) return onSpread(g, cid) and g.cards[cid].loc.pos or nil end

local function filter(list, fn)
	local out = {}
	for _, v in ipairs(list) do if fn(v) then out[#out + 1] = v end end
	return out
end

local function copyList(list)
	local out = {}
	for i, v in ipairs(list) do out[i] = v end
	return out
end

local function spread(g, pid) return g:spreadCards(pid) end
local function allSpread(g, me) return g:allSpreadCards(me) end
local function faceUpSpread(g, me) return filter(allSpread(g, me), function(c) return g.cards[c].faceUp end) end
local function others(g, me, list) return filter(list, function(c) return c ~= me end) end

-- Deal `amount` damage to a player `me` chooses (from `candidates`, default everyone).
local function damageChosen(g, me, amount, prompt, candidates)
	local target = g:choosePlayer(me, prompt or ("Deal " .. amount .. " damage to which player?"), candidates)
	if target then return g:damage(target, amount, me), target end
	return 0
end

-- The player(s) with the most/least life; a tie is broken by `me`.
local function extremeLife(g, me, most, prompt)
	local best, tied = nil, {}
	for _, pid in ipairs(g:living()) do
		local life = g.players[pid].life
		if best == nil or (most and life > best) or (not most and life < best) then
			best, tied = life, { pid }
		elseif life == best then
			tied[#tied + 1] = pid
		end
	end
	if #tied == 1 then return tied[1] end
	return g:choosePlayer(me, prompt, tied)
end

-- A player discards a card of their choice. Returns it, or nil if they can't.
local function discardOne(g, pid, prompt)
	local hand = g.players[pid].hand
	if #hand == 0 then return nil end
	local cid = g:chooseCard(pid, prompt or "Discard a card.", copyList(hand))
	g:discard(cid)
	return cid
end

-- Let a player flip a face-down card at any time to activate and silence it.
local function permitFlip(g, pid, cid)
	g:addPermission({ player = pid, kind = "flip", card = cid, uses = 1,
		desc = "flip a face-down card at any time to activate it and silence it" })
end

-- "You may reverse them": choose none, one or both of two cards to reverse.
local function mayReverseEither(g, me, a, b, both)
	local items = { { label = "Neither", value = "none" },
		{ label = "Reverse " .. g:cardLabel(a, me), value = "a" },
		{ label = "Reverse " .. g:cardLabel(b, me), value = "b" } }
	if both then items[#items + 1] = { label = "Reverse both", value = "both" } end
	local pick = g:chooseOne(me, "Reverse a card?", items, { always = true })
	if (pick == "a" or pick == "both") and onSpread(g, a) then g:reverse(a) end
	if (pick == "b" or pick == "both") and onSpread(g, b) then g:reverse(b) end
end

-- Copy an effect of either side of one of `cids` (ruling 7: "this card" is the
-- copier and "you" its controller). A copy can't copy an effect it is already
-- part of (5 of Cups copying itself, or two copy cards copying each other),
-- which would never end.
local function copyEffect(g, ctx, cids, sideFixed)
	local me = ctx.controller
	local chain = {}
	for k in pairs(ctx.chain or {}) do chain[k] = true end
	chain[g.cards[ctx.copying or ctx.card].name .. ":" .. ctx.side] = true
	local function allowed(cid, side) return not chain[g.cards[cid].name .. ":" .. side] end

	local target, side
	if sideFixed then
		local items = {}
		for _, a in ipairs(cids) do
			if allowed(a.card, a.side) then
				items[#items + 1] = { label = g.cards[a.card].name .. " (" .. a.side .. "): " .. (g.cards[a.card].def[a.side] or ""), value = a }
			end
		end
		local pick = g:chooseOne(me, "Copy which effect?", items)
		if not pick then return end
		target, side = pick.card, pick.side
	else
		cids = filter(cids, function(c) return allowed(c, "upright") or allowed(c, "reversed") end)
		target = g:chooseCard(me, "Copy an effect of which card?", cids)
		if not target then return end
		local def, items = g.cards[target].def, {}
		for _, s in ipairs({ "upright", "reversed" }) do
			if allowed(target, s) then
				items[#items + 1] = { label = (s == "upright" and "Upright: " or "Reversed: ") .. (def[s] or ""), value = s }
			end
		end
		side = g:chooseOne(me, "Copy which side of " .. g.cards[target].name .. "?", items, { always = true })
	end
	g:say("%s copies %s (%s).", g.players[me].name, g.cards[target].name, side)
	g:runEffect(target, side, { card = ctx.card, controller = me, side = side, copying = target, chain = chain })
end

-- Move up to `n` cards from the top of a deck to memory (not a draw).
local function deckToMemory(g, pid, n)
	for _ = 1, n do
		local top = g:topOfDeck(pid)
		if not top then return end
		g:putCard(top, pid, "memory")
	end
	g:say("%s moves %d card(s) from their deck to memory.", g.players[pid].name, n)
end

-- Draw until you have `n` cards in hand.
local function drawUpTo(g, pid, n)
	while #g.players[pid].hand < n and not g.players[pid].drewFromEmpty do g:draw(pid) end
end

-- Reveal any number of cards from your hand; count those of `suit`.
local function revealAndCount(g, me, suit, verb)
	local shown = g:chooseCards(me, "Reveal cards from your hand (" .. verb .. ")", copyList(g.players[me].hand))
	local n = 0
	for _, cid in ipairs(shown) do
		g:reveal(cid, me)
		if suitOf(g, cid) == suit then n = n + 1 end
	end
	return n
end

local function countSuit(g, pid, suit)
	return #filter(spread(g, pid), function(c) return suitOf(g, c) == suit end)
end

-- "Name a card. Cards with the chosen name cannot be <events> until your next turn."
local function forbidByName(g, me, events, verb)
	local name = g:chooseName(me, "Name a card.")
	g:say("%s names %s.", g.players[me].name, name)
	for _, event in ipairs(events) do
		g:addModifier({ event = event, ["until"] = { turnOf = me },
			desc = name .. " can't be " .. verb .. " until " .. g.players[me].name .. "'s next turn",
			applies = function(g, ev) return g.cards[ev.card].name == name end,
			replace = function(g, ev)
				g:say("%s can't be %s right now.", name, verb)
				return nil
			end })
	end
	return name
end

-- "Reveal the top N cards of your deck. Until the end of this turn, whenever
-- you (would) place a card, you may place one of those cards instead and
-- remove the rest from the game."
local function revealTopForPlacing(g, me, n)
	local deck = g.players[me].deck
	local shown = {}
	for i = #deck, math.max(1, #deck - n + 1), -1 do
		shown[#shown + 1] = deck[i]
		g:reveal(deck[i], me)
	end
	if #shown == 0 then return end
	local m
	m = g:addModifier({ event = "place", ["until"] = "end_of_turn", desc = "place a revealed card instead",
		applies = function(g, ev)
			if m.done or ev.player ~= me then return false end
			for _, cid in ipairs(shown) do
				if g.cards[cid].loc and g.cards[cid].loc.zone == "deck" and g.cards[cid].loc.player == me then return true end
			end
		end,
		replace = function(g, ev)
			local still = filter(shown, function(cid)
				local l = g.cards[cid].loc
				return l and l.zone == "deck" and l.player == me
			end)
			local items = {}
			for _, cid in ipairs(still) do items[#items + 1] = { label = g.cards[cid].name .. " (revealed)", value = cid } end
			local pick = g:chooseOne(me, "Place one of your revealed cards instead?", items,
				{ optional = true, noneLabel = "No, place the card I chose" })
			if not pick then return ev end
			m.done = true
			for _, cid in ipairs(still) do
				if cid ~= pick then g:removeFromGame(cid, me) end
			end
			ev.card, ev.from = pick, "deck"
			return ev
		end })
end

-- "The next time you would place a card, you may place a card from your memory instead."
local function memoryInstead(g, me, cost, permanent)
	g:addModifier({ event = "place", uses = (not permanent) and 1 or nil,
		desc = "place a card from memory instead" .. (cost and (" (pay " .. cost .. " life)") or ""),
		applies = function(g, ev)
			return ev.player == me and ev.from ~= "memory" and #g.players[me].memory > 0
				and (not cost or g.players[me].life > 0)
		end,
		replace = function(g, ev)
			local prompt = "Place a card from your memory instead" .. (cost and (" (pay " .. cost .. " life)?") or "?")
			local pick = g:chooseCard(me, prompt, copyList(g.players[me].memory),
				{ optional = true, noneLabel = "No, place the card I chose" })
			if not pick then return ev end
			if cost then g:setLife(me, g.players[me].life - cost) end
			ev.card, ev.from = pick, "memory"
			return ev
		end })
end

-- "The next time you would place a card, you may <do something> instead."
local function insteadOfPlacing(g, me, desc, action)
	g:addModifier({ event = "place", uses = 1, desc = desc,
		applies = function(g, ev) return ev.player == me and ev.source == me end,
		replace = function(g, ev)
			if g:yesNo(me, "Instead of placing that card: " .. desc .. "?") then
				action(g)
				return nil
			end
			return ev
		end })
end

-- Activate a card on its player's behalf (it goes on the stack).
local function activateCard(g, cid)
	if onSpread(g, cid) then g:activate(cid, g:cardPlayer(cid)) end
end

-- Choose a card on `me`'s spread other than this one, face up.
local function otherOwnFaceUp(g, ctx)
	return filter(spread(g, ctx.controller), function(c) return c ~= ctx.card and g.cards[c].faceUp end)
end

-- Exchange this card with another/any card; then maybe reverse either.
local function exchangeAndMayReverse(g, me, a, b)
	if not (onSpread(g, a) and onSpread(g, b)) or a == b then return end
	g:swap(a, b)
	mayReverseEither(g, me, a, b, true)
end

---------------------------------------------------------------------------
-- Major cards
---------------------------------------------------------------------------

card("The Fool",
	function(g, ctx) -- Reveal the top card of each player's deck. You may place one of them. Remove the rest from the game.
		local me, tops = ctx.controller, {}
		for _, pid in ipairs(g:inOrderFrom(me)) do
			local top = g:topOfDeck(pid)
			if top then
				g:reveal(top, pid)
				tops[#tops + 1] = top
			end
		end
		local pick = g:chooseCard(me, "Place one of the revealed cards?", tops, { optional = true, noneLabel = "Don't place one" })
		if pick then
			if not g:placeStep(me, { card = pick }) then pick = nil end
		end
		for _, cid in ipairs(tops) do
			if cid ~= pick and g.cards[cid].loc and g.cards[cid].loc.zone == "deck" then g:removeFromGame(cid, me) end
		end
	end,
	function(g, ctx) -- Deal 5 damage to each player.
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do g:damage(pid, 5, ctx.controller) end
	end)

card("The Magician",
	function(g, ctx) -- Place a card. You may reverse this card.
		g:placeOrDraw(ctx.controller)
		if onSpread(g, ctx.card) and g:yesNo(ctx.controller, "Reverse " .. g.cards[ctx.card].name .. "?") then g:reverse(ctx.card) end
	end,
	function(g, ctx) -- Draw 3, then discard 3. If you cannot do either, you win the game.
		local me = ctx.controller
		if #g.players[me].deck < 3 then return g:win(me) end
		for _ = 1, 3 do g:draw(me) end
		for _ = 1, 3 do discardOne(g, me, "Discard a card (Magician).") end
	end)

card("The High Priestess",
	function(g, ctx) -- Name a card. Choose a player to reveal cards from their deck until they reveal the named card. If they do, put the revealed cards in their memory. Otherwise, that player shuffles.
		local me = ctx.controller
		local name = g:chooseName(me, "Name a card.")
		g:say("%s names %s.", g.players[me].name, name)
		local target = g:choosePlayer(me, "Who reveals cards from their deck?")
		local deck, revealed, found = g.players[target].deck, {}, false
		for i = #deck, 1, -1 do
			revealed[#revealed + 1] = deck[i]
			g:reveal(deck[i], target)
			if g.cards[deck[i]].name == name then found = true break end
		end
		if found then
			for _, cid in ipairs(revealed) do g:putCard(cid, target, "memory") end
			g:say("The revealed cards go to %s's memory.", g.players[target].name)
		else
			g:shuffleDeck(target)
		end
	end,
	function(g, ctx) -- Place any number of cards face-down. Each player may flip a face-down card face up at any time to activate it and silence it.
		while g:placeStep(ctx.controller, { faceDown = true, optional = true }) do end
		for _, pid in ipairs(g:living()) do permitFlip(g, pid) end
	end)

local function emperorEmpress(other)
	return function(g, ctx) -- If The <other> is on your spread, you win the game.
		for _, cid in ipairs(spread(g, ctx.controller)) do
			if g.cards[cid].name == other then return g:win(ctx.controller) end
		end
	end
end
local function placeFromAnyMemory(g, ctx) -- You may place a card from any player's memory, then silence it and reverse this card.
	local placed = g:placeStep(ctx.controller, { from = { "memory" }, memoryOf = g:living(), optional = true })
	if placed then
		g:silence(placed)
		if onSpread(g, ctx.card) then g:reverse(ctx.card) end
	end
end
card("The Empress", emperorEmpress("The Emperor"), placeFromAnyMemory)
card("The Emperor", emperorEmpress("The Empress"),
	function(g, ctx) -- You may replace any other card on your spread with a card from any player's spread, then reverse this card.
		local me = ctx.controller
		local mine = others(g, ctx.card, spread(g, me))
		local victim = g:chooseCard(me, "Replace which card on your spread?", mine, { optional = true, noneLabel = "Don't replace" })
		if not victim then return end
		local pos = posOf(g, victim)
		local from = filter(allSpread(g, me), function(c) return c ~= victim and c ~= ctx.card end)
		local taken = g:chooseCard(me, "With which card from any player's spread?", from, { optional = true, noneLabel = "Don't replace" })
		if not taken then return end
		g:putCard(victim, me, "memory")
		g:say("%s goes to memory.", g.cards[victim].name)
		g:place(me, taken, pos, g.cards[taken].reversed, { faceDown = not g.cards[taken].faceUp })
		if onSpread(g, ctx.card) then g:reverse(ctx.card) end
	end)

card("The Hierophant",
	function(g, ctx) -- Choose Wands, Cups, Swords, or Pentacles. Remove all cards that aren't of the chosen suit from the game.
		local suit = g:chooseSuit(ctx.controller, "Choose a suit.", { "Wands", "Cups", "Swords", "Pentacles" })
		for _, cid in ipairs(allSpread(g, ctx.controller)) do
			if suitOf(g, cid) ~= suit then g:removeFromGame(cid, ctx.controller) end
		end
	end,
	function(g, ctx) -- Dismiss all Major cards. For each card dismissed this way, its player may place a Minor card from their hand to that position.
		local gone = {}
		for _, cid in ipairs(allSpread(g, ctx.controller)) do
			if g.cards[cid].major then
				local pid, pos = g:cardPlayer(cid), posOf(g, cid)
				if g:dismiss(cid, ctx.controller) then gone[#gone + 1] = { pid = pid, pos = pos } end
			end
		end
		for _, s in ipairs(gone) do
			g:placeStep(s.pid, { from = { "hand" }, at = s.pos, optional = true,
				filter = function(g, c) return not g.cards[c].major end,
				prompt = "You may place a Minor card from your hand in your " .. s.pos .. "." })
		end
	end)

card("The Lovers",
	function(g, ctx) -- Each player chooses to draw 2 or gain 5 life.
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do
			if g:yesNo(pid, "The Lovers: draw 2 cards or gain 5 life?", "Draw 2", "Gain 5 life") then
				g:draw(pid); g:draw(pid)
			else
				g:gainLife(pid, 5, ctx.controller)
			end
		end
	end,
	function(g, ctx) -- Each opponent must discard. If they cannot, deal 3 damage to them.
		for _, pid in ipairs(g:opponents(ctx.controller)) do
			if not discardOne(g, pid, "The Lovers: you must discard a card.") then g:damage(pid, 3, ctx.controller) end
		end
	end)

card("The Chariot",
	function(g, ctx) -- Take a card and put it on your spread. You may reverse it. You cannot replace Major cards this way.
		local me = ctx.controller
		local cands = others(g, ctx.card, allSpread(g, me))
		local taken = g:chooseCard(me, "Take which card?", cands)
		if not taken then return g:placeOrDraw(me, { from = {} }) end -- nothing to take: can't place
		if g:placeOrDraw(me, { card = taken, orientation = false }) and onSpread(g, taken)
			and g:yesNo(me, "Reverse " .. g:cardLabel(taken, me) .. "?") then
			g:reverse(taken)
		end
	end,
	function(g, ctx) -- Remove all cards in a player's memory from the game.
		local target = g:choosePlayer(ctx.controller, "Remove all cards in whose memory?")
		for _, cid in ipairs(copyList(g.players[target].memory)) do g:removeFromGame(cid, ctx.controller) end
	end)

card("Strength",
	function(g, ctx) -- Deal damage to an opponent equal to half their life rounded down, then deal that much damage to yourself. This cannot reduce your life total to less than 1.
		local me = ctx.controller
		local op = g:choosePlayer(me, "Which opponent?", g:opponents(me))
		if not op then return end
		local dealt = g:damage(op, math.floor(math.max(g.players[op].life, 0) / 2), me)
		local selfDamage = math.min(dealt, math.max(g.players[me].life - 1, 0))
		g:damage(me, selfDamage, me)
	end,
	function(g, ctx) -- Choose any number up to 10. Deal that much damage to each player.
		local n = g:chooseNumber(ctx.controller, "Choose a number up to 10.", 0, 10)
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do g:damage(pid, n, ctx.controller) end
	end)

card("The Hermit",
	function(g, ctx) -- You may dismiss this card to reveal cards from your deck until you reveal a Major card. You may replace this card with it or draw it. Shuffle your deck.
		local me = ctx.controller
		if not onSpread(g, ctx.card) or not g:yesNo(me, "Dismiss The Hermit to look for a Major card?") then return end
		local pos, owner = posOf(g, ctx.card), g:cardPlayer(ctx.card)
		g:dismiss(ctx.card, me)
		local deck, found = g.players[me].deck, nil
		for i = #deck, 1, -1 do
			g:reveal(deck[i], me)
			if g.cards[deck[i]].major then found = deck[i] break end
		end
		if found then
			local canReplace = owner == me and not g.players[me].spread[pos]
			if canReplace and g:yesNo(me, "Put " .. g.cards[found].name .. " where The Hermit was, or draw it?", "Put it in your " .. pos, "Draw it") then
				g:placeStep(me, { card = found, at = pos })
			else
				g:putCard(found, me, "hand")
				g:say("%s draws %s.", g.players[me].name, g.cards[found].name)
			end
		end
		g:shuffleDeck(me)
	end,
	function(g, ctx) -- Each player chooses up to 2 cards. Dismiss all other cards.
		local keep = {}
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do
			for _, cid in ipairs(g:chooseCards(pid, "The Hermit: choose up to 2 cards to keep", allSpread(g, ctx.controller), 2)) do
				keep[cid] = true
			end
		end
		for _, cid in ipairs(allSpread(g, ctx.controller)) do
			if not keep[cid] then g:dismiss(cid, ctx.controller) end
		end
	end)

card("The Wheel of Fortune",
	function(g, ctx) -- Flip a coin. If you win, gain 5 life and flip again. Repeat until you lose a flip.
		for _ = 1, 100 do
			local win = g:coin()
			g:say("Coin flip: %s.", win and "won" or "lost")
			if not win then break end
			g:gainLife(ctx.controller, 5, ctx.controller)
		end
	end,
	function(g, ctx) -- Choose an opponent. Flip a coin. Deal 2 damage to the loser. The winner may flip again, doubling the damage dealt that flip. Repeat this process until the winner chooses not to flip.
		local me = ctx.controller
		local op = g:choosePlayer(me, "Choose an opponent.", g:opponents(me))
		if not op then return end
		local amount = 2
		for _ = 1, 30 do
			local winner = g:coin() and me or op
			local loser = winner == me and op or me
			g:say("Coin flip: %s wins.", g.players[winner].name)
			g:damage(loser, amount, me)
			amount = amount * 2
			if not g:yesNo(winner, "You won the flip. Flip again for " .. amount .. " damage?") then break end
		end
	end)

card("Justice",
	function(g, ctx) -- The player with the least life gains 5 life, then deal 5 damage to the player with the most life. If there is a tie, you choose.
		local me = ctx.controller
		g:gainLife(extremeLife(g, me, false, "Tied for least life: who gains 5?"), 5, me)
		g:damage(extremeLife(g, me, true, "Tied for most life: who takes 5 damage?"), 5, me)
	end,
	function(g, ctx) -- The player with the greatest life gains 5 life, then deal 5 damage to the player with the least life. If there is a tie, you choose.
		local me = ctx.controller
		g:gainLife(extremeLife(g, me, true, "Tied for most life: who gains 5?"), 5, me)
		g:damage(extremeLife(g, me, false, "Tied for least life: who takes 5 damage?"), 5, me)
	end)

card("The Hanged Man",
	function(g, ctx) -- Dismiss any number of cards on your spread. On this turn, whenever you place a card, you may place an additional card for each card you dismissed.
		local me = ctx.controller
		local n = 0
		for _, cid in ipairs(g:chooseCards(me, "Dismiss cards on your spread", spread(g, me))) do
			if g:dismiss(cid, me) then n = n + 1 end
		end
		if n == 0 then return end
		local busy = false
		g:addTrigger({ event = "place", controller = me, ["until"] = "end_of_turn",
			desc = "place " .. n .. " additional card(s)",
			applies = function(g, ev) return ev.player == me and not busy end,
			run = function(g)
				busy = true
				for _ = 1, n do
					if not g:placeStep(me, { optional = true, prompt = "The Hanged Man: place an additional card?" }) then break end
				end
				busy = false
			end })
	end,
	function(g, ctx) -- The next time a player's life total would be reduced to less than 1, it is reduced to 1 instead.
		g:addModifier({ event = "damage", uses = 1, desc = "life can't go below 1 (once)",
			applies = function(g, ev) return g.players[ev.player].life - ev.amount < 1 end,
			replace = function(g, ev)
				ev.amount = math.max(g.players[ev.player].life - 1, 0)
				return ev
			end })
	end)

card("Death",
	function(g, ctx) -- Place up to 3 cards. Deal damage to a player equal to 5 minus the number of cards placed.
		local me, n = ctx.controller, 0
		for _ = 1, 3 do
			if not g:placeStep(me, { optional = true, prompt = "Place up to 3 cards (" .. n .. " placed)." }) then break end
			n = n + 1
		end
		damageChosen(g, me, 5 - n)
	end,
	function(g, ctx) -- Dismiss up to 3 cards on your spread. Deal 5 damage to a player for each card dismissed.
		local me = ctx.controller
		for _, cid in ipairs(g:chooseCards(me, "Dismiss up to 3 cards on your spread", spread(g, me), 3)) do
			if g:dismiss(cid, me) then damageChosen(g, me, 5) end
		end
	end)

card("Temperance",
	function(g, ctx) -- Deal damage to players who have more life than the lowest life total until all players have the same life total.
		local low
		for _, pid in ipairs(g:living()) do
			if not low or g.players[pid].life < low then low = g.players[pid].life end
		end
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do
			local over = g.players[pid].life - low
			if over > 0 then g:damage(pid, over, ctx.controller) end
		end
	end,
	function(g, ctx) -- If you have the lowest life total among all players, increase your life total to the lowest life total among all other players.
		local me = ctx.controller
		local mine, low = g.players[me].life, nil
		for _, pid in ipairs(g:opponents(me)) do
			if not low or g.players[pid].life < low then low = g.players[pid].life end
		end
		if low and mine <= low and low > mine then g:gainLife(me, low - mine, me) end
	end)

card("The Devil",
	function(g, ctx) -- Deal 3 damage to each opponent. Gain 1 life for each opponent damaged this way.
		local hit = 0
		for _, pid in ipairs(g:opponents(ctx.controller)) do
			if g:damage(pid, 3, ctx.controller) > 0 then hit = hit + 1 end
		end
		g:gainLife(ctx.controller, hit, ctx.controller)
	end,
	function(g, ctx) -- Remove all cards on your spread from the game. For the rest of the game, whenever you would place a card, you may pay 2 life to place a card from your memory instead.
		local me = ctx.controller
		for _, cid in ipairs(spread(g, me)) do g:removeFromGame(cid, me) end
		memoryInstead(g, me, 2, true)
	end)

card("The Tower",
	function(g, ctx) -- Remove this card from the game. Shuffle all cards into their players' decks. Starting with you, each player places 2 cards and cannot replace cards this way.
		local me = ctx.controller
		g:removeFromGame(ctx.card, me)
		for _, cid in ipairs(allSpread(g, me)) do g:putCard(cid, g:cardPlayer(cid), "deck") end
		for _, pid in ipairs(g:inOrderFrom(me)) do g:shuffleDeck(pid) end
		for _, pid in ipairs(g:inOrderFrom(me)) do
			for _ = 1, 2 do g:placeOrDraw(pid, { noReplace = true, prompt = "The Tower: place a card (no replacing)." }) end
		end
	end,
	function(g, ctx) -- Remove this card from the game, then flip all cards. Each player may flip a face-down card at any time to activate it and silence it.
		g:removeFromGame(ctx.card, ctx.controller)
		for _, cid in ipairs(allSpread(g, ctx.controller)) do g:flip(cid) end
		for _, pid in ipairs(g:living()) do permitFlip(g, pid) end
	end)

card("The Star",
	function(g, ctx) -- Gain 3 life. If you have at least 10 more life than each opponent, you win the game.
		local me = ctx.controller
		g:gainLife(me, 3, me)
		for _, pid in ipairs(g:opponents(me)) do
			if g.players[me].life < g.players[pid].life + 10 then return end
		end
		g:win(me)
	end,
	function(g, ctx) -- Deal 2 damage to each player, then deal damage to each opponent equal to the damage you have dealt to them this turn.
		local me = ctx.controller
		for _, pid in ipairs(g:inOrderFrom(me)) do g:damage(pid, 2, me) end
		for _, pid in ipairs(g:opponents(me)) do g:damage(pid, g:damageDealt(me, pid), me) end
	end)

card("The Moon",
	function(g, ctx) -- Return all other cards to their players' hands and remove this card from the game. Starting with you, each player places 2 cards to any other player's spread.
		local me = ctx.controller
		for _, cid in ipairs(others(g, ctx.card, allSpread(g, me))) do g:returnToHand(cid) end
		g:removeFromGame(ctx.card, me)
		for _, pid in ipairs(g:inOrderFrom(me)) do
			for _ = 1, 2 do
				local onto = g:choosePlayer(pid, "The Moon: place a card on whose spread?", g:opponents(pid))
				if onto then g:placeOrDraw(pid, { onto = onto }) end
			end
		end
	end,
	function(g, ctx) -- For each card in an opponent's hand and spread, its player moves one card from their deck to memory.
		for _, pid in ipairs(g:opponents(ctx.controller)) do
			deckToMemory(g, pid, #g.players[pid].hand + #spread(g, pid))
		end
	end)

card("The Sun",
	function(g, ctx) -- If you have fewer than 5 cards in hand, you may draw until you have 5 cards in hand. You may draw to less than 5.
		local me = ctx.controller
		local room = 5 - #g.players[me].hand
		if room <= 0 then return end
		for _ = 1, g:chooseNumber(me, "Draw how many cards?", 0, room) do g:draw(me) end
	end,
	function(g, ctx) -- Deal damage to each player equal to the number of cards in their hand.
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do g:damage(pid, #g.players[pid].hand, ctx.controller) end
	end)

card("Judgement",
	function(g, ctx) -- Dismiss all cards. For each card on an opponent's spread dismissed this way, deal 2 damage to that player.
		local me = ctx.controller
		for _, cid in ipairs(allSpread(g, me)) do
			local pid = g:cardPlayer(cid)
			if g:dismiss(cid, me) and pid ~= me then g:damage(pid, 2, me) end
		end
	end,
	function(g, ctx) -- Dismiss this card. Place up to 3 cards.
		local me = ctx.controller
		if onSpread(g, ctx.card) then g:dismiss(ctx.card, me) end
		for i = 1, 3 do
			if not g:placeStep(me, { optional = true, prompt = "Place up to 3 cards (" .. (i - 1) .. " placed)." }) then break end
		end
	end)

card("The World",
	function(g, ctx) -- Put a counter on The World, then deal damage to each opponent equal to the number of counters on The World.
		if not onSpread(g, ctx.card) then return end
		g:addCounter(ctx.card, "generic", 1)
		local n = g:counters(ctx.card, "generic")
		for _, pid in ipairs(g:opponents(ctx.controller)) do g:damage(pid, n, ctx.controller) end
	end,
	function(g, ctx) -- Put 7 counters on The World. If there are 21 or more counters on The World, reverse it.
		if not onSpread(g, ctx.card) then return end
		g:addCounter(ctx.card, "generic", 7)
		g:say("%s has %d counters.", g.cards[ctx.card].name, g:counters(ctx.card, "generic"))
		if g:counters(ctx.card, "generic") >= 21 then g:reverse(ctx.card) end
	end)

---------------------------------------------------------------------------
-- Pentacles
---------------------------------------------------------------------------

card("Ace of Pentacles",
	function(g, ctx) -- Deal 2 damage to yourself. The next time you place a card, draw 2.
		local me = ctx.controller
		g:damage(me, 2, me)
		g:addTrigger({ event = "place", controller = me, uses = 1, desc = "draw 2 after your next place",
			applies = function(g, ev) return ev.player == me end,
			run = function(g) g:draw(me); g:draw(me) end })
	end,
	function(g, ctx) -- Dismiss a non-Wand, non-Pentacle card.
		local cands = filter(allSpread(g, ctx.controller), function(c) local s = suitOf(g, c) return s ~= "Wands" and s ~= "Pentacles" end)
		local cid = g:chooseCard(ctx.controller, "Dismiss which card?", cands)
		if cid then g:dismiss(cid, ctx.controller) end
	end)

card("2 of Pentacles",
	function(g, ctx) -- Deal damage to a player equal to the number of cards in their hand.
		local target = g:choosePlayer(ctx.controller, "Deal damage equal to whose hand size?")
		g:damage(target, #g.players[target].hand, ctx.controller)
	end,
	function(g, ctx) -- Exchange the positions of two cards. You may reverse them. If both cards are on spreads other than yours, draw.
		local me = ctx.controller
		local pair = g:chooseCards(me, "Exchange which two cards?", allSpread(g, me), 2, { min = 2 })
		if #pair < 2 then return end
		local a, b = pair[1], pair[2]
		local bothOthers = g:cardPlayer(a) ~= me and g:cardPlayer(b) ~= me
		exchangeAndMayReverse(g, me, a, b)
		if bothOthers then g:draw(me) end
	end)

card("3 of Pentacles",
	function(g, ctx) -- Choose a player to reveal their hand. Choose a card from it. That player discards that card.
		local me = ctx.controller
		local target = g:choosePlayer(me, "Who reveals their hand?")
		local hand = copyList(g.players[target].hand)
		for _, cid in ipairs(hand) do g:reveal(cid, target) end
		local items = {}
		for _, cid in ipairs(hand) do items[#items + 1] = { label = g.cards[cid].name, value = cid } end
		local cid = g:chooseOne(me, "Which card do they discard?", items)
		if cid then g:discard(cid) end
	end,
	function(g, ctx) -- Deal damage to each player equal to 5 minus the number of cards they have in hand. If the damage is negative, that player draws that many.
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do
			local n = 5 - #g.players[pid].hand
			if n > 0 then g:damage(pid, n, ctx.controller) end
			for _ = 1, -n do g:draw(pid) end
		end
	end)

card("4 of Pentacles",
	function(g, ctx) -- Dismiss this card. Take a card and put it on your spread. At the end of your next turn, dismiss that card.
		local me = ctx.controller
		if onSpread(g, ctx.card) then g:dismiss(ctx.card, me) end
		local taken = g:chooseCard(me, "Take which card?", allSpread(g, me))
		if not taken then return g:placeOrDraw(me, { from = {} }) end -- nothing to take: can't place
		if not g:placeOrDraw(me, { card = taken, orientation = false }) then return end
		local now = g.turnNumber
		g:addTrigger({ event = "turn_end", controller = me, uses = 1, desc = "dismiss " .. g.cards[taken].name,
			applies = function(g, ev) return ev.player == me and g.turnNumber > now end,
			run = function(g) if onSpread(g, taken) then g:dismiss(taken, me) end end })
	end,
	function(g, ctx) -- Deal 2 damage to any number of players, then those players each draw.
		local targets = g:choosePlayers(ctx.controller, "Deal 2 damage to which players?")
		for _, pid in ipairs(targets) do g:damage(pid, 2, ctx.controller) end
		for _, pid in ipairs(targets) do if not g.players[pid].eliminated then g:draw(pid) end end
	end)

card("5 of Pentacles",
	function(g, ctx) -- Each opponent with a Major card or a Swords card on their spread discards.
		for _, pid in ipairs(g:opponents(ctx.controller)) do
			local has = #filter(spread(g, pid), function(c) return g.cards[c].major or suitOf(g, c) == "Swords" end) > 0
			if has then discardOne(g, pid, "5 of Pentacles: discard a card.") end
		end
	end,
	function(g, ctx) -- If you have fewer than 2 cards in hand, draw until you have 2 cards in hand.
		drawUpTo(g, ctx.controller, 2)
	end)

card("6 of Pentacles",
	function(g, ctx) -- Gain life equal to the number of cards you have in hand.
		g:gainLife(ctx.controller, #g.players[ctx.controller].hand, ctx.controller)
	end,
	function(g, ctx) -- Each opponent may give you a card from their hand. Deal 3 damage to each opponent who doesn't.
		local me = ctx.controller
		for _, pid in ipairs(g:opponents(me)) do
			local gift = g:chooseCard(pid, "Give " .. g.players[me].name .. " a card, or take 3 damage?",
				copyList(g.players[pid].hand), { optional = true, noneLabel = "Take 3 damage" })
			if gift then
				g:putCard(gift, me, "hand")
				g:say("%s gives %s a card.", g.players[pid].name, g.players[me].name)
			else
				g:damage(pid, 3, me)
			end
		end
	end)

card("7 of Pentacles",
	function(g, ctx) -- Put a counter on this card. You may dismiss this card. If you do, your life total becomes equal to 7 times the number of counters on this card.
		local me = ctx.controller
		if not onSpread(g, ctx.card) then return end
		g:addCounter(ctx.card, "generic", 1)
		local n = g:counters(ctx.card, "generic")
		if g:yesNo(me, "Dismiss it to set your life to " .. (7 * n) .. "?") and g:dismiss(ctx.card, me) then
			g:setLife(me, 7 * n)
		end
	end,
	function(g, ctx) -- Choose a player with at least one card in their hand. That player discards their hand, then draws that many minus 1.
		local cands = filter(g:living(), function(pid) return #g.players[pid].hand > 0 end)
		local target = g:choosePlayer(ctx.controller, "Who discards their hand?", cands)
		if not target then return end
		local n = #g.players[target].hand
		for _, cid in ipairs(copyList(g.players[target].hand)) do g:discard(cid) end
		for _ = 1, n - 1 do g:draw(target) end
	end)

card("8 of Pentacles",
	function(g, ctx) -- Copy an effect of either side of a card on another player's spread.
		local cands = filter(faceUpSpread(g, ctx.controller), function(c) return g:cardPlayer(c) ~= ctx.controller end)
		copyEffect(g, ctx, cands)
	end,
	function(g, ctx) -- You may reveal a Major card or Pentacles card from your hand. If you do, place it.
		local me = ctx.controller
		local cands = filter(g.players[me].hand, function(c) return g.cards[c].major or suitOf(g, c) == "Pentacles" end)
		local cid = g:chooseCard(me, "Reveal and place which card?", cands, { optional = true, noneLabel = "Don't reveal" })
		if cid then
			g:reveal(cid, me)
			g:placeOrDraw(me, { card = cid })
		end
	end)

card("9 of Pentacles",
	function(g, ctx) -- Until the end of this turn, whenever you place a card, you may draw.
		local me = ctx.controller
		g:addTrigger({ event = "place", controller = me, ["until"] = "end_of_turn", desc = "you may draw",
			applies = function(g, ev) return ev.player == me end,
			run = function(g) if g:yesNo(me, "9 of Pentacles: draw a card?") then g:draw(me) end end })
	end,
	function(g, ctx) -- Return any number of cards from your memory to your hand. Deal damage to yourself equal to the number of cards returned.
		local me = ctx.controller
		local back = g:chooseCards(me, "Return cards from your memory to your hand", copyList(g.players[me].memory))
		for _, cid in ipairs(back) do g:putCard(cid, me, "hand") end
		if #back > 0 then
			g:say("%s returns %d card(s) from memory to hand.", g.players[me].name, #back)
			g:damage(me, #back, me)
		end
	end)

card("10 of Pentacles",
	function(g, ctx) -- Place a card from your memory.
		g:placeOrDraw(ctx.controller, { from = { "memory" } })
	end,
	function(g, ctx) -- Choose up to three cards from one player's memory and remove them from the game.
		local me = ctx.controller
		local cands = filter(g:living(), function(pid) return #g.players[pid].memory > 0 end)
		local target = g:choosePlayer(me, "From whose memory?", cands)
		if not target then return end
		for _, cid in ipairs(g:chooseCards(me, "Remove up to 3 cards from the game", copyList(g.players[target].memory), 3)) do
			g:removeFromGame(cid, me)
		end
	end)

card("Page of Pentacles",
	function(g, ctx) -- Reveal any number of cards from your hand. For each Pentacles card you revealed and each Pentacles card on your spread, deal 2 damage to a player and gain 1 life.
		local me = ctx.controller
		local n = revealAndCount(g, me, "Pentacles", "Pentacles count") + countSuit(g, me, "Pentacles")
		for i = 1, n do
			damageChosen(g, me, 2, string.format("Deal 2 damage to which player? (%d of %d)", i, n))
			g:gainLife(me, 1, me)
		end
	end,
	function(g, ctx) -- Choose up to 3 cards from your memory. For each chosen card, remove that card from the game and deal 1 damage to any player.
		local me = ctx.controller
		for _, cid in ipairs(g:chooseCards(me, "Choose up to 3 cards from your memory", copyList(g.players[me].memory), 3)) do
			g:removeFromGame(cid, me)
			damageChosen(g, me, 1)
		end
	end)

card("Knight of Pentacles",
	function(g, ctx) -- You may place a card in your Future position. You may exchange its position with another card on your spread and reverse either card.
		local me = ctx.controller
		local placed = g:placeStep(me, { at = "future", optional = true })
		if not placed then return end
		local other = g:chooseCard(me, "Exchange it with another card on your spread?", others(g, placed, spread(g, me)),
			{ optional = true, noneLabel = "Don't exchange" })
		if other then
			g:swap(placed, other)
			mayReverseEither(g, me, placed, other, false)
		end
	end,
	function(g, ctx) -- If you have fewer than 2 cards in hand, draw until you have 2 cards in hand.
		drawUpTo(g, ctx.controller, 2)
	end)

card("Queen of Pentacles",
	function(g, ctx) -- Move 3 cards from your deck to your memory. The next time you would place a card, you may place a card from your memory instead.
		deckToMemory(g, ctx.controller, 3)
		memoryInstead(g, ctx.controller)
	end,
	function(g, ctx) -- Deal 2 damage to a player, then gain life equal to the damage dealt this way.
		local dealt = damageChosen(g, ctx.controller, 2)
		g:gainLife(ctx.controller, dealt, ctx.controller)
	end)

local function dismissAllWhere(g, ctx, test, includeThis)
	local me, drawers = ctx.controller, {}
	for _, cid in ipairs(allSpread(g, me)) do
		if test(cid) and (includeThis or cid ~= ctx.card) then
			local pid = g:cardPlayer(cid)
			if g:dismiss(cid, me) then drawers[#drawers + 1] = pid end
		end
	end
	return drawers
end
local function eachMayDraw(g, drawers)
	for _, pid in ipairs(drawers) do
		if not g.players[pid].eliminated and g:yesNo(pid, "You may draw a card.", "Draw", "Don't draw") then g:draw(pid) end
	end
end
card("King of Pentacles",
	function(g, ctx) -- Dismiss all Major cards, then dismiss this card. For each card dismissed, its player may draw.
		local drawers = dismissAllWhere(g, ctx, function(c) return g.cards[c].major end)
		if onSpread(g, ctx.card) then
			local pid = g:cardPlayer(ctx.card)
			if g:dismiss(ctx.card, ctx.controller) then drawers[#drawers + 1] = pid end
		end
		eachMayDraw(g, drawers)
	end,
	function(g, ctx) -- Dismiss all Minor cards. For each card dismissed, its player may draw.
		eachMayDraw(g, dismissAllWhere(g, ctx, function(c) return not g.cards[c].major end, true))
	end)

---------------------------------------------------------------------------
-- Swords
---------------------------------------------------------------------------

local function chooseAndReverse(g, ctx)
	local cid = g:chooseCard(ctx.controller, "Reverse which card?", allSpread(g, ctx.controller))
	if cid then g:reverse(cid) end
end
local function exchangeWithOther(g, ctx) -- Exchange a card on your spread with a card on another player's spread. You may reverse those cards.
	local me = ctx.controller
	local mine = g:chooseCard(me, "Exchange which card on your spread?", spread(g, me))
	if not mine then return end
	local theirs = g:chooseCard(me, "With which card on another spread?",
		filter(allSpread(g, me), function(c) return g:cardPlayer(c) ~= me end))
	if theirs then exchangeAndMayReverse(g, me, mine, theirs) end
end

card("Ace of Swords",
	function(g, ctx) -- Choose Wands, Cups, or Swords. For each card of the chosen suit, deal 2 damage to its player.
		local me = ctx.controller
		local suit = g:chooseSuit(me, "Choose a suit.", { "Wands", "Cups", "Swords" })
		for _, cid in ipairs(allSpread(g, me)) do
			if suitOf(g, cid) == suit then g:damage(g:cardPlayer(cid), 2, me) end
		end
	end,
	function(g, ctx) -- Dismiss a card. Its player may place another card in its place.
		local me = ctx.controller
		local cid = g:chooseCard(me, "Dismiss which card?", allSpread(g, me))
		if not cid then return end
		local pid, pos = g:cardPlayer(cid), posOf(g, cid)
		if g:dismiss(cid, me) then
			g:placeStep(pid, { at = pos, optional = true, prompt = "You may place a card in your " .. pos .. "." })
		end
	end)

card("2 of Swords",
	function(g, ctx) -- Choose a player. They may exchange the positions of any cards on their spread. If they do, they may reverse those cards.
		local target = g:choosePlayer(ctx.controller, "Choose a player.")
		local moved = {}
		for _ = 1, 6 do
			local a = g:chooseCard(target, "Exchange a card on your spread?", spread(g, target), { optional = true, noneLabel = "Done exchanging" })
			if not a then break end
			-- Exchange with another card, or move it to an empty space
			local items = {}
			for _, pos in ipairs(TTE.POSITIONS) do
				local there = g.players[target].spread[pos]
				if there ~= a then
					items[#items + 1] = { label = there and g:cardLabel(there, target) or ("empty " .. pos), value = there or pos }
				end
			end
			local b = g:chooseOne(target, "Exchange it with?", items)
			if type(b) == "number" then
				g:swap(a, b)
				moved[a], moved[b] = true, true
			elseif b then
				g:putCard(a, target, "spread", b)
				moved[a] = true
			end
		end
		for cid in pairs(moved) do
			if onSpread(g, cid) and g:yesNo(target, "Reverse " .. g:cardLabel(cid, target) .. "?") then g:reverse(cid) end
		end
	end,
	function(g, ctx) -- Reverse all cards.
		for _, cid in ipairs(allSpread(g, ctx.controller)) do g:reverse(cid) end
	end)

card("3 of Swords",
	function(g, ctx) -- Silence a card.
		local cid = g:chooseCard(ctx.controller, "Silence which card?", allSpread(g, ctx.controller))
		if cid then g:silence(cid) end
	end,
	function(g, ctx) -- Prevent the next instance of damage that would be dealt to you.
		local me = ctx.controller
		g:addModifier({ event = "damage", uses = 1, desc = "prevent the next damage to " .. g.players[me].name,
			applies = function(g, ev) return ev.player == me and ev.amount > 0 end,
			replace = function(g, ev)
				g:say("The damage to %s is prevented.", g.players[me].name)
				return nil
			end })
	end)

card("4 of Swords", exchangeWithOther,
	function(g, ctx) -- Deal 3 damage to the player with the most life. In the event of a tie, you choose which player.
		g:damage(extremeLife(g, ctx.controller, true, "Tied for most life: who takes 3 damage?"), 3, ctx.controller)
	end)

card("5 of Swords",
	function(g, ctx) -- Dismiss this card, then dismiss any other card.
		local me = ctx.controller
		if onSpread(g, ctx.card) then g:dismiss(ctx.card, me) end
		local cid = g:chooseCard(me, "Dismiss which other card?", others(g, ctx.card, allSpread(g, me)))
		if cid then g:dismiss(cid, me) end
	end,
	function(g, ctx) -- Choose another player. You and that player each draw.
		local me = ctx.controller
		local other = g:choosePlayer(me, "Choose another player.", g:opponents(me))
		g:draw(me)
		if other then g:draw(other) end
	end)

card("6 of Swords",
	function(g, ctx) -- Dismiss a Wand.
		local cid = g:chooseCard(ctx.controller, "Dismiss which Wand?",
			filter(allSpread(g, ctx.controller), function(c) return suitOf(g, c) == "Wands" end))
		if cid then g:dismiss(cid, ctx.controller) end
	end,
	function(g, ctx) -- Name a card. Cards with the chosen name cannot be dismissed until your next turn.
		forbidByName(g, ctx.controller, { "dismiss" }, "dismissed")
	end)

card("7 of Swords",
	function(g, ctx) -- Dismiss this card, then take any card and place it in this card's position. You may reverse it.
		local me = ctx.controller
		if not onSpread(g, ctx.card) or g:cardPlayer(ctx.card) ~= me then return end
		local pos = posOf(g, ctx.card)
		g:dismiss(ctx.card, me)
		local taken = g:chooseCard(me, "Take which card?", allSpread(g, me))
		if not taken then return g:placeOrDraw(me, { from = {} }) end -- nothing to take: can't place
		if g:placeOrDraw(me, { card = taken, at = pos, orientation = false })
			and g:yesNo(me, "Reverse " .. g:cardLabel(taken, me) .. "?") then
			g:reverse(taken)
		end
	end,
	chooseAndReverse)

card("8 of Swords",
	function(g, ctx) -- Dismiss a card on the spread of the player with the most life. In the event of a tie, you choose.
		local me = ctx.controller
		local most
		for _, pid in ipairs(g:living()) do
			if not most or g.players[pid].life > g.players[most].life then most = pid end
		end
		local tied = filter(g:living(), function(pid) return g.players[pid].life == g.players[most].life end)
		local target = #tied == 1 and tied[1] or g:choosePlayer(me, "Tied for most life: whose card?", tied)
		local cid = g:chooseCard(me, "Dismiss which card?", spread(g, target))
		if cid then g:dismiss(cid, me) end
	end,
	chooseAndReverse)

card("9 of Swords",
	function(g, ctx) -- The next time you would place a card, you may dismiss a card instead.
		local me = ctx.controller
		insteadOfPlacing(g, me, "dismiss a card", function(g)
			local cid = g:chooseCard(me, "Dismiss which card?", allSpread(g, me))
			if cid then g:dismiss(cid, me) end
		end)
	end,
	chooseAndReverse)

card("10 of Swords", exchangeWithOther,
	function(g, ctx) -- Shuffle up to 3 cards of your choice from your memory into your deck.
		local me = ctx.controller
		local back = g:chooseCards(me, "Shuffle up to 3 cards from memory into your deck", copyList(g.players[me].memory), 3)
		for _, cid in ipairs(back) do g:putCard(cid, me, "deck") end
		if #back > 0 then g:shuffleDeck(me) end
	end)

card("Page of Swords",
	function(g, ctx) -- Choose a number from 0 to 3. Each player draws that many.
		local n = g:chooseNumber(ctx.controller, "Each player draws how many?", 0, 3)
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do
			for _ = 1, n do g:draw(pid) end
		end
	end,
	function(g, ctx) -- Silence a card on each player's spread.
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do
			local cid = g:chooseCard(ctx.controller, "Silence which card on " .. (pid == ctx.controller and "your" or g.players[pid].name .. "'s") .. " spread?", spread(g, pid))
			if cid then g:silence(cid) end
		end
	end)

card("Knight of Swords",
	function(g, ctx) -- The next time you place a card, you may activate it and silence it.
		local me = ctx.controller
		g:addTrigger({ event = "place", controller = me, uses = 1, desc = "activate and silence your next placed card",
			applies = function(g, ev) return ev.player == me end,
			run = function(g, ev)
				if onSpread(g, ev.card) and g.cards[ev.card].faceUp and g:yesNo(me, "Activate " .. g.cards[ev.card].name .. " now and silence it?") then
					g:activate(ev.card, me)
					g:silence(ev.card)
				end
			end })
	end,
	function(g, ctx) -- Each player simultaneously chooses a number. Deal damage to each player equal to the number they chose. Dismiss a card on the spread of each player who chose the smallest number.
		local me, chosen, low = ctx.controller, {}, nil
		local order = g:inOrderFrom(me)
		for _, pid in ipairs(order) do
			chosen[pid] = g:chooseNumber(pid, "Secretly choose a number (you take that much damage).", 0, 10)
			if not low or chosen[pid] < low then low = chosen[pid] end
		end
		for _, pid in ipairs(order) do g:say("%s chose %d.", g.players[pid].name, chosen[pid]) end
		for _, pid in ipairs(order) do g:damage(pid, chosen[pid], me) end
		for _, pid in ipairs(order) do
			if chosen[pid] == low and not g.players[pid].eliminated then
				local cid = g:chooseCard(me, "Dismiss a card on " .. g.players[pid].name .. "'s spread.", spread(g, pid))
				if cid then g:dismiss(cid, me) end
			end
		end
	end)

card("Queen of Swords",
	function(g, ctx) -- Dismiss a card from each player's spread.
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do
			local cid = g:chooseCard(ctx.controller, "Dismiss which card from " .. (pid == ctx.controller and "your" or g.players[pid].name .. "'s") .. " spread?", spread(g, pid))
			if cid then g:dismiss(cid, ctx.controller) end
		end
	end,
	function(g, ctx) -- Name a card. Cards with the chosen name do not activate until your next turn.
		forbidByName(g, ctx.controller, { "activate" }, "activated")
	end)

card("King of Swords",
	function(g, ctx) -- Dismiss all cards.
		for _, cid in ipairs(allSpread(g, ctx.controller)) do g:dismiss(cid, ctx.controller) end
	end,
	function(g, ctx) -- You may dismiss any number of cards on your spread. Each opponent dismisses that many cards on their spread.
		local me, n = ctx.controller, 0
		for _, cid in ipairs(g:chooseCards(me, "Dismiss cards on your spread", spread(g, me))) do
			if g:dismiss(cid, me) then n = n + 1 end
		end
		if n == 0 then return end
		for _, pid in ipairs(g:opponents(me)) do
			local theirs = spread(g, pid)
			for _, cid in ipairs(g:chooseCards(pid, "Dismiss " .. n .. " card(s) on your spread", theirs, n, { min = math.min(n, #theirs) })) do
				g:dismiss(cid, pid)
			end
		end
	end)

---------------------------------------------------------------------------
-- Wands
---------------------------------------------------------------------------

local function damagePerSuitOnSpread(suit, per)
	return function(g, ctx)
		local target = g:choosePlayer(ctx.controller, "Which player?")
		g:damage(target, per * (suit == "Major" and #filter(spread(g, target), function(c) return g.cards[c].major end)
			or countSuit(g, target, suit)), ctx.controller)
	end
end

card("Ace of Wands",
	function(g, ctx) -- Reveal the top 3 cards of your deck. Until the end of this turn, whenever you place a card, you may place one of those cards and remove the rest from the game.
		revealTopForPlacing(g, ctx.controller, 3)
	end,
	function(g, ctx) -- Dismiss a card on your spread and place a card.
		local me = ctx.controller
		local cid = g:chooseCard(me, "Dismiss which card on your spread?", spread(g, me))
		if cid then g:dismiss(cid, me) end
		g:placeOrDraw(me)
	end)

card("2 of Wands",
	function(g, ctx) -- Until the end of this turn, the next time you would deal damage, deal double that damage instead. This can stack.
		local me = ctx.controller
		g:addModifier({ event = "damage", uses = 1, ["until"] = "end_of_turn", commutes = true, desc = "double your next damage",
			applies = function(g, ev) return ev.source == me and ev.amount > 0 end,
			replace = function(g, ev) ev.amount = ev.amount * 2 return ev end })
	end,
	function(g, ctx) -- Place a card. The next time you would place a card, do not.
		local me = ctx.controller
		g:placeOrDraw(me)
		g:addModifier({ event = "place", uses = 1, desc = "skip your next place",
			applies = function(g, ev) return ev.player == me and ev.source == me end,
			replace = function(g, ev)
				g:say("%s doesn't place a card (2 of Wands).", g.players[me].name)
				return nil
			end })
	end)

card("3 of Wands",
	function(g, ctx) -- Deal 2 damage to a player if this card is in the Past position, 3 damage if this card is in the Present position, or 4 damage if this card is in the Future position.
		local amount = ({ past = 2, present = 3, future = 4 })[posOf(g, ctx.card) or ""]
		if amount then damageChosen(g, ctx.controller, amount) end
	end,
	function(g, ctx) -- Dismiss a Minor card. Its player reveals the top card of their deck. If it's a Minor card, they may place it in the same position.
		local me = ctx.controller
		local cid = g:chooseCard(me, "Dismiss which Minor card?", filter(allSpread(g, me), function(c) return not g.cards[c].major end))
		if not cid then return end
		local pid, pos = g:cardPlayer(cid), posOf(g, cid)
		if not g:dismiss(cid, me) then return end
		local top = g:topOfDeck(pid)
		if not top then return end
		g:reveal(top, pid)
		if not g.cards[top].major and g:yesNo(pid, "Place " .. g.cards[top].name .. " in your " .. pos .. "?") then
			g:placeStep(pid, { card = top, at = pos })
		end
	end)

card("4 of Wands",
	function(g, ctx) -- Dismiss this card, then place a card. Each player discards their hand then draws 3.
		local me = ctx.controller
		if onSpread(g, ctx.card) then g:dismiss(ctx.card, me) end
		g:placeOrDraw(me)
		for _, pid in ipairs(g:inOrderFrom(me)) do
			for _, cid in ipairs(copyList(g.players[pid].hand)) do g:discard(cid) end
			for _ = 1, 3 do g:draw(pid) end
		end
	end,
	function(g, ctx) -- You may reveal any number of cards in your hand. Deal 2 damage to a player for each Wand you reveal and each Wand on your spread.
		local me = ctx.controller
		local n = revealAndCount(g, me, "Wands", "Wands count") + countSuit(g, me, "Wands")
		for i = 1, n do damageChosen(g, me, 2, string.format("Deal 2 damage to which player? (%d of %d)", i, n)) end
	end)

card("5 of Wands",
	function(g, ctx) -- Deal 3 damage to a player. Flip this card. You may flip a face-down card at any time to activate it and silence it.
		local me = ctx.controller
		damageChosen(g, me, 3)
		if onSpread(g, ctx.card) then
			g:flip(ctx.card)
			permitFlip(g, me, not g.cards[ctx.card].faceUp and ctx.card or nil)
		end
	end,
	function(g, ctx) -- Deal 1 damage to each opponent.
		for _, pid in ipairs(g:opponents(ctx.controller)) do g:damage(pid, 1, ctx.controller) end
	end)

card("6 of Wands",
	function(g, ctx) -- Activate another card on your spread.
		local cid = g:chooseCard(ctx.controller, "Activate which card?", otherOwnFaceUp(g, ctx))
		if cid then activateCard(g, cid) end
	end,
	function(g, ctx) -- Silence a card on your spread.
		local cid = g:chooseCard(ctx.controller, "Silence which card on your spread?", spread(g, ctx.controller))
		if cid then g:silence(cid) end
	end)

card("7 of Wands",
	function(g, ctx) -- Until your next turn, whenever a card on your spread is dismissed, deal 5 damage to any player.
		local me = ctx.controller
		g:addTrigger({ event = "dismiss", controller = me, ["until"] = { turnOf = me }, desc = "5 damage when your cards are dismissed",
			applies = function(g, ev) return ev.player == me end,
			run = function(g) if not g.players[me].eliminated then damageChosen(g, me, 5, "7 of Wands: deal 5 damage to which player?") end end })
	end,
	function(g, ctx) -- Discard a card. If you do, deal 4 damage to a player.
		if discardOne(g, ctx.controller) then damageChosen(g, ctx.controller, 4) end
	end)

card("8 of Wands",
	function(g, ctx) -- Deal 3 damage to a player, then replace this card with one from your hand or deck. It does not activate until your next turn.
		local me = ctx.controller
		damageChosen(g, me, 3)
		local pos = g:cardPlayer(ctx.card) == me and posOf(g, ctx.card)
		if not pos then return end
		local new = g:placeOrDraw(me, { at = pos, prompt = "Replace the 8 of Wands with a card from your hand or deck." })
		if new then
			g:addModifier({ event = "activate", ["until"] = { turnOf = me }, desc = g.cards[new].name .. " doesn't activate until your next turn",
				applies = function(g, ev) return ev.card == new end,
				replace = function() return nil end })
		end
	end,
	function(g, ctx) -- Dismiss a card. Until your next turn, whenever its player would place a card, they may place that card instead.
		local me = ctx.controller
		local cid = g:chooseCard(me, "Dismiss which card?", allSpread(g, me))
		if not cid then return end
		local owner = g:cardPlayer(cid)
		if not g:dismiss(cid, me) then return end
		g:addModifier({ event = "place", ["until"] = { turnOf = me }, desc = "you may place " .. g.cards[cid].name .. " instead",
			applies = function(g, ev)
				local l = g.cards[cid].loc
				return ev.player == owner and ev.card ~= cid and l and l.zone == "memory" and l.player == owner
			end,
			replace = function(g, ev)
				if g:yesNo(owner, "Place " .. g.cards[cid].name .. " from your memory instead?") then
					ev.card, ev.from = cid, "memory"
				end
				return ev
			end })
	end)

card("9 of Wands",
	function(g, ctx) -- Deal damage to a player equal to the total number of damage you've dealt this turn, plus 1.
		damageChosen(g, ctx.controller, g:damageDealt(ctx.controller) + 1)
	end,
	function(g, ctx) -- You may remove a card from your memory from the game and return a card from your memory to your hand.
		local me = ctx.controller
		local gone = g:chooseCard(me, "Remove a card in your memory from the game?", copyList(g.players[me].memory),
			{ optional = true, noneLabel = "Don't" })
		if not gone then return end
		g:removeFromGame(gone, me)
		local back = g:chooseCard(me, "Return which card from your memory to your hand?", copyList(g.players[me].memory))
		if back then
			g:putCard(back, me, "hand")
			g:say("%s returns %s to their hand.", g.players[me].name, g.cards[back].name)
		end
	end)

card("10 of Wands", damagePerSuitOnSpread("Cups", 3), damagePerSuitOnSpread("Major", 2))

card("Page of Wands",
	function(g, ctx) -- Exchange this card with another card. You may reverse either card.
		local other = g:chooseCard(ctx.controller, "Exchange the Page of Wands with which card?", others(g, ctx.card, allSpread(g, ctx.controller)))
		if other and onSpread(g, ctx.card) then exchangeAndMayReverse(g, ctx.controller, ctx.card, other) end
	end,
	function(g, ctx) -- The next time you would place a card, you may deal 5 damage to any player instead.
		local me = ctx.controller
		insteadOfPlacing(g, me, "deal 5 damage to a player", function(g) damageChosen(g, me, 5) end)
	end)

card("Knight of Wands",
	function(g, ctx) -- You may replace this card with one from your hand and activate the new card.
		local me = ctx.controller
		local pos = g:cardPlayer(ctx.card) == me and posOf(g, ctx.card)
		if not pos then return end
		local new = g:placeStep(me, { from = { "hand" }, at = pos, optional = true, prompt = "Replace this card with one from your hand?" })
		if new then activateCard(g, new) end
	end,
	function(g, ctx) -- Activate another card on your spread twice, then silence it.
		local cid = g:chooseCard(ctx.controller, "Activate which card twice?", otherOwnFaceUp(g, ctx))
		if not cid then return end
		activateCard(g, cid)
		activateCard(g, cid)
		g:silence(cid)
	end)

card("Queen of Wands",
	function(g, ctx) -- Choose Wands, Cups, or Pentacles. Dismiss all cards of that suit. Dismiss this card.
		local me = ctx.controller
		local suit = g:chooseSuit(me, "Choose a suit.", { "Wands", "Cups", "Pentacles" })
		for _, cid in ipairs(allSpread(g, me)) do
			if suitOf(g, cid) == suit and cid ~= ctx.card then g:dismiss(cid, me) end
		end
		if onSpread(g, ctx.card) then g:dismiss(ctx.card, me) end
	end,
	function(g, ctx) -- Until your next turn, the next time you activate a card, activate it an additional time.
		local me = ctx.controller
		g:addTrigger({ event = "activate", controller = me, uses = 1, ["until"] = { turnOf = me }, desc = "activate your next card again",
			applies = function(g, ev) return ev.player == me end,
			run = function(g, ev) activateCard(g, ev.card) end })
	end)

card("King of Wands",
	function(g, ctx) -- Deal 3 damage to each opponent.
		for _, pid in ipairs(g:opponents(ctx.controller)) do g:damage(pid, 3, ctx.controller) end
	end,
	function(g, ctx) -- Reveal the top 2 cards of your deck. Until the end of this turn, whenever you would place a card, you may place one of those cards instead and remove the other from the game.
		revealTopForPlacing(g, ctx.controller, 2)
	end)

---------------------------------------------------------------------------
-- Cups
---------------------------------------------------------------------------

local function placeFaceDownMayFlip(g, ctx) -- You may place a card face-down. You may flip a face-down card at any time to activate it and silence it.
	local placed = g:placeStep(ctx.controller, { faceDown = true, optional = true, prompt = "You may place a card face down." })
	if placed then permitFlip(g, ctx.controller, placed) end
end
local function copyAny(g, ctx) -- Copy an effect of either side of a card.
	copyEffect(g, ctx, faceUpSpread(g, ctx.controller))
end

card("Ace of Cups",
	function(g, ctx) -- Look at the top card of your deck. You may put it on the top or bottom of your deck. Draw.
		local me = ctx.controller
		local top = g:topOfDeck(me)
		if top then
			local bottom = g:chooseOne(me, "Top card of your deck: " .. g.cards[top].name .. ". Keep it on top or put it on the bottom?",
				{ { label = "Keep it on top", value = false }, { label = "Put it on the bottom", value = true } },
				{ always = true, card = top, private = true })
			if bottom then g:putCard(top, me, "deck", nil, { bottom = true }) end
		end
		g:draw(me)
	end,
	placeFaceDownMayFlip)

card("2 of Cups",
	function(g, ctx) -- Draw for each Cup on your spread. You may reverse this card.
		local me = ctx.controller
		for _ = 1, countSuit(g, me, "Cups") do g:draw(me) end
		if onSpread(g, ctx.card) and g:yesNo(me, "Reverse " .. g.cards[ctx.card].name .. "?") then g:reverse(ctx.card) end
	end,
	function(g, ctx) -- Deal damage to an opponent equal to the number of cards in your hand.
		local me = ctx.controller
		damageChosen(g, me, #g.players[me].hand, "Which opponent?", g:opponents(me))
	end)

card("3 of Cups",
	function(g, ctx) -- Activate each other card on your spread in any order.
		local cands = otherOwnFaceUp(g, ctx)
		local order = g:chooseCards(ctx.controller, "Activate your other cards: choose the order", cands, #cands, { min = #cands })
		-- The stack resolves last-in first-out, so push in reverse
		for i = #order, 1, -1 do activateCard(g, order[i]) end
	end,
	function(g, ctx) -- Flip a card on your spread. You may flip a face-down card at any time to activate it and silence it.
		local me = ctx.controller
		local cid = g:chooseCard(me, "Flip which card on your spread?", spread(g, me))
		if not cid then return end
		g:flip(cid)
		if not g.cards[cid].faceUp then permitFlip(g, me, cid) end
	end)

card("4 of Cups", placeFaceDownMayFlip,
	function(g, ctx) -- Return all cards on your spread to your hand.
		for _, cid in ipairs(spread(g, ctx.controller)) do g:returnToHand(cid) end
	end)

card("5 of Cups",
	function(g, ctx) -- Copy an effect that has activated this turn.
		local seen, cands = {}, {}
		for _, a in ipairs(g.turnActivations or {}) do
			local key = a.card .. a.side
			if not seen[key] then
				seen[key] = true
				cands[#cands + 1] = a
			end
		end
		copyEffect(g, ctx, cands, true)
	end,
	function(g, ctx) -- You may shuffle your hand into your deck and draw that many.
		local me = ctx.controller
		local n = #g.players[me].hand
		if n == 0 or not g:yesNo(me, "Shuffle your hand into your deck and draw " .. n .. "?") then return end
		for _, cid in ipairs(copyList(g.players[me].hand)) do g:putCard(cid, me, "deck") end
		g:shuffleDeck(me)
		for _ = 1, n do g:draw(me) end
	end)

card("6 of Cups",
	function(g, ctx) -- Restart the turn from the Past. Remove this card from the game.
		g:restartFromPast()
		g:removeFromGame(ctx.card, ctx.controller)
	end,
	copyAny)

card("7 of Cups",
	function(g, ctx) -- Choose 2 cards on the same spread. That player chooses a card from among those. Dismiss that card.
		local me = ctx.controller
		local cands = filter(g:living(), function(pid) return #spread(g, pid) >= 2 end)
		local target = g:choosePlayer(me, "Choose 2 cards on whose spread?", cands)
		if not target then return end
		local pair = g:chooseCards(me, "Choose 2 cards", spread(g, target), 2, { min = 2 })
		local cid = g:chooseCard(target, "Which of these is dismissed?", pair)
		if cid then g:dismiss(cid, me) end
	end,
	function(g, ctx) -- Deal damage to a player equal to the number of cards in your hand.
		damageChosen(g, ctx.controller, #g.players[ctx.controller].hand)
	end)

card("8 of Cups",
	function(g, ctx) -- For each opponent, return a card on their spread to their hand. Dismiss this card.
		local me = ctx.controller
		for _, pid in ipairs(g:opponents(me)) do
			local cid = g:chooseCard(me, "Return which card on " .. g.players[pid].name .. "'s spread to their hand?", spread(g, pid))
			if cid then g:returnToHand(cid) end
		end
		if onSpread(g, ctx.card) then g:dismiss(ctx.card, me) end
	end,
	function(g, ctx) -- Flip a card on your spread or place one face-down. You may flip a face-down card at any time to activate it and silence it.
		local me = ctx.controller
		local flip = #spread(g, me) > 0 and g:yesNo(me, "Flip a card on your spread, or place one face down?", "Flip a card", "Place one face down")
		local cid
		if flip then
			cid = g:chooseCard(me, "Flip which card?", spread(g, me))
			if cid then g:flip(cid) end
		else
			cid = g:placeOrDraw(me, { faceDown = true })
		end
		if cid and onSpread(g, cid) and not g.cards[cid].faceUp then permitFlip(g, me, cid) end
	end)

card("9 of Cups",
	function(g, ctx) -- You may end the turn and flip this card. You may flip it at any time to activate it and silence it.
		local me = ctx.controller
		if not g:yesNo(me, "End the turn and flip the 9 of Cups face down?") then return end
		g:endTurn()
		if onSpread(g, ctx.card) and g.cards[ctx.card].faceUp then
			g:flip(ctx.card)
			permitFlip(g, me, ctx.card)
		end
	end,
	copyAny)

card("10 of Cups",
	function(g, ctx) -- You may reveal any number of cards in your hand. Draw for each Cup you reveal and each Cup on your spread.
		local me = ctx.controller
		local n = revealAndCount(g, me, "Cups", "Cups count") + countSuit(g, me, "Cups")
		for _ = 1, n do g:draw(me) end
	end,
	function(g, ctx) -- Dismiss this card. Return all cards to their players' hands.
		if onSpread(g, ctx.card) then g:dismiss(ctx.card, ctx.controller) end
		for _, cid in ipairs(allSpread(g, ctx.controller)) do g:returnToHand(cid) end
	end)

card("Page of Cups",
	function(g, ctx) -- Each player reveals the top card of their deck. You may draw.
		for _, pid in ipairs(g:inOrderFrom(ctx.controller)) do
			local top = g:topOfDeck(pid)
			if top then g:reveal(top, pid) end
		end
		if g:yesNo(ctx.controller, "Draw a card?", "Draw", "Don't draw") then g:draw(ctx.controller) end
	end,
	placeFaceDownMayFlip)

card("Knight of Cups",
	function(g, ctx) -- Copy an effect of either side of a card in your memory.
		copyEffect(g, ctx, copyList(g.players[ctx.controller].memory))
	end,
	function(g, ctx) -- Choose a player. That player puts 3 cards from their deck into their memory.
		deckToMemory(g, g:choosePlayer(ctx.controller, "Who puts 3 cards from their deck into memory?"), 3)
	end)

card("Queen of Cups",
	function(g, ctx) -- Name a card. Until your next turn, cards with the chosen name cannot be dismissed, removed from the game, or placed.
		forbidByName(g, ctx.controller, { "dismiss", "remove", "place" }, "dismissed, removed or placed")
	end,
	function(g, ctx) -- Return any number of cards from your memory to your hand, then discard that many.
		local me = ctx.controller
		local back = g:chooseCards(me, "Return cards from your memory to your hand", copyList(g.players[me].memory))
		for _, cid in ipairs(back) do g:putCard(cid, me, "hand") end
		for _ = 1, #back do discardOne(g, me) end
	end)

card("King of Cups",
	function(g, ctx) -- Each player may draw. Until your next turn, each player who draws this way may not damage you or dismiss cards on your spread.
		local me, drew = ctx.controller, {}
		for _, pid in ipairs(g:inOrderFrom(me)) do
			if g:yesNo(pid, "King of Cups: draw a card? (If you do, you can't damage " .. g.players[me].name ..
				" or dismiss their cards until their next turn.)", "Draw", "Don't draw") then
				g:draw(pid)
				if pid ~= me then drew[pid] = true end
			end
		end
		for _, event in ipairs({ "damage", "dismiss" }) do
			g:addModifier({ event = event, ["until"] = { turnOf = me }, desc = "protected by the King of Cups",
				applies = function(g, ev) return ev.player == me and drew[ev.source] end,
				replace = function(g, ev)
					g:say("The King of Cups protects %s.", g.players[me].name)
					return nil
				end })
		end
	end,
	function(g, ctx) -- Flip any number of cards on your spread. You may flip a face-down card at any time to activate it and silence it.
		local me = ctx.controller
		for _, cid in ipairs(g:chooseCards(me, "Flip cards on your spread", spread(g, me))) do g:flip(cid) end
		permitFlip(g, me)
	end)
