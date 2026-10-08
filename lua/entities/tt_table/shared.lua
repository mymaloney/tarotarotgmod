ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Card Table"
ENT.Author = "Tarotarot"
ENT.Category = "Tabletop"
ENT.Spawnable = true
ENT.RenderGroup = RENDERGROUP_OPAQUE

function ENT:TableBounds()
	local cfg = TT.Config
	return Vector(-cfg.TableW / 2, -cfg.TableD / 2, 0), Vector(cfg.TableW / 2, cfg.TableD / 2, cfg.TableHeight)
end

-- Solid oriented box so players can't walk through it; it isn't physics-driven.
function ENT:SetupCollision()
	local mins, maxs = self:TableBounds()
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_OBB)
	self:SetCollisionBounds(mins, maxs)
end

function ENT:SetupDataTables()
	-- Who owns each seat's hand, and how many cards are in it (contents are private)
	self:NetworkVar("Entity", 0, "Seat1")
	self:NetworkVar("Entity", 1, "Seat2")
	self:NetworkVar("Int", 0, "HandCount1")
	self:NetworkVar("Int", 1, "HandCount2")
end

function ENT:SeatOwner(seat)
	return self["GetSeat" .. seat](self)
end

function ENT:HandCount(seat)
	return self["GetHandCount" .. seat](self)
end

-- The seat a player owns at this table, if any.
function ENT:SeatOf(ply)
	for seat = 1, 2 do
		if self:SeatOwner(seat) == ply then return seat end
	end
end
