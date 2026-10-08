-- Tarotarot Tabletop: deck definitions.
--
-- Card text comes from a CSV file and card art from the atlas sheets built by
-- tools/build_cards.py. CSV columns (header row required, extra columns ignored):
--   name, suit, image, upright, reversed
-- `image` is the source art's file name, which is how a row finds its picture
-- in the atlas (see lua/tabletop/sh_atlas.lua).

TT.Decks = TT.Decks or {}

function TT.RegisterDeck(name, data)
	data.name = name
	data.title = data.title or name
	data.cards = data.cards or {}
	TT.Decks[name] = data
end

-- Minimal RFC 4180 CSV parser: quoted fields, "" escapes, commas/newlines in quotes.
function TT.ParseCSV(text)
	local rows, row, field = {}, {}, {}
	local i, len, inQuotes = 1, #text, false

	local function endField()
		row[#row + 1] = table.concat(field)
		field = {}
	end
	local function endRow()
		endField()
		if #row > 1 or row[1] ~= "" then rows[#rows + 1] = row end
		row = {}
	end

	while i <= len do
		local c = text:sub(i, i)
		if inQuotes then
			if c == '"' then
				if text:sub(i + 1, i + 1) == '"' then
					field[#field + 1] = '"'
					i = i + 1
				else
					inQuotes = false
				end
			else
				field[#field + 1] = c
			end
		elseif c == '"' then
			inQuotes = true
		elseif c == "," then
			endField()
		elseif c == "\n" then
			endRow()
		elseif c ~= "\r" then
			field[#field + 1] = c
		end
		i = i + 1
	end
	if #field > 0 or #row > 0 then endRow() end

	-- Turn rows into tables keyed by the header names
	local header, out = rows[1] or {}, {}
	for r = 2, #rows do
		local rec = {}
		for col, key in ipairs(header) do
			rec[string.Trim(key):lower()] = rows[r][col] or ""
		end
		out[#out + 1] = rec
	end
	return out
end

-- Load a deck from a CSV shipped in the addon's data_static folder.
function TT.LoadCSVDeck(name, path, data)
	local text = file.Read("data_static/" .. path, "GAME") or file.Read(path, "DATA")
	if not text then
		ErrorNoHalt("[Tabletop] Couldn't read deck CSV '" .. path .. "'\n")
		return
	end

	data = data or {}
	data.cards = {}
	for _, rec in ipairs(TT.ParseCSV(text)) do
		if rec.name and rec.name ~= "" then
			if rec.image ~= "" and not TT.Atlas.cells[rec.image] then
				ErrorNoHalt("[Tabletop] " .. path .. ": no art for '" .. rec.image .. "' - rerun tools/build_cards.py\n")
			end
			data.cards[#data.cards + 1] = {
				name = rec.name,
				suit = rec.suit,
				image = rec.image,
				upright = rec.upright,
				reversed = rec.reversed,
			}
		end
	end
	TT.RegisterDeck(name, data)
end

TT.LoadCSVDeck("tarotarot", "tarotarot/cards.csv", {
	title = "Tarotarot",
	back = TT.Atlas.back,
})
