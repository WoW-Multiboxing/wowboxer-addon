# Feedback 2026-10-29 20:39 (the owner, after testing the new squad + book)

"It looks a lot better." Four changes:

## 1. Recommended settings
- **Sticky targeting:** recommend Blizzard's normal behaviour, `deselectOnClick = 1` (clicking empty ground clears the
  target), for leader and followers. WoWBoxer's keys use macros (mouseover / leader's target), so sticky targeting is
  not needed and is annoying. Today `Rules.CVARS` recommends `0`. Update the label/why text to match
  ("Clear target on click" – On).
- **Nameplates:** recommend showing **enemy nameplates** and **friendly nameplates** (`nameplateShowEnemies = 1`,
  `nameplateShowFriends = 1`), plus the **personal nameplate / your own** where the client has it
  (`nameplateShowSelf` – modern UI; probe).
- **Cast bars for friends/allies:** recommend showing cast bars on friendly nameplates / party frames where the client
  has a setting for it. The CVar names differ per client and are not verified [AFKLAR]: probe on both clients
  (search `C_CVar.GetCVarInfo` / the console's CVar list for names containing `nameplate` + `cast`, and party/raid
  frame cast bar options), log what exists in the diagnose, and only list CVars that exist. Missing ones stay hidden.
- All of these go through the existing allow-list with backup + Restore.

## 2. "Place all" on both pages
Keep the one-click button that puts every key on the action bars – and give **each page its own**: left page
(Spells + Sequences) **Place spells**, right page (Squad keys / helpers) **Place squad keys**. Same rules as today
(empty or own buttons only unless Replace; fly animation; never in combat; skips "Keep off my bars" keys).

## 3. Bind key is broken
Binding a key reports "4 already does ACTIONBUTTON4" although nothing is wrong: key 4 is simply the key of action
button 4 (the default bar). Fix the flow:
- If the chosen key belongs to an **action button** (`ACTIONBUTTONn`, `MULTIACTIONBAR…BUTTONn`):
  - the button already holds **this** WBX key → "Already on 4" (nothing to do);
  - the button is **empty** → put the key on that button (PickupMacro + PlaceAction, out of combat) instead of
    rebinding – one click, no warning;
  - the button holds **something else** → plain question: "4 is action button 4 (Shadow Bolt). Put this key there?"
    [Put it there] [Use another key]. Never show raw command names like ACTIONBUTTON4.
- If the key does something else (a game function, another macro) → "4 opens the bags. Use it anyway?" with the game's
  own binding name (`GetBindingText`) and Yes/No; only then `SetBindingMacro` + `SaveBindings(2)`.
- Unbound key → bind directly, no question.
- Tests: all four cases, plain text only, and a regression test for "key of an empty action button".

## 4. Release
Ship it live as the next version (changelog for players, tag, CurseForge upload checked).
