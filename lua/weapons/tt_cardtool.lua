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

local GENERIC, SILENCE = 1, 2

function SWEP:SetupDataTables()
	self:NetworkVar("Entity", 0, "HeldCard")
	self:NetworkVar("Int", 0, "HandIndex") -- selected hand card (set by the owner's mouse wheel)
end

function SWEP:Initialize()
	self:SetHoldType("normal")
	self:SetHandIndex(1)
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

		local shift, alt = ply:KeyDown(IN_SPEED), ply:KeyDown(IN_WALK)
		local tbl, zone = self:AimZone()
		local onLife = zone and zone.kind == "life" and not IsValid(held)

		if onLife and (ply:KeyPressed(IN_ATTACK) or ply:KeyPressed(IN_ATTACK2)) then
			local delta = (ply:KeyPressed(IN_ATTACK) and -1 or 1) * (shift and 5 or 1)
			tbl:SetLife(zone.seat, tbl:Life(zone.seat) + delta)
		elseif ply:KeyPressed(IN_ATTACK) then
			if shift then
				self:ChangeCounter(GENERIC, 1)
			elseif alt and not self:TakeFromHand(false) then
				self:ChangeCounter(GENERIC, -1)
			elseif not alt then
				self:PickOrDrop()
			end
		elseif ply:KeyPressed(IN_ATTACK2) then
			if shift then
				self:ChangeCounter(SILENCE, 1)
			elseif alt then
				self:ChangeCounter(SILENCE, -1)
			else
				self:FlipCard()
			end
		elseif ply:KeyPressed(IN_RELOAD) then
			self:TurnCard()
		elseif ply:KeyPressed(IN_USE) then
			self:UseZone(tbl, zone, shift)
		end
	end

	function SWEP:AimZone()
		local tbl, hit = TT.FindTable(self:GetOwner())
		return tbl, tbl and TT.ZoneAt(hit)
	end

	-- E: sit at an empty seat, draw from your own deck, Shift+E shuffles a deck.
	function SWEP:UseZone(tbl, zone, shift)
		if not zone then return end
		local ply = self:GetOwner()
		if zone.seat and not IsValid(tbl:SeatOwner(zone.seat)) then
			local ok, why = tbl:ClaimSeat(zone.seat, ply)
			if not ok then ply:PrintMessage(HUD_PRINTCENTER, why) end
		elseif zone.kind == "pile" and shift then
			tbl:ShuffleZone(zone.id)
		elseif zone.kind == "pile" and zone.seat and tbl:SeatOwner(zone.seat) == ply then
			if not tbl:DrawCard(zone.seat) then ply:PrintMessage(HUD_PRINTCENTER, "Your deck is empty") end
		end
	end

	-- If the player is aiming at their own hand zone with nothing held, take
	-- the selected card from their hand. Returns true if it did.
	function SWEP:TakeFromHand(faceUp)
		if IsValid(self:GetHeldCard()) then return false end
		local ply = self:GetOwner()
		local tbl, hit = TT.FindTable(ply)
		local zone = tbl and TT.ZoneAt(hit)
		if not zone or zone.kind ~= "hand" then return false end

		if tbl:SeatOwner(zone.seat) ~= ply then
			local owner = tbl:SeatOwner(zone.seat)
			ply:PrintMessage(HUD_PRINTCENTER, IsValid(owner) and ("That's " .. owner:Nick() .. "'s hand") or "Nobody sits here - press E to sit")
			return true
		end
		local card = tbl:TakeFromHand(ply, self:GetHandIndex(), faceUp)
		if IsValid(card) then self:SetHeldCard(card) end
		return true
	end

	function SWEP:PickOrDrop()
		local ply = self:GetOwner()
		local held = self:GetHeldCard()
		if IsValid(held) then
			local tbl = held:GetBoard()
			local ok, why = tbl:TryDrop(held, tbl:WorldToLocal(held:GetPos()), ply)
			if ok then
				self:SetHeldCard(NULL)
			else
				ply:PrintMessage(HUD_PRINTCENTER, why or "You can't put the card there")
			end
			return
		end

		if self:TakeFromHand(true) then return end

		local card, tbl = self:TargetCard()
		if not IsValid(card) then return end
		tbl:PickUp(card, ply)
		self:SetHeldCard(card)
	end

	function SWEP:FlipCard()
		local card = self:TargetCard()
		if IsValid(card) then card:Flip() end
	end

	function SWEP:TurnCard()
		local card, tbl = self:TargetCard()
		if IsValid(card) then tbl:TurnCard(card) end
	end

	function SWEP:ChangeCounter(kind, delta)
		local card = self:TargetCard()
		if IsValid(card) then card:AddCounter(kind, delta) end
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
		{ "R", "Turn 180° (reverse)" },
		{ "E", "Sit at an empty seat / draw from your deck" },
		{ "Shift+E", "Shuffle deck" },
		{ "LMB/RMB on Life", "-1 / +1 (Shift: 5)" },
		{ "Shift+LMB", "Add Generic counter" },
		{ "Shift+RMB", "Add Silence counter" },
		{ "Alt+LMB/RMB", "Remove Generic / Silence" },
		{ "Wheel", "Choose card in hand" },
		{ "LMB on hand", "Play it face up" },
		{ "Alt+LMB on hand", "Play it face down" },
	}

	local BG = Color(0, 0, 0, 170)
	local DIM = Color(170, 170, 170)
	local HIGHLIGHT = Color(255, 220, 60)

	function SWEP:DrawHUD()
		-- Controls panel
		local x, w = 20, 430
		local y = ScrH() - 40 - (#controls + 1) * 22
		draw.RoundedBox(8, x, y, w, (#controls + 1) * 22 + 16, BG)
		draw.SimpleText("Card Hand", "TT_HUDTitle", x + 12, y + 8, color_white)
		for i, c in ipairs(controls) do
			local ly = y + 12 + i * 22
			draw.SimpleText(c[1], "TT_HUD", x + 12, ly, DIM)
			draw.SimpleText(c[2], "TT_HUD", x + 150, ly, color_white)
		end

		self:DrawPlayers()

		TT.DrawHand()

		-- Zone name (and size) when pointing at one
		local tbl = TT.HoverTable
		local zone = TT.GetZone(TT.HoverZone)
		if IsValid(tbl) and zone then
			local label = zone.name
			if zone.kind == "pile" or zone.kind == "row" then
				label = label .. ": " .. TT.CountInZone(tbl, zone) .. " cards"
			elseif zone.kind == "hand" then
				label = label .. ": " .. tbl:HandCount(zone.seat) .. " cards"
			end
			draw.SimpleTextOutlined(label, "TT_HUDTitle", ScrW() / 2, ScrH() / 2 + 40, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
		end

		-- Enlarged preview of the held or hovered card, or of the selected hand
		-- card when pointing at your own hand
		local ph = math.floor(ScrH() * 0.5)
		local pw = math.floor(ph * TT.Config.CardW / TT.Config.CardH)
		local px, py = ScrW() - pw - 30, math.floor(ScrH() / 2 - ph / 2)

		local card = self:GetHeldCard()
		if not IsValid(card) then card = TT.HoverCard end
		if IsValid(card) then
			TT.DrawCardSurface(card, px, py, false, pw, ph, true)
			local _, data, peeked = TT.GetCardData(card, true)
			self:DrawCardText(data, card:GetReversed(), peeked, px - 360, py, 340)
			return
		end

		if zone and zone.kind == "hand" and IsValid(tbl) and tbl:SeatOwner(zone.seat) == LocalPlayer() then
			local cards = TT.MyHand(tbl)
			local entry = cards[math.Clamp(TT.HandSel, 1, math.max(#cards, 1))]
			if entry then
				local deck, data = TT.HandCardData(entry)
				TT.DrawCardFace(deck, data, px, py, pw, ph)
				self:DrawCardText(data, false, false, px - 360, py, 340)
			end
		end
	end

	-- Top-left: everyone seated at the table you're looking at (or sitting at).
	function SWEP:DrawPlayers()
		local tbl = TT.HoverTable
		if not IsValid(tbl) then tbl = TT.Hand.table end
		if not IsValid(tbl) then return end

		local rows = {}
		for seat = 1, TT.MaxSeats do
			local ply = tbl:SeatOwner(seat)
			if IsValid(ply) then
				local first = tbl:GetFirstSeat() == seat and "  (first)" or ""
				rows[#rows + 1] = { ply:Nick() .. first, tbl:Life(seat), tbl:HandCount(seat), ply == LocalPlayer() }
			end
		end
		if #rows == 0 then
			draw.SimpleTextOutlined("Press E on a seat's zones to sit, then say !deal", "TT_HUDTitle", ScrW() / 2, 40, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
			return
		end

		local x, y, w = 20, 20, 300
		draw.RoundedBox(8, x, y, w, 40 + #rows * 24, BG)
		draw.SimpleText("Player", "TT_HUD", x + 12, y + 10, DIM)
		draw.SimpleText("Life", "TT_HUD", x + 200, y + 10, DIM, TEXT_ALIGN_RIGHT)
		draw.SimpleText("Hand", "TT_HUD", x + 280, y + 10, DIM, TEXT_ALIGN_RIGHT)
		for i, r in ipairs(rows) do
			local ly, col = y + 12 + i * 24, r[4] and HIGHLIGHT or color_white
			draw.SimpleText(r[1], "TT_HUDText", x + 12, ly, col)
			draw.SimpleText(r[2], "TT_HUDText", x + 200, ly, col, TEXT_ALIGN_RIGHT)
			draw.SimpleText(r[3], "TT_HUDText", x + 280, ly, col, TEXT_ALIGN_RIGHT)
		end
	end

	-- Name, orientation and both effects; the active effect is highlighted.
	function SWEP:DrawCardText(data, reversed, peeked, x, y, w)
		local blocks = {}
		if data then
			local title = data.name
			if data.suit and data.suit ~= "" then title = title .. "  -  " .. data.suit end
			local active, other = data.upright, data.reversed
			if reversed then active, other = other, active end

			blocks[#blocks + 1] = { title, "TT_HUDTitle", color_white }
			if peeked then blocks[#blocks + 1] = { "Face down - only you can see it", "TT_HUD", DIM } end
			blocks[#blocks + 1] = { reversed and "Reversed (active)" or "Upright (active)", "TT_HUD", HIGHLIGHT }
			blocks[#blocks + 1] = { active ~= "" and active or "-", "TT_HUDText", color_white }
			blocks[#blocks + 1] = { reversed and "Upright" or "Reversed", "TT_HUD", DIM }
			blocks[#blocks + 1] = { other ~= "" and other or "-", "TT_HUDText", DIM }
		else
			blocks[#blocks + 1] = { "Face-down card", "TT_HUDTitle", color_white }
		end

		local lines = {}
		for bi, b in ipairs(blocks) do
			for _, line in ipairs(TT.WrapText(b[1], b[2], w - 24)) do
				lines[#lines + 1] = { line, b[2], b[3], bi }
			end
		end

		local LINE, GAP = 24, 8
		local height = #lines * LINE + (#blocks - 1) * GAP + 24
		draw.RoundedBox(8, x, y, w, height, BG)
		local ly = y + 12
		for i, l in ipairs(lines) do
			if i > 1 and lines[i - 1][4] ~= l[4] then ly = ly + GAP end
			draw.SimpleText(l[1], l[2], x + 12, ly, l[3])
			ly = ly + LINE
		end
	end
end
