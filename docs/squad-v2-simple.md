# Squad v2 – simple (the owner, 2026-10-29 19:48)

Supersedes the Squad parts of `docs/squad-overhaul.md` where they differ. The owner after testing:
- "Not very intuitive what it does and how to do it." Too many buttons.
- How do I add my party? How do I add characters that are **not** in my party?
- "If I make a party, how do I confirm it?"
- "I added my party, then took a template, and my party got removed. I don't know what templates do."
- At login it says keys are not on your action bar **every time** – needs a "Don't show again" that is remembered.
- Follow / invite macros must be **visible** (not appear out of nowhere) and **linked to the squad** – especially invite.

## 1. What went wrong (from the code)
- **Templates create a new squad and switch to it** (`S.fromTemplate` + active squad change). The party squad still
  exists but is no longer shown, so it looks deleted. → Remove templates (low value, high confusion).
- There is no visible "save": edits are saved instantly but nothing says so, so players look for a confirm button.
- The Squad bookmark opens on Home with 6+ buttons (Edit squad, Send squad, Readiness, Save preset, preset dropdown,
  sub-page buttons) before the player has a squad at all.
- The login reminder (`Core.checkOffer("login")`) fires every session while anything is pending – including keys the
  player deliberately keeps off his bars (own keys, extras). `lastOffer` is session-only.
- Helper keys (Follow, Assist, Focus, Pet) are generated from the squad role but appear in the book without the player
  ever choosing them; there is no Invite key at all.

## 2. The new Squad page – one screen, one job
```
 SQUAD: Undead trio                                   [Rename]  Saved ✓
 ┌───────────────────────────────────────────────────────────────────┐
 │ 👑 Dorin      Paladin · Tank      Leader          This character   │
 │    Wow2       Priest  · Healer    follows Dorin          [x]      │
 │    Kirra      Warlock · Ranged    follows Dorin          [x]      │
 │  + Add character   [ name ______ ] [Class ▾] [Add]                 │
 └───────────────────────────────────────────────────────────────────┘
 [Add my party (2)]                         [Send to my other characters]
 Squad keys:  Invite squad ✓   Follow ✓   Assist ✓        (on your bars)
```
- **Empty state** (no squad / solo): one sentence + two big buttons: **Use my party** (shown when grouped; count in
  the label) and **Add by name**. Nothing else.
- **Rows**: name (class colour), class · role (role dropdown on click), "Leader" or "follows <leader>", remove [x].
  Click the crown column to make someone leader. "This character" tag on your own row. Click a row = small inline editor
  (name, class, race, role, sequence) – no separate Edit page.
- **Add by name** (characters not in your party): name box + class dropdown + Add (race defaults to the first valid
  race, editable later). If that character later appears in your party, WoWBoxer fills in race/level automatically.
  If another client running WoWBoxer is in your party but not in the squad, show a one-line suggestion
  "Wow2 (Priest) is in your party – Add" (display + click on this client).
- **No confirm button: changes save immediately**, with a "Saved ✓" tick that flashes after each change. The one
  explicit action is **Send to my other characters** (the existing offer: they Review/Import).
- **Templates: removed.** Leader presets, tags, notes, key map, plan, readiness move under a small **More ▾** menu
  (Readiness can stay as a status line: "2/3 ready – show").
- Multiple squads stay possible but out of the way: squad name is a dropdown with "New squad…" / "Delete squad…" at the
  bottom. Switching never happens as a side effect.
- Squad guide ("?") becomes 3 steps: Add your characters → Pick the leader → Send to your other characters (then
  Place all on each).

## 3. Squad keys – visible and tied to the squad
A short section on the Squad page **and** a "Squad keys" section on the right page of My keys, each with a tick box,
so the player chooses them and sees them:
| Key | Who gets it | Macro (built from the squad, rebuilt when the squad changes) |
|---|---|---|
| **Invite squad** | leader (any character can tick it) | `/invite Wow2` + `/invite Kirra` … one line per other member (≤255 chars; split into "Invite 2" if needed) |
| **Follow** | followers | `/follow party1` (the member's unit, as today) |
| **Assist** | followers | `/assist party1` |
| **Target leader** | followers (off by default) | `/target party1` |
| **Focus leader** | followers using focus | `/focus [@target,help,nodead]` (as today) |
| Pet attack / Pet back | pet classes | as today |
- **Decision (the owner, 19:51): only Invite uses names.** (20:57: Follow (line) also stays on party units – see `follow-line.md`.) Follow, Assist, Target and all spell keys stay on party units
  (party1–4 / focus), exactly as today. Invite uses `Name-Realm` when the member is on another realm.
- `/invite` must be added to `Rules.SLASH_WHITELIST` (`/target` is already there) (`/invite` is a normal chat command; one press sends
  the invites, the other characters still accept by hand – **never auto-accept**).
- Spell keys keep the unit-based conditions (`[@party1target…]`) – the companion's rules and parity tests stay.
- Default ticks: leader → Invite squad on; followers → Follow + Assist on. Unticked squad keys are not created.

## 4. Login / level-up reminders that respect the player
- The login check only reminds about **real changes** (a key whose macro text changed, or a new key), never about keys
  the player has chosen to keep off his bars.
- Per key: right-click → **Keep off my bars** (stored per character; the key is then never counted as "not on a bar").
  Own/custom keys and extras are "keep off bars" by default until the player drags or places them once.
- The toast/banner gets a **Don't show again** tick box: stores the current pending signature per character
  (`cdb.offerSeen`), so the same pending state never shows again after a reload; a *new* change (level-up, new spell)
  shows again. Setup gets "Level-up reminders: On / Off" (off = never toast; the book still shows the orange dots).
- No chat spam at login: at most one line, and only when there is a new change.

## 5. Tests
- Squad: add by name, add my party, remove, leader change, rename – all saved without a confirm; no action switches the
  active squad as a side effect; templates gone.
- Squad keys: invite macro lists the other members (realm suffix when needed), rebuilds after add/remove/rename, stays
  ≤255 (split), passes the whitelist; follow/assist/target keep the member's party unit.
- Reminders: "Don't show again" survives a simulated reload; a new level-up shows again; "Keep off my bars" keys never
  trigger the reminder; login with nothing new writes no chat line.
- Copy budgets and the resolution/overlap matrix stay green.
