-- Tarotarot Tabletop: loader. Runs before entities/weapons are registered,
-- so the shared TT table is available to them.
TT = TT or {}

local shared = {
	"tabletop/sh_config.lua",
	"tabletop/sh_atlas.lua",
	"tabletop/sh_decks.lua",
	"tabletop/sh_util.lua",
}

for _, f in ipairs(shared) do
	if SERVER then AddCSLuaFile(f) end
	include(f)
end

if SERVER then
	AddCSLuaFile("tabletop/cl_render.lua")
	AddCSLuaFile("tabletop/cl_hand.lua")
	AddCSLuaFile("tabletop/cl_engine.lua")
	include("tabletop/sv_commands.lua")

	-- Rules engine (server only); the table runs games with it (tt_table/sv_engine.lua)
	include("tarotarot_engine/init.lua")
	TTE.Load(function(f) include("tarotarot_engine/" .. f) end)
else
	include("tabletop/cl_render.lua")
	include("tabletop/cl_hand.lua")
	include("tabletop/cl_engine.lua")
end
