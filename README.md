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
   22-card Major Arcana deck.
2. Spawn menu → **Weapons → Tabletop → Card Hand**, and equip it.
3. Look at the table and play.

## Controls (Card Hand)

| Key | Action |
| --- | --- |
| LMB | Pick up the card under the crosshair (the top card of a pile) / place the held card |
| RMB | Flip card face up / face down |
| R | Rotate card 90° clockwise (tap/exhaust) |
| E | Shuffle the pile you're looking at |
| Shift + LMB / RMB | Add / remove a counter of the selected type |
| Shift + R | Cycle the counter type (Generic, Damage, Shield, Charge) |

If you're holding a card, Flip, Rotate and counter actions apply to that card.
The HUD shows an enlarged preview of the card you're pointing at.

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

## Customising

- **Layout, sizes, colours, counter types**: `lua/tabletop/sh_config.lua`.
  Zones are plain tables (`kind = "pile"` or `"grid"`, position, facing).
- **Decks**: `lua/tabletop/sh_decks.lua`. Call `TT.RegisterDeck(name, { cards = {...} })`.
  Each card can have `name`, `num`, `text`, `color` and `material` (card art;
  e.g. put a PNG in `materials/tabletop/mydeck/fool.png` and set
  `material = "tabletop/mydeck/fool.png"`).

## Notes

- A face-down card's identity is never sent to clients, so players can't peek.
- The table is a fixed object. Remove it with the remover tool or undo, and
  its cards go with it.

## Layout

```
lua/autorun/sh_tabletop.lua      loader
lua/tabletop/sh_config.lua       sizes, zones, counter types
lua/tabletop/sh_decks.lua        deck definitions (Tarot Major Arcana)
lua/tabletop/sh_util.lua         zone geometry + aiming helpers
lua/tabletop/cl_render.lua       card drawing, hover detection
lua/tabletop/sv_commands.lua     console commands
lua/entities/tt_table/           the table and its zone/card bookkeeping
lua/entities/tt_card/            a single card
lua/weapons/tt_cardtool.lua      the "Card Hand" you interact with
```
