-- Tarotarot Tabletop: running a rules-engine game (lua/tarotarot_engine) on the table.
--
-- While a game runs, the engine is the authority. After every decision the
-- table rebuilds its zones, hands and life totals from the engine's state
-- (SyncFromEngine). Table gestures become answers to the engine's current
-- decision: during your place step, dropping a card on your spread places
-- it; while resolving a card by hand, moves become keyword actions (spread
-- -> memory dismisses, hand -> memory discards, anything -> Out of Game
-- removes, and so on). Anything the engine won't accept is refused.

local cfg = TT.Config

-- Decisions answered with a pop-up of buttons. The others are made on the
-- table (Shift+R still opens a list of options for them).
local POPUP_KINDS = { may_draw = true, priority = true, order_replacements = true, choose = true }

-- Extra answers for manual resolution, offered as buttons
local MANUAL_EXTRAS = {
	{ id = "done", label = "Done resolving this card" },
	{ id = "restart", label = "Restart the turn from the Past" },
	{ id = "permit_flip", label = "Let me flip a face-down card later (at any time)" },
	{ id = "win", label = "I win the game" },
}

---------------------------------------------------------------------------
-- Starting and stopping
---------------------------------------------------------------------------

function ENT:StartEngineGame()
	local seats = self:SeatedSeats()
	if #seats < 2 then return false, "At least 2 players need to sit down first" end

	self:ClearTable()
	self.CardEnts = {}       -- engine card id -> card entity
	self.EngineSeats = seats -- engine player id -> seat
	self.DecisionSerial = 0
	-- Names for the log; a player holding several seats (solo) gets one per seat
	local names, count = {}, {}
	for _, seat in ipairs(seats) do
		local ply = self:SeatOwner(seat)
		count[ply] = (count[ply] or 0) + 1
	end
	for i, seat in ipairs(seats) do
		local ply = self:SeatOwner(seat)
		names[i] = ply:Nick() .. (count[ply] > 1 and (" (seat " .. seat .. ")") or "")
	end

	local g = TTE.new({
		players = names,
		cards = TT.Decks[cfg.DefaultDeck].cards,
		seed = math.random(1, 1073741823),
		first = math.random(#seats),
	})
	self.Engine, self.EngineLogN = g, 0
	self:SetEngineOn(true)
	self:SetFirstSeat(seats[g.firstChoice])
	for seat = 1, TT.MaxSeats do self:SetLife(seat, 0) end
	PrintMessage(HUD_PRINTTALK, "[Tarotarot] New game: " .. table.concat(names, ", ") .. ". The rules engine is running it.")

	self:AfterEngine(pcall(g.start, g))
	return true
end

function ENT:StopEngineGame()
	if not self.Engine then return end
	self.Engine = nil
	self.Staged = nil
	self:SetEngineOn(false)
	self:SetWaitSeat(0)
	self:SetStatus("")
	-- Clear everyone's decision prompts. The cards stay where they are (free play).
	for seat = 1, TT.MaxSeats do
		local ply = self:SeatOwner(seat)
		if IsValid(ply) then
			net.Start("tt_decision")
			net.WriteEntity(self)
			net.WriteString("")
			net.Send(ply)
		end
	end
end

---------------------------------------------------------------------------
-- Engine -> table
---------------------------------------------------------------------------

function ENT:EnginePidOfSeat(seat)
	for pid, s in ipairs(self.EngineSeats) do
		if s == seat then return pid end
	end
end

-- The engine's pending decision, if it belongs to (one of) ply's seats.
function ENT:MyDecision(ply)
	local g = self.Engine
	local d = g and g.pending
	if d and self:SeatOwner(self.EngineSeats[d.player]) == ply then return d end
end

function ENT:WaitingMessage()
	local g = self.Engine
	local d = g and g.pending
	if not d then return "Not now" end
	return "Waiting for " .. self.Engine.players[d.player].name .. ": " .. self:PublicStatus(d)
end

-- What everyone may know about a decision (prompts can contain private cards).
function ENT:PublicStatus(d)
	local g = self.Engine
	local who = self:SeatOwner(self.EngineSeats[d.player])
	local name = g.players[d.player].name
	if d.kind == "survey_past" then return name .. " is choosing how their Past card faces" end
	if d.kind == "place_source" or d.kind == "place_target" then return name .. " is placing a card" end
	if d.kind == "may_draw" then return name .. " may draw a card" end
	if d.kind == "priority" then return name .. " has priority" end
	if d.kind == "order_replacements" then return name .. " is choosing the order of effects" end
	if d.kind == "manual" then return name .. " is resolving " .. g:describe(d.card) end
	if d.kind == "choose" then return name .. " is choosing" end
	return name .. " is deciding"
end

-- Called after every engine step.
function ENT:AfterEngine(ok, err)
	local g = self.Engine
	if not g then return end
	if not ok then
		ErrorNoHalt("[Tarotarot] rules engine error: " .. tostring(err) .. "\n")
		PrintMessage(HUD_PRINTTALK, "[Tarotarot] The rules engine hit an error and stopped; carry on in free play. (" .. tostring(err) .. ")")
		self:StopEngineGame()
		return
	end

	self:SyncFromEngine()

	for i = self.EngineLogN + 1, #g.log do
		net.Start("tt_log")
		net.WriteEntity(self)
		net.WriteString(g.log[i])
		net.Broadcast()
	end
	self.EngineLogN = #g.log

	self:SendDecisions()
	if g.over then
		PrintMessage(HUD_PRINTTALK, "[Tarotarot] " .. g.log[#g.log])
		self:StopEngineGame()
	end
end

-- Rebuild the table's zones, hands and life totals from the engine.
function ENT:SyncFromEngine()
	local g = self.Engine
	local deckName = cfg.DefaultDeck

	self.Lists, self.Slots = {}, {}
	for _, zone in ipairs(TT.Zones) do
		if zone.kind == "grid" then self.Slots[zone.id] = {} else self.Lists[zone.id] = {} end
	end

	local wanted = {}
	local function isHeld(ent) return IsValid(ent) and (ent.IsHeld or ent == self.Staged) end
	local function show(cid, zoneId)
		wanted[cid] = true
		local ent = self.CardEnts[cid]
		if not IsValid(ent) then
			ent = self:CreateCard(deckName, cid)
			self.CardEnts[cid] = ent
		end
		if isHeld(ent) then return end -- someone has it in hand; leave it be

		local c, zone = g.cards[cid], TT.GetZone(zoneId)
		ent.ZoneId, ent.Slot, ent.BaseYaw = zoneId, nil, zone.yaw
		if ent.FaceUp ~= c.faceUp then ent:SetFaceUp(c.faceUp) end
		if zone.kind == "pile" then ent:SetPeek(nil) end
		ent:SetReversed(c.reversed)
		ent:SetCounter1(c.counters.generic or 0)
		ent:SetCounter2(c.counters.silence or 0)
		if zone.kind == "grid" then
			ent.Slot = 1
			self.Slots[zoneId][1] = ent
			self:SetCardTransform(ent, TT.SlotPos(zone, 1), cfg.SurfaceOffset)
		else
			table.insert(self.Lists[zoneId], ent)
		end
	end

	for pid, p in ipairs(g.players) do
		local seat = self.EngineSeats[pid]
		local pre = "p" .. seat .. "_"
		for _, cid in ipairs(p.deck) do show(cid, pre .. "deck") end
		for _, cid in ipairs(p.memory) do show(cid, pre .. "memory") end
		for _, pos in ipairs(TTE.POSITIONS) do
			if p.spread[pos] then show(p.spread[pos], pre .. pos) end
		end

		local hand = {}
		for _, cid in ipairs(p.hand) do
			if isHeld(self.CardEnts[cid]) then
				wanted[cid] = true -- taken out to play; stays out of the hand strip
			else
				hand[#hand + 1] = { deck = deckName, id = cid }
			end
		end
		self.Hands[seat] = hand
		self:SyncHand(seat)
		self:SetLife(seat, p.life)
	end
	for _, cid in ipairs(g.out) do show(cid, "out") end

	-- Cards in hands (or left out of the deal) have no entity
	for cid, ent in pairs(self.CardEnts) do
		if not wanted[cid] then
			if IsValid(ent) then
				ent:SetBoard(NULL)
				ent:Remove()
			end
			self.CardEnts[cid] = nil
		end
	end
	for zoneId in pairs(self.Lists) do self:LayoutZone(zoneId) end
end

-- Surveying the Past: the card you've put in your Past but not confirmed yet.
function ENT:StagedCard()
	local d = self.Engine and self.Engine.pending
	local card = self.Staged
	if IsValid(card) and d and d.kind == "survey_past" and d.card == card.CardId then return card end
end

-- Each player seated at the table, once (solo players hold several seats).
function ENT:SeatedPlayers()
	local out, seen = {}, {}
	for seat = 1, TT.MaxSeats do
		local ply = self:SeatOwner(seat)
		if IsValid(ply) and not seen[ply] then
			seen[ply] = true
			out[#out + 1] = ply
		end
	end
	return out
end

-- The buttons offered for a decision.
function ENT:DecisionOptions(d)
	if d.kind == "manual" then return MANUAL_EXTRAS end
	if d.kind == "survey_past" then
		local staged = self:StagedCard()
		local out = {}
		if staged then
			out[1] = { id = "staged", label = "Confirm: " .. self.Engine.cards[d.card].name .. (staged:GetReversed() and ", reversed" or ", upright") }
		end
		for _, opt in ipairs(d.options) do out[#out + 1] = opt end
		return out
	end
	return d.options
end

-- Status for everyone, and the decision itself for the player making it.
function ENT:SendDecisions()
	local g = self.Engine
	local d = g.pending
	local waitSeat = d and self.EngineSeats[d.player] or 0
	self:SetTurnNumber(g.turnNumber)
	self:SetTurnSeat(g.active and self.EngineSeats[g.active] or 0)
	self:SetWaitSeat(waitSeat)
	self:SetStatus(d and self:PublicStatus(d) or "")

	if d and not d.serial then
		self.DecisionSerial = self.DecisionSerial + 1
		d.serial = self.DecisionSerial
	end
	-- One message per player, not per seat: a solo player holds several seats,
	-- and a "nothing to decide" for one seat must not wipe the real decision.
	local decider = d and self:SeatOwner(waitSeat)
	for _, ply in ipairs(self:SeatedPlayers()) do
		do
			net.Start("tt_decision")
			net.WriteEntity(self)
			if d and ply == decider then
				local options = self:DecisionOptions(d)
				net.WriteString(d.kind)
				net.WriteUInt(waitSeat, 3)
				net.WriteString(d.prompt or "")
				net.WriteUInt(d.serial, 32)
				net.WriteBool(POPUP_KINDS[d.kind] == true)
				net.WriteUInt(d.card or 0, 16)
				net.WriteUInt(#options, 8)
				for _, opt in ipairs(options) do
					net.WriteString(opt.id)
					net.WriteString(opt.label or opt.id)
				end
			else
				net.WriteString("")
			end
			net.Send(ply)
		end
	end

	-- A card revealed only to the decider (placing from the deck, surveying the Past)
	if d and d.card and d.private and IsValid(self.CardEnts[d.card]) then
		self.CardEnts[d.card]:SetPeek(self:SeatOwner(waitSeat))
	end
end

---------------------------------------------------------------------------
-- Table -> engine
---------------------------------------------------------------------------

-- Answer the engine's pending decision on ply's behalf.
function ENT:EngineAnswer(ply, answer)
	local g = self.Engine
	if not g then return false, "No game is running" end
	local d = self:MyDecision(ply)
	if not d then return false, self:WaitingMessage() end

	-- Button answers for manual resolution
	if d.kind == "manual" and type(answer) == "string" then
		local pid = d.player
		answer = ({
			done = { action = "done" },
			restart = { action = "restart" },
			permit_flip = { action = "permit_flip", player = pid },
			win = { action = "win", player = pid },
		})[answer]
		if not answer then return false, "Unknown option" end
	end

	if d.kind == "survey_past" then
		if answer == "staged" then
			local staged = self:StagedCard()
			if not staged then return false, "Put the card in your Past first" end
			answer = staged:GetReversed() and "reversed" or "upright"
		end
		self.Staged = nil -- the engine places it now
	end

	local called, good, err = pcall(g.answer, g, d.player, answer)
	if not called then
		self:AfterEngine(false, good)
		return false, "The rules engine hit an error"
	end
	if not good then return false, err == "that action isn't legal" and "That isn't allowed by the rules" or err end
	self:AfterEngine(true)
	return true
end

-- Picking a card up off the table. Returns ok, why-or-answer.
function ENT:EnginePickUp(card, ply)
	local d = self:MyDecision(ply)
	if not d then return false, self:WaitingMessage() end
	local cid = card.CardId
	if d.kind == "manual" then return true end
	if d.kind == "survey_past" then
		if cid ~= d.card then return false, "Survey the Past: take the top card of your deck" end
		if card == self.Staged then self.Staged = nil end
		return true
	end
	if d.kind == "place_source" then
		-- Any card the decision offers (a memory card, say), or the deck's top card
		for _, opt in ipairs(d.options) do
			if opt.id == "card:" .. cid then return true, opt.id end
		end
		if self.Engine:topOfDeck(d.player) == cid then
			for _, opt in ipairs(d.options) do
				if opt.id == "deck" then return true, "deck" end -- choosing the deck reveals the card to you
			end
		end
		return false, "You can't place that card"
	end
	if d.kind == "place_target" and d.card == cid then return true end
	return false, "You can't move cards right now"
end

-- Taking a card out of your hand (LMB on your hand zone).
function ENT:EngineTakeFromHand(ply, index, faceUp, seat)
	local hand = self.Hands[seat]
	if not hand or #hand == 0 then return nil end
	local entry = hand[math.Clamp(index, 1, #hand)]
	local cid = entry.id

	local d = self:MyDecision(ply)
	if not d then return nil, self:WaitingMessage() end
	if self.EngineSeats[d.player] ~= seat and d.kind ~= "manual" then
		return nil, "It's seat " .. self.EngineSeats[d.player] .. "'s decision, not this hand's"
	end
	local answer
	if d.kind == "place_source" then
		answer = "card:" .. cid
		local offered = false
		for _, opt in ipairs(d.options) do
			if opt.id == answer then offered = true end
		end
		if not offered then return nil, "You can't place that card" end
		faceUp = true
	elseif d.kind == "place_target" then
		if d.card ~= cid then return nil, "Place the card you chose" end
		faceUp = true
	elseif d.kind ~= "manual" then
		return nil, "You can't play cards right now"
	end

	TTE.removeValue(hand, entry)
	self:SyncHand(seat)
	local zone = TT.HandZone(seat)
	local card = self:CreateCard(entry.deck, cid)
	self.CardEnts[cid] = card
	card:SetFaceUp(faceUp)
	if not faceUp then card:SetPeek(ply) end
	card.BaseYaw = zone.yaw
	card.IsHeld = true
	card:SetHolder(ply)
	self:MoveHeld(card, zone.pos)
	if answer then self:EngineAnswer(ply, answer) end
	return card
end

local function release(card)
	card.IsHeld = false
	card:SetHolder(NULL)
end

local function hold(card, ply)
	card.IsHeld = true
	card:SetHolder(ply)
end

-- Dropping a held card at table-local point p.
function ENT:EngineDrop(card, p, ply)
	local g = self.Engine
	local zone = TT.ZoneAt(p)
	if not zone then return false, "Cards can only go in a zone" end
	local d = self:MyDecision(ply)
	if not d then return false, self:WaitingMessage() end

	local cid, c = card.CardId, g.cards[card.CardId]
	local target = zone.seat and self:EnginePidOfSeat(zone.seat)
	if zone.seat and not target then return false, "Nobody is playing at that seat" end
	local key = zone.id:match("_(%a+)$")

	if d.kind == "survey_past" then
		if zone.kind ~= "grid" or key ~= "past" or target ~= d.player then return false, "Put it in your Past" end
		-- Staged: it sits in the Past (still hidden from others) until confirmed
		release(card)
		self.Staged = card
		card.BaseYaw = zone.yaw
		self:SetCardTransform(card, TT.SlotPos(zone, 1), cfg.SurfaceOffset)
		self:SendDecisions()
		return true
	end

	local answer
	if d.kind == "place_source" or d.kind == "place_target" then
		local onto = d.onto or d.player
		if zone.kind ~= "grid" or target ~= onto then
			return false, onto == d.player and "Place it on your own spread" or ("Place it on " .. g.players[onto].name .. "'s spread")
		end
		answer = key .. ":" .. (card:GetReversed() and "reversed" or "upright")
		-- Some places keep the card's orientation: then that space's only option is it
		local exact, only, count = false, nil, 0
		for _, opt in ipairs(d.options or {}) do
			if opt.id == answer then exact = true end
			if opt.id:match("^(%a+):") == key then only, count = opt.id, count + 1 end
		end
		if not exact and count == 1 then answer = only end
	elseif d.kind ~= "manual" then
		return false, "You can't move cards right now"
	elseif zone.kind == "grid" then
		local there = g.players[target].spread[key]
		if there == cid then
			release(card)
			self:SyncFromEngine()
			return true
		elseif there and c.loc.zone == "spread" then
			answer = { action = "swap", card = cid, card2 = there }
		else
			answer = { action = "place", player = target, card = cid, pos = key,
				reversed = card:GetReversed(), faceDown = not card.FaceUp }
		end
	elseif zone.kind == "pile" then
		answer = { action = "move", card = cid, player = target, zone = "deck" }
	elseif zone.id == "out" then
		answer = { action = "remove", card = cid }
	elseif zone.kind == "row" then
		if c.loc.zone == "hand" and c.loc.player == target then
			answer = { action = "discard", card = cid }
		elseif c.loc.zone == "spread" and c.loc.player == target then
			answer = { action = "dismiss", card = cid }
		else
			answer = { action = "move", card = cid, player = target, zone = "memory" }
		end
	elseif zone.kind == "hand" then
		if c.loc.zone == "spread" and c.loc.player == target then
			answer = { action = "to_hand", card = cid }
		else
			answer = { action = "move", card = cid, player = target, zone = "hand" }
		end
	else
		return false, "That's the life counter"
	end

	-- Let go first so the sync can put the card where the engine says
	release(card)
	local ok, why = self:EngineAnswer(ply, answer)
	if not ok and IsValid(card) then hold(card, ply) end
	return ok, why
end

-- The holder put the card away: back to wherever the engine has it.
function ENT:EngineReturn(card)
	release(card)
	self:SyncFromEngine()
end

-- Flip / turn / counters on a card. Held cards are only adjusted locally
-- (e.g. choosing the orientation before placing); cards on the table need
-- an engine action, so only while you're resolving a card by hand.
function ENT:EngineCardAction(ply, card, action, kind, delta)
	if card == self:StagedCard() and self:MyDecision(ply) then
		if action ~= "turn" then return false, "Your Past card goes in face up: R turns it, Shift+R confirms" end
		card:SetReversed(not card:GetReversed())
		card:SetLocalAngles(self:CardAngle(card))
		self:SendDecisions() -- update the Confirm button
		return true
	end
	if card.IsHeld then
		if action == "turn" then
			card:SetReversed(not card:GetReversed())
			card:SetLocalAngles(self:CardAngle(card))
			return true
		elseif action == "flip" then
			card:SetFaceUp(not card.FaceUp)
			return true
		end
		return false, "Put the card down first"
	end

	local d = self:MyDecision(ply)
	if not d or d.kind ~= "manual" then return false, d and "You can't change cards right now" or self:WaitingMessage() end
	local cid = card.CardId
	local answer
	if action == "flip" then
		answer = { action = "flip", card = cid }
	elseif action == "turn" then
		answer = { action = "reverse", card = cid }
	elseif action == "counter" and kind == 2 and delta > 0 then
		answer = { action = "silence", card = cid }
	elseif action == "counter" then
		answer = { action = "counter", card = cid, kind = kind == 2 and "silence" or "generic", delta = delta }
	end
	return self:EngineAnswer(ply, answer)
end

function ENT:EngineLife(ply, seat, delta)
	local target = self:EnginePidOfSeat(seat)
	if not target then return false, "Nobody is playing at that seat" end
	if delta < 0 then
		return self:EngineAnswer(ply, { action = "damage", player = target, amount = -delta })
	end
	return self:EngineAnswer(ply, { action = "gain_life", player = target, amount = delta })
end

-- E on a deck: draw (your optional draw, or a draw while resolving);
-- Shift+E: shuffle (while resolving).
function ENT:EngineUseDeck(ply, zone, shift)
	local d = self:MyDecision(ply)
	if not d then return false, self:WaitingMessage() end
	local target = self:EnginePidOfSeat(zone.seat)
	if not target then return false, "Nobody is playing at that seat" end
	if d.kind == "may_draw" and not shift and target == d.player then
		return self:EngineAnswer(ply, "draw")
	elseif d.kind == "manual" then
		return self:EngineAnswer(ply, { action = shift and "shuffle" or "draw", player = target })
	end
	return false, "You can't do that right now"
end
