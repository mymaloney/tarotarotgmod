AddCSLuaFile()

SWEP.PrintName = "Card Hand"
SWEP.Author = "Tarotarot"
SWEP.Category = "Tabletop"
SWEP.Instructions = "Look at a card table and use the controls shown on screen."
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 5
SWEP.ViewModel = ""
SWEP.WorldModel = ""
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

function SWEP:SetupDataTables()
	self:NetworkVar("Int", 0, "CounterType")
	self:NetworkVar("Entity", 0, "HeldCard")
end

function SWEP:Initialize()
	self:SetHoldType("normal")
	self:SetCounterType(1)
end

-- All input is handled in Think so each key press acts exactly once.
function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:Reload() end
function SWEP:DrawWorldModel() end

if SERVER then
	-- The held card if there is one, otherwise the card under the crosshair.
	function SWEP:TargetCard()
		local held = self:GetHeldCard()
		if IsValid(held) then return held, held:GetBoard() end

		local tbl = TT.FindTable(self:GetOwner())
		if not tbl then return end
		local card = TT.TraceCard(tbl, self:GetOwner())
		if not IsValid(card) then return end
		return tbl:TopOf(card), tbl
	end

	function SWEP:Think()
		local ply = self:GetOwner()
		if not IsValid(ply) then return end

		local held = self:GetHeldCard()
		if IsValid(held) and IsValid(held:GetBoard()) then
			local tbl = held:GetBoard()
			local o, d = TT.RayToLocal(tbl, ply:EyePos(), ply:GetAimVector())
			local hit = TT.RayPlaneZ(o, d, TT.Config.TableHeight)
			if hit then tbl:MoveHeld(held, hit) end
		end

		local shift = ply:KeyDown(IN_SPEED)
		if ply:KeyPressed(IN_ATTACK) then
			if shift then self:ChangeCounter(1) else self:PickOrDrop() end
		elseif ply:KeyPressed(IN_ATTACK2) then
			if shift then self:ChangeCounter(-1) else self:FlipCard() end
		elseif ply:KeyPressed(IN_RELOAD) then
			if shift then self:CycleCounterType() else self:RotateCard() end
		elseif ply:KeyPressed(IN_USE) then
			self:ShufflePile()
		end
	end

	function SWEP:PickOrDrop()
		local ply = self:GetOwner()
		local held = self:GetHeldCard()
		if IsValid(held) then
			local tbl = held:GetBoard()
			if tbl:TryDrop(held, tbl:WorldToLocal(held:GetPos())) then
				self:SetHeldCard(NULL)
			else
				ply:PrintMessage(HUD_PRINTCENTER, "No room for the card there")
			end
			return
		end

		local card, tbl = self:TargetCard()
		if not IsValid(card) then return end
		tbl:PickUp(card, ply)
		self:SetHeldCard(card)
	end

	function SWEP:FlipCard()
		local card = self:TargetCard()
		if IsValid(card) then card:Flip() end
	end

	function SWEP:RotateCard()
		local card, tbl = self:TargetCard()
		if IsValid(card) then tbl:RotateCard(card, 1) end
	end

	function SWEP:ChangeCounter(delta)
		local card = self:TargetCard()
		if IsValid(card) then card:AddCounter(self:GetCounterType(), delta) end
	end

	function SWEP:CycleCounterType()
		self:SetCounterType(self:GetCounterType() % #TT.CounterTypes + 1)
	end

	function SWEP:ShufflePile()
		local tbl, hit = TT.FindTable(self:GetOwner())
		if not tbl then return end
		local zone = TT.ZoneAt(hit)
		if zone and zone.kind == "pile" then tbl:ShuffleZone(zone.id) end
	end

	function SWEP:ReleaseCard()
		local held = self:GetHeldCard()
		if IsValid(held) and IsValid(held:GetBoard()) then held:GetBoard():ReturnCard(held) end
		self:SetHeldCard(NULL)
	end

	function SWEP:Holster()
		self:ReleaseCard()
		return true
	end

	function SWEP:OnDrop()
		self:ReleaseCard()
	end

	function SWEP:OnRemove()
		self:ReleaseCard()
	end
end

if CLIENT then
	local controls = {
		{ "LMB", "Pick up / place card" },
		{ "RMB", "Flip card" },
		{ "R", "Rotate 90°" },
		{ "E", "Shuffle pile" },
		{ "Shift+LMB", "Add counter" },
		{ "Shift+RMB", "Remove counter" },
		{ "Shift+R", "Change counter type" },
	}

	local BG = Color(0, 0, 0, 170)
	local DIM = Color(200, 200, 200)

	function SWEP:DrawHUD()
		-- Controls panel
		local x, y, w = 20, ScrH() - 60 - (#controls + 2) * 22, 280
		draw.RoundedBox(8, x, y, w, (#controls + 2) * 22 + 16, BG)
		draw.SimpleText("Card Hand", "TT_HUDTitle", x + 12, y + 8, color_white)
		for i, c in ipairs(controls) do
			local ly = y + 12 + i * 22
			draw.SimpleText(c[1], "TT_HUD", x + 12, ly, DIM)
			draw.SimpleText(c[2], "TT_HUD", x + 110, ly, color_white)
		end
		local kind = TT.CounterTypes[self:GetCounterType()] or TT.CounterTypes[1]
		local ly = y + 12 + (#controls + 1) * 22
		draw.SimpleText("Counter:", "TT_HUD", x + 12, ly, DIM)
		draw.RoundedBox(8, x + 110, ly + 2, 16, 16, kind.color)
		draw.SimpleText(kind.name, "TT_HUD", x + 134, ly, color_white)

		-- Pile size when pointing at a pile
		local zone = TT.GetZone(TT.HoverZone)
		if IsValid(TT.HoverTable) and zone then
			local label = zone.name
			if zone.kind == "pile" then label = label .. ": " .. TT.CountInZone(TT.HoverTable, zone) .. " cards" end
			draw.SimpleTextOutlined(label, "TT_HUDTitle", ScrW() / 2, ScrH() / 2 + 40, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
		end

		-- Enlarged preview of the held or hovered card
		local card = self:GetHeldCard()
		if not IsValid(card) then card = TT.HoverCard end
		if not IsValid(card) then return end

		local pw, ph = TT.CardPixelSize[1], TT.CardPixelSize[2]
		local px, py = ScrW() - pw - 30, ScrH() / 2 - ph / 2
		TT.DrawCardSurface(card, px, py, false)

		local deck, data = TT.GetCardData(card)
		local title = data and data.name or "Face-down card"
		draw.SimpleTextOutlined(title, "TT_HUDTitle", px + pw / 2, py + ph + 10, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
		if data and data.text then
			draw.SimpleTextOutlined(data.text, "TT_HUD", ScrW() - 30, py + ph + 40, DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, color_black)
		end
	end
end
