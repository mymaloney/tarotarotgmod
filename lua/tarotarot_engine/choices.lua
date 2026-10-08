-- Tarotarot rules engine: choice helpers for card scripts.
--
-- Each one asks a player to pick from a list (a "choose" decision, shown as
-- buttons). Labels never reveal a card the chooser isn't allowed to see.

local Game = TTE.Game

local function possessive(g, pid, viewer)
	return pid == viewer and "your" or (g.players[pid].name .. "'s")
end

-- How a card is described to `viewer`.
function Game:cardLabel(cid, viewer)
	local card = self.cards[cid]
	local loc = card.loc
	if not loc then return card.name end
	if loc.zone == "spread" then
		local who = possessive(self, loc.player, viewer)
		if card.faceUp then return self:describe(cid) .. " (" .. who .. " " .. loc.pos .. ")" end
		return "face-down card (" .. who .. " " .. loc.pos .. ")"
	elseif loc.zone == "hand" then
		if loc.player == viewer then return card.name .. " (your hand)" end
		for i, h in ipairs(self.players[loc.player].hand) do
			if h == cid then return "card " .. i .. " in " .. self.players[loc.player].name .. "'s hand" end
		end
	elseif loc.zone == "memory" then
		return card.name .. " (" .. possessive(self, loc.player, viewer) .. " memory)"
	elseif loc.zone == "deck" then
		return "a card in " .. possessive(self, loc.player, viewer) .. " deck"
	end
	return card.name
end

-- Pick one item. items: list of { label =, value = }. Returns the value, or
-- nil if opts.optional and the player declines (or there's nothing to pick).
function Game:chooseOne(player, prompt, items, opts)
	opts = opts or {}
	if #items == 0 then return nil end
	if #items == 1 and not opts.optional and not opts.always then return items[1].value end
	local options = {}
	for i, item in ipairs(items) do options[i] = { id = tostring(i), label = item.label } end
	if opts.optional then options[#options + 1] = { id = "none", label = opts.noneLabel or "None" } end
	local pick = self:ask(player, "choose", prompt, options, { card = opts.card, private = opts.private })
	if pick == "none" then return nil end
	return items[tonumber(pick)].value
end

function Game:yesNo(player, prompt, yesLabel, noLabel)
	return self:chooseOne(player, prompt, {
		{ label = yesLabel or "Yes", value = true },
		{ label = noLabel or "No", value = false },
	}, { always = true }) == true
end

function Game:choosePlayer(player, prompt, candidates, opts)
	local items = {}
	for _, pid in ipairs(candidates or self:living()) do
		local p = self.players[pid]
		items[#items + 1] = { label = (pid == player and "You" or p.name) .. " (life " .. p.life .. ")", value = pid }
	end
	return self:chooseOne(player, prompt, items, opts)
end

function Game:chooseCard(player, prompt, cids, opts)
	local items = {}
	for _, cid in ipairs(cids) do items[#items + 1] = { label = self:cardLabel(cid, player), value = cid } end
	return self:chooseOne(player, prompt, items, opts)
end

-- Pick up to `max` cards (opts.min required), one at a time. Returns a list.
function Game:chooseCards(player, prompt, cids, max, opts)
	opts = opts or {}
	local chosen, left = {}, {}
	for i, cid in ipairs(cids) do left[i] = cid end
	while #chosen < (max or #cids) and #left > 0 do
		local need = #chosen < (opts.min or 0)
		local label = prompt .. (max and string.format(" (%d of up to %d chosen)", #chosen, max) or string.format(" (%d chosen)", #chosen))
		local cid = self:chooseCard(player, label, left, { optional = not need, noneLabel = "Done choosing", always = true })
		if not cid then break end
		chosen[#chosen + 1] = cid
		TTE.removeValue(left, cid)
	end
	return chosen
end

-- Pick any number of players.
function Game:choosePlayers(player, prompt, candidates)
	local chosen, left = {}, {}
	for i, pid in ipairs(candidates or self:living()) do left[i] = pid end
	while #left > 0 do
		local pid = self:choosePlayer(player, prompt .. string.format(" (%d chosen)", #chosen), left,
			{ optional = true, noneLabel = "Done choosing", always = true })
		if not pid then break end
		chosen[#chosen + 1] = pid
		TTE.removeValue(left, pid)
	end
	return chosen
end

function Game:chooseNumber(player, prompt, lo, hi)
	local items = {}
	for n = lo, hi do items[#items + 1] = { label = tostring(n), value = n } end
	return self:chooseOne(player, prompt, items, { always = true })
end

function Game:chooseSuit(player, prompt, suits)
	local items = {}
	for _, suit in ipairs(suits) do items[#items + 1] = { label = suit, value = suit } end
	return self:chooseOne(player, prompt, items)
end

-- "Name a card": any card name in the game.
function Game:chooseName(player, prompt)
	local items, seen = {}, {}
	for _, card in ipairs(self.cards) do
		if not seen[card.name] then
			seen[card.name] = true
			items[#items + 1] = { label = card.name, value = card.name }
		end
	end
	return self:chooseOne(player, prompt, items, { always = true })
end

-- A coin flip: true for heads.
function Game:coin()
	return self.rng(2) == 1
end

-- Show a card to everyone.
function Game:reveal(cid, who)
	self:say("%s reveals %s.", who and self.players[who].name or "Revealed:", self.cards[cid].name)
end
