-- Tarotarot Tabletop: deck definitions.
--
-- Register your own deck with TT.RegisterDeck(name, data). Each card can have:
--   name     - shown on the card and in the HUD (required)
--   num      - small label at the top of the card
--   text     - description shown in the HUD when hovering the card
--   color    - face background colour
--   material - path to card art, e.g. "tabletop/mydeck/fool.png"
--              (put the file in materials/tabletop/mydeck/fool.png)

TT.Decks = TT.Decks or {}

function TT.RegisterDeck(name, data)
	data.name = name
	data.title = data.title or name
	data.faceColor = data.faceColor or Color(60, 60, 70)
	data.backColor = data.backColor or Color(30, 30, 40)
	data.accent = data.accent or Color(220, 220, 220)
	data.backText = data.backText or ""
	TT.Decks[name] = data
end

local majorArcana = {
	{ "0",     "The Fool",           "Beginnings, innocence, a leap of faith" },
	{ "I",     "The Magician",       "Willpower, skill, manifestation" },
	{ "II",    "The High Priestess", "Intuition, mystery, the inner voice" },
	{ "III",   "The Empress",        "Abundance, nurturing, fertility" },
	{ "IV",    "The Emperor",        "Authority, structure, control" },
	{ "V",     "The Hierophant",     "Tradition, institutions, belief" },
	{ "VI",    "The Lovers",         "Union, choice, harmony" },
	{ "VII",   "The Chariot",        "Determination, victory, momentum" },
	{ "VIII",  "Strength",           "Courage, patience, compassion" },
	{ "IX",    "The Hermit",         "Solitude, reflection, guidance" },
	{ "X",     "Wheel of Fortune",   "Cycles, fate, a turning point" },
	{ "XI",    "Justice",            "Fairness, truth, consequence" },
	{ "XII",   "The Hanged Man",     "Surrender, a new perspective, pause" },
	{ "XIII",  "Death",              "Endings, transformation, transition" },
	{ "XIV",   "Temperance",         "Balance, moderation, patience" },
	{ "XV",    "The Devil",          "Bondage, temptation, materialism" },
	{ "XVI",   "The Tower",          "Upheaval, revelation, sudden change" },
	{ "XVII",  "The Star",           "Hope, renewal, inspiration" },
	{ "XVIII", "The Moon",           "Illusion, dreams, the unconscious" },
	{ "XIX",   "The Sun",            "Joy, success, vitality" },
	{ "XX",    "Judgement",          "Reckoning, rebirth, awakening" },
	{ "XXI",   "The World",          "Completion, fulfilment, wholeness" },
}

local cards = {}
for i, c in ipairs(majorArcana) do
	cards[i] = {
		num = c[1],
		name = c[2],
		text = c[3],
		color = HSVToColor((i - 1) * (360 / #majorArcana), 0.45, 0.45),
	}
end

TT.RegisterDeck("tarot_major", {
	title = "Tarot: Major Arcana",
	backColor = Color(36, 26, 82),
	accent = Color(214, 182, 96),
	backText = "TAROT",
	cards = cards,
})
