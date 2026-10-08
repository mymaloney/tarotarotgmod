# Tarotarot Tabletop (Garry's Mod)

A basic tabletop card-game simulator for Garry's Mod (Sandbox). It has a
two-player table with fixed zones, cards you can pick up, flip and rotate,
and counters you can put on cards.

## Install

Copy (or clone) this folder into `garrysmod/addons/`, e.g.
`garrysmod/addons/tarotarot_tabletop/`, then start a Sandbox game.

## Quick start

1. Spawn menu (Q) → **Entities → Tabletop → Card Table**. The table faces
   you, so you're Player 1 on the near side. Each player gets a shuffled
   78-card Tarotarot deck.
2. Spawn menu → **Weapons → Tabletop → Card Hand**, and equip it.
3. Look at the table and play.

## Controls (Card Hand)

| Key | Action |
| --- | --- |
| LMB | Pick up the card under the crosshair (the top card of a pile) / place the held card |
| RMB | Flip card face up / face down |
| R | Turn card 180° (upright ↔ reversed) |
| E | Shuffle the pile you're looking at |
| Shift + LMB / RMB | Add / remove a counter of the selected type |
| Shift + R | Cycle the counter type (Generic, Damage, Shield, Charge) |

If you're holding a card, Flip, Turn and counter actions apply to that card.
The HUD shows an enlarged preview of the card you're pointing at, plus its
upright and reversed text from the CSV (the active side is highlighted).
"Reversed" is relative to the player whose zone the card is in.

## Zones

Each side of the table has:

- **Deck**: a pile. Cards stack and E shuffles it.
- **Discard**: a pile.
- **Field**: a 5 × 2 grid with one card per slot. A card dropped into the
  field snaps to the nearest free slot.

You can only drop cards inside a zone. A card placed in a pile is reset to
upright. Cards take on the facing of the zone they're placed in, so cards on
Player 2's side face Player 2.

## Console commands

- `tt_decks`: list registered decks
- `tt_spawndeck <deck>`: add a deck to the pile zone you're looking at
- `tt_reset`: clear the table you're looking at and deal fresh decks

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
  Zones are plain tables (`kind = "pile"` or `"grid"`, position, facing).
- **More decks**: `TT.LoadCSVDeck(name, "folder/file.csv", { back = "back.png" })`
  in `lua/tabletop/sh_decks.lua`. Point `tools/build_cards.py` at the new art.

## Notes

- A face-down card's identity is never sent to clients, so players can't peek.
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
lua/tabletop/cl_render.lua       card drawing, hover detection
lua/tabletop/sv_commands.lua     console commands
lua/entities/tt_table/           the table and its zone/card bookkeeping
lua/entities/tt_card/            a single card
lua/weapons/tt_cardtool.lua      the "Card Hand" you interact with
data_static/tarotarot/cards.csv  card names and rules text
materials/tarotarot/             GENERATED: atlas sheets (.vtf/.vmt)
source/cards/                    full-size card art (not shipped)
tools/build_cards.py             builds the atlas sheets
```
