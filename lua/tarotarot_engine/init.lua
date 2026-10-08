-- Tarotarot rules engine loader. `load` is Garry's Mod's include, or dofile
-- with a path prefix when running outside the game (see tests/).
TTE = TTE or {}
TTE.FILES = { "game.lua", "actions.lua", "turn.lua" }

function TTE.Load(load)
	for _, f in ipairs(TTE.FILES) do load(f) end
end
