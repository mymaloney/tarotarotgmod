include("shared.lua")

function ENT:Initialize()
	self:SetRenderBounds(Vector(-25, -25, -1), Vector(25, 25, 6))
end

function ENT:Draw()
	TT.DrawCard3D(self)
end
