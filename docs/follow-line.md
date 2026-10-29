# Follow in a line (the owner, 29 Oct 2026, 20:51)

Goal: by default, followers follow in a **line**. Follower 1 follows the leader, follower 2 follows follower 1, and so
on. A second key keeps the old behaviour where everyone follows the leader. Both keys exist; the line is the default.

## 1. The two keys (followers only; the leader gets neither)

| Key | Macro name | Label in the book | Body |
|---|---|---|---|
| `Follow` (main bar slot 11, as today) | `WBX Follow` | **Follow (line)** | `/follow <party unit of the member ahead>` |
| `FollowL` (new) | `WBX FollowLead` | **Follow leader** | `/follow <unit>` – exactly today's body (`u.main`: party1–4 or focus) |

- **Ahead in the line** = the previous member in squad order: the leader first, then the followers in the order the
  Squad page shows. For the first follower, the member ahead is the leader, so both keys follow the leader.
- **Decision (the owner, 20:57): both keys use party units (party1–4), never names.** Only Invite uses names, as in
  `squad-v2-simple.md`.
- **Party slots are per client.** On follower 2, follower 1 may be party2, while on follower 3, follower 2 may be
  party1. So the addon works out the line unit for this character itself:
  - Store it as `m.lineUnit`, next to `m.unit`, which is used for the leader.
  - When grouped, `Squad.unitOf(<name of member ahead>)` gives the slot. Save it to `m.lineUnit` only after a click
    (Update / Place / the checklist Fix), never on its own.
  - Not grouped, or the member ahead isn't found: keep the last saved `m.lineUnit`. If none is saved, use `m.unit`
    (follow the leader) and say so in the checklist.
  - The first follower: `m.lineUnit` = `m.unit`.
- The party changes and the member ahead is now in another slot: `WBX Follow` shows as "to update", and the checklist
  says "Bo is now party2 – Fix: Use party2". This is the same pattern as today's leader unit hint, `Squad.unitHint`.
  The Fix changes only WoWBoxer data; the macro is rewritten after the usual click, out of combat.
- Focus users: Follow leader stays `/follow focus`. Follow (line) still uses the party unit of the member ahead.
- `/follow` is already whitelisted. Bodies stay far under 255 chars. Names ≤ 16 chars with the `WBX` prefix.
- The share string / Sync must not carry `lineUnit`: it is per client. Recompute it on each client.

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

- Follower checklist: "Follow (line): you follow Bo (party2)." If Bo is not in the party on this client: "Bo is not in
  your party – Follow (line) follows the last known slot; use Follow leader." The only Fix is "Use partyN", which
  changes WoWBoxer data, never the game.
- Help "?" on the Squad page: two sentences about line vs leader. Line: fewer bodies stuck in doorways and an easier
  trail through narrow paths. Leader: everyone stays close to the leader.

## 5. Tests and the companion

- Tests:
  - leader: no follow keys;
  - follower 1: both bodies follow the leader;
  - follower 2: follows follower 1's party unit as seen from follower 2's client;
  - a party reshuffle gives "to update" plus the Fix;
  - no party falls back to the saved slot, then to the leader;
  - reordering changes the line;
  - unticked key is not created;
  - placement: slot 11 + secondary;
  - no names in either body.
- Rule 6 in CLAUDE.md: the web companion should give the same two keys.
  - `K.helpers` is not covered by the parity vectors, so the addon can go first.
  - Add a handover note for workstream A in LOG.md / 00_Workstreams.md row A: "Companion: Follow (line) + Follow
    leader, see wowboxer-addon docs/follow-line.md".
