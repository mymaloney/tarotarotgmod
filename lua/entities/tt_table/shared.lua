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
