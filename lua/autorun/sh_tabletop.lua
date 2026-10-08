-- Tarotarot Tabletop: loader. Runs before entities/weapons are registered,
-- so the shared TT table is available to them.
TT = TT or {}

local shared = {
	"tabletop/sh_config.lua",
	"tabletop/sh_decks.lua",
	"tabletop/sh_util.lua",
}

for _, f in ipairs(shared) do
	if SERVER then AddCSLuaFile(f) end
	include(f)
end

if SERVER then
	AddCSLuaFile("tabletop/cl_render.lua")
	include("tabletop/sv_commands.lua")
else
	include("tabletop/cl_render.lua")
end
