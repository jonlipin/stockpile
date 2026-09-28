## 1.0.3

### Fixed
- Want could not be set above 999. The box accepted a ceiling of 9999, but the Blizzard template it is built from limits typing to three characters, so the fourth digit was unreachable both by typing and by holding the arrows. The numeric ceiling and the character limit now come from the same number, so they cannot disagree again. Thanks to the user who reported it and pinned down the cause.
