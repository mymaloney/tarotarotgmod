# Tarotarot Tabletop (Garry's Mod)

A tabletop simulator for the card game Tarotarot in Garry's Mod (Sandbox),
for 2–4 players. It has a table laid out like the rulebook, hidden hands,
life counters, cards you can pick up, flip and turn, and counters you can put
on cards. Rules aren't enforced yet; you play them by hand. The rules and
designer rulings are in [docs/RULES.md](docs/RULES.md).

## Install

Copy (or clone) this folder into `garrysmod/addons/`, e.g.
`garrysmod/addons/tarotarot_tabletop/`, then start a Sandbox game.

## Quick start

1. Spawn menu (Q) → **Entities → Tabletop → Card Table**. Seat 1 faces you.
2. Spawn menu → **Weapons → Tabletop → Card Hand**, and equip it.
3. Each player walks to a side of the table and presses **E** on that seat's
   zones to sit. For 2 players, sit on opposite sides.
4. Say **`!deal`** in chat (or run `tt_newgame`). The game is set up as in the
   rulebook:
   - all 78 cards are shuffled and dealt equally (39 / 26 / 19 each);
   - each player's top card goes face up into their Past (press R on it to
     reverse it);
   - everyone draws 3 and starts at 20 life;
   - a random first player is announced.

## Controls (Card Hand)

| Key | Action |
| --- | --- |
| LMB | Pick up the card under the crosshair (top card of the deck) / place the held card |
| RMB | Flip card face up / face down |
| R | Turn card 180° (upright ↔ reversed) |
| E | Sit at an empty seat / draw from your own deck |
| Shift + E | Shuffle the deck you're looking at |
| LMB / RMB on a Life counter | -1 / +1 life (hold Shift for 5) |
| Shift + LMB / RMB | Add a Generic / Silence counter |
| Alt + LMB / RMB | Remove a Generic / Silence counter |
| Mouse wheel | Choose a card in your hand |
| LMB on your hand zone | Take the chosen hand card, face up |
| Alt + LMB on your hand zone | Take it face down (only you can see what it is) |

If you're holding a card, Flip, Turn and counter actions apply to that card.
The HUD shows an enlarged preview of the card you're pointing at, plus its
upright and reversed text from the CSV (the active side is highlighted).
"Reversed" is relative to the player whose zone the card is in.

## Zones

The table is square with a seat on each side. Seats go clockwise: 1 south,
2 west, 3 north, 4 east. From each player's view, left to right:

**Life | Deck | Past | Present | Future | Memory**, with their **Hand** along the edge.

- **Life**: that player's life total. Click it to change it.
- **Deck**: a face-down pile. Cards put on it turn face down and upright.
- **Past, Present, Future** (the spread): one card each.
- **Memory**: a row of any length. Cards fan out and overlap as it fills,
  every card can be picked up, and a dropped card goes where you drop it in the row.
- **Hand**: hidden. Drop a card on a seated player's hand zone to put it in
  their hand. Your hand shows along the bottom of your screen while the Card
  Hand is out. Everyone else sees only card backs and the count.

Shared: **Out of Game**, in the middle, for cards removed from the game.

A players panel (top left) shows everyone's life and hand size, and who went
first.

You can only drop cards inside a zone, and an occupied Past/Present/Future
slot won't take another card. Cards take on the facing of the zone they're
placed in.

## Console commands

- `tt_newgame` (or `!deal` in chat; `tt_reset` also works): deal a new game to
  everyone seated at the table you're looking at
- `tt_leave`: give up your seat. Any hand stays with the seat for whoever
  sits there next.
- `tt_decks`: list registered decks
- `tt_spawndeck <deck>`: add a whole deck to the pile zone you're looking at (for testing)

## Cards: text and art

- **Text:** `data_static/tarotarot/cards.csv` is the card sheet, exported
  as-is: `Name, Upright Effect, Reversed Effect`. Re-export it from the
  spreadsheet and drop it in. Text edits only need a map reload. Row order sets
  the deck order, and extra columns are ignored. You can add optional `Suit`
  and `Image` columns; otherwise the suit comes from the name ("... of Cups",
  else Major).
- **Art:** the full-size source PNGs live in `source/cards/`, named after the
  card (`The Fool` → `the-fool.png`, `Ace of Cups` → `ace-of-cups.png`). That folder isn't
  shipped (see `addon.json`'s `ignore`). The game uses compressed atlas sheets
  built from them instead:

  ```
  python3 tools/build_cards.py      # needs Pillow >= 11
  ```

  The builder packs the art for every card in the CSV, plus `cardback.png`, into 4096×4096 DXT1 `.vtf` sheets in `materials/tarotarot/`,
  each with mipmaps. It also writes `lua/tabletop/sh_atlas.lua`, which maps
  each image to its cell. Rerun it whenever you add, remove, rename or reorder
  cards, or change their art.
  It's ~22 MB for the 79 images, versus 122 MB of PNGs, and the sheets stay
  compressed in video memory.

## Customising

- **Layout, sizes, colours, counter types**: `lua/tabletop/sh_config.lua`.
  The seat layout is worked out from the card size, and the table is sized to fit it.
- **More decks**: `TT.LoadCSVDeck(name, "folder/file.csv", { back = "back.png" })`
  in `lua/tabletop/sh_decks.lua`. Point `tools/build_cards.py` at the new art.

## Notes

- A face-down card's identity is only sent to a player allowed to see it:
  someone who played it face down from their own hand.
- On a dedicated server, players need the content too. Upload the addon to
  the Workshop and add `resource.AddWorkshop("<id>")` on the server.
- The table is a fixed object. Remove it with the remover tool or undo, and
  its cards go with it.

## Layout

```
lua/autorun/sh_tabletop.lua      loader
lua/tabletop/sh_config.lua       sizes, zones, counter types
lua/tabletop/sh_atlas.lua        GENERATED: image -> atlas cell map
lua/tabletop/sh_decks.lua        CSV deck loader
lua/tabletop/sh_util.lua         zone geometry + aiming helpers
lua/tabletop/cl_render.lua       card drawing, hover detection, peeks
lua/tabletop/cl_hand.lua         your hidden hand: HUD strip + wheel selection
lua/tabletop/sv_commands.lua     net messages, console commands, !deal
lua/entities/tt_table/           the table and its zone/card bookkeeping
lua/entities/tt_card/            a single card
lua/weapons/tt_cardtool.lua      the "Card Hand" you interact with
data_static/tarotarot/cards.csv  card names and rules text
docs/RULES.md                    game rules + designer rulings (rules engine spec)
materials/tarotarot/             GENERATED: atlas sheets (.vtf/.vmt)
source/cards/                    full-size card art (not shipped)
tools/build_cards.py             builds the atlas sheets
```
