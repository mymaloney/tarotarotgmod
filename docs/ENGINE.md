# Rules engine

`lua/tarotarot_engine/` is a rules engine for Tarotarot written in plain
Lua 5.1, with no Garry's Mod code, so it runs and is tested outside the game.
[RULES.md](RULES.md) is its spec. The card table runs games with it
(`lua/entities/tt_table/sv_engine.lua`): see "On the table" below.

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

## On the table

`!deal` starts an engine game for everyone seated. The engine is the
authority. After every decision the table rebuilds its zones, hands, life
totals, card orientation and counters from the engine's state
(`SyncFromEngine`). Table gestures are translated into answers
(`EngineDrop`, `EngineCardAction`, …; the README has the full move →
action table), and anything the engine rejects is refused with a reason. The
deciding player gets the full decision. Everyone else gets a public status
line, so private prompts (like the card you're placing from your deck) stay
private. A card the engine reveals to one player is peeked to that player only.

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
lua tests/table_test.lua       # the table, against a minimal mock of the Garry's Mod API
```

They cover setup for 2–4 players, turn order, orientation, silence, placing
rules, can't-place-draw, elimination (including simultaneous), "win the
game", priority and instant flips, replacement ordering, prevention, expiry,
triggers, restart-from-Past and manual resolution. They also play 200 random
games with every card resolved by random keyword actions, checking that each
game ends and no cards are lost.

`table_test.lua` drives engine games through the same table methods the Card
Hand calls: survey, placing from hand and from the deck (with the private
reveal), refused moves, manual dismiss/damage, the optional draw. It then
plays 40+ random 2–4 player games with random gestures, checking after every
step that the table and the engine agree on every card. Rendering, pop-ups
and networking can only be checked in the game itself.
