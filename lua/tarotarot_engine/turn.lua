-- Tarotarot rules engine: setup, the turn structure, activation, and the
-- stack with priority (ruling 2).

local Game = TTE.Game

---------------------------------------------------------------------------
-- Setup (docs/RULES.md "Setup")
---------------------------------------------------------------------------

function Game:setup()
	local n = #self.players
	local ids = {}
	for id in ipairs(self.cards) do ids[id] = id end
	self:shuffle(ids)

	-- Deal equally (39 / 26 / 19 each); leftovers are removed
	local each = math.floor(#ids / n)
	local k = 0
	for _, p in ipairs(self.players) do
		for _ = 1, each do
			k = k + 1
			self:putCard(ids[k], p.id, "deck")
		end
	end
	for i = k + 1, #ids do self:putCard(ids[i], nil, "unused") end
	self:say("Dealt %d cards to each of %d players.", each, n)

	-- Survey the Past: top card face up, in either orientation
	for _, p in ipairs(self.players) do
		local top = self:topOfDeck(p.id)
		local side = self:ask(p.id, "survey_past",
			"Survey the Past: put " .. self.cards[top].name .. " in your Past upright or reversed?",
			{ { id = "upright", label = "Upright" }, { id = "reversed", label = "Reversed" } },
			{ card = top, private = true })
		self:place(p.id, top, "past", side == "reversed")
	end

	for _, p in ipairs(self.players) do
		for _ = 1, TTE.START_HAND do self:draw(p.id) end
	end

	self.active = self.firstChoice or self.rng(n)
	self:say("%s goes first.", self.players[self.active].name)
end

---------------------------------------------------------------------------
-- The turn (docs/RULES.md "On your turn")
---------------------------------------------------------------------------

function Game:run()
	self:setup()
	self:checkState()
	while true do
		self:takeTurn(self.active)
		self:expire("end_of_turn")
		self:checkState()
		self.active = self:nextPlayer(self.active)
	end
end

function Game:takeTurn(player)
	local p = self.players[player]
	self.turnNumber = self.turnNumber + 1
	self.turn = { player = player, step = "activate" }
	self:expire("start_of_turn", player)
	self:say("Turn %d: %s.", self.turnNumber, p.name)

	-- 1. Activate the spread: Past, then Present, then Future. Only face-up
	--    cards activate (ruling 1). "Restart the turn from the Past" starts
	--    this step over without undoing anything (ruling 3).
	self:runStack()
	local i = 1
	while i <= #TTE.POSITIONS and not p.eliminated do
		local cid = p.spread[TTE.POSITIONS[i]]
		if cid and self.cards[cid].faceUp then
			self:activate(cid, player)
			self:runStack()
		end
		if self.turn.restart then
			self.turn.restart = false
			self:say("The turn restarts from the Past.")
			i = 1
		else
			i = i + 1
		end
	end
	if p.eliminated then return end

	-- 2. Place one card face up; if you can't, draw instead (ruling 6)
	self.turn.step = "place"
	self:runStack()
	if not self:placeStep(player) then
		self:say("%s can't place a card, so draws.", p.name)
		self:draw(player)
	end
	self:checkState()
	self:runStack()
	if p.eliminated then return end

	-- 3. You may draw a card
	self.turn.step = "draw"
	local choice = self:ask(player, "may_draw", "Draw a card?",
		{ { id = "draw", label = "Draw a card" }, { id = "skip", label = "Don't draw" } })
	if choice == "draw" then self:draw(player) end
	self:checkState()
	self:runStack()
	self.turn.step = "end"
end

-- "Restart the turn from the Past."
function Game:restartFromPast()
	if self.turn then self.turn.restart = true end
end

---------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------

-- Activate a card: put its effect (the side facing its player) on the stack.
-- Silence replaces the activation (removing one counter).
function Game:activate(cid, controller)
	local card = self.cards[cid]
	controller = controller or self:cardPlayer(cid)
	if self:counters(cid, "silence") > 0 then
		self:addCounter(cid, "silence", -1)
		self:say("%s is silenced: its silence counter is removed instead.", card.name)
		return false
	end
	local ev = self:replace({ name = "activate", player = controller, card = cid })
	if not ev then return false end
	self:push({
		kind = "activation", card = cid, controller = controller,
		side = card.reversed and "reversed" or "upright",
		desc = self:describe(cid),
	})
	self:fire(ev)
	return true
end

---------------------------------------------------------------------------
-- The stack and priority (ruling 2)
---------------------------------------------------------------------------
-- Items on the stack resolve last-in, first-out. Before each resolution,
-- every living player in turn order (from the active player) gets priority;
-- the top item resolves once all pass in a row. "At any time" actions can
-- only be taken while the stack is empty. Players with nothing they could do
-- pass automatically, so priority only asks when there's a real choice.

function Game:push(item)
	item.id = self:uid()
	self.stack[#self.stack + 1] = item
end

-- Things a player could do right now with priority, as decision options.
function Game:instantActions(player)
	local out = {}
	if #self.stack > 0 then return out end
	for _, perm in ipairs(self.permissions) do
		if perm.player == player and perm.kind == "flip" then
			local cards = perm.card and { perm.card } or self:allSpreadCards(player)
			for _, cid in ipairs(cards) do
				local card = self.cards[cid]
				if card.loc and card.loc.zone == "spread" and not card.faceUp then
					out[#out + 1] = { id = "flip:" .. cid .. ":" .. perm.id,
						label = "Flip " .. (self:cardPlayer(cid) == player and card.name or "a face-down card") .. " face up and activate it" }
				end
			end
		end
	end
	return out
end

function Game:takeInstantAction(player, id)
	local cid, permId = id:match("^flip:(%d+):(%d+)$")
	cid, permId = tonumber(cid), tonumber(permId)
	for _, perm in ipairs(self.permissions) do
		if perm.id == permId then
			if perm.uses then
				perm.uses = perm.uses - 1
				if perm.uses <= 0 then TTE.removeValue(self.permissions, perm) end
			end
			break
		end
	end
	-- "Flip it ... to activate it and silence it"
	self.cards[cid].faceUp = true
	self:say("%s flips %s face up.", self.players[player].name, self.cards[cid].name)
	self:activate(cid, self:cardPlayer(cid))
	self:silence(cid)
end

-- One round of priority. Returns once every living player has passed in a row.
function Game:priorityRound()
	local order = self:inOrderFrom(self.active or 1)
	local passes, i = 0, 1
	while passes < #order do
		local pid = order[i]
		local actions = self:instantActions(pid)
		if #actions == 0 then
			passes = passes + 1
		else
			actions[#actions + 1] = { id = "pass", label = "Pass" }
			local choice = self:ask(pid, "priority", "You have priority.", actions)
			if choice == "pass" then
				passes = passes + 1
			else
				self:takeInstantAction(pid, choice)
				passes = 0
				order = self:inOrderFrom(pid) -- the same player gets priority again
				i = 0
			end
		end
		i = i % #order + 1
	end
end

-- Give priority and resolve the stack until it's empty and everyone passes.
function Game:runStack()
	while true do
		self:priorityRound()
		local item = table.remove(self.stack)
		if not item then return end
		self:resolve(item)
		self:checkState()
	end
end

function Game:resolve(item)
	if item.kind == "trigger" then
		item.run(self)
		return
	end
	local card = self.cards[item.card]
	self:say("%s activates: %s", item.desc, card.def[item.side] or "")
	local script = self.effects[card.name]
	local fn = script and script[item.side]
	if fn then
		fn(self, { card = item.card, controller = item.controller, side = item.side })
	else
		self:resolveManually(item)
	end
end

---------------------------------------------------------------------------
-- Manual resolution
---------------------------------------------------------------------------
-- Cards without a script are resolved by their controller: they carry out the
-- text with keyword actions, then answer "done". Answers are tables:
--   { action = "damage", player = id, amount = n }   { action = "done" }
-- See TTE.MANUAL_ACTIONS for the full list.

local function isPlayer(g, id) return type(id) == "number" and g.players[id] ~= nil end
local function isCard(g, id) return type(id) == "number" and g.cards[id] ~= nil and g.cards[id].loc ~= nil end
local function onSpread(g, id) return isCard(g, id) and g.cards[id].loc.zone == "spread" end
local function inHand(g, id) return isCard(g, id) and g.cards[id].loc.zone == "hand" end
local function isAmount(n) return type(n) == "number" and n >= 0 and n == math.floor(n) end
local ZONES = { deck = true, hand = true, memory = true, out = true }

TTE.MANUAL_ACTIONS = {
	damage = { check = function(g, a) return isPlayer(g, a.player) and isAmount(a.amount) end,
		run = function(g, a) g:damage(a.player, a.amount) end },
	gain_life = { check = function(g, a) return isPlayer(g, a.player) and isAmount(a.amount) end,
		run = function(g, a) g:gainLife(a.player, a.amount) end },
	set_life = { check = function(g, a) return isPlayer(g, a.player) and type(a.life) == "number" end,
		run = function(g, a) g:setLife(a.player, a.life) end },
	draw = { check = function(g, a) return isPlayer(g, a.player) end,
		run = function(g, a) g:draw(a.player) end },
	discard = { check = function(g, a) return inHand(g, a.card) end,
		run = function(g, a) g:discard(a.card) end },
	dismiss = { check = function(g, a) return onSpread(g, a.card) end,
		run = function(g, a) g:dismiss(a.card) end },
	remove = { check = function(g, a) return isCard(g, a.card) end,
		run = function(g, a) g:removeFromGame(a.card) end },
	reverse = { check = function(g, a) return onSpread(g, a.card) end,
		run = function(g, a) g:reverse(a.card) end },
	flip = { check = function(g, a) return onSpread(g, a.card) end,
		run = function(g, a) g:flip(a.card) end },
	silence = { check = function(g, a) return onSpread(g, a.card) end,
		run = function(g, a) g:silence(a.card) end },
	counter = { check = function(g, a) return onSpread(g, a.card) and type(a.kind) == "string" and type(a.delta) == "number" end,
		run = function(g, a) g:addCounter(a.card, a.kind, a.delta) end },
	shuffle = { check = function(g, a) return isPlayer(g, a.player) end,
		run = function(g, a) g:shuffleDeck(a.player) end },
	to_hand = { check = function(g, a) return onSpread(g, a.card) end,
		run = function(g, a) g:returnToHand(a.card) end },
	-- Put a card on a spread, following the place rules (ruling 4)
	place = {
		check = function(g, a)
			if not (isPlayer(g, a.player) and isCard(g, a.card)) then return false end
			local ok = false
			for _, pos in ipairs(g:legalSpaces(a.player)) do
				if pos == a.pos then ok = true end
			end
			return ok
		end,
		run = function(g, a) g:place(a.player, a.card, a.pos, a.reversed, { faceDown = a.faceDown }) end },
	-- Exchange the positions of two cards on spreads
	swap = { check = function(g, a) return onSpread(g, a.card) and onSpread(g, a.card2) and a.card ~= a.card2 end,
		run = function(g, a) g:swap(a.card, a.card2) end },
	-- Escape hatch: move any card to any player's deck/hand/memory, or out
	move = { check = function(g, a) return isCard(g, a.card) and ZONES[a.zone] and (a.zone == "out" or isPlayer(g, a.player)) end,
		run = function(g, a) g:putCard(a.card, a.player, a.zone, nil, { bottom = a.bottom }) end },
	restart = { check = function() return true end,
		run = function(g) g:restartFromPast() end },
	permit_flip = { check = function(g, a) return isPlayer(g, a.player) and (a.card == nil or onSpread(g, a.card)) end,
		run = function(g, a) g:addPermission({ player = a.player, kind = "flip", card = a.card, uses = 1 }) end },
	win = { check = function(g, a) return isPlayer(g, a.player) end,
		run = function(g, a) g:win(a.player) end },
}

function Game:resolveManually(item)
	local text = self.cards[item.card].def[item.side] or ""
	while true do
		local a = self:ask(item.controller, "manual",
			"Resolve " .. item.desc .. ": " .. text, nil, {
				card = item.card,
				validate = function(ans)
					if type(ans) ~= "table" then return false, "answer with a table" end
					if ans.action == "done" then return true end
					local def = TTE.MANUAL_ACTIONS[ans.action]
					if not def then return false, "unknown action" end
					if not def.check(self, ans) then return false, "that action isn't legal" end
					return true
				end,
			})
		if a.action == "done" then return end
		TTE.MANUAL_ACTIONS[a.action].run(self, a)
	end
end
