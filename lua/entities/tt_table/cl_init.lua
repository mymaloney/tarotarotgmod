include("shared.lua")

local cfg = TT.Config
local ZS = 0.25 -- 3D2D scale for table markings (4 px per unit)

function ENT:Initialize()
	self:SetupCollision()
	local mins, maxs = self:TableBounds()
	self:SetRenderBounds(mins, maxs + Vector(0, 0, 20))
end

function ENT:Draw()
	local pos, ang = self:GetPos(), self:GetAngles()
	local hw, hd, h = cfg.TableW / 2, cfg.TableD / 2, cfg.TableHeight

	render.SetColorMaterial()
	render.DrawBox(pos, ang, Vector(-hw, -hd, h - 4), Vector(hw, hd, h), cfg.TableColor)
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			local x, y = sx * (hw - 10), sy * (hd - 10)
			render.DrawBox(pos, ang, Vector(x - 3, y - 3, 0), Vector(x + 3, y + 3, h - 4), cfg.LegColor)
		end
	end

	-- Felt and centre line
	cam.Start3D2D(self:LocalToWorld(Vector(0, 0, h + 0.1)), ang, ZS)
		surface.SetDrawColor(cfg.FeltColor)
		surface.DrawRect((-hw + 5) / ZS, (-hd + 5) / ZS, (cfg.TableW - 10) / ZS, (cfg.TableD - 10) / ZS)
		surface.SetDrawColor(255, 255, 255, 30)
		surface.DrawRect((-hw + 10) / ZS, -2, (cfg.TableW - 20) / ZS, 4)
	cam.End3D2D()

	for _, zone in ipairs(TT.Zones) do self:DrawZone(zone) end
end

local labelColor = Color(255, 255, 255, 140)
local faintLabel = Color(255, 255, 255, 45)

function ENT:DrawZone(zone)
	local ang = self:GetAngles()
	ang:RotateAroundAxis(ang:Up(), zone.yaw)
	local pos = self:LocalToWorld(Vector(zone.pos.x, zone.pos.y, cfg.TableHeight + 0.25))
	local hover = TT.HoverTable == self and TT.HoverZone == zone.id
	local w, h = zone.hx * 2 / ZS, zone.hy * 2 / ZS
	local label = zone.name

	cam.Start3D2D(pos, ang, ZS)
		if hover then
			surface.SetDrawColor(255, 255, 255, 20)
			surface.DrawRect(-w / 2, -h / 2, w, h)
		end
		surface.SetDrawColor(255, 255, 255, hover and 160 or 70)
		surface.DrawOutlinedRect(-w / 2, -h / 2, w, h, zone.kind == "grid" and 2 or 3)

		if zone.kind == "hand" then
			label = self:DrawHandFan(zone)
		elseif zone.kind == "life" then
			local seated = IsValid(self:SeatOwner(zone.seat))
			draw.SimpleText(seated and self:Life(zone.seat) or "-", "TT_Life", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		if zone.labelInside then
			draw.SimpleText(label, "TT_Zone", 0, 0, faintLabel, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			-- Label sits on the owner's side of the zone
			draw.SimpleText(label, "TT_Zone", 0, h / 2 + 2, labelColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
	cam.End3D2D()
end

-- Card backs for each card in a seat's hand. Returns the zone's label.
function ENT:DrawHandFan(zone)
	local n = self:HandCount(zone.seat)
	local deck = TT.Decks[cfg.DefaultDeck]
	local cw, ch = cfg.CardW / ZS, cfg.CardH / ZS
	for i = 1, n do
		TT.DrawCardFace(deck, nil, TT.RowX(zone, i, n) / ZS - cw / 2, -ch / 2, cw, ch)
	end

	local owner = self:SeatOwner(zone.seat)
	local who = IsValid(owner) and owner:Nick() or "empty seat"
	return string.format("Hand: %s (%d)", who, n)
end
