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
	self.Piles, self.Slots = {}, {}
	for _, zone in ipairs(TT.Zones) do
		if zone.kind == "pile" then self.Piles[zone.id] = {} else self.Slots[zone.id] = {} end
	end
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

-- Spawn every card of a deck face down into a pile zone, then shuffle it.
function ENT:SpawnDeck(zoneId, deckName)
	local zone, deck = TT.GetZone(zoneId), TT.Decks[deckName]
	if not zone or zone.kind ~= "pile" or not deck then return end

	for id in ipairs(deck.cards) do
		local card = ents.Create("tt_card")
		card:Spawn()
		card:SetParent(self)
		card:SetBoard(self)
		card:SetCard(deckName, id)
		self:PlaceCard(card, zoneId)
	end
	self:ShuffleZone(zoneId)
end

---------------------------------------------------------------------------
-- Card placement
---------------------------------------------------------------------------

function ENT:SetCardTransform(card, pos, z)
	card:SetLocalPos(Vector(pos.x, pos.y, cfg.TableHeight + z))
	card:SetLocalAngles(Angle(0, card.BaseYaw - 90 * card.Rot, 0))
end

function ENT:LayoutPile(zoneId)
	local zone = TT.GetZone(zoneId)
	for i, card in ipairs(self.Piles[zoneId]) do
		self:SetCardTransform(card, zone.pos, cfg.SurfaceOffset + (i - 1) * cfg.CardThick)
	end
end

-- Put a card into a zone. Piles stack on top; grids need a free slot number.
function ENT:PlaceCard(card, zoneId, slot)
	local zone = TT.GetZone(zoneId)
	card.ZoneId, card.Slot, card.IsHeld = zoneId, slot, false
	card.BaseYaw = zone.yaw
	card:SetHolder(NULL)

	if zone.kind == "pile" then
		card.Rot = 0
		table.insert(self.Piles[zoneId], card)
		self:LayoutPile(zoneId)
	else
		self.Slots[zoneId][slot] = card
		self:SetCardTransform(card, TT.SlotPos(zone, slot), cfg.SurfaceOffset)
	end
end

-- Take a card out of whatever zone it is in.
function ENT:DetachCard(card)
	local zone = TT.GetZone(card.ZoneId)
	if zone and zone.kind == "pile" then
		if table.RemoveByValue(self.Piles[zone.id], card) then self:LayoutPile(zone.id) end
	elseif zone and self.Slots[zone.id][card.Slot] == card then
		self.Slots[zone.id][card.Slot] = nil
	end
	card.ZoneId, card.Slot = nil, nil
end

-- If the card is in a pile, you always get the top card.
function ENT:TopOf(card)
	local zone = TT.GetZone(card.ZoneId)
	if zone and zone.kind == "pile" then
		local pile = self.Piles[zone.id]
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

-- Drop a held card at table-local point p. Returns false if there's no room.
function ENT:TryDrop(card, p)
	local zone = TT.ZoneAt(p)
	if not zone then return false end

	local slot
	if zone.kind == "grid" then
		slot = self:NearestFreeSlot(zone, p)
		if not slot then return false end
	end
	self:PlaceCard(card, zone.id, slot)
	card:EmitSound("physics/cardboard/cardboard_box_impact_soft1.wav", 55, math.random(115, 135))
	return true
end

-- Put a held card back where it came from (used when the holder lets go).
function ENT:ReturnCard(card)
	local zone = TT.GetZone(card.OriginZone)
	if zone and zone.kind == "pile" then
		self:PlaceCard(card, zone.id)
		return
	end
	if zone then
		local slot = card.OriginSlot
		if not slot or IsValid(self.Slots[zone.id][slot]) then slot = self:NearestFreeSlot(zone, zone.pos) end
		if slot then
			self:PlaceCard(card, zone.id, slot)
			return
		end
	end
	for _, z in ipairs(TT.Zones) do
		if z.kind == "pile" then
			self:PlaceCard(card, z.id)
			return
		end
	end
end

function ENT:RotateCard(card, dir)
	card.Rot = (card.Rot + dir) % 4
	card:SetLocalAngles(Angle(0, card.BaseYaw - 90 * card.Rot, 0))
end

function ENT:ShuffleZone(zoneId)
	local pile = self.Piles[zoneId]
	if not pile then return end
	for i = #pile, 2, -1 do
		local j = math.random(i)
		pile[i], pile[j] = pile[j], pile[i]
	end
	self:LayoutPile(zoneId)
	self:EmitSound("physics/cardboard/cardboard_box_impact_soft2.wav", 60, 90)
end
