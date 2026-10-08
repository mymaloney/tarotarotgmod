-- Tests for the card table's server logic, using a minimal mock of the
-- Garry's Mod API (no rendering or networking). Run from the repo root with
-- any Lua 5.1+ or LuaJIT:   lua tests/table_test.lua
local VM = {}; VM.__index = VM
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VM) end
VM.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
VM.__sub = function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
VM.__mul = function(a,s) return Vector(a.x*s,a.y*s,a.z*s) end
function VM:Rotate(ang) local r = math.rad(ang.y); local c,s = math.cos(r), math.sin(r)
  local x,y = self.x*c - self.y*s, self.x*s + self.y*c; self.x, self.y = x, y end
function VM:DistToSqr(o) local d = self - o; return d.x*d.x+d.y*d.y+d.z*d.z end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
SERVER, CLIENT = true, false
function ErrorNoHalt(m) error(m) end
function Base_noop() end
string.Trim = function(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
function table.RemoveByValue(t, v) for i, x in ipairs(t) do if x == v then table.remove(t, i) return i end end return false end
function math.Clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
function math.Round(v, d) local m = 10 ^ (d or 0); return math.floor(v * m + 0.5) / m end
HUD_PRINTTALK = 3
CHAT = {}
function PrintMessage(_, m) CHAT[#CHAT + 1] = m end
NULL = setmetatable({}, {__index = function() return function() end end})
function IsValid(e) return e ~= nil and e ~= NULL and not e.__removed end
function AddCSLuaFile() end
hook = { Add = function() end }
timer = { Simple = function() end }
MOVETYPE_NONE, SOLID_OBB, SOLID_NONE = 0, 0, 0
SENT_LOG = {}
net = { msg = nil }
function net.Start(n) net.msg = { name = n, data = {} } end
local function w(v) table.insert(net.msg.data, v) end
net.WriteEntity, net.WriteUInt, net.WriteString, net.WriteBool = w, w, w, w
function net.Broadcast() table.insert(SENT_LOG, { to = "all", msg = net.msg }) end
function net.Send(ply) table.insert(SENT_LOG, { to = ply, msg = net.msg }) end
file = { Read = function(p, where)
  if where ~= "GAME" then return nil end
  local f = io.open(p, "rb"); if not f then return nil end; local t = f:read("*a"); f:close(); return t end }

TT = {}
dofile("lua/tabletop/sh_config.lua"); dofile("lua/tabletop/sh_atlas.lua")
dofile("lua/tarotarot_engine/init.lua"); TTE.Load(function(f) dofile("lua/tarotarot_engine/" .. f) end)
dofile("lua/tabletop/sh_decks.lua"); dofile("lua/tabletop/sh_util.lua")

-- Entity base
local ALL = {}
local Base = {}
function Base:SetModel() end function Base:DrawShadow() end function Base:SetMoveType() end
function Base:SetSolid() end function Base:SetCollisionBounds() end function Base:EmitSound() end
function Base:SetParent(p) self.parent = p end
function Base:SetLocalPos(p) self.lpos = p end
function Base:SetLocalAngles(a) self.lang = a end
function Base:GetPos() return self.lpos or Vector() end   -- table sits at the origin, unrotated
function Base:GetAngles() return self.lang or Angle() end
function Base:WorldToLocal(p) return Vector(p.x, p.y, p.z) end
function Base:WorldToLocalAngles(a) return a end
function Base:Remove() if self.OnRemove then self:OnRemove() end self.__removed = true end
function Base:NetworkVar(kind, slot, name)
  local key = "_nv_" .. name
  local defaults = { Int = 0, String = "" }
  self["Get" .. name] = function(s)
    local v = s[key]
    if v ~= nil then return v end
    if kind == "Bool" then return false end
    if defaults[kind] ~= nil then return defaults[kind] end
    return NULL
  end
  self["Set" .. name] = function(s, v) s[key] = v end
end

local classes = {}
local function loadEnt(class)
  ENT = {}
  local dir = "lua/entities/" .. class .. "/"
  include = function(f) dofile(dir .. f) end
  dofile(dir .. "init.lua")
  classes[class] = ENT
  ENT = nil
end
loadEnt("tt_table"); loadEnt("tt_card")

ents = {}
function ents.Create(class)
  local e = setmetatable({ class = class }, { __index = function(t, k) return classes[class][k] or Base[k] end })
  if e.SetupDataTables then e:SetupDataTables() end
  ALL[#ALL + 1] = e
  return e
end
function Base:Spawn() if self.Initialize then self:Initialize() end end
function ents.FindByClass(c) local out = {} for _, e in ipairs(ALL) do if e.class == c and not e.__removed then out[#out+1] = e end end return out end

local function Player(name)
  local p = { msgs = {} }
  p.Nick = function() return name end
  p.ChatPrint = function(_, m) p.msgs[#p.msgs + 1] = m end
  p.PrintMessage = p.ChatPrint
  return p
end

local function check(c, m) if not c then error("FAIL: " .. m, 2) end end

local function check(c, m) if not c then error("FAIL: " .. m, 2) end end
local cfg = TT.Config

-- Geometry: every zone (plus its label strip) on the felt, no overlaps, 4 seats mirrored by rotation
local half = cfg.TableW / 2 - 5
local function rect(z, pad)
  local corners = {}
  for _, c in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
    local v = Vector(c[1] * z.hx, c[2] * z.hy - (c[2] < 0 and (pad or 0) or 0), 0); v:Rotate(Angle(0, z.yaw, 0))
    corners[#corners + 1] = v + Vector(z.pos.x, z.pos.y, 0)
  end
  local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
  for _, c in ipairs(corners) do x0 = math.min(x0, c.x); x1 = math.max(x1, c.x); y0 = math.min(y0, c.y); y1 = math.max(y1, c.y) end
  return x0, x1, y0, y1
end
for _, z in ipairs(TT.Zones) do
  local x0, x1, y0, y1 = rect(z, z.labelInside and 0 or 9)
  check(x0 >= -half - 1e-6 and x1 <= half + 1e-6 and y0 >= -half - 1e-6 and y1 <= half + 1e-6, "on table (incl. label) " .. z.id)
  check(TT.ZoneAt(z.pos) == z, "centre resolves " .. z.id)
  for _, o in ipairs(TT.Zones) do if o ~= z then
    local a0, a1, b0, b1 = rect(z); local c0, c1, d0, d1 = rect(o)
    check(a1 <= c0 + 1e-6 or c1 <= a0 + 1e-6 or b1 <= d0 + 1e-6 or d1 <= b0 + 1e-6, "overlap " .. z.id .. " / " .. o.id)
  end end
end
-- Rulebook layout: deck left of the spread, memory right, from each player's own view
for seat = 1, 4 do
  local function x(key) return TT.TableToZone({ pos = Vector(), yaw = TT.GetZone("p"..seat.."_deck").yaw }, TT.GetZone("p"..seat.."_"..key).pos).x end
  check(x("deck") < x("past") and x("past") < x("present") and x("present") < x("future") and x("future") < x("memory"), "left-to-right order seat " .. seat)
end
-- Clockwise seat order seen from above: south, west, north, east
local function hz(s) return TT.HandZone(s).pos end
check(hz(1).y < 0 and hz(2).x < 0 and hz(3).y > 0 and hz(4).x > 0, "seat positions")

local tbl = ents.Create("tt_table"); tbl:Spawn()
local alice, bob, carol, dave = Player("alice"), Player("bob"), Player("carol"), Player("dave")

-- Need two seated players to deal
check(not tbl:NewGame(), "can't deal alone")
check(tbl:ClaimSeat(1, alice) and tbl:SeatOwner(1) == alice, "sit")
check(not tbl:ClaimSeat(2, alice), "one seat each")
check(not tbl:ClaimSeat(1, bob), "taken seat")
check(not tbl:NewGame(), "still alone")
check(tbl:ClaimSeat(3, bob), "bob sits opposite")

local function setupChecks(seats, each)
  for _, s in ipairs(seats) do
    local p = "p" .. s .. "_"
    check(#tbl.Lists[p .. "deck"] == each - 1 - cfg.StartHand, "deck size seat " .. s .. ": " .. #tbl.Lists[p .. "deck"])
    check(#tbl.Hands[s] == cfg.StartHand and tbl:HandCount(s) == cfg.StartHand, "starting hand seat " .. s)
    local past = tbl.Slots[p .. "past"][1]
    check(past and past:GetFaceId() > 0, "past face up seat " .. s)
    check(tbl:Life(s) == cfg.StartLife, "life seat " .. s)
  end
  check(#TT.GetCardsAll() == #seats * (each - cfg.StartHand), "card entities")
end
function TT.GetCardsAll() return ents.FindByClass("tt_card") end

check(tbl:NewGame(), "deal 2p")
setupChecks({1, 3}, 39)
check(tbl:Life(2) == 0 and tbl:Life(4) == 0, "empty seats have no life")
check(tbl:GetFirstSeat() == 1 or tbl:GetFirstSeat() == 3, "first player")
check(CHAT[#CHAT]:find("39 cards each"), "announce: " .. CHAT[#CHAT])
-- All 78 distinct cards dealt
local seen = {}
for _, c in ipairs(TT.GetCardsAll()) do seen[c.CardId] = true end
for s = 1, 4 do for _, e in ipairs(tbl.Hands[s]) do seen[e.id] = true end end
local n = 0; for _ in pairs(seen) do n = n + 1 end
check(n == 78, "78 distinct cards dealt, got " .. n)

-- 3 and 4 players
check(tbl:ClaimSeat(2, carol), "carol")
check(tbl:NewGame(), "deal 3p"); setupChecks({1, 2, 3}, 26)
check(tbl:ClaimSeat(4, dave), "dave")
check(tbl:NewGame(), "deal 4p"); setupChecks({1, 2, 3, 4}, 19)

-- Hand only accepts cards for a seated player
local top = tbl:TopCard("p1_deck"); tbl:PickUp(top, alice)
check(tbl:TryDrop(top, TT.HandZone(3).pos, alice) and #tbl.Hands[3] == 4, "give a card to bob")
tbl:LeaveSeat(dave)
local t2 = tbl:TopCard("p1_deck"); tbl:PickUp(t2, alice)
local ok, why = tbl:TryDrop(t2, TT.HandZone(4).pos, alice)
check(not ok and why:find("Nobody"), "empty seat hand rejects")
check(not tbl:TryDrop(t2, TT.GetZone("p1_life").pos, alice), "life zone rejects cards")
-- Draw
local before = #tbl.Lists.p1_deck
check(tbl:DrawCard(1) and #tbl.Lists.p1_deck == before - 1 and #tbl.Hands[1] == 4, "draw")
tbl.Lists.p2_deck = {}
check(not tbl:DrawCard(2), "empty deck draw fails")
-- Play from hand face down, peek, into Future; slot occupied afterwards
local played = tbl:TakeFromHand(alice, 1, false)
check(played and played:GetFaceId() == 0, "face down from hand")
check(tbl:TryDrop(played, TT.GetZone("p1_future").pos, alice), "into future")
-- Memory row on a rotated seat (2, west): cards run along that player's left->right
local mz = TT.GetZone("p2_memory")
for i = 1, 3 do local c = tbl:TopCard("p3_deck"); tbl:PickUp(c, bob); check(tbl:TryDrop(c, mz.pos, bob), "mem drop " .. i) end
local row = tbl.Lists.p2_memory
check(#row == 3, "row size")
check(row[2]:GetPos().y < row[1]:GetPos().y and row[2]:GetAngles().y == 270, "seat 2 row runs along its own x (towards -y)")
-- Holder vanishes with a hand card whose seat emptied -> that seat's deck
local h = tbl:TakeFromHand(carol, 1, true); tbl:LeaveSeat(carol)
local d0 = #tbl.Lists.p2_deck; tbl:ReturnCard(h)
check(#tbl.Lists.p2_deck == d0 + 1, "orphan hand card -> deck")
-- Life clamps
tbl:SetLife(1, -500); check(tbl:Life(1) == -99, "life clamp")
-- Counters
local c = tbl.Slots.p1_future[1]; c:AddCounter(2, 1); c:AddCounter(2, -5)
check(c:GetCounter(2) == 0, "silence counter clamp")


print("free play: ok")

---------------------------------------------------------------------------
-- Rules-engine games driven through the same table methods the Card Hand uses
---------------------------------------------------------------------------

local function decisionFor(tbl)
  local g = tbl.Engine
  local d = g and g.pending
  if not d then return end
  return d, tbl:SeatOwner(tbl.EngineSeats[d.player])
end

local function entityCount(tbl)
  local n = 0
  for _ in pairs(tbl.CardEnts) do n = n + 1 end
  return n
end

-- Table and engine agree on where every card is
local function consistent(tbl)
  local g = tbl.Engine
  for pid, p in ipairs(g.players) do
    local seat = tbl.EngineSeats[pid]
    check(#tbl.Lists["p" .. seat .. "_deck"] == #p.deck, "deck size seat " .. seat)
    check(#tbl.Lists["p" .. seat .. "_memory"] == #p.memory, "memory size seat " .. seat)
    check(#tbl.Hands[seat] == #p.hand, "hand size seat " .. seat)
    check(tbl:Life(seat) == p.life, "life seat " .. seat)
    for _, pos in ipairs(TTE.POSITIONS) do
      local ent = tbl.Slots["p" .. seat .. "_" .. pos][1]
      check((ent and ent.CardId) == p.spread[pos], pos .. " seat " .. seat)
      if ent then
        local c = g.cards[ent.CardId]
        check(ent.FaceUp == c.faceUp and ent:GetReversed() == c.reversed, "face/orientation " .. pos)
      end
    end
    for i, cid in ipairs(p.deck) do check(tbl.Lists["p" .. seat .. "_deck"][i].CardId == cid, "deck order") end
  end
  check(#tbl.Lists.out == #g.out, "out size")
  local inHands = 0
  for _, p in ipairs(g.players) do inHands = inHands + #p.hand end
  check(entityCount(tbl) == 78 - inHands - #g.unused, "entities = cards on the table")
end

local t2 = ents.Create("tt_table"); t2:Spawn()
local ann, ben = Player("ann"), Player("ben")
t2:ClaimSeat(1, ann); t2:ClaimSeat(3, ben)
check(t2:StartEngineGame(), "engine game starts")
check(t2:GetEngineOn(), "engine on")
check(not t2:ClaimSeat(2, Player("late")), "no sitting down mid-game")

-- Survey the Past: each player gets a pop-up decision with their card revealed only to them
local d, who = decisionFor(t2)
check(d.kind == "survey_past" and who == ann, "ann surveys first")
local peekEnt = t2.CardEnts[d.card]
check(peekEnt.PeekPlayer == ann and peekEnt:GetFaceId() == 0, "survey card peeked privately")
local ok, why = t2:EngineAnswer(ben, "upright")
check(not ok and why:find("Waiting for ann"), "ben can't answer ann's decision: " .. tostring(why))
check(t2:EngineAnswer(ann, "reversed"), "ann answers")
check(t2:EngineAnswer(ben, "upright"), "ben answers")
consistent(t2)
check(#t2.Hands[1] == 3 and #t2.Hands[3] == 3 and t2:Life(1) == 20, "setup on the table")
check(t2.Slots.p1_past[1]:GetReversed(), "ann's Past is reversed")

-- Activations of unscripted cards resolve manually: play through until a place step,
-- checking table/engine agreement after every step
local guard = 0
local function step(policy)
  guard = guard + 1
  check(guard < 5000, "runaway")
  local d, ply = decisionFor(t2)
  policy(d, ply)
  if t2.Engine then consistent(t2) end
end

-- 1. The first player's manual resolution: others can't touch cards; damage via the life counter; Done
d, who = decisionFor(t2)
check(d.kind == "manual", "first activation resolves manually, got " .. d.kind)
local other = who == ann and ben or ann
local otherSeat = t2:SeatOf(other)
local okP, whyP = t2:PickUp(t2.Slots["p" .. otherSeat .. "_past"][1], other)
check(not okP and whyP:find("Waiting"), "other player can't pick up cards")
local lifeBefore = t2:Life(otherSeat)
check(t2:ChangeLife(otherSeat, -3, who), "damage by clicking life")
check(t2:Life(otherSeat) == lifeBefore - 3, "life synced")
-- Dismiss the other player's Past card: drag it to their memory
local victim = t2.Slots["p" .. otherSeat .. "_past"][1]
check(t2:PickUp(victim, who), "resolver picks up a card")
check(t2:TryDrop(victim, TT.GetZone("p" .. otherSeat .. "_memory").pos, who), "drop in memory")
check(t2.Engine.cards[victim.CardId].loc.zone == "memory", "engine: dismissed")
consistent(t2)
-- Can't drop on the life counter; card stays held
local mySeat = t2:SeatOf(who)
local mine = t2.Slots["p" .. mySeat .. "_past"][1]
check(t2:PickUp(mine, who))
local okL = t2:TryDrop(mine, TT.GetZone("p" .. mySeat .. "_life").pos, who)
check(not okL and mine.IsHeld, "refused drop keeps the card held")
t2:ReturnCard(mine)
check(not mine.IsHeld and t2.Slots["p" .. mySeat .. "_past"][1] == mine, "returned to its slot")
check(t2:EngineAnswer(who, "done"), "done")
consistent(t2)

-- 2. Play until the active player's place step, resolving any activations with Done
while true do
  d, who = decisionFor(t2)
  if d.kind == "place_source" then break end
  step(function(d, ply) check(t2:EngineAnswer(ply, d.kind == "manual" and "done" or d.options[1].id), "answer " .. d.kind) end)
end
local seat = t2:SeatOf(who)
-- Placing from hand: take the selected card, turn it, drop it on Present
local card = t2:TakeFromHand(who, 1, false)
check(card and card.FaceUp, "hand card comes out face up on the place step")
check(t2.Engine.pending.kind == "place_target", "source answered on take")
check(t2:TurnCard(card, who), "turning a held card is local")
local okW = t2:TryDrop(card, TT.GetZone("p" .. (seat == 1 and 3 or 1) .. "_present").pos, who)
check(not okW and card.IsHeld, "can't place on another player's spread")
check(t2:TryDrop(card, TT.GetZone("p" .. seat .. "_present").pos, who), "placed")
local placed = t2.Engine.players[t2:EnginePidOfSeat(seat)].spread.present
check(placed == card.CardId and t2.Engine.cards[placed].reversed, "engine: placed reversed in Present")
consistent(t2)

-- 3. Optional draw with E on your own deck
d, who = decisionFor(t2)
check(d.kind == "may_draw", "may draw, got " .. d.kind)
local handBefore = #t2.Hands[seat]
check(t2:UseDeck(TT.GetZone("p" .. seat .. "_deck"), false, who), "E draws")
check(#t2.Hands[seat] == handBefore + 1, "drew")
consistent(t2)

-- 4. Placing from the deck: picking up the top card answers "deck" and reveals it privately
while true do
  d, who = decisionFor(t2)
  if d.kind == "place_source" then break end
  step(function(d, ply) check(t2:EngineAnswer(ply, d.kind == "manual" and "done" or d.options[1].id)) end)
end
seat = t2:SeatOf(who)
local top = t2:TopCard("p" .. seat .. "_deck")
local okT, whyT = t2:PickUp(t2.Lists["p" .. seat .. "_deck"][1], who)
check(t2.Engine.pending.kind == "place_source", "bottom card refused")
check(t2:PickUp(top, who) and top.IsHeld, "top card picked up")
check(t2.Engine.pending.kind == "place_target" and top.PeekPlayer == who and top:GetFaceId() == 0, "revealed privately")
check(t2:TryDrop(top, TT.GetZone("p" .. seat .. "_future").pos, who), "placed from deck")
consistent(t2)

-- 5. Play the rest with random table gestures; the table must stay in step.
-- Then 40 more random games from the start, with 2-4 players.
local r = 12345
local function rand(k) r = r * 48271 % 2147483647; return r % k + 1 end

local function randomStep(t2)
  local d, ply = decisionFor(t2)
  local s = t2.EngineSeats[d.player] -- (a solo player owns several seats)
  if d.kind == "place_source" then
    if #t2.Hands[s] > 0 and rand(2) == 1 then
      local c = t2:TakeFromHand(ply, rand(#t2.Hands[s]), true, s)
      if c then
        local spaces = t2.Engine:legalSpaces(d.player)
        if rand(2) == 1 then t2:TurnCard(c, ply) end
        if not t2:TryDrop(c, TT.GetZone("p" .. s .. "_" .. spaces[rand(#spaces)]).pos, ply) then t2:ReturnCard(c) end
      end
    else
      check(t2:EngineAnswer(ply, d.options[rand(#d.options)].id), "place via list")
    end
  elseif d.kind == "manual" and rand(3) > 1 then
    -- a random gesture; refusals are fine, crashes and desyncs are not
    local cards = {}
    for _, e in pairs(t2.CardEnts) do if IsValid(e) and e.ZoneId and e.ZoneId ~= "out" then cards[#cards + 1] = e end end
    table.sort(cards, function(a, b) return a.CardId < b.CardId end)
    local e = cards[rand(#cards)]
    local g = rand(6)
    if g == 1 and e and t2:PickUp(e, ply) then
      local zones = TT.Zones
      if not t2:TryDrop(e, zones[rand(#zones)].pos, ply) then t2:ReturnCard(e) end
    elseif g == 2 and e then t2:FlipCard(e, ply)
    elseif g == 3 and e then t2:TurnCard(e, ply)
    elseif g == 4 and e then t2:CounterCard(e, rand(2), rand(2) == 1 and 1 or -1, ply)
    elseif g == 5 then
      local seatHand = t2.Hands[s]
      if #seatHand > 0 then
        local c = t2:TakeFromHand(ply, rand(#seatHand), rand(2) == 1, s)
        if c and not t2:TryDrop(c, TT.Zones[rand(#TT.Zones)].pos, ply) then t2:ReturnCard(c) end
      end
    else t2:ChangeLife(t2.EngineSeats[rand(#t2.EngineSeats)], -rand(4), ply) end
  else
    local answer = d.kind == "manual" and "done" or d.options[rand(#d.options)].id
    check(t2:EngineAnswer(ply, answer), "answer " .. d.kind)
  end
  if t2.Engine then consistent(t2) end
end

while t2.Engine do guard = guard + 1; check(guard < 5000, "runaway"); randomStep(t2) end
check(not t2:GetEngineOn() and t2:GetStatus() == "", "engine stopped at game over")
local over = false
for _, m in ipairs(CHAT) do if m:find("Game over") then over = true end end
check(over, "game over announced")

local games, steps = 0, 0
for i = 1, 40 do
  math.randomseed(i)
  local t = ents.Create("tt_table"); t:Spawn()
  local seats = ({ { 1, 3 }, { 1, 2, 3 }, { 1, 2, 3, 4 } })[i % 3 + 1]
  for _, seat in ipairs(seats) do t:ClaimSeat(seat, Player("p" .. seat)) end
  check(t:StartEngineGame(), "start " .. i)
  local n = 0
  while t.Engine do
    n = n + 1
    check(n < 20000, "runaway game " .. i)
    randomStep(t)
  end
  games, steps = games + 1, steps + n
end
-- Solo (hotseat) games: one player holds 2-4 seats and plays them all
local soloGames = 0
for i = 1, 12 do
  math.randomseed(100 + i)
  local t = ents.Create("tt_table"); t:Spawn()
  local me = Player("solo")
  check(t:ClaimSeat(1, me), "sit")
  check(not t:ClaimSeat(3, me), "a second seat needs the solo flag")
  local n = i % 3 + 2
  for seat = 2, n do check(t:ClaimSeat(seat == 2 and 3 or (seat == 3 and 2 or 4), me, true), "solo seat") end
  check(#t:SeatedSeats() == n, "solo seats taken")
  check(t:StartEngineGame(), "solo start")
  check(t.Engine.players[1].name ~= t.Engine.players[2].name, "seat names are distinct")
  -- Survey: every decision is mine, whichever seat
  local d1 = t.Engine.pending
  check(t:MyDecision(me) == d1, "solo player owns every decision")
  -- Taking from a hand that isn't the deciding seat's is refused on the place step
  while t.Engine and t.Engine.pending.kind ~= "place_source" do randomStep(t) end
  if t.Engine then
    local deciding = t.EngineSeats[t.Engine.pending.player]
    local other
    for _, seat in ipairs(t.EngineSeats) do if seat ~= deciding and #t.Hands[seat] > 0 then other = seat end end
    if other then
      local c, why = t:TakeFromHand(me, 1, true, other)
      check(not c and why and why:find("decision"), "wrong seat's hand refused: " .. tostring(why))
    end
  end
  local steps = 0
  while t.Engine do
    steps = steps + 1
    check(steps < 20000, "runaway solo game")
    randomStep(t)
  end
  soloGames = soloGames + 1
  check(t:LeaveSeat(me) and not t:SeatOf(me), "leaving frees all seats")
end
print("solo games: " .. soloGames .. " ok")
print(string.format("random table games: %d games, %d steps, table and engine in step throughout", games, steps))
print("engine game: ok (" .. guard .. " steps)")
print("table tests ok")
