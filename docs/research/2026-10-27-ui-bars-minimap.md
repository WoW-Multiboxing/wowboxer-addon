# Research: minimap button, drag & drop, action bars, keybindings (2026-10-27)

Cloud session, for the Claude Code session that owns the code. Facts are tagged **[C]** confirmed (primary source or
The owner's own client files), **[R]** reported by a third party, **[?]** not verified – check in the client with
`/wbx selftest` or a probe before relying on it.

## 1. What the owner's clients actually have (from `WoWBoxerDB.diag`, Classic Era 1.15.9.70576) [C]
- `MAX_CHARACTER_MACROS` = **30** (not 18) on Classic Era. `MAX_ACCOUNT_MACROS` present.
- `C_SpellBook`, `C_Spell`, `C_EncodingUtil`, `C_Traits`, `issecretvalue`, `Settings`, `BackdropTemplateMixin` all exist on
  Classic Era 1.15.9. `C_ClassTalents` is **missing** on Era (talent read-back there needs `GetTalentInfo`).
- Forever 1.60.1.70532 addons in `_forever_\Interface\AddOns`: `## Interface: 16001`; several use
  `## AddonCompartmentFunc:` (Leatrix Plus, ForeverMove, SkillUpForever, ForeverDungeonJournal) → **the addon
  compartment exists on Forever** [C]. Leatrix Plus and TomTom embed LibDBIcon-1.0; ForeverDungeonJournal uses
  LibDBIcon for its minimap button [C].

## 2. Minimap button + addon compartment
- **Addon compartment** (the addons dropdown next to the minimap on the modern UI): TOC fields
  `## AddonCompartmentFunc: WoWBoxer_OnCompartmentClick`, optional `AddonCompartmentFuncOnEnter/OnLeave`, icon from
  `## IconTexture` [C, warcraft.wiki.gg Addon compartment + TOC format]. The functions must be **globals**. Since 11.0
  the click handler gets `(addonName, buttonName)` [C]. Guard with `[AllowLoadGameType …]` is not needed – unknown TOC
  fields are ignored on clients without the compartment [R].
- **Minimap button:** two options.
  1. **Embed LibDBIcon-1.0** (+ LibStub, CallbackHandler-1.0, LibDataBroker-1.1). Licence: Ace3-style BSD → OK to
     embed in an MIT addon with the licence files [C, CurseForge page]. Has a Forever file (v12.1.2, 21 Oct 2026) [C].
     Pros: works with minimap-button collectors, square/round minimaps, Forever already proven by other addons.
     This is a deliberate exception to "no libraries" – recommended. Put libs under `WoWBoxer/Libs/` and list them first
     in the TOC.
  2. Own ~80-line button (no libs): `Minimap` child, 31×31, `MiniMap-TrackingBorder` ring, drag updates an angle with
     `math.atan2(cy - my, cx - mx)` from `GetCursorPosition()/UIParent:GetEffectiveScale()`, position
     `(cos(a)*r, sin(a)*r)`; square minimaps (`GetMinimapShape()`) need clamping. More code to maintain.
  Behaviour (both): left-click toggles `/wbx`; right-click small menu (Sync keys, Settings, Hide button);
  tooltip shows character, level and "N keys to update"; option to hide (saved per account); `/wbx minimap` brings it back.
  An attention marker (small dot) when keys can be updated after a level-up is a nice touch.

## 3. Drag & drop from WoWBoxer onto the action bars
- Pattern (all standard, no protected calls): rows/icons `RegisterForDrag("LeftButton")`; `OnDragStart` →
  if `InCombatLockdown()` stop; make sure the WBX macro exists and is current (CreateMacro/EditMacro), then
  `PickupMacro(index)`. The player drops it on any action button himself. This is exactly what the macro UI does,
  so it is the safest possible placement path (no `PlaceAction` from code) [C, warcraft.wiki.gg OnDragStart /
  RegisterForDrag].
- Show a big draggable icon per key (like the spellbook), with the key text and a hint "drag to your bar".
- Spells in the "other spells" list: drag creates an extra `WBX <spell>` macro first (respecting the free-slot count),
  then picks it up.
- Optional later: `OnReceiveDrag` on the custom-key editor to drop spells into a sequence (read `GetCursorInfo()` →
  "spell", spellID) – data only, no casting.
- Keep "Create & place keys" (one click) for players who want the fixed layout.

## 4. Action bar slots, stance pages and why bar 1 can look empty
- Slot ranges (classic layout, also used by the modern UI for the first bars) [R, needs a probe in Forever]:
  bar 1 page 1 = 1–12 (pages 2–6 = 13–72), Right = 25–36, Right 2/Left = 37–48, Bottom Right = 49–60,
  Bottom Left = 61–72; modern extra bars 5–7 = 145–180 [?].
- **Bonus bars (important bug class):** Warriors (always in a stance), Druids in forms and Rogues in stealth show a
  *different* set of slots on bar 1: slot = `1 + (6 + offset - 1) * 12` → offset 1 = 73–84, 2 = 85–96, 3 = 97–108,
  4 = 109–120 [C, warcraft.wiki.gg GetBonusBarOffset]. Offsets: Warrior Battle 1 / Defensive 2 / Berserker 3; Druid
  Cat 1, Tree 2, Bear 3, Moonkin 4; Rogue stealth 1; Priest Shadowform 1 [C]. So WBX keys placed in 1–12 are invisible
  for a Warrior. Fix: for stance classes either place on the current bonus page (`GetBonusBarOffset()`), or default
  the main keys to Bottom Left for them, and tell the player.
- `GetBonusBarOffset` is **deprecated since 12.0.0** [C] – Forever is built on 12.1.5, so probe the replacement
  (`C_ActionBar.GetBonusBarOffset` / `GetBonusBarIndex`) first and fall back. [AFKLAR: exact name in Forever.]
- Forever has **Edit Mode** (HUD) and players can enable more action bars there [R, Method + Mobalytics]. Check
  `IsActionBarVisible`-style APIs or `Settings` before placing on a bar the player cannot see; otherwise tell him
  which bar to switch on.

## 5. Keybindings
- Forever has Blizzard's **Quick Keybind mode** (hover a button, press a key) [R, Method]. Cheapest good UX: show the
  current key for each WBX key and a button that opens Quick Keybind mode (or the Key Bindings panel) – no binding
  code at all.
- Showing the key: `GetBindingKey(command)` returns all keys for a command [C]. Commands per bar [R, verify]:
  `ACTIONBUTTON1–12` (bar 1, also for the bonus pages), `MULTIACTIONBAR1BUTTON1–12` (Bottom Left),
  `MULTIACTIONBAR2BUTTON…` (Bottom Right), `MULTIACTIONBAR3BUTTON…` (Right), `MULTIACTIONBAR4BUTTON…` (Right 2/Left),
  `MULTIACTIONBAR5–7BUTTON…` (modern extra bars).
- Optional "bind directly": `SetBindingMacro(key, "WBX K1")` then `SaveBindings(GetCurrentBindingSet())` – out of
  combat, after a click, and only per character (`2` = character set). Must never overwrite a key without asking.

## 6. Other multibox addons (ideas, not to copy)
- **BoxTrack** (Classic Era 1.15.9, not Forever) [C, CurseForge]: per-character fading bars, party status panel
  (health/resources/XP/durability/gold), lost-follow detection, off-target warning, macro generation (`/bt genmacro`),
  setup wizard per role combo, export/import of bar layouts. It also auto-sells/repairs – WoWBoxer must not (rules).
- For WoWBoxer later: display-only status between clients (lost follow via `AUTOFOLLOW_END`, different target than
  the leader, low mana) fits the hard rules; nothing that acts.

## 7. Macro facts for Forever
- 255 characters per macro; `/castsequence` advances only on a successful cast; reset options as in Classic [R,
  RankedBoost Forever macros].
- RankedBoost's macro pack says "No macro here can use Shift" and "Alt is left for Self Cast" – suggests Forever's
  default self-cast modifier is Alt and Shift is used by something else [?]. WoWBoxer macros use no modifiers today; keep
  it that way until checked.

## Sources
- [warcraft.wiki.gg – Addon compartment](https://warcraft.wiki.gg/wiki/Addon_compartment)
- [warcraft.wiki.gg – TOC format](https://warcraft.wiki.gg/wiki/AddOn_Keywords)
- [CurseForge – LibDBIcon-1.0](https://www.curseforge.com/wow/addons/libdbicon-1-0)
- [warcraft.wiki.gg – UIHANDLER OnDragStart](https://warcraft.wiki.gg/wiki/UIHANDLER_OnDragStart), [Frame:RegisterForDrag](https://warcraft.wiki.gg/wiki/API:Frame_RegisterForDrag)
- [warcraft.wiki.gg – GetBonusBarOffset](https://warcraft.wiki.gg/wiki/API_GetBonusBarOffset)
- [warcraft.wiki.gg – GetBindingKey](https://warcraft.wiki.gg/wiki/API_GetBindingKey), [SaveBindings](https://warcraft.wiki.gg/wiki/API:SaveBindings)
- [Method – WoW Forever UI](https://www.method.gg/wow-forever/understanding-wow-forevers-ui), [Mobalytics – Forever UI settings](https://mobalytics.gg/wow-forever/guides/ui-settings-guide)
- [CurseForge – BoxTrack](https://www.curseforge.com/wow/addons/boxtrack)
- [RankedBoost – WoW Forever macros](https://rankedboost.com/world-of-warcraft/forever/macros/)
