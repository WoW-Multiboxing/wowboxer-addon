# Compliance review: which features make another character act (4 Nov 2026)

**Decision (the owner, 4 Nov 2026): the 29 Oct automation policy stands – "we can automate anything except sending key
strokes". Nothing below is removed.** X1–X10 stay as named, squad-only options in Setup → Automation (CLAUDE.md hard
rules 1 and 5, `docs/automation-policy.md`). The display-only rule in `01_Research/platform/04-addon.md` §4 is
superseded by that policy. This review stays as the inventory of which options act on another character's behalf,
so player texts can say so plainly.

## Why this review
A community member compared WoWBoxer with Mama-forever and listed as "already in WoWBoxer": accept/share/abandon
quests together, accept invites, follow dialogs (copying the leader's gossip, quest and flight choice), and accept
resurrection/summons on by default.

The question: does any feature let **one character's action, or an addon message, make another character act**?

Two documents disagree on the answer:

| Source | Says |
|---|---|
| `01_Research/platform/04-addon.md` §4 (Oct 2026) | Cross-client messages are for display only, never to trigger actions. Skip EMA-style auto-accept quests, auto-taxi and follow strobing. Reason: Blizzard bans "anything used to automate or streamline multiboxing in any way", and that wording is vague. |
| `docs/automation-policy.md` (the owner, 29 Oct 2026) and CLAUDE.md hard rules 1 + 5 today | Addon automation through WoW's normal API is allowed (accept, share, sync, sell, repair, loot, trade), for squad members only. Addon messages may trigger it. |

The request of 4 Nov goes back to the research rule. This review lists what that would change.

## The test
A feature is **per-window** (keep) when it acts only on the window where the player just did something themselves:
they opened that merchant, that quest giver, that NPC.

A feature is **cross-character** (remove, or turn into display / a click on that window) when the trigger comes from
outside this window. The trigger can be:
- another character's action (an invite, res, summon, quest share, role check, the leader's dialog pick);
- an addon message;
- a timer.

Using another client's data **only as a filter or display** (for example "the leader also has this quest") is not a
trigger.

## Inventory (`WoWBoxer/Auto.lua`; Sync.lua and Team.lua are display/offer only)

### Cross-character: another character or a message makes this one act

| # | Option (key) | Default | Trigger → action on this character | Proposal |
|---|---|---|---|---|
| X1 | Follow dialogs (`dialog`) | on in preset + recommended | Leader picks gossip / quest from list / **flight** → message `D` → follower calls `SelectOption` / `SelectAvailableQuest` / **`TakeTaxiNode`** (the follower flies) | **Remove the action.** Display only: the follower's open NPC window highlights the leader's pick ("Leader picked: Ironforge"); the player clicks it. |
| X2 | Abandon together (`abandon`) | off | Leader abandons → message `QA` → follower `AbandonQuest` | **Remove.** Replace with a chat line on the follower: "Leader abandoned X". |
| X3 | Turn in quests, reward rule "leader's choice" (`turnin` + `autoReward=leader`) | turn-in on in preset | Leader takes a reward → message `QR` → follower `GetQuestReward(i)` | **Remove the message trigger.** The follower's reward window shows "Leader took: X"; the player clicks. The rule "best vendor value" stays (per-window). |
| X4 | Accept quests (`quests`), quest **shared** by another player | on in preset | Leader's share pops up `QUEST_DETAIL` on the follower → `AcceptQuest` | **Remove for shares** (detect: `UnitIsPlayer("npc")`). Keep it when this window opened the quest giver itself (P2). |
| X5 | Accept quests, escort / group start (`QUEST_ACCEPT_CONFIRM`) | on in preset | Another player starts an escort → `ConfirmAcceptQuest` | **Remove.** |
| X6 | Accept invites (`invite`) | on in preset | Another player invites → `AcceptGroup` | **Remove.** Blizzard's popup stays; the player clicks Accept. Optional: flash/sound "Invite from squad member X". |
| X7 | Invite the squad (`autoInvite`) | on in recommended | **30 s timer**, no key press → `InviteUnit` | **Remove.** The existing Invite key (one press = one invite round) stays. |
| X8 | Accept resurrection (`res`) | **on by default** | Another player casts a res → `AcceptResurrect` | **Remove.** |
| X9 | Accept summons (`summon`) | **on by default** | Another player summons → `ConfirmSummon` (this character teleports) | **Remove.** |
| X10 | Accept role checks (`rolecheck`) | on in preset | Group leader queues → `CompleteLFGRoleCheck` | **Remove.** |

### Per-window: acts only where the player did something on this window (keep)

| # | Option | What it does |
|---|---|---|
| P1 | Turn in quests (`turnin`) | This window opened the quest giver → `CompleteQuest`; reward when there is one choice or by "best vendor value". |
| P2 | Accept quests (`quests` / `questAny`) at a quest giver **this window opened** | `AcceptQuest`. The leader's quest list (message `QL`) is only a filter: no message, no accept. |
| P3 | Share quests (`share`) | The leader accepts a quest with their own click; their own client then shares it. Followers get Blizzard's normal popup and click it (after X4). |
| P4 | Sell junk (`sell`) + sell list | This window opened a merchant → sells its own greys / list items. |
| P5 | Repair (`repair`) | Same merchant, with a gold floor. |
| P6 | Restock reagents (`restock`) | Same merchant. |
| P7 | Chat line (`chat`) | Display. |

### Display / offer only (no change)
- **Team panel** (`Team.lua`, prefix `WBX1`): level, mana, follow, target, combat – shown, never acted on.
- **Squad sync** (`Sync.lua`): squad, preset and guide offers show *Review / Apply / Ignore*. Only the click on that
  client changes anything.
- The session card after login.

## What removing X1–X10 would have touched (not done)
- `Auto.lua`:
  - drop the handlers and the `D`, `QA` and `QR` message kinds (`QL` stays, as a filter);
  - drop the timer;
  - add the `UnitIsPlayer("npc")` share check.
- Setup → Automation:
  - remove the options;
  - remove the "Accept from" choice (it only serves the accepts);
  - update the "Default squad values" preset, the recommended set and the login nudge text.
- Saved data: the old option keys stay in `WoWBoxerDB` untouched but are ignored (`tests/test_savedvars.lua` must
  still pass). Share strings: `AU.import` already drops unknown keys.
- Tests: `tests/test_auto.lua` (most of it).
- Player texts:
  - CurseForge and Wago description ("automates invites, quests, dialogs …");
  - in-game help;
  - README;
  - wowboxer.com/addon/ and the guides (workstream F/D).
- CLAUDE.md hard rules 1 and 5 go back to: "cross-client messages are data for display; they never make a character
  act", and `docs/automation-policy.md` gets a superseded note.

## Reasoning for the rejected proposal (kept for the record)
- Blizzard's line is input broadcasting. The vaguer "anything used to automate or streamline multiboxing" is where
  X1–X10 sit: one player action fans out into actions on several characters. "One key press = one action on one
  character" is only true if the addon does not add actions on top.
- Per-window conveniences (P1–P6) behave like any solo-player addon (auto-sell, auto-repair, quest auto-accept at an
  NPC you opened). They don't depend on having other characters.
- Display and offers keep most of the value (you see what the leader did; one click on that window does it) without
  the fan-out.
