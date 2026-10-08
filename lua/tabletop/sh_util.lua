-- Tarotarot Tabletop: shared helpers (zone geometry and aiming).

local cfg = TT.Config

-- Precompute zone extents and an id lookup.
TT.ZoneById = {}
for _, zone in ipairs(TT.Zones) do
	if zone.kind == "grid" then
		zone.hx = zone.cols * cfg.SlotX / 2
		zone.hy = zone.rows * cfg.SlotY / 2
	elseif zone.kind == "row" or zone.kind == "hand" then
		zone.hx = zone.width / 2
		zone.hy = cfg.CardH / 2 + 3
	else
		zone.hx = cfg.CardW / 2 + 3
		zone.hy = cfg.CardH / 2 + 3
	end
	TT.ZoneById[zone.id] = zone
end

function TT.GetZone(id)
	return id and TT.ZoneById[id]
end

local function rotateYaw(v, yaw)
	local r = Vector(v.x, v.y, 0)
	r:Rotate(Angle(0, yaw, 0))
	return r
end

-- Zone-local offset -> table-local position (z = 0).
function TT.ZoneToTable(zone, offset)
	return Vector(zone.pos.x, zone.pos.y, 0) + rotateYaw(offset, zone.yaw)
end

-- Table-local position -> zone-local offset.
function TT.TableToZone(zone, p)
	return rotateYaw(Vector(p.x - zone.pos.x, p.y - zone.pos.y, 0), -zone.yaw)
end

function TT.ZoneAt(p)
	for _, zone in ipairs(TT.Zones) do
		local l = TT.TableToZone(zone, p)
		if math.abs(l.x) <= zone.hx and math.abs(l.y) <= zone.hy then
			return zone
		end
	end
end

-- Grid slots are numbered left to right, front row (nearest the owner) first.
function TT.SlotOffset(zone, slot)
	local col = (slot - 1) % zone.cols
	local row = math.floor((slot - 1) / zone.cols)
	return Vector((col - (zone.cols - 1) / 2) * cfg.SlotX, (row - (zone.rows - 1) / 2) * cfg.SlotY, 0)
end

function TT.SlotPos(zone, slot)
	return TT.ZoneToTable(zone, TT.SlotOffset(zone, slot))
end

-- Row/hand zones: zone-local x of card i of n. Cards sit side by side from the
-- left edge, overlapping more as the row fills up.
function TT.RowX(zone, i, n)
	local first = -zone.hx + 2 + cfg.CardW / 2
	if n <= 1 then return first end
	local step = math.min(cfg.CardW + 2, (zone.hx * 2 - 4 - cfg.CardW) / (n - 1))
	return first + (i - 1) * step
end

-- The hand zone belonging to a seat.
function TT.HandZone(seat)
	for _, zone in ipairs(TT.Zones) do
		if zone.kind == "hand" and zone.seat == seat then return zone end
	end
end

-- Convert a world-space ray into the table's local space.
function TT.RayToLocal(tbl, origin, dir)
	local o = tbl:WorldToLocal(origin)
	return o, tbl:WorldToLocal(origin + dir) - o
end

-- Intersect a local ray with the horizontal plane at height z (looking down only).
function TT.RayPlaneZ(o, d, z)
	if d.z > -1e-4 then return end
	local t = (z - o.z) / d.z
	if t < 0 then return end
	return o + d * t, t
end

-- The table the player is aiming at, and the table-local point they aim at.
function TT.FindTable(ply)
	local eye, aim = ply:EyePos(), ply:GetAimVector()
	local best, bestT, bestHit
	for _, tbl in ipairs(ents.FindByClass("tt_table")) do
		local o, d = TT.RayToLocal(tbl, eye, aim)
		local hit, t = TT.RayPlaneZ(o, d, cfg.TableHeight)
		if hit and t <= cfg.Reach
			and math.abs(hit.x) <= cfg.TableW / 2 and math.abs(hit.y) <= cfg.TableD / 2
			and (not bestT or t < bestT) then
			best, bestT, bestHit = tbl, t, hit
		end
	end
	return best, bestHit
end

function TT.GetCards(tbl)
	local out = {}
	for _, card in ipairs(ents.FindByClass("tt_card")) do
		if card:GetBoard() == tbl then out[#out + 1] = card end
	end
	return out
end

-- The topmost card (not held by anyone) under the player's crosshair.
function TT.TraceCard(tbl, ply)
	local o, d = TT.RayToLocal(tbl, ply:EyePos(), ply:GetAimVector())
	local best, bestZ
	for _, card in ipairs(TT.GetCards(tbl)) do
		if not IsValid(card:GetHolder()) then
			local lp = tbl:WorldToLocal(card:GetPos())
			local hit = TT.RayPlaneZ(o, d, lp.z)
			if hit and (not bestZ or lp.z > bestZ) then
				local delta = hit - lp
				delta:Rotate(Angle(0, -tbl:WorldToLocalAngles(card:GetAngles()).y, 0))
				if math.abs(delta.x) <= cfg.CardW / 2 and math.abs(delta.y) <= cfg.CardH / 2 then
					best, bestZ = card, lp.z
				end
			end
		end
	end
	return best
end

-- Number of resting (not held) cards inside a zone.
function TT.CountInZone(tbl, zone)
	local n = 0
	for _, card in ipairs(TT.GetCards(tbl)) do
		if not IsValid(card:GetHolder()) and TT.ZoneAt(tbl:WorldToLocal(card:GetPos())) == zone then
			n = n + 1
		end
	end
	return n
end
