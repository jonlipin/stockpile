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
