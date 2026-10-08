ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Card"
ENT.Author = "Tarotarot"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_OPAQUE

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Board")
	self:NetworkVar("Entity", 1, "Holder")
	self:NetworkVar("String", 0, "DeckName")
	-- Index into the deck's card list, or 0 while face down. The real identity
	-- of a face-down card stays on the server so clients can't peek.
	self:NetworkVar("Int", 0, "FaceId")
	-- Turned 180 degrees relative to the zone's owner
	self:NetworkVar("Bool", 0, "Reversed")
	for i = 1, #TT.CounterTypes do
		self:NetworkVar("Int", i, "Counter" .. i)
	end
end

function ENT:GetCounter(kind)
	return self["GetCounter" .. kind](self)
end

function ENT:IsFaceUp()
	return self:GetFaceId() > 0
end
