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
	for seat = 1, TT.MaxSeats do
		-- Who sits there, how many cards are in their hand (contents are private), and their life
		self:NetworkVar("Entity", seat - 1, "Seat" .. seat)
		self:NetworkVar("Int", seat - 1, "HandCount" .. seat)
		self:NetworkVar("Int", TT.MaxSeats + seat - 1, "Life" .. seat)
	end
	self:NetworkVar("Int", 2 * TT.MaxSeats, "FirstSeat") -- 0 until a game is dealt
end

function ENT:SeatOwner(seat)
	return self["GetSeat" .. seat](self)
end

function ENT:HandCount(seat)
	return self["GetHandCount" .. seat](self)
end

function ENT:Life(seat)
	return self["GetLife" .. seat](self)
end

-- The seat a player owns at this table, if any.
function ENT:SeatOf(ply)
	for seat = 1, TT.MaxSeats do
		if self:SeatOwner(seat) == ply then return seat end
	end
end
