## 1.0.2

### Reagent bag support
- The reagent bag, which sits in its own slot after the last normal bag, is now included everywhere the addon looks at your bags. Items kept there count towards Have, surplus can be deposited from it, and withdrawals can go into it.
- Withdrawals prefer an ordinary bag and only use a specialised bag when the item belongs there, so the reagent bag does not get filled with things that could have gone anywhere.
- Items that do not belong in a specialised bag are never pushed into one. If a reagent bag, quiver or soul bag is the only free space, the addon reports bags full rather than attempting a move the game would refuse.
- `/stockpile debug` now lists the bags it can see, with each one's free slots and family, so a reagent bag that is not being picked up is easy to spot.
