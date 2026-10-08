# Tarotarot rules (spec for the rules engine)

From the printed rules sheet, plus rulings from the designer. When the
engine and this file disagree, this file is right.

## Components and setup

- 78 cards: 22 **Major** (unique, gold background) and 56 **Minor** (rank
  Ace, 2–10, Page, Knight, Queen, King; suit Wands, Pentacles, Cups, Swords).
- 2–4 players. Each has a **Deck** (on their left), **Past**, **Present** and
  **Future** spaces in the middle (together their **Spread**), and a
  **Memory** (on their right). Players also have a hand.
- Setup:
  1. Shuffle all 78 cards together and deal them face down equally:
     39 each (2 players), 26 each (3), 19 each (4). Leftover cards are removed.
  2. **Survey the Past:** each player puts the top card of their deck face up,
     in either orientation, into their Past.
  3. Each player draws 3 cards. Players may look at their hand.
  4. Each player starts with 20 life.
  5. Randomly pick the starting player.

## On your turn

1. **Activate the cards on your spread:** Past, then Present, then Future.
   If a card refers to a card, it means cards on any player's spread.
   - Only face-up cards activate in this step. *(ruling)*
2. **Place one card, face up, on your spread, upright or reversed.** It
   doesn't take effect until you activate it.
   - Place it from your hand or from the top of your deck. When placing from
     the deck, you may look at the card before placing it.
   - You may place into an empty space, or replace a **Minor** card by sending
     it to memory. You may not replace Major cards.
   - If you can't place a card, draw a card. "Can't place" means no legal
     space, as well as an empty hand and deck. *(ruling)*
3. **You may draw a card.** Play passes to the next player clockwise.

## End

- A player who runs out of life, or tries to draw from an empty deck, is
  removed from the game, along with every card in their spread, hand, memory
  and deck.
- Play ends when one player or none remain. Any remaining player wins.

## Keywords

| Keyword | Meaning |
| --- | --- |
| Activate | Follow the instructions on the side of the card facing its player. |
| Damage | Reduce a player's life. |
| Discard | Move a card from hand to memory. |
| Dismiss | Move a card on a spread to its player's memory. |
| Place | Put a card on your spread from your hand or deck. Placing from card effects follows the same rules as the turn's place step *(ruling)*. |
| Reverse | Rotate a card 180 degrees. |
| Silence | Put a silence counter on a card. When a card with a silence counter would activate, remove that counter instead. |
| Spread | A player's Past, Present and Future. |

## Rulings

1. Only face-up cards activate in step 1.
2. **Timing:** a digital engine needs a priority system like Magic: The
   Gathering's. Effects such as "you may flip a face-down card at any time to
   activate it" can be used whenever the effect stack is empty.
3. **Restart the turn from the Past** (6 of Cups) re-runs activation starting
   from the Past. Nothing is undone.
4. "Place a card" on a card follows the normal place rules (hand or top of
   deck, may replace Minor cards).
5. "Take a card" (The Chariot) means any card on any spread.
6. "Can't place a card" means no legal space, as well as an empty hand and deck. This
   applies to places that card effects require too (not "may" places): if you
   can't make one, you draw instead.
7. **Copying** ("copy an effect of either side of a card"): "this card" is the
   card doing the copying, and "you" is the player who controls the copier.
8. When several effects would replace the same event, the player the event
   applies to chooses their order.
