# Rules engine

`lua/tarotarot_engine/` is a rules engine for Tarotarot written in plain
Lua 5.1, with no Garry's Mod code, so it runs and is tested outside the game.
[RULES.md](RULES.md) is its spec. It's loaded on the server but **not yet
hooked up to the table**: the table is still played by hand.

## How it works

- **One coroutine runs the whole game.** When a player has to decide
  something, the engine stores it in `game.pending` and pauses. A UI (or a
  test) answers with `game:answer(player, choice)`.
- **Decisions** have a `kind`, a `prompt`, and usually `options` (`{ id, label }`):

  | kind | when |
  | --- | --- |
  | `survey_past` | setup: put your top card in the Past upright or reversed |
  | `place_source` | step 2: a hand card or the top of your deck |
  | `place_target` | step 2: space and orientation. From the deck, `card` is revealed to you (`private`) |
  | `may_draw` | step 3 |
  | `priority` | only when you could do something "at any time" (e.g. flip a face-down card) |
  | `order_replacements` | several "instead" effects apply to you: pick which goes first |
  | `manual` | resolve an unscripted card: answer with keyword actions, then `{ action = "done" }` |

- **Turn structure** follows the rulebook: activate Past → Present → Future
  (face-up cards only, silence replaces an activation), place (or draw if you
  can't), may draw, next living player clockwise.
- **Stack and priority** (ruling 2): activations and triggers go on a stack.
  Before each resolution, players get priority in turn order. "At any time"
  actions are only allowed while the stack is empty. Players with nothing
  they could do pass automatically, so priority only asks when there's a
  real choice.
- **Replacement effects** (`addModifier`): change or cancel an event (damage,
  draw, place, activate, dismiss…) before it happens. When several apply,
  the affected player picks the order (ruling 8). They can be single-use or
  last until end of turn / the start of a player's next turn.
- **Triggers** (`addTrigger`): "whenever…" effects go on the stack after the event.
- **Eliminations** are checked at safe points (after each resolution and
  each turn step), so simultaneous lethal damage removes everyone it should
  before the game ends. One or no players left ends the game.

## Card scripts

`TTE.Cards[name] = { upright = function(g, ctx) ... end, reversed = ... }`,
where `ctx = { card, controller, side }`. A script calls keyword actions
(`g:damage`, `g:draw`, `g:dismiss`, `g:placeStep`, …) and `g:ask(...)` for
choices. **No cards are scripted yet.** Every card resolves through `manual`,
so the engine can already run a complete game.

## Assumptions (not in the rules; correct me)

1. Cards leaving a spread lose their orientation and counters.
2. Memory and Out of Game are face up (public). Deck and hand are hidden.
3. Replacing a Minor card while placing sends it to memory, but does **not**
   count as "dismissed" for effects like 7 of Wands.
4. An activation still resolves if its card leaves the spread first.
5. Eliminated players' cards go to Out of Game. Their flip permissions
   end, but lasting effects they created stay until they expire.
6. Flipping a face-down card "to activate it and silence it": the
   activation goes on the stack, then the silence counter is added. A silence
   counter already on the card stops that activation.

## Tests

```
lua tests/engine_test.lua      # any Lua 5.1+ or LuaJIT, from the repo root
```

They cover setup for 2–4 players, turn order, orientation, silence, placing
rules, can't-place-draw, elimination (including simultaneous), "win the
game", priority and instant flips, replacement ordering, prevention, expiry,
triggers, restart-from-Past and manual resolution. They also play 200 random
games with every card resolved by random keyword actions, checking that each
game ends and no cards are lost.
