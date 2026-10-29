# Competitors on CurseForge + why WoWBoxer is not found for "multibox" (29 Oct 2026)

## 1. Search: why "multibox" does not find WoWBoxer

- **The CurseForge app with the Forever filter, searching "multibox",** shows 2 projects: MAMA and Multibox Follower
  Helper (the owner's screenshot).
- **The website, searching "multibox",** shows 7 projects. All of them have "Multibox", "Multi…" or "MultiBar" in
  the **name**. WoWBoxer is not among them.
- **The website, searching "multiboxing",** shows 11 projects. WoWBoxer is #8, because its **summary** contains the
  word "Multiboxing".
- **Conclusion:** the search matches whole words in the name and the summary. "multibox" does not match
  "Multiboxing", and the name "WoWBoxer" contains neither word.

**Fix (the owner, CurseForge project settings; the slug `wowboxer` stays the same):**

- **Name:** `WoWBoxer - Multibox Companion`. Hydra uses the same pattern: "Hydra - Multibox Leveling Helper".
- **Summary:** `Multibox companion for WoW Forever and Classic: multiboxing macros, sequences, follow line and talents for every character. No broadcasting.`
- The first line of the description should also use multibox, multiboxing, dual box and multi-boxing once each.
- Check afterwards: search "multibox", "multiboxing", "dual box" and "wowboxer" on the website and in the app with the
  Forever filter.
- The TOC `## Title` can stay "WoWBoxer". The in-game list does not affect the CurseForge search.

## 2. The competitors

| Addon | Downloads | Forever | What it is | Automation? |
|---|---|---|---|---|
| **MAMA** (MooreaTV, LGPLv3, open source) | 62.8K | yes, main target, updated 25 Oct | Team slots + secret token; follow/assist macro that follows the current lead; follow train; auto-accept invites and quests; **mirrors gossip/flight paths/popups** to all windows; trade fill; vendor sell list; master loot; follow-broken alerts; whisper forwarding; status window (bags, gold, away); first-login setup (bars, keys, autoloot) | **Lots** |
| **Multibox Follower Helper** (Zensunim) | 23.2K | yes | Auto quest share/accept/complete, auto leave group, auto role accept; **sounds** when followers start/stop following or are low on health/mana; error watch | Yes (quests, group) |
| **Hydra** (Phanx) | 38.4K | no (7.0.3) | Old leveling helper | Yes |
| **EMA / DynamicBoxer / GSE-MultiboxMacros** | – | no / partly | Team management (EMA, DynamicBoxer); GnomeSequencer macro packs | Yes / GSE |
| **BoxTrack** | 26 | no (Era/HC) | "Multiboxing Companion": `/bt genmacro` macro templates; smart bars; buff/CC/totem timers; lost-follow and off-target warnings; party panel (health, XP, durability, gold, professions); auto-sell/repair; setup wizard per role pair; profiles as strings | Some (economy) |
| **MB Assist** (Soninox) | 81 | yes, updated today | "Visual helper for manual multiboxing – no broadcasting or automation":
- **status borders** around each follower window (following, low HP/aggro, low mana, casting, same target);
- **full-size quest/NPC windows** for small follower windows;
- big HP/mana bars;
- control bar (invite, mute client, window size);
- big error text;
- bags-full and totem reminders.
German only. | **No** – closest to WoWBoxer |
| **FollowLock** | 56 | no | Locks movement keys while auto-following; follow/unfollow text and sound on both screens | Touches bindings |

**Positioning:**

- MAMA and Multibox Follower Helper win on convenience, but they automate a lot: quests, dialogs, invites and trades.
- WoWBoxer's line: **the right macros for every character + no automation.** Only MB Assist is in the same "manual"
  space, and it is German-only with 81 downloads.
- The description should say plainly what we do instead of mirroring dialogs: "one press, one action, so it stays
  within Blizzard's multiboxing rules".

## 3. What WoWBoxer can take (all display-only or one click, inside the hard rules)

**P1, small and high value. These extend the Team panel (display only, rule 5).**

1. **Follow-broken alert on the leader.**
   - A follower's `AUTOFOLLOW_END` out of combat → an addon message → the leader's screen shows a big
     "Bo stopped following" plus an optional sound.
   - Optionally also on the follower's own screen.
   - Source: MAMA, Multibox Follower Helper, FollowLock, BoxTrack.
2. **Low health / low mana / aggro cues for followers.** A sound and a colour on the leader's Team panel; thresholds
   in Setup. Source: Multibox Follower Helper, BoxTrack.
3. **Status border on each window.** A thin coloured frame at the screen edge of each client:
   - green = following;
   - red = low health / aggro;
   - blue = low mana;
   - yellow = not on the leader's target.
   - It is the best "glance" signal with 3–5 small windows, and fits the window app (C). Source: MB Assist.
4. **Team panel extras:** free bag slots, durability %, gold, "away", and an off-target warning. Source: MAMA, BoxTrack.

**P2.**

5. **Whispers to followers shown on the leader** (display only): "[Bo] whisper from X: …", GM whispers in red.
   Source: MAMA.
6. **Big quest/NPC text for small windows:** an option to scale the quest, gossip and merchant frames on follower
   clients. Only a picture; you still click. Source: MB Assist.
7. **Reminders:**
   - bags nearly full;
   - durability low;
   - missing self-buff, missing weapon enchant (poison, Windfury) and missing totem, as small icons;
   - reagents low (Soul Shards, Symbol of Divinity).
   - Source: BoxTrack, MB Assist.
8. **Mute this client** button (one click, `Sound_EnableAllSound`, backup/restore like the other CVars). Source: MB
   Assist.
9. **New character setup in one click.** On a level-1 character, one button runs Place all + recommended settings +
   squad macros, with a summary. Source: MAMA's first-login setup, but on a click instead of automatically.

**Not taken (breaks hard rule 1):**

- auto-accept of quests and invites;
- mirroring dialogs, flight paths or popups;
- trade fill and auto-sell/auto-repair (a click-to-sell junk button could be OK later);
- master-loot assignment;
- movement-key locking (writes bindings automatically).

## 4. Order

- Do the CurseForge name and summary now (the owner, 2 minutes).
- After launch, build P1 1–4 as one "Team alerts" release, then P2.
- Keep the feature freeze before 5 Nov.

## 5. Inside the code (the owner's zips: MAMA v2.12.2 LGPLv3, Multibox Follower Helper 3.0.1 All Rights Reserved)

We take **ideas only**. We do not copy code: MAMA is LGPLv3 and WoWBoxer is MIT, and MFH is All Rights Reserved.

**Forever facts found in MAMA's code (useful for our [AFKLAR] list):**

- **Forever is interface 16001.** MFH ships a `_Camelot.toc`; MAMA has `## Interface: 16001, 120105`.
- **`/follow Name` and `/assist Name` work on Forever** from an action-bar macro. `/click Button` from a macro does
  nothing on Forever, but a CLICK keybind works. This closes the open question in `follow-line.md` (we use party
  units anyway).
- **Forever has these APIs:** `C_SpellBook.IsSpellKnown`, `Settings.GetSetting("PROXY_SHOW_ACTIONBAR_2..5")` (turn
  bars 2–5 on through the Settings proxies), `Constants.MacroConsts.MAX_ACCOUNT_MACROS`, and `C_CVar`.
- **Whispers can arrive "secret" (chat lockdown) on Forever.** MAMA forwards "a whisper we can't read" in that case.
  Our team messages must handle secret values too: `issecretvalue`, as already probed in `Compat`.

**How MAMA's follow-broken alert avoids false alarms (copy the idea):**

- **When a follower warns:**
  - `AUTOFOLLOW_END` out of combat starts a 1 s ticker for up to 10 s.
  - It warns only if the lead is then out of follow range (`CheckInteractDistance(unit, 4)`) and we did not start
    following again.
  - A `/follow` that didn't start within 1 s (detected by hooking `FollowUnit`) also warns.
- **When it stays quiet:**
  - in combat, within 5 s after combat, or while casting;
  - when the lead was not seen in the last 120 s;
  - when the lead or the follower is dead, a ghost or on a taxi;
  - at most once per 15 s per window.
- **On the lead's side:** drop warnings for 20 s after a loading screen, landing, release or resurrection. Then a raid
  warning + sound.

**MFH ideas:**

- **Its own short sounds** (follow on/off, low health/mana/no mana, mount on/off) on the **Master** channel, so they
  are heard while other sounds are off.
- **Followers' `UI_ERROR_MESSAGE` sent to the master** ("error sharing"): the leader sees "Bo: Out of range" /
  "Bo: Not enough mana". Display only, and very useful for spotting a follower that is not casting.
- **Mount on/off cue:** the leader hears when a follower mounts or dismounts.

**Added to §3:**

- **P1 #5:** error sharing (followers' red error text shown on the leader, rate-limited).
- **P2 #10:** mount/dismount cue.
- **P2 #11:** "Show action bars 2–5" in Setup, one click through the Settings proxies, because Place all uses Bottom
  Left/Right and those bars are hidden on a new character.
