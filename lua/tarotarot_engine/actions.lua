-- Tarotarot rules engine: keyword actions, replacement effects, triggers,
-- lasting effects and elimination.

local Game = TTE.Game
local removeValue = TTE.removeValue
local unpack = TTE.unpack

---------------------------------------------------------------------------
-- Replacement effects, triggers and lasting effects
---------------------------------------------------------------------------
-- A modifier changes an event before it happens ("instead" effects):
--   g:addModifier{
--     event = "damage",                 -- event name
--     applies = function(g, ev) -> bool, -- optional filter
--     replace = function(g, ev) -> ev|nil, -- return the changed event, or nil to cancel it
--     uses = 1,                          -- optional: expires after this many uses
--     commutes = true,                   -- optional: order doesn't matter (e.g. doubling), so don't ask
--     ["until"] = "end_of_turn" | { turnOf = playerId }, -- optional expiry
--     desc = "...",
--   }
-- When several apply to one event, the player it applies to (ev.player)
-- picks the order (ruling 8). Each modifier changes an event at most once.
--
-- A trigger runs after an event happens ("whenever ..."), going on the stack:
--   g:addTrigger{ event =, applies =, controller =, run = function(g, ev) end, uses =, ["until"] =, desc = }

function Game:addModifier(m)
	m.id = self:uid()
	self.modifiers[#self.modifiers + 1] = m
	return m
end

function Game:addTrigger(t)
	t.id = self:uid()
	self.triggers[#self.triggers + 1] = t
	return t
end

-- A one-off permission, e.g. "you may flip a face-down card at any time".
--   g:addPermission{ player =, kind = "flip", card = cid (optional), ["until"] =, desc = }
function Game:addPermission(p)
	p.id = self:uid()
	self.permissions[#self.permissions + 1] = p
	return p
end

local function useUp(list, item)
	if item.uses then
		item.uses = item.uses - 1
		if item.uses <= 0 then removeValue(list, item) end
	end
end

-- Expire lasting effects. when = "end_of_turn" or "start_of_turn" (for `player`).
function Game:expire(when, player)
	for _, list in ipairs({ self.modifiers, self.triggers, self.permissions }) do
		for i = #list, 1, -1 do
			local u = list[i]["until"]
			if (when == "end_of_turn" and u == "end_of_turn")
				or (when == "start_of_turn" and type(u) == "table" and u.turnOf == player) then
				table.remove(list, i)
			end
		end
	end
end

-- Run an event through the replacement effects. Returns the final event, or
-- nil if it was replaced with nothing.
function Game:replace(ev)
	local used = {}
	while ev do
		local candidates = {}
		for _, m in ipairs(self.modifiers) do
			if m.event == ev.name and not used[m] and (not m.applies or m.applies(self, ev)) then
				candidates[#candidates + 1] = m
			end
		end
		if #candidates == 0 then return ev end

		local m = candidates[1]
		local allCommute = true
		for _, c in ipairs(candidates) do
			if not c.commutes then allCommute = false end
		end
		if #candidates > 1 and not allCommute then
			local options = {}
			for _, c in ipairs(candidates) do
				options[#options + 1] = { id = tostring(c.id), label = c.desc or ("effect " .. c.id) }
			end
			local chooser = ev.player or self.active
			local pick = self:ask(chooser, "order_replacements",
				"Several effects change this " .. ev.name .. ". Which applies first?", options)
			for _, c in ipairs(candidates) do
				if tostring(c.id) == pick then m = c end
			end
		end
		used[m] = true
		useUp(self.modifiers, m)
		ev = m.replace(self, ev)
	end
end

-- After an event: put matching triggers on the stack.
function Game:fire(ev)
	for _, t in ipairs({ unpack(self.triggers) }) do
		if t.event == ev.name and (not t.applies or t.applies(self, ev)) then
			useUp(self.triggers, t)
			self:push({ kind = "trigger", controller = t.controller, desc = t.desc,
				run = function(g) t.run(g, ev) end })
		end
	end
end

---------------------------------------------------------------------------
-- Keyword actions (docs/RULES.md "Keywords")
---------------------------------------------------------------------------
-- These don't check for eliminations: that happens at safe points
-- (Game:checkState), so "deal 5 damage to each player" hits everyone before
-- anyone is removed.

-- Damage: reduce a player's life.
function Game:damage(player, amount, source)
	local ev = self:replace({ name = "damage", player = player, amount = amount, source = source })
	if not ev or ev.amount <= 0 or self.players[ev.player].eliminated then return 0 end
	local p = self.players[ev.player]
	p.life = p.life - ev.amount
	self:say("%s takes %d damage (life %d).", p.name, ev.amount, p.life)
	-- "damage you have dealt this turn" (source = the player dealing it)
	if type(ev.source) == "number" and self.turnDamage then
		local t = self.turnDamage[ev.source] or { total = 0 }
		t.total = t.total + ev.amount
		t[ev.player] = (t[ev.player] or 0) + ev.amount
		self.turnDamage[ev.source] = t
	end
	self:fire(ev)
	return ev.amount
end

-- Damage `source` has dealt this turn, in total or to one player.
function Game:damageDealt(source, to)
	local t = self.turnDamage and self.turnDamage[source]
	if not t then return 0 end
	if to then return t[to] or 0 end
	return t.total
end

function Game:gainLife(player, amount, source)
	local ev = self:replace({ name = "gain_life", player = player, amount = amount, source = source })
	if not ev or ev.amount <= 0 then return 0 end
	local p = self.players[ev.player]
	p.life = p.life + ev.amount
	self:say("%s gains %d life (life %d).", p.name, ev.amount, p.life)
	self:fire(ev)
	return ev.amount
end

function Game:setLife(player, life)
	local p = self.players[player]
	p.life = life
	self:say("%s's life becomes %d.", p.name, life)
end

-- Draw: top card of your deck into your hand. Drawing from an empty deck
-- removes you from the game (at the next state check).
function Game:draw(player)
	local ev = self:replace({ name = "draw", player = player })
	if not ev then return nil end
	local p = self.players[ev.player]
	local top = self:topOfDeck(ev.player)
	if not top then
		p.drewFromEmpty = true
		self:say("%s tries to draw from an empty deck.", p.name)
		return nil
	end
	self:putCard(top, ev.player, "hand")
	self:say("%s draws a card.", p.name)
	self:fire({ name = "draw", player = ev.player, card = top })
	return top
end

-- Discard: move a card from hand to memory.
function Game:discard(cid)
	local player = self:cardPlayer(cid)
	self:putCard(cid, player, "memory")
	self:say("%s discards %s.", self.players[player].name, self.cards[cid].name)
	self:fire({ name = "discard", player = player, card = cid })
end

-- Dismiss: move a card on a spread to its player's memory. `source` is the
-- player doing it (for effects like "may not dismiss cards on your spread").
function Game:dismiss(cid, source)
	local loc = self.cards[cid].loc
	if not loc or loc.zone ~= "spread" then return false end
	local ev = self:replace({ name = "dismiss", player = loc.player, card = cid, pos = loc.pos, source = source })
	if not ev then return false end
	self:putCard(cid, loc.player, "memory")
	self:say("%s is dismissed.", self.cards[cid].name)
	self:fire(ev)
	return true
end

-- Remove from the game.
function Game:removeFromGame(cid, source)
	local loc = self.cards[cid].loc
	if loc and loc.zone == "out" then return false end
	local ev = self:replace({ name = "remove", player = loc and loc.player, card = cid, source = source })
	if not ev then return false end
	self:putCard(cid, nil, "out")
	self:say("%s is removed from the game.", self.cards[cid].name)
	return true
end

-- Reverse: rotate a card 180 degrees.
function Game:reverse(cid)
	local card = self.cards[cid]
	card.reversed = not card.reversed
	self:say("%s is reversed (now %s).", card.name, card.reversed and "reversed" or "upright")
end

function Game:flip(cid)
	local card = self.cards[cid]
	card.faceUp = not card.faceUp
	self:say("%s is flipped face %s.", card.faceUp and card.name or "a card", card.faceUp and "up" or "down")
end

function Game:addCounter(cid, kind, n)
	local counters = self.cards[cid].counters
	counters[kind] = math.max(0, (counters[kind] or 0) + (n or 1))
end

function Game:counters(cid, kind)
	return self.cards[cid].counters[kind] or 0
end

-- Silence: put a silence counter on a card.
function Game:silence(cid)
	self:addCounter(cid, "silence", 1)
	self:say("%s is silenced.", self.cards[cid].name)
end

function Game:shuffleDeck(player)
	self:shuffle(self.players[player].deck)
	self:say("%s shuffles their deck.", self.players[player].name)
end

-- Return a card to its player's hand.
function Game:returnToHand(cid)
	local player = self:cardPlayer(cid)
	self:putCard(cid, player, "hand")
	self:say("%s returns to %s's hand.", self.cards[cid].name, self.players[player].name)
end

-- Exchange the positions of two cards on spreads (orientation, face and
-- counters go with each card).
function Game:swap(a, b)
	local la, lb = self.cards[a].loc, self.cards[b].loc
	local pa, pb = { player = la.player, pos = la.pos }, { player = lb.player, pos = lb.pos }
	self.players[pa.player].spread[pa.pos] = nil
	self.players[pb.player].spread[pb.pos] = nil
	self.players[pa.player].spread[pa.pos] = b
	self.players[pb.player].spread[pb.pos] = a
	self.cards[a].loc = { zone = "spread", player = pb.player, pos = pb.pos }
	self.cards[b].loc = { zone = "spread", player = pa.player, pos = pa.pos }
	self:say("%s and %s exchange positions.", self.cards[a].faceUp and self.cards[a].name or "a face-down card",
		self.cards[b].faceUp and self.cards[b].name or "a face-down card")
end

---------------------------------------------------------------------------
-- Placing (turn step 2, and "place a card" effects: ruling 4)
---------------------------------------------------------------------------

-- Spread positions on `player`'s spread where a card may go: empty, or
-- holding a Minor card (unless noReplace).
function Game:legalSpaces(player, noReplace)
	local out = {}
	local spread = self.players[player].spread
	for _, pos in ipairs(TTE.POSITIONS) do
		local cid = spread[pos]
		if not cid or (not noReplace and not self.cards[cid].major) then out[#out + 1] = pos end
	end
	return out
end

-- Can `player` place a card at all? (ruling 6)
function Game:canPlace(player)
	local p = self.players[player]
	return #self:legalSpaces(player) > 0 and (#p.hand > 0 or #p.deck > 0)
end

-- Put a card on `player`'s spread. A Minor card already there goes to its
-- player's memory. opts.faceDown places it face down. Returns the card that
-- was placed (a replacement effect can swap it for another), or false.
function Game:place(player, cid, pos, reversed, opts)
	opts = opts or {}
	local from = self.cards[cid].loc and self.cards[cid].loc.zone
	local ev = self:replace({ name = "place", player = player, card = cid, pos = pos, reversed = reversed,
		from = from, faceDown = opts.faceDown, source = opts.source or player })
	if not ev then return false end

	local spread = self.players[ev.player].spread
	local old = spread[ev.pos]
	if old == ev.card then old = nil end
	if old then
		if self.cards[old].major then return false end -- (a replacement moved it somewhere illegal)
		self:putCard(old, ev.player, "memory")
		self:say("%s goes to memory.", self.cards[old].name)
	end
	local card = self.cards[ev.card]
	self:putCard(ev.card, ev.player, "spread", ev.pos)
	card.reversed = ev.reversed and true or false
	card.faceUp = not ev.faceDown
	card.counters = {}
	self:say("%s places %s in their %s.", self.players[ev.player].name,
		card.faceUp and self:describe(ev.card) or "a face-down card", ev.pos)
	self:fire(ev)
	return ev.card
end

-- Interactive place. The player picks a card and then a space and an
-- orientation. Returns the placed card id, or nil and why not:
--   "cant"      no legal space, or nothing to place (ruling 6)
--   "declined"  an optional place the player passed on
--   "prevented" a replacement effect stopped it (e.g. 2 of Wands)
--   opts.onto       whose spread (default: the player's own)
--   opts.from       sources: { "hand", "deck" } (default) or { "memory" }
--   opts.memoryOf   with "memory": whose memories (default: the player's)
--   opts.card       place this specific card (skips choosing one)
--   opts.at         the space to use (skips choosing one)
--   opts.noReplace  only empty spaces
--   opts.filter     function(g, cid) -> bool, which cards may be chosen
--   opts.faceDown   place it face down
--   opts.optional   the player may decline
--   opts.orientation false = keep the card's current orientation (no choice)
function Game:placeStep(player, opts)
	opts = opts or {}
	local onto = opts.onto or player
	local p = self.players[player]

	local spaces = {}
	for _, pos in ipairs(self:legalSpaces(onto, opts.noReplace)) do
		if not opts.at or opts.at == pos then spaces[#spaces + 1] = pos end
	end
	if #spaces == 0 then return nil, "cant" end

	local cid, private = opts.card, false
	if not cid then
		local options = {}
		local from = opts.from or { "hand", "deck" }
		for _, zone in ipairs(from) do
			if zone == "hand" then
				for _, h in ipairs(p.hand) do
					if not opts.filter or opts.filter(self, h) then
						options[#options + 1] = { id = "card:" .. h, label = self.cards[h].name .. " (your hand)" }
					end
				end
			elseif zone == "deck" and #p.deck > 0 then
				if not opts.filter then options[#options + 1] = { id = "deck", label = "Top of your deck" } end
			elseif zone == "memory" then
				for _, owner in ipairs(opts.memoryOf or { player }) do
					for _, m in ipairs(self.players[owner].memory) do
						if not opts.filter or opts.filter(self, m) then
							options[#options + 1] = { id = "card:" .. m,
								label = self.cards[m].name .. " (" .. (owner == player and "your" or (self.players[owner].name .. "'s")) .. " memory)" }
						end
					end
				end
			end
		end
		if #options == 0 then return nil, "cant" end
		if opts.optional then options[#options + 1] = { id = "none", label = "Don't place a card" } end
		local where = onto == player and "your spread" or (self.players[onto].name .. "'s spread")
		local source = self:ask(player, "place_source", opts.prompt or ("Place a card on " .. where .. "."), options)
		if source == "none" then return nil, "declined" end
		if source == "deck" then
			cid, private = self:topOfDeck(player), true
		else
			cid = tonumber(source:match("^card:(%d+)$"))
		end
	end

	local targets = {}
	for _, pos in ipairs(spaces) do
		local there = self.players[onto].spread[pos]
		local suffix = (there and there ~= cid) and (" (replacing " .. self:cardLabel(there, player) .. ")") or ""
		if opts.orientation == false then
			targets[#targets + 1] = { id = pos .. ":" .. (self.cards[cid].reversed and "reversed" or "upright"), label = pos .. suffix }
		else
			targets[#targets + 1] = { id = pos .. ":upright", label = pos .. ", upright" .. suffix }
			targets[#targets + 1] = { id = pos .. ":reversed", label = pos .. ", reversed" .. suffix }
		end
	end
	local target = self:ask(player, "place_target", "Where does " .. self.cards[cid].name .. " go?", targets,
		{ card = cid, private = private, onto = onto })
	local pos, side = target:match("^(%a+):(%a+)$")
	local placed = self:place(onto, cid, pos, side == "reversed", { faceDown = opts.faceDown, source = player })
	if placed then return placed end
	return nil, "prevented"
end

-- A place an effect requires: if the player can't place, they draw instead
-- (ruling 6, applied to effects as well as the turn's place step). A place
-- stopped by a replacement effect isn't "can't place", so no draw.
function Game:placeOrDraw(player, opts)
	local placed, why = self:placeStep(player, opts)
	if not placed and why == "cant" then
		self:say("%s can't place a card, so draws.", self.players[player].name)
		self:draw(player)
	end
	return placed, why
end

---------------------------------------------------------------------------
-- Elimination (docs/RULES.md "End")
---------------------------------------------------------------------------

function Game:eliminate(player, why)
	local p = self.players[player]
	if p.eliminated then return end
	p.eliminated = true
	for _, cid in ipairs(self:spreadCards(player)) do self:putCard(cid, nil, "out") end
	for _, zone in ipairs({ "hand", "memory", "deck" }) do
		while #p[zone] > 0 do self:putCard(p[zone][1], nil, "out") end
	end
	self:say("%s is removed from the game (%s).", p.name, why)
	-- Their lasting effects and permissions go with them
	for _, list in ipairs({ self.permissions }) do
		for i = #list, 1, -1 do
			if list[i].player == player then table.remove(list, i) end
		end
	end
end

-- State check, run at safe points: remove players at 0 life or who drew
-- from an empty deck, then end the game if one or no players remain.
function Game:checkState()
	local out = {}
	for _, p in ipairs(self.players) do
		if not p.eliminated and (p.life <= 0 or p.drewFromEmpty) then out[#out + 1] = p end
	end
	for _, p in ipairs(out) do
		self:eliminate(p.id, p.life <= 0 and "out of life" or "drew from an empty deck")
	end
	local living = self:living()
	if #living <= 1 then self:endGame(living, "last player standing") end
end
