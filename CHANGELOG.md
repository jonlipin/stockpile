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
