# Stockpile 1.1.0 - 2026-10-10

## Window styles
- A **Look** button at the right end of the toolbar opens a small panel with a Window style button: Automatic, Blizzard or Dark. Left-click it for the next style, right-click for the previous one. A line under it says which style is in use.
- **Dark** is a flat dark style built in, needing no other addon. The window and the Look panel get a dark background with thin edges, the search and add boxes become dark fields, buttons and checkboxes go flat, the column headers become a plain sort bar, and the item icons go square with a thin edge in the item's quality color. The round portrait goes and the search box moves into its room.
- A **Dark background opacity** slider, 0 to 100%, sets how much of the world shows through. It applies as you drag, and it is grayed out unless Dark is chosen.
- **EllesmereUI support**: with EllesmereUI installed and the style on Automatic, Stockpile takes on its look. The Restock buttons on the vendor, bank and guild bank windows follow those windows, so they match EllesmereUI's and stay as the game draws them under Dark. EllesmereUI is optional, not a requirement.
- **Automatic** is the default, so nothing changes unless you have EllesmereUI or pick a style.
- Going from Blizzard to Dark happens at once. Any other switch takes a reload of the interface, so Stockpile asks, with a Reload now button.
- `/stockpile style` moves to the next style, and `/stockpile style auto`, `/stockpile style blizzard` and `/stockpile style dark` pick one. `/stockpile debug` shows the style chosen and which look is drawn.

## Changes
- The column headers are plain labels with the sort arrow, on the list's own background, instead of tab art.

## Fixes
- The window's close X, and the Look panel's, now work in combat. They went through the game's own panel closing, which the game refuses for an addon while you are fighting; the windows now simply hide.
- Fixed the item icons in the list. Each icon was both cropped and rounded off by a mask, and this client refuses to crop an icon once it has a mask. The icon is now only masked, centered in its quality border.
- Fixed the sort arrow's stand-in art, used when the auction house arrow is missing, pointing at a broken file path.
- A minimap button collector, such as EllesmereUI's, keeps Stockpile's minimap button where it put it instead of having it pulled back to the minimap rim.
- American spelling throughout.

# Stockpile 1.0.5

## New
- Hold shift as a vendor, bank or guild bank opens and Stockpile leaves it alone for that visit. Useful when you are there to sell, or to move something yourself, and do not want the list acting first. It says so in chat rather than staying silent.
- The Restock button and the slash commands still run normally with shift held, so skipping the automatic pass does not take manual control away.
- A "Shift skips" box in the footer turns it off if you would rather shift did nothing. The window is a little wider to fit it, which also gives item names more room.

# Stockpile 1.0.4

## Fixed
- Every character shared one list. Stockpile kept an account-wide copy of each character's items as a safety net, filed under the character name, but this client reports the player as "Unknown" at the moment addons load, so every character wrote into and read from the same drawer. Any character without a list of its own picked up whichever character had logged out last.
- The safety net is gone. Lists are per character and nothing else writes to them. The account-wide file the addon used to keep is no longer created, and an old one is ignored and can be deleted.

## If your characters ended up sharing a list
- Each character keeps whatever it is showing now, so trim each one once and it will stay put.

# Stockpile 1.0.3

## Fixed
- Want could not be set above 999. The box accepted a ceiling of 9999, but the Blizzard template it is built from limits typing to three characters, so the fourth digit was unreachable both by typing and by holding the arrows. The numeric ceiling and the character limit now come from the same number, so they cannot disagree again. Thanks to the user who reported it and pinned down the cause.

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
- Item icons with quality borders, quality-colored names and full tooltips
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
