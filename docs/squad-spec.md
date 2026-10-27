# Squad + sequence spec (the owner, 2026-10-27 20:34)

The owner: "make an extensive prompt to work further with the squad capabilities"; "the sequencing must be a tick on/off
and a drop-down between Simple, Medium and Advanced"; "make it clear which spells are sequences and which are not";
"is there a way to have icons that are combined icons of the spells used for sequences?"
Builds on what exists: Squad tab with Edit, Team status (`Team.lua`, `UI/TeamFrame.lua`, display only), share string,
checklist with "Use partyN" fix, solo squad, the spellbook window (`UI/Book.lua`).

## A. The core problem the squad must solve
Every client is normally its own WoW account, so every client has its **own SavedVariables**. Today the player has to
build the same squad on every client or copy a string. The squad features below make "one squad, every client agrees"
easy – without any client ever acting on another (hard rule: messages are shown, the player clicks on each client).

## B. Squad features (in priority order)
1. **Create from my party.** One click on any client: a squad from the current party – names and classes
   (`UnitName`/`UnitClass` on party1–4; guard secrets), races where known, default roles from class, this client's
   character marked; leader = the party leader (`UnitIsGroupLeader`) or "I lead" toggle. Then the normal editor.
2. **Share squad with the party (offer, not push).** Button "Send squad to my party" sends the squad (the same
   `!WBX:1!` payload, split into addon-message chunks with a checksum) to the party. Every other client running
   WoWBoxer shows a small offer: "Dorin shares squad 'Undead trio' (3 characters) – **Review** / Ignore". Review opens
   the Share import preview; nothing changes until the player clicks **Import squad on that client**. No auto-accept,
   no setting that accepts for you. Throttle and size-limit like `Team.lua`. Log every offer received.
   (the owner's call per the plan §3 – he asked for this now; if he says no, keep it behind a setting that is off.)
3. **Who am I + which unit, automatically suggested.** On each client: recognise this character by name (exists) and
   check which partyN holds the leader; if it differs from the member's unit, show "Dorin is party2 here – use party2?"
   with one button (exists as a checklist fix → also show it in the book's next-step line).
4. **Squad overview (the party-frame of WoWBoxer).** One compact panel/page showing every member: class icon, name,
   role icon, leader crown, level (from Team status when available, else the squad value), "keys up to date / N to
   update", follow status, same target as the leader, mana. Clicking a member on *your own* client opens its card;
   other members are view-only. Everything comes from display-only Team messages.
5. **Squad readiness checklist.** One line per member, aggregated from Team messages: in party, unit matches, keys
   placed and current, follow/assist keys on bars, settings applied. Each client can only fix itself – the panel says
   "fix on Wow2's window".
6. **Same key, same job on every client.** Optional "squad layout": key 1 = main attack/heal, key 2 = …, Follow on 11,
   Assist on 12, on every member (uses the existing fixed slots). Show it as a table (member × key) in the Squad view
   so the owner can learn one keyboard layout for all characters (hover-to-focus play). Printable cheat sheet text.
7. **Templates.** New squad from a template: Duo (Tank + Healer), Trio (Tank/Healer/DPS), 5-man; the Undead trio as an
   example; suggest classes per role from the data (no claims about "best").
8. **Members, full editing.** Add, remove, reorder (drag in the list), rename, class, race (valid for class), role,
   leader, unit, sequence on/off + tier, guide, level link. Validation identical to the companion (`State.newMember`).
9. **Multiple squads.** Switch, duplicate, delete with confirm, rename; the active squad is shared with the website
   string as today.
10. **Leader helpers.** Optional leader keys from the whitelist only: "Mark target" (`/tm 8` or `/targetmarker`, only if
    the slash command exists on the client), "Follow me" is NOT possible (nothing may make others act). Follower keys:
    Follow, Assist, Focus (exist).

Not allowed / out of scope: any message that makes another client target, follow, cast, accept, or change keys by
itself; auto-invite; auto-accept of offers; quest/taxi mirroring.

## C. Sequences: clear on/off, tiers, and telling them apart
1. **On/off + tier.** Per character: a checkbox **Use sequence keys** and a dropdown **Simple / Medium / Advanced**
   (disabled while off). Same control in the guide's step 1, on the "My keys" page header and in the member editor.
   Classes without built-in sequences show the checkbox disabled with "Built-in sequences: Paladin, Priest, Warlock –
   make your own on the Custom keys page". The dropdown must be our own small list frame (works on Forever and Era;
   do not depend on `UIDropDownMenu`, which is deprecated in the modern UI).
2. **Make it obvious which keys are sequences.** In the book:
   - Sections with headers: **Single-spell keys** (one spell per press), **Sequence keys** (/castsequence: one press =
     the next spell in the list), **Priority keys** (Paladin: casts the first ready spell), **Helpers** (follow, assist,
     pet).
   - A badge on the button corner: "SEQ" / "PRI"; a different border colour for sequence keys (purple `#8a5cd6`);
     second line "Sequence · Medium · 6 casts · loop ~15 s".
   - Tooltip shows the steps as a row of small icons with arrows: Immolate → Shadow Bolt ×4, and in words "Each press
     casts the next spell; restarts after combat."
3. **Combined icons.**
   - **In WoWBoxer's own window: yes.** Draw the sequence button as a composite of its spells: 2 spells = diagonal
     split or side by side, 3–4 = 2×2 quadrants (`SetTexCoord` on 2–4 textures inside the button), the filler spell gets
     the largest part. Same for Custom keys.
   - **On the action bar: the macro itself can only have one icon.** With `#showtooltip` (what WoWBoxer uses) the icon
     already changes to the *next* spell in the sequence as you press it – that is the most useful live indicator, keep
     it. A WoW macro cannot get a generated combined image (macro icons are file IDs; addons cannot create new icon
     files at runtime, and shipping a picture for every combination is not feasible).
   - **Optional overlay on the action bar:** a small "SEQ" corner badge (and optionally a thin purple border) drawn as
     a texture on top of the action buttons that hold a WBX sequence macro. Purely visual; build it so it only adds
     textures (no changes to the button's scripts or attributes) and hide it for bar addons. [AFKLAR: check for taint
     in combat on Forever and Era with `/console taintLog 1` – if anything taints, drop the overlay.]
