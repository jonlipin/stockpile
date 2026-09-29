## 1.0.4

### Fixed
- Every character shared one list. Stockpile kept an account-wide copy of each character's items as a safety net, filed under the character name, but this client reports the player as "Unknown" at the moment addons load, so every character wrote into and read from the same drawer. Any character without a list of its own picked up whichever character had logged out last.
- The safety net is gone. Lists are per character and nothing else writes to them. The account-wide file the addon used to keep is no longer created, and an old one is ignored and can be deleted.

### If your characters ended up sharing a list
- Each character keeps whatever it is showing now, so trim each one once and it will stay put.
