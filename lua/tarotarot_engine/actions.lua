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
		if #candidates > 1 then
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
	self:fire(ev)
	return ev.amount
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

-- Dismiss: move a card on a spread to its player's memory.
function Game:dismiss(cid)
	local loc = self.cards[cid].loc
	if not loc or loc.zone ~= "spread" then return false end
	local ev = self:replace({ name = "dismiss", player = loc.player, card = cid, pos = loc.pos })
	if not ev then return false end
	self:putCard(cid, loc.player, "memory")
	self:say("%s is dismissed.", self.cards[cid].name)
	self:fire(ev)
	return true
end

-- Remove from the game.
function Game:removeFromGame(cid)
	self:putCard(cid, nil, "out")
	self:say("%s is removed from the game.", self.cards[cid].name)
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

---------------------------------------------------------------------------
-- Placing (turn step 2, and "place a card" effects: ruling 4)
---------------------------------------------------------------------------

-- Spread positions where `player` may place: empty, or holding a Minor card.
function Game:legalSpaces(player)
	local out = {}
	local spread = self.players[player].spread
	for _, pos in ipairs(TTE.POSITIONS) do
		local cid = spread[pos]
		if not cid or not self.cards[cid].major then out[#out + 1] = pos end
	end
	return out
end

-- Can `player` place a card at all? (ruling 6)
function Game:canPlace(player)
	local p = self.players[player]
	return #self:legalSpaces(player) > 0 and (#p.hand > 0 or #p.deck > 0)
end

-- Put a card on `player`'s spread. A Minor card already there goes to its
-- player's memory. opts.faceDown places it face down.
function Game:place(player, cid, pos, reversed, opts)
	opts = opts or {}
	local ev = self:replace({ name = "place", player = player, card = cid, pos = pos, reversed = reversed })
	if not ev then return false end

	local spread = self.players[ev.player].spread
	local old = spread[ev.pos]
	if old then
		assert(not self.cards[old].major, "can't replace a Major card")
		self:putCard(old, ev.player, "memory")
		self:say("%s goes to memory.", self.cards[old].name)
	end
	local card = self.cards[ev.card]
	self:putCard(ev.card, ev.player, "spread", ev.pos)
	card.reversed = ev.reversed and true or false
	card.faceUp = not opts.faceDown
	card.counters = {}
	self:say("%s places %s in their %s.", self.players[ev.player].name,
		card.faceUp and self:describe(ev.card) or "a face-down card", ev.pos)
	self:fire(ev)
	return true
end

-- Interactive place: the player picks a source (hand card or top of deck),
-- then a space and an orientation. Returns false if they can't place.
function Game:placeStep(player, opts)
	opts = opts or {}
	if not self:canPlace(player) then return false end
	local p = self.players[player]

	local options = {}
	for _, cid in ipairs(p.hand) do
		options[#options + 1] = { id = "hand:" .. cid, label = self.cards[cid].name .. " (hand)", card = cid }
	end
	if #p.deck > 0 then options[#options + 1] = { id = "deck", label = "Top of your deck" } end
	local source = self:ask(player, "place_source", opts.prompt or "Place a card: choose one from your hand or the top of your deck.", options)

	local cid = source == "deck" and self:topOfDeck(player) or tonumber(source:match("^hand:(%d+)$"))
	local targets = {}
	for _, pos in ipairs(self:legalSpaces(player)) do
		local there = p.spread[pos]
		local suffix = there and (" (replacing " .. self.cards[there].name .. ")") or ""
		targets[#targets + 1] = { id = pos .. ":upright", label = pos .. ", upright" .. suffix }
		targets[#targets + 1] = { id = pos .. ":reversed", label = pos .. ", reversed" .. suffix }
	end
	-- When placing from the deck, the player may look at the card first
	local target = self:ask(player, "place_target", "Where does " .. self.cards[cid].name .. " go?", targets,
		{ card = cid, private = source == "deck" })
	local pos, side = target:match("^(%a+):(%a+)$")
	return self:place(player, cid, pos, side == "reversed", { faceDown = opts.faceDown })
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
