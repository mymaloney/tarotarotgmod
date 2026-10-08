AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local cfg = TT.Config

function ENT:SpawnFunction(ply, tr, class)
	if not tr.Hit then return end

	-- Face the table towards the spawning player, who becomes Player 1 (-Y side).
	local yaw = math.Round((ply:EyeAngles().y - 90) / 90) * 90
	local forward = Angle(0, yaw + 90, 0):Forward()

	local ent = ents.Create(class)
	ent:SetPos(tr.HitPos + forward * (cfg.TableD / 2 + 20))
	ent:SetAngles(Angle(0, yaw, 0))
	ent:Spawn()
	ent:Activate()
	ent:SetupDefaultGame()
	return ent
end

function ENT:Initialize()
	self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
	self:SetupCollision()
	self:DrawShadow(false)
	self:ResetZones()
end

function ENT:ResetZones()
	-- Lists: ordered cards in pile/row zones. Slots: grid slot -> card.
	-- Hands: per-seat list of { deck = name, id = card index } (no entities).
	self.Lists, self.Slots, self.Hands = {}, {}, { {}, {} }
	for _, zone in ipairs(TT.Zones) do
		if zone.kind == "grid" then self.Slots[zone.id] = {} else self.Lists[zone.id] = {} end
	end
	for seat = 1, 2 do self:SyncHand(seat) end
end

function ENT:OnRemove()
	for _, card in ipairs(TT.GetCards(self)) do card:Remove() end
end

---------------------------------------------------------------------------
-- Game setup
---------------------------------------------------------------------------

function ENT:SetupDefaultGame()
	for _, zone in ipairs(TT.Zones) do
		if zone.startDeck then self:SpawnDeck(zone.id, zone.startDeck) end
	end
end

function ENT:ResetGame()
	for _, card in ipairs(TT.GetCards(self)) do
		card:SetBoard(NULL)
		card:Remove()
	end
	self:ResetZones()
	self:SetupDefaultGame()
end

function ENT:CreateCard(deckName, id)
	local card = ents.Create("tt_card")
	card:Spawn()
	card:SetParent(self)
	card:SetBoard(self)
	card:SetCard(deckName, id)
	return card
end

-- Spawn every card of a deck face down into a pile zone, then shuffle it.
function ENT:SpawnDeck(zoneId, deckName)
	local zone, deck = TT.GetZone(zoneId), TT.Decks[deckName]
	if not zone or zone.kind ~= "pile" or not deck then return end

	for id in ipairs(deck.cards) do
		self:PlaceCard(self:CreateCard(deckName, id), zoneId)
	end
	self:ShuffleZone(zoneId)
end

---------------------------------------------------------------------------
-- Card placement
---------------------------------------------------------------------------

function ENT:SetCardTransform(card, pos, z)
	card:SetLocalPos(Vector(pos.x, pos.y, cfg.TableHeight + z))
	card:SetLocalAngles(self:CardAngle(card))
end

function ENT:CardAngle(card)
	return Angle(0, card.BaseYaw + (card:GetReversed() and 180 or 0), 0)
end

function ENT:LayoutZone(zoneId)
	local zone = TT.GetZone(zoneId)
	local list = self.Lists[zoneId]
	for i, card in ipairs(list) do
		if zone.kind == "row" then
			local pos = TT.ZoneToTable(zone, Vector(TT.RowX(zone, i, #list), 0, 0))
			self:SetCardTransform(card, pos, cfg.SurfaceOffset + (i - 1) * cfg.RowStep)
		else
			self:SetCardTransform(card, zone.pos, cfg.SurfaceOffset + (i - 1) * cfg.CardThick)
		end
	end
end

-- Put a card into a zone. Piles stack on top; rows insert at `index` (default:
-- the end); grids need a free slot number. Hands go through AddToHand instead.
function ENT:PlaceCard(card, zoneId, index)
	local zone = TT.GetZone(zoneId)
	card.ZoneId, card.Slot, card.IsHeld = zoneId, nil, false
	card.BaseYaw = zone.yaw
	card:SetHolder(NULL)

	if zone.kind == "grid" then
		card.Slot = index
		self.Slots[zoneId][index] = card
		self:SetCardTransform(card, TT.SlotPos(zone, index), cfg.SurfaceOffset)
		return
	end

	if zone.kind == "pile" then
		card:SetReversed(false)
		if zone.faceDown then
			card:SetFaceUp(false)
			card:SetPeek(nil)
		end
	end
	local list = self.Lists[zoneId]
	table.insert(list, math.Clamp(index or #list + 1, 1, #list + 1), card)
	self:LayoutZone(zoneId)
end

-- Take a card out of whatever zone it is in.
function ENT:DetachCard(card)
	local zone = TT.GetZone(card.ZoneId)
	if zone and zone.kind == "grid" then
		if self.Slots[zone.id][card.Slot] == card then self.Slots[zone.id][card.Slot] = nil end
	elseif zone and self.Lists[zone.id] then
		if table.RemoveByValue(self.Lists[zone.id], card) then self:LayoutZone(zone.id) end
	end
	card.ZoneId, card.Slot = nil, nil
end

-- If the card is in a pile, you always get the top card.
function ENT:TopOf(card)
	local zone = TT.GetZone(card.ZoneId)
	if zone and zone.kind == "pile" then
		local pile = self.Lists[zone.id]
		return pile[#pile] or card
	end
	return card
end

function ENT:NearestFreeSlot(zone, p)
	local best, bestDist
	for slot = 1, zone.cols * zone.rows do
		if not IsValid(self.Slots[zone.id][slot]) then
			local dist = TT.SlotPos(zone, slot):DistToSqr(Vector(p.x, p.y, 0))
			if not bestDist or dist < bestDist then best, bestDist = slot, dist end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------

function ENT:PickUp(card, ply)
	card.OriginZone, card.OriginSlot = card.ZoneId, card.Slot
	self:DetachCard(card)
	card.IsHeld = true
	card:SetHolder(ply)
	self:MoveHeld(card, self:WorldToLocal(card:GetPos()))
end

function ENT:MoveHeld(card, p)
	local hw, hd = cfg.TableW / 2, cfg.TableD / 2
	local pos = Vector(math.Clamp(p.x, -hw, hw), math.Clamp(p.y, -hd, hd), 0)
	self:SetCardTransform(card, pos, cfg.HoldHeight)
end

-- Drop a held card at table-local point p. Returns false (and a reason) if
-- it can't go there.
function ENT:TryDrop(card, p, ply)
	local zone = TT.ZoneAt(p)
	if not zone then return false, "Cards can only go in a zone" end

	if zone.kind == "hand" then
		return self:AddToHand(zone.seat, card, ply)
	end

	local index
	if zone.kind == "grid" then
		index = self:NearestFreeSlot(zone, p)
		if not index then return false, zone.name .. " is taken" end
	elseif zone.kind == "row" then
		-- Insert where it was dropped, among the cards already there
		local x = TT.TableToZone(zone, p).x
		index = 1
		for _, other in ipairs(self.Lists[zone.id]) do
			if TT.TableToZone(zone, self:WorldToLocal(other:GetPos())).x < x then index = index + 1 end
		end
	end
	self:PlaceCard(card, zone.id, index)
	card:EmitSound("physics/cardboard/cardboard_box_impact_soft1.wav", 55, math.random(115, 135))
	return true
end

-- Put a held card back where it came from (used when the holder lets go).
function ENT:ReturnCard(card)
	local zone = TT.GetZone(card.OriginZone)
	if zone and zone.kind == "hand" then
		if self:AddToHand(zone.seat, card, self:SeatOwner(zone.seat)) then return end
		zone = TT.GetZone("p" .. zone.seat .. "_deck")
	end
	if zone and zone.kind == "grid" then
		local slot = card.OriginSlot
		if not slot or IsValid(self.Slots[zone.id][slot]) then slot = self:NearestFreeSlot(zone, zone.pos) end
		if slot then
			self:PlaceCard(card, zone.id, slot)
			return
		end
		zone = TT.GetZone("p" .. zone.seat .. "_memory")
	end
	self:PlaceCard(card, (zone or TT.GetZone("out")).id)
end

---------------------------------------------------------------------------
-- Hidden hands
---------------------------------------------------------------------------

-- Send a seat's hand contents to its owner only; everyone else sees the count.
function ENT:SyncHand(seat, to)
	local hand = self.Hands[seat]
	self["SetHandCount" .. seat](self, #hand)

	to = to or self:SeatOwner(seat)
	if not IsValid(to) then return end
	net.Start("tt_hand")
	net.WriteEntity(self)
	net.WriteUInt(seat, 2)
	net.WriteUInt(#hand, 8)
	for _, entry in ipairs(hand) do
		net.WriteString(entry.deck)
		net.WriteUInt(entry.id, 16)
	end
	net.Send(to)
end

-- Give a seat to a player. Their hand comes with the seat.
function ENT:ClaimSeat(seat, ply)
	self["SetSeat" .. seat](self, ply)
	self:SyncHand(seat)
	ply:ChatPrint("You took seat " .. seat .. " at this table.")
end

function ENT:LeaveSeat(ply)
	local seat = self:SeatOf(ply)
	if not seat then return end
	self["SetSeat" .. seat](self, NULL)
	-- Clear their screen; the cards stay with the seat for whoever sits next
	net.Start("tt_hand")
	net.WriteEntity(self)
	net.WriteUInt(0, 2)
	net.WriteUInt(0, 8)
	net.Send(ply)
end

-- Put a held card into a seat's hand. An empty seat is claimed by ply.
function ENT:AddToHand(seat, card, ply)
	local owner = self:SeatOwner(seat)
	if not IsValid(owner) then
		if not IsValid(ply) then return false end
		if self:SeatOf(ply) then return false, "You already have a hand at this table" end
		self:ClaimSeat(seat, ply)
	end

	local hand = self.Hands[seat]
	if #hand >= 255 then return false, "That hand is full" end
	hand[#hand + 1] = { deck = card:GetDeckName(), id = card.CardId }
	card.IsHeld = false
	card:SetBoard(NULL)
	card:Remove()
	self:SyncHand(seat)
	self:EmitSound("physics/cardboard/cardboard_box_impact_soft1.wav", 50, 150)
	return true
end

-- Take card `index` out of ply's own hand and give it to them to hold.
function ENT:TakeFromHand(ply, index, faceUp)
	local seat = self:SeatOf(ply)
	if not seat then return end
	local hand = self.Hands[seat]
	local entry = hand[math.Clamp(index, 1, #hand)]
	if not entry then return end
	table.RemoveByValue(hand, entry)
	self:SyncHand(seat)

	local zone = TT.HandZone(seat)
	local card = self:CreateCard(entry.deck, entry.id)
	card:SetFaceUp(faceUp)
	if not faceUp then card:SetPeek(ply) end
	card.BaseYaw = zone.yaw
	card.OriginZone, card.OriginSlot = zone.id, nil
	card.IsHeld = true
	card:SetHolder(ply)
	self:MoveHeld(card, zone.pos)
	return card
end

-- Turn a card 180 degrees (upright <-> reversed).
function ENT:TurnCard(card)
	card:SetReversed(not card:GetReversed())
	card:SetLocalAngles(self:CardAngle(card))
end

function ENT:ShuffleZone(zoneId)
	local pile = self.Lists[zoneId]
	if not pile then return end
	for i = #pile, 2, -1 do
		local j = math.random(i)
		pile[i], pile[j] = pile[j], pile[i]
	end
	self:LayoutZone(zoneId)
	self:EmitSound("physics/cardboard/cardboard_box_impact_soft2.wav", 60, 90)
end
