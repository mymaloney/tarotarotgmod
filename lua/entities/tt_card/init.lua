AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
	self:SetModel("models/hunter/plates/plate05x075.mdl")
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_NONE)
	self:DrawShadow(false)

	self.CardId = self.CardId or 1
	self.FaceUp = false
	self.BaseYaw = 0
	TT.NextSerial = (TT.NextSerial or 0) + 1
	self:SetSerial(TT.NextSerial)
end

function ENT:SetCard(deckName, id)
	self:SetDeckName(deckName)
	self.CardId = id
	self:SetFaceUp(false)
end

function ENT:SetFaceUp(up)
	self.FaceUp = up
	self:SetFaceId(up and self.CardId or 0)
end

-- Let one player (or nobody, with nil) see this card while it's face down.
function ENT:SetPeek(ply)
	if IsValid(self.PeekPlayer) and self.PeekPlayer ~= ply then
		net.Start("tt_peek")
		net.WriteUInt(self:GetSerial(), 32)
		net.WriteUInt(0, 16)
		net.Send(self.PeekPlayer)
	end
	self.PeekPlayer = ply
	if IsValid(ply) then
		net.Start("tt_peek")
		net.WriteUInt(self:GetSerial(), 32)
		net.WriteUInt(self.CardId, 16)
		net.Send(ply)
	end
end

function ENT:Flip()
	self:SetFaceUp(not self.FaceUp)
	self:EmitSound("physics/cardboard/cardboard_box_impact_soft1.wav", 50, math.random(150, 170))
end

function ENT:AddCounter(kind, delta)
	local value = math.Clamp(self:GetCounter(kind) + delta, 0, TT.Config.MaxCounter)
	self["SetCounter" .. kind](self, value)
end

-- Safety net: if the player holding this card vanished, put it back.
function ENT:Think()
	if self.IsHeld and not IsValid(self:GetHolder()) and IsValid(self:GetBoard()) then
		self:GetBoard():ReturnCard(self)
	end
	self:NextThink(CurTime() + 1)
	return true
end

function ENT:OnRemove()
	local board = self:GetBoard()
	if IsValid(board) then board:DetachCard(self) end
end
