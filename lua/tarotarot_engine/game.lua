-- Tarotarot rules engine: game state, zones, decisions and the coroutine driver.
--
-- Plain Lua 5.1 with no Garry's Mod dependencies, so it runs (and is tested)
-- outside the game. docs/RULES.md is the spec.
--
-- The whole game runs inside one coroutine. Whenever a player has to decide
-- something, the engine stores a decision in game.pending and yields; the UI
-- (or a test) calls game:answer(player, choice) to continue.

TTE = TTE or {}
TTE.Cards = TTE.Cards or {} -- card scripts: TTE.Cards["The Fool"] = { upright = fn, reversed = fn }

local Game = {}
Game.__index = Game
TTE.Game = Game

TTE.POSITIONS = { "past", "present", "future" }
TTE.START_LIFE = 20
TTE.START_HAND = 3

-- Sentinel error used to unwind the coroutine when the game ends.
local GAME_OVER = setmetatable({}, { __tostring = function() return "game over" end })
TTE.GAME_OVER = GAME_OVER

local unpack = table.unpack or unpack

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function removeValue(list, value)
	for i = #list, 1, -1 do
		if list[i] == value then
			table.remove(list, i)
			return i
		end
	end
end
TTE.removeValue = removeValue

-- Deterministic RNG (Park-Miller) so games can be replayed from a seed.
local function makeRng(seed)
	local state = (seed or os.time()) % 2147483647
	if state <= 0 then state = state + 2147483646 end
	return function(n)
		state = (state * 16807) % 2147483647
		if n then return state % n + 1 end
		return state / 2147483647
	end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

-- TTE.new{
--   players = { "alice", "bob" },       -- 2-4 names, in clockwise seat order
--   cards   = { { name =, suit = }, ...},  -- card definitions (suit "Major" for Majors)
--   seed    = number,                     -- optional, for reproducible games
--   first   = index,                      -- optional starting player (else random)
--   effects = table,                      -- optional card scripts (default TTE.Cards)
-- }
function TTE.new(opts)
	assert(opts.players and #opts.players >= 2 and #opts.players <= 4, "2-4 players")
	local g = setmetatable({}, Game)
	g.rng = makeRng(opts.seed)
	g.effects = opts.effects or TTE.Cards or {}
	g.firstChoice = opts.first
	g.log = {}
	g.cards = {}
	g.out = {}      -- removed from the game
	g.unused = {}   -- left over after dealing
	g.stack = {}
	g.modifiers = {}
	g.triggers = {}
	g.permissions = {}
	g.nextId = 0
	g.turnNumber = 0

	g.players = {}
	for i, name in ipairs(opts.players) do
		g.players[i] = {
			id = i, name = name, life = TTE.START_LIFE,
			deck = {}, hand = {}, memory = {}, spread = {},
			eliminated = false,
		}
	end

	for i, def in ipairs(opts.cards) do
		g.cards[i] = {
			id = i, def = def, name = def.name, major = def.suit == "Major",
			faceUp = false, reversed = false, counters = {}, loc = nil,
		}
	end
	return g
end

function Game:uid()
	self.nextId = self.nextId + 1
	return self.nextId
end

function Game:say(fmt, ...)
	local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
	self.log[#self.log + 1] = msg
	if self.onLog then self.onLog(msg) end
end

function Game:shuffle(list)
	for i = #list, 2, -1 do
		local j = self.rng(i)
		list[i], list[j] = list[j], list[i]
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

function Game:player(id) return self.players[id] end

function Game:living()
	local out = {}
	for _, p in ipairs(self.players) do
		if not p.eliminated then out[#out + 1] = p.id end
	end
	return out
end

-- Living players starting from `from` (inclusive) and going clockwise.
function Game:inOrderFrom(from)
	local out, n = {}, #self.players
	for k = 0, n - 1 do
		local id = (from - 1 + k) % n + 1
		if not self.players[id].eliminated then out[#out + 1] = id end
	end
	return out
end

function Game:opponents(id)
	local out = {}
	for _, pid in ipairs(self:inOrderFrom(id)) do
		if pid ~= id then out[#out + 1] = pid end
	end
	return out
end

function Game:nextPlayer(id)
	local order = self:inOrderFrom(id % #self.players + 1)
	return order[1]
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------
-- A card's location is card.loc = { zone = "deck"|"hand"|"memory"|"spread"|"out"|"unused",
-- player = id (nil for out/unused), pos = "past"|"present"|"future" (spread only) }.
-- Decks are ordered bottom -> top (top is the last element).

function Game:card(id) return self.cards[id] end

function Game:zoneList(player, zone)
	if zone == "out" then return self.out end
	if zone == "unused" then return self.unused end
	return self.players[player][zone]
end

-- Take a card out of wherever it is.
function Game:lift(cid)
	local card = self.cards[cid]
	local loc = card.loc
	if not loc then return end
	if loc.zone == "spread" then
		local spread = self.players[loc.player].spread
		if spread[loc.pos] == cid then spread[loc.pos] = nil end
	else
		removeValue(self:zoneList(loc.player, loc.zone), cid)
	end
	card.loc = nil
end

-- Put a card into a zone. Leaving the spread clears orientation and
-- counters. Decks and hands are face down; memory and out are face up.
-- opts.bottom puts a card at the bottom of a deck.
function Game:putCard(cid, player, zone, pos, opts)
	opts = opts or {}
	local card = self.cards[cid]
	self:lift(cid)
	if zone == "spread" then
		local spread = self.players[player].spread
		assert(spread[pos] == nil, "space is occupied")
		spread[pos] = cid
		card.loc = { zone = "spread", player = player, pos = pos }
		return
	end

	card.reversed = false
	card.counters = {}
	card.faceUp = zone == "memory" or zone == "out"
	local list = self:zoneList(player, zone)
	if zone == "deck" and opts.bottom then
		table.insert(list, 1, cid)
	else
		list[#list + 1] = cid
	end
	card.loc = { zone = zone, player = (zone ~= "out" and zone ~= "unused") and player or nil }
end

function Game:topOfDeck(player)
	local deck = self.players[player].deck
	return deck[#deck]
end

-- The player whose spread/hand/memory/deck a card is in ("its player").
function Game:cardPlayer(cid)
	local loc = self.cards[cid].loc
	return loc and loc.player
end

function Game:spreadCards(player)
	local out = {}
	local spread = self.players[player].spread
	for _, pos in ipairs(TTE.POSITIONS) do
		if spread[pos] then out[#out + 1] = spread[pos] end
	end
	return out
end

-- Every card on every living player's spread, in turn order from `from`.
function Game:allSpreadCards(from)
	local out = {}
	for _, pid in ipairs(self:inOrderFrom(from or 1)) do
		for _, cid in ipairs(self:spreadCards(pid)) do out[#out + 1] = cid end
	end
	return out
end

-- Effect text on the side of a card facing its player.
function Game:activeText(cid)
	local card = self.cards[cid]
	return card.reversed and card.def.reversed or card.def.upright
end

function Game:describe(cid)
	local card = self.cards[cid]
	return card.name .. (card.reversed and " (reversed)" or "")
end

---------------------------------------------------------------------------
-- Decisions and the coroutine driver
---------------------------------------------------------------------------

-- Ask a player to decide. Must be called from inside the game coroutine.
--   options:  list of { id = string, label = string } the answer must pick from
--   validate: alternatively, function(answer) -> ok, err for free-form answers
--   data:     anything the UI needs (e.g. a privately revealed card)
function Game:ask(player, kind, prompt, options, extra)
	local d = { player = player, kind = kind, prompt = prompt, options = options }
	if extra then for k, v in pairs(extra) do d[k] = v end end
	while true do
		self.pending = d
		local answer = coroutine.yield(d)
		self.pending = nil
		local ok, err = self:validateAnswer(d, answer)
		if ok then return answer end
		self.lastError = err
	end
end

function Game:validateAnswer(d, answer)
	if d.validate then return d.validate(answer) end
	if d.options then
		for _, opt in ipairs(d.options) do
			if opt.id == answer then return true end
		end
		return false, "not one of the options"
	end
	return true
end

-- Start the game: runs until the first decision (or the end).
function Game:start()
	self.co = coroutine.create(function() self:run() end)
	return self:resume()
end

-- Answer the pending decision. Returns ok, err.
function Game:answer(player, answer)
	local d = self.pending
	if self.over then return false, "the game is over" end
	if not d then return false, "nothing to decide" end
	if d.player ~= player then return false, "it's not your decision" end
	local ok, err = self:validateAnswer(d, answer)
	if not ok then return false, err end
	self:resume(answer)
	return true
end

function Game:resume(answer)
	local ok, err = coroutine.resume(self.co, answer)
	if not ok then
		if err == GAME_OVER then
			self.pending = nil
			return
		end
		self.crashed = err
		error(err, 0)
	end
end

---------------------------------------------------------------------------
-- End of the game
---------------------------------------------------------------------------

function Game:endGame(winners, why)
	self.over = true
	self.winners = winners
	local names = {}
	for _, pid in ipairs(winners) do names[#names + 1] = self.players[pid].name end
	self:say("Game over%s: %s.", why and (" (" .. why .. ")") or "",
		#names > 0 and (table.concat(names, ", ") .. " wins") or "nobody wins")
	error(GAME_OVER, 0)
end

-- "You win the game."
function Game:win(player)
	self:endGame({ player }, self.players[player].name .. " won by card effect")
end

TTE.unpack = unpack
