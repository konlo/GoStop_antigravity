# GoStop Play Validation Rules

This file tracks the rules used by the automated AI Player to validate the correctness of the game simulator.

## 1. Score Consistency
The final `score` of each player must match the cards they have captured.
- **Pi (Junk)**: 1 point for 10 cards, +1 point for each additional card. Double Pi cards count as 2.
- **Five (Ribbon)**: 1 point for 5 cards, +1 point for each additional card. Special combinations (Red/Blue/Grass) add 3 points each.
- **Ten (Animal)**: 1 point for 5 cards, +1 point for each additional card. Godori (Birds) adds 5 points.
- **Bright (Kwang)**: 3 cards = 3 points (unless Bi-Kwang is included, then 2), 4 cards = 4 points, 5 cards = 15 points.

**Verification Logic**:
1. Sum of `scoreItems` points must equal `player.score`.
2. The `count` of cards in `scoreItems` must match the count of relevant cards in `player.capturedCards`.
