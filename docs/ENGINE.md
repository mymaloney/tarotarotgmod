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

All 78 cards are scripted, both sides, in `lua/tarotarot_engine/cards.lua`:
`TTE.Cards[name] = { upright = fn(g, ctx), reversed = fn(g, ctx) }`, where
`ctx = { card, controller, side }`. A script calls keyword actions
(`g:damage`, `g:draw`, `g:dismiss`, `g:placeStep`, …) and choice helpers
(`lua/tarotarot_engine/choices.lua`: `choosePlayer`, `chooseCard`,
`chooseCards`, `chooseNumber`, `chooseSuit`, `chooseName`, `yesNo`). These
appear as pop-up buttons on the table. A card label never reveals a card the
chooser isn't allowed to see ("card 2 in Bo's hand"). A card with no script
(e.g. a new card added to the CSV) still resolves by hand, as before.

### How the cards were read

Where a card's text leaves something open, the script does this:

- **"A card"** means a card on any player's spread (rulebook), including
  yours. **"A player"** includes you; **"an opponent"** doesn't.
- **"Place a card"** follows the place rules: hand or top of deck, no
  replacing Majors (ruling 4). If an effect requires a place (not a "may" or
  "up to") and you can't make it, you draw instead, as on your turn (ruling 6:
  no legal space, or nothing to place from that effect's source). That covers
  The Magician, The Tower, The Moon, The Chariot, 4 and 10 of Pentacles,
  8 of Pentacles (reversed), 7 of Swords, Ace/2/4/8 of Wands and 8 of Cups
  (reversed). A place stopped by another effect (2 of Wands reversed, 9 of
  Swords, Page of Wands reversed) isn't "can't place", so there's no draw.
- **"Activate"** (6 of Wands, 3 of Cups, Knight of Wands) only activates
  face-up cards, and the activation goes on the stack after the current
  effect. 3 of Cups pushes them so they resolve in the order you chose.
- **Copying** (5, 6, 9 and Knight of Cups, 8 of Pentacles) only offers face-up
  cards (or memory cards, for the Knight of Cups). A copy can't copy an effect
  it's already part of, so 5 of Cups can't copy itself and two copy cards
  can't loop.
- **The Tower:** "all cards" shuffled into decks means the cards on spreads.
- **Knight of Swords (reversed):** players choose a number from 0 to 10.
- **Strength (reversed):** "any number up to 10" is 0–10.
- **King of Cups (upright):** players who draw can't damage you or dismiss
  cards on your spread until your next turn; your own actions aren't
  affected.
- **The Devil (reversed)** and **Queen of Pentacles:** "place from your memory
  instead" swaps the card being placed, so the original stays where it was.
  The Devil's "pay 2 life" reduces life directly (it isn't damage).
- **2 of Wands (upright):** several "double your next damage" effects all
  apply to that next damage (×2 each) without asking for an order.
- **Wheel of Fortune (reversed):** the coin decides between you and the
  chosen opponent; the damage doubles each flip.

### Endless loops

Some combinations activate each other forever. For example, the 5 of Cups
copies the Knight of Wands reversed ("activate another card on your spread
twice, then silence it"). That activates the Knight, which activates the
5 of Cups, which copies the Knight again, and so on. The engine caps
activations at 100 per turn (`TTE.MAX_ACTIVATIONS_PER_TURN`). Past that, it
logs an endless loop and nothing else activates that turn; the turn carries on.

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
lua tests/cards_test.lua       # the card scripts, with the real card list
lua tests/table_test.lua       # the table, against a minimal mock of the Garry's Mod API
```

`cards_test.lua` checks that every card has both sides scripted, then:
- activates every side 12 times on a busy 3-player board (full spreads,
  face-down cards, memories, hands) with random answers;
- plays 60 random full games with every card live;
- runs rules checks for 36 cards with specific logic (numbers, "instead"
  effects, lasting effects, restarts, copies, triggers).

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
