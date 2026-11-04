# Security policy

## Reporting a vulnerability
Please **do not open a public issue** for a security problem. Report it privately through
[GitHub's private vulnerability reporting](https://github.com/WoW-Multiboxing/wowboxer-addon/security/advisories/new).
You get an answer within a few days.

Examples of what counts:
- a share string or an addon message that makes WoWBoxer run code;
- a macro body that gets past the slash-command allow-list (`/run`, `/script`, `/console`, `/click`);
- a way for a player outside your squad to trigger an automation;
- anything that sends input to the game, or calls a protected function without a key press.

## Supported versions
Only the latest release on CurseForge, Wago and GitHub Releases gets fixes.

## What WoWBoxer handles
WoWBoxer runs inside World of Warcraft's addon sandbox. It has no network access beyond WoW's own addon messages
between your characters, and it stores data only in WoW's SavedVariables (`WoWBoxerDB`, `WoWBoxerCharDB`).
`/wbx report` leaves out character and realm names unless you tick the box.
