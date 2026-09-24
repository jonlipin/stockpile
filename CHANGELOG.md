# Stockpile 1.0.2

## Reagent bag support
- The reagent bag, which sits in its own slot after the last normal bag, is now included everywhere the addon looks at your bags. Items kept there count towards Have, surplus can be deposited from it, and withdrawals can go into it.
- Withdrawals prefer an ordinary bag and only use a specialised bag when the item belongs there, so the reagent bag does not get filled with things that could have gone anywhere.
- Items that do not belong in a specialised bag are never pushed into one. If a reagent bag, quiver or soul bag is the only free space, the addon reports bags full rather than attempting a move the game would refuse.
- `/stockpile debug` now lists the bags it can see, with each one's free slots and family, so a reagent bag that is not being picked up is easy to spot.

# Stockpile 1.0.1

## Faster bank and guild bank transfers
- Depositing and withdrawing is around five times quicker. A deposit of seven stacks, two of them needing a split, now takes about 1.4 seconds instead of about 7.
- Every move is still confirmed with the server before the next one is issued, so nothing is fired blindly and the safety checks are unchanged.
- The speed-up comes from two things: the mover no longer idles for a whole extra tick after each confirmation, and the tick interval dropped from 0.25s to 0.1s.
- Waiting periods are now measured in seconds rather than ticks, so a slow server still gets the same patience it had before.

# Stockpile 1.0.0: Initial release

For **WoW: Forever** (Interface 16001).

## Restocking
- Keeps at least your chosen **Want** amount of each item in your bags
- Per-item sources: independent **Vendor**, **Bank** and **Guild** checkboxes. Tick any combination
- Runs automatically when you open a vendor, your bank or the guild bank, or on demand with the **Restock** button added to those windows
- **Bank extras** (per item): deposits anything over your Want, so the rest stays banked
- **Gold reserve**: optional "Keep" amount. Vendor buying never takes you below it, and buys nothing if you're already under it

## Vendor buying
- Handles bundle pricing correctly (items sold in stacks of 5)
- Never overbuys; stops when you can't afford more
- Chat summary reports what actually arrived in your bags and roughly what it cost

## Bank handling
- Moves one stack at a time and verifies every move
- Splits stacks cleanly when only part of a stack is needed, leaving your original stack in place
- Clear messages when something can't be moved: bags full, bank full, not enough in the bank, guild withdrawal limit reached
- Guild bank *(experimental)*: withdraws from any tab you can view, respects daily withdrawal limits, deposits extras into the tab you have open

## Interface
- Window built from Blizzard's own interface art
- Drag and drop items from your bags to add them, or add by item ID
- Item icons with quality borders, quality-coloured names and full tooltips
- Sortable columns, search box, **Have** and **In bank** counts (red when short, green when stocked)
- Per-item enable toggle, minimap button (left-click: open, right-click: restock now)
- Footer toggles for auto vendor / auto bank / auto guild / chat summary
- Each character keeps its own list

## Commands
- `/stockpile` (alias `/restock`): open the window
- `/stockpile vendor` · `bank` · `guild`: restock now
- `/stockpile minimap`: show / hide the minimap button
- `/stockpile trace`: print every bank move, for troubleshooting
- `/stockpile debug`: diagnostic report for bug reports

## Known issues
- **Settings reset every session on the Forever beta.** This is a client bug affecting all addons and parts of the default UI (see the official forum thread *"UI/Addon settings wiped on client restart"*), not something an addon can fix. Settings will persist normally once Blizzard patches the client.
- Guild bank support has had limited testing. Reports are welcome, ideally with `/stockpile trace` output.
