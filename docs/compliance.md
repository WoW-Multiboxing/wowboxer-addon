# Compliance: what WoWBoxer automates, what it never does, and why

Policy: CLAUDE.md hard rules 1–6 and `docs/automation-policy.md` (the owner, 29 Oct 2026; confirmed 4 Nov 2026: "we can
automate anything except sending key strokes").

## Blizzard's line
Blizzard's multiboxing rules (news post Nov 2020, forum update May 2021, Support article 24258) say:
- Multiboxing is allowed.
- **Input broadcasting** is banned: software or hardware that sends one key press or click to several game clients.
- So is anything that plays the game for you without a key press. WoW enforces this itself: casting, targeting,
  moving, following and interacting with an NPC are **protected** or need a **hardware event**. An addon cannot do
  them without the player's own key press on that client.

Addons may use the rest of WoW's addon API. That includes accepting popups, choosing dialog options, selling,
repairing and addon-to-addon messages (`C_ChatInfo.SendAddonMessage`). Multibox addons (EMA, Jamba, MAMA, Multibox
Follower Helper) have done this for years.

## What WoWBoxer never does
- **No input broadcasting.** Nothing outside WoW sends keys or clicks to the game. WoWBoxer is an addon. It has no
  program that runs next to WoW and never talks to other windows. (The WoWBoxer window app places windows and sends
  no input either.)
- **One key press = one action on one character.**
  - Every **cast, target, move, follow and NPC interaction** comes from the player's own key press on that character.
  - WoWBoxer only builds the macros (`/cast`, `/assist`, `/follow` …) and the player presses them.
  - The addon never calls a protected or hardware-event function from a script (`CastSpell`, `TargetUnit`,
    `FollowUnit`, `InteractUnit` …) and never tries to get around those checks.
- **No hidden code.**
  - Imported strings and addon messages are data only. They are never run (`loadstring`/`RunScript` are banned and
    `tools/lint51.py` checks for them).
  - Macros never contain `/run`, `/script`, `/console` or `/click`.
- **No writes behind your back.** Macros, action bars, key bindings and settings change only after a click, and never
  in combat.
- **No strangers.** Every automation reacts only to the characters of your WoWBoxer squad, matched by name and in
  your party. The Accept-from setting can widen the accepts to friends and guild, or everyone after a warning.

## What WoWBoxer automates (Setup → Automation)
Only resurrection and summons are on before the player chooses; the presets (*Default squad values*, *Recommended*) turn
the others on in one click.
Each item is a named option with a one-line explanation and can be turned off. Holding **Shift** skips it once, and
every automatic action is logged.

| Option | What it does | On without a choice? |
|---|---|---|
| Accept invites | Accepts a group invite from a squad member. | no |
| Invite the squad | Leader: invites squad members who are not in the group. | no |
| Accept quests / Accept any quest | Accepts quests the leader has (or every quest) when the quest window opens. | no |
| Share quests | Leader: shares every quest you accept. | no |
| Turn in quests | Completes finished quests at the quest giver; picks the reward by rule (leader's choice, best vendor value, or ask). | no |
| Abandon together | When the leader abandons a quest: followers drop it too (Automatically), ask with Abandon / Keep it (Ask on every quest, the default) or keep it (Never). Never a completed quest. | ask |
| Follow dialogs | Picks the leader's dialog, quest or flight choice when the follower has the **same NPC window open**. The follower opened that NPC with their own key press. Never syncs logout, delete, unlearn and similar options, or flights over 2 gold. | no |
| Accept resurrection / summons | From squad members. | **yes** |
| Accept role checks | When the group leader is in your squad. | no |
| Sell junk, Repair, Restock reagents | At a merchant that window opened. Repair keeps a gold floor. | no |

Display only (never acted on): the team panel (level, mana, follow, target, combat), squad sync offers
(Review / Apply / Ignore, which act only on a click on that client), and the session card.

## Why this stays inside the rules
1. **The trigger is never an input sent to the game.** Everything above runs inside one client through WoW's normal
   addon API, the same as any quest or vendor addon a solo player uses.
2. **Playing still takes a key press per character.** Fighting, healing, moving, following and talking to NPCs all
   need the player on that window. Automation removes popups and menus. It never moves a character or casts a spell.
3. **The game's own protection holds.** WoW blocks protected calls from addons, and WoWBoxer does not try to get
   around that. When a client does not allow a call without a key press, the automation just does nothing.
   [AFKLAR: `InviteUnit`, `TakeTaxiNode` and `AcceptQuest` without a key press on Forever – checked in the launch test,
   probe results in the diagnose.]
4. **It is visible and optional.** Every automation is named, off for strangers, can be switched off, and is logged.
   The player texts (CurseForge, Wago, website, README) say plainly what it does.

## Kept for the record
On 4 Nov 2026 a request to strip cross-character automation (based on the older display-only note in
`01_Research/platform/04-addon.md` §4) was reviewed and **cancelled by the owner**. The older note is superseded by the 29
Oct policy.
