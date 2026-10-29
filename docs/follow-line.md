# Follow in a line (the owner, 29 Oct 2026, 20:51)

Goal: by default, followers follow in a **line**. Follower 1 follows the leader, follower 2 follows follower 1, and so
on. A second key keeps the old behaviour where everyone follows the leader. Both keys exist; the line is the default.

## 1. The two keys (followers only; the leader gets neither)

| Key | Macro name | Label in the book | Body |
|---|---|---|---|
| `Follow` (main bar slot 11, as today) | `WBX Follow` | **Follow (line)** | `/follow <Name of the member ahead>` |
| `FollowL` (new) | `WBX FollowLead` | **Follow leader** | `/follow <unit>` – exactly today's body (`u.main`: party1–4 or focus) |

- **Ahead in the line** = the previous member in squad order, counting the leader first and then the followers in the
  order the Squad page shows. The first follower's "member ahead" is the leader, so both keys follow the leader.
- **The line key uses the name, not a party unit.** party1–4 differ on every client and move when people join or
  leave, so a unit would point at the wrong member. Use `Name` (or `Name-Realm` when the realm is known and differs).
  This extends the decision in `squad-v2-simple.md` (only Invite uses names): **Invite and Follow (line) use names.
  Follow leader, Assist, Target, Focus and the pet keys stay on party units.**
- `/follow` is already whitelisted. Bodies stay far under 255 chars. Names ≤ 16 chars with the `WBX` prefix.
- [AFKLAR: check on both clients that `/follow Name` follows a party member by name. If it does not, use the
  member ahead's party unit from `Squad.unitOf(name)` when the macros are built, rebuild when the party changes, and
  write the result in the diagnose.]

## 2. Squad page

- One line under the member list: **Line: Leader → Anna → Bo → Cid** (the real names), with this tip: "Follow (line) on
  each character follows the one before it. Change the order with the arrows; your keys update."
- Reordering members (the arrows that already exist) changes the line. The affected followers' `WBX Follow` show as
  "to update", as on level-up. Never update outside combat or without a click, as today.
- Squad keys list: **Follow (line)** and **Follow leader** are separate tick boxes, both ticked by default. If you
  untick one, the macro is still not created and the slot stays free.

## 3. Bars

- `Follow` keeps primary slot 11 (muscle memory). `FollowL` goes on the secondary bar's first free slot, then into the
  extras, using the same rules as other keys ("Keep off my bars" respected).
- Existing users: their current `WBX Follow` (body `/follow party1`) gets the new body after their next click on
  Update/Place. The changelog says that the old behaviour is now the **Follow leader** key.

## 4. Checklist / help (display only)

- Follower checklist: "Follow (line): you follow Bo." If Bo is not in the party on this client: "Bo is not in your
  party – Follow (line) will not work; use Follow leader." No Fix button: nothing is automated.
- Help "?" on the Squad page: two sentences about line vs leader. Line: fewer bodies stuck in doorways and an easier
  trail through narrow paths. Leader: everyone stays close to the leader.

## 5. Tests and the companion

- Tests:
  - leader: no follow keys;
  - follower 1: both bodies follow the leader;
  - follower 2: follows follower 1 by name;
  - reordering changes the bodies;
  - realm suffix;
  - unticked key is not created;
  - placement: slot 11 + secondary.
- Rule 6 in CLAUDE.md: the web companion should give the same two keys.
  - `K.helpers` is not covered by the parity vectors, so the addon can go first.
  - Add a handover note for workstream A in LOG.md / 00_Workstreams.md row A: "Companion: Follow (line) + Follow
    leader, see wowboxer-addon docs/follow-line.md".
