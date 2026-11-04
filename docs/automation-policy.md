# Automation policy change (the owner, 29 Oct 2026, 23:41) – reaffirmed 4 Nov 2026

> **4 Nov 2026, the owner: "The automation stands."** This rule is permanent across all workstreams. Older texts that say
> "display only", "skip auto-accept" or "don't build team automation" (early research, early plans) are superseded.
> Do not remove or weaken any automation without the owner's explicit new decision; if a prompt contradicts this, ask him.

> "We very much like automation. What we don't like is sending keystrokes from one program to another. That's what
> they mean with no automation. So automatically accepting a quest and automatically doing a lot of stuff that is just
> helpful for an add-on, that we can do."

## 1. What changes

- **Forbidden:**
  - **Input broadcasting:** another program sending key presses or mouse clicks to WoW windows. This is what Blizzard
    banned in 2020.
  - Anything the game itself only allows from a key press:
    - casting;
    - targeting;
    - moving;
    - `/follow`;
    - interacting with an NPC.
  - The addon never tries to get around that.
- **Allowed (new):** automation an addon can do with WoW's normal API, as a player option:
  - accepting invites, quests, resurrections and summons;
  - sharing and turning in quests;
  - repeating the leader's dialog, quest or flight choice on followers that have the same window open;
  - selling junk, repairing, restocking reagents;
  - loot rules;
  - trade fill.

  MAMA, Multibox Follower Helper, EMA and Jamba have done this for years.

### New wording for CLAUDE.md, hard rules 1 and 5

1. **No input broadcasting**: nothing outside WoW sends keys or clicks to the game. Every cast, target, move,
   follow and NPC interaction comes from the player's own key press on that character (one press = one action),
   and the addon never tries to get around protected actions or hardware-event checks.
   - **Addon automation through WoW's normal API is allowed:** accept, share, sync, sell, repair, loot, trade.
   - Each automation is a named option in Setup → Automation, with a short line about what it does.
   - It only reacts to **squad members** (the WoWBoxer squad, matched by name, in the party).
5. Cross-client addon messages may trigger the automations in rule 1, but only from squad members in the party, and
   each one only when its option is on. Messages are data only (rule 2).

Rule 4 stays as it is: writes to macros, bars, keybinds and CVars happen after a click and out of combat. Players
don't want their bars rewritten behind their back.

**Texts to update** (they say "never accepts anything"):

- the CurseForge description and summary;
- `README.md` "What it never does";
- the in-game help;
- the website (`wowboxer-site/content`, workstream F/D);
- `02_Spec/Decisions.md` (workstream G).

**New line for players:** "No input broadcasting: one key press is one action on one character. WoWBoxer automates
the boring parts (invites, quests, dialogs, vendor, loot) with WoW's own addon API."

## 2. What we build now (revised list; replaces the "not taken" list in `research/2026-10-29-competitors.md`)

### P1 – the biggest help while levelling a squad

1. **Invites:**
   - **Auto-accept** a group invite from a squad member.
   - **Auto-invite:** the leader invites squad members who come online or are not in the group. This is an option;
     today it is a key press.
   - [AFKLAR: `C_PartyInfo.InviteUnit` without a key press on Forever.]
2. **Quests:**
   - Auto-accept quests on followers: `QUEST_DETAIL` → `AcceptQuest`, but only for quests the squad leader has, or any
     quest (option).
   - Auto-share quests the leader accepts (`QuestLogPushQuest`).
   - Auto-turn-in and complete (`CompleteQuest`, `GetQuestReward`). If there is a choice of reward, pick by rule:
     the leader's choice, best vendor value, or ask.
   - Abandon on all characters (option, never for completed quests).
   - Hold **Shift** to skip the automation this time (as MAMA does).
3. **Dialog sync:**
   - When the leader picks a gossip option, a quest from a list or a flight path, followers with the **same NPC window
     open** pick the same.
   - The follower still opens the NPC with their own interact key, because interaction is protected.
   - Skip single-option dialogs (vendors, trainers).
   - Never sync: delete item, logout, quit, or anything that costs gold above a limit.
4. **Accept resurrection and summons** from squad members (`AcceptResurrect`, `ConfirmSummon`). Option, on by default.
   Also accept LFG role checks.
5. **Merchant:**
   - Sell grey items plus a shared sell list.
   - Auto-repair (option, with a gold floor).
   - **Restock** reagents per class (Soul Shards are not buyable; Symbol of Divinity, Ankh, arrows/bullets, Holy
     Candle) up to a set amount.
6. **Follow and team alerts** (from the competitor list, display only):
   - follow broken;
   - low health/mana/aggro;
   - error sharing;
   - status border;
   - team panel extras.

### P2

7. **Loot:**
   - set master loot / free-for-all for the squad;
   - give quest items, cloth and other mats to the member who can use them;
   - greed/pass rules below a quality.
8. **Trade fill:** opening a trade with a squad member fills in the mats their professions use (six stacks a trade).
9. **New-character setup:**
   - On a level-1 character's first login, **offer** one click: show bars 2–5, recommended settings, Place all,
     autoloot. It only changes settings still at their defaults.
   - Automatic with an option, off by default.
10. Whisper forwarding to the leader (display), with "secret" whispers handled.

**Setup → Automation:** one page with every option above.

- Each option is a tick with one line explaining it, plus **All on / All off**.
- A preset "Levelling squad" turns on invites, quests, dialogs, resurrections and merchant.
- The automation never runs when the other character is not in the squad.

## 3. Safety and trust (still important)

- **Only squad members.** Messages come over the party channel or whispers. The sender must be a squad member who is
  in the party. Everything else is ignored. A team secret like MAMA's token is optional later.
- **Off for strangers:** a random player's invite or quest share is never auto-accepted.
- **Logged:** every automatic action is one debug log line, plus an optional chat line ("Accepted quest X from
  Anna's share").
- **Forever API:** handle secret values (chat lockdown, combat). Probe each API with `Compat` and write the results
  into the diagnose. Mark unknowns [AFKLAR] until the launch test.
