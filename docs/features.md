# WoWBoxer – what it does (and never does)

For the website's add-on page. Plain English, kept in sync with the add-on (last checked: 0.9.4, 2026-10-29).
WoWBoxer runs in **WoW: Forever** and **Classic Era**. Free, no ads, open source (MIT).

## What it does
- **The right macros for your character.** For your class, role and level, WoWBoxer builds the macros you need and shows
  them in a spellbook. Drag them onto your action bars, or press **Place all**.
- **Level-ups without the work.** When a level-up or a new spell changes a macro, it gets an orange dot. One click
  updates it – same button, same keybind, new spell.
- **What's next.** The top line tells you the one thing to do now: macros to place, a trainer visit ("trainer at 12:
  Redemption"), talent points to spend.
- **All spells**, including the ones you learn later, with search, ranks and "New at <level>". Drag any spell onto
  your bar – a spell you haven't learned yet just starts working when you do.
- **Sequence macros** (Simple, Medium, Advanced) for your rotation, and your own macros in the macro editor. One press is
  still one spell.
- **Talents:** pick a guide (each shows its source and type), see your next point, and plan ahead to any level.
- **Squad:** the characters you play together, who leads, everyone's role. Add your party with one click, or add
  characters by name. **Send to my other characters** – each one reviews and imports it with a click.
- **Squad macros you choose:** Invite squad, Follow, Assist, Target leader, Focus and pet macros.
- **Setup:** where your macros go, recommended game settings (with backup and restore), a multibox checklist and an
  addon check. Reminders you can turn off, and "Don't show again".
- **Share** your squad with your other characters as a text string.

## What it never does
- **One key press = one action on one character.** No input broadcasting, no key cloning between windows.
- No input broadcasting: one key press is one action on one character. WoWBoxer automates the boring parts (invites, quests, dialogs, vendor, loot) with WoW's own addon API.
- Casting, targeting, moving, following and talking to NPCs stay your own key press. Each automation (accept invites,
  quests, resurrections and summons; follow the leader's dialogs and flights; sell junk, repair, restock) is a tick in
  Setup → Automation and only reacts to the characters of your squad.
- It only changes the game when you click (Place all, Update macros, Apply settings) and never in combat.
- It only touches macros whose name starts with **WBX** – never your own macros.
- Imported text is data only: no code is ever run from a string.
- Messages between your clients are data only; they only trigger an automation you ticked, and only from your squad.

## Credits
Talent data: Zephras (zephras.com), CC BY 4.0, changed by WoWBoxer; The Forever Era. World of Warcraft names and
icons © Blizzard Entertainment.
