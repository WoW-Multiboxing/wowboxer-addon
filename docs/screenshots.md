# In-game screenshots (website, later CurseForge)

Real screenshots of WoWBoxer, captured **read-only**: `tools/capture.py` copies the pixels of the WoW window with
PrintWindow (`tools/wowgrab.py`). Nothing is sent to the game – no keys, no clicks, no focus. The owner opens each page
himself from the checklist below; the watcher saves a frame whenever the WoWBoxer window changed and then stood still.

## The shots (Classic Era now, Forever after launch)

| id | What it shows | Crop |
|---|---|---|
| `main` | My macros: macro cards, squad macros, the next step | the WoWBoxer window |
| `action-bars` | macros on the action bars after Place all | window + action bars (chat and player frame blurred) |
| `level-up` | "N macros changed" + Update macros | window |
| `squad` | Squad page | window (names blurred) |
| `settings` | Setup: bars, checklist, game settings (CVars) | window |
| `automation` | Automation ON/OFF switches | window |
| `community` | copy box with the Discord invite | window + box |
| `report` | Report a problem | window + report window |

The character name in the header chip is blurred on every shot; squad names and the follow line on the Squad page.
Each export is checked by eye before it is committed.

## The owner's checklist (one client: Classic Era, windowed; wait ~3 s after each step, hands off)
1. Log in a character in a squad, out of combat, quiet spot (Claude's watcher is already running).
2. `/wbx` → **My macros**. Then **Place all** (macros on your bars).
3. Role dropdown → another role (macros show "changed"); after 3 s set it back.
4. Rail → **Squad**, then **Setup**, then **Automation**.
5. Rail → **Discord** (copy box), Esc. Rail → **Problem report**, then Close. Tell Claude "capture done".

## After the capture (Claude)
1. Look at `dist/capture/era/*.png`, put the chosen candidate per shot into `media/screenshots/shots.json` → `source.era`.
2. `python tools/capture.py export --client _classic_era_` → `media/screenshots/era/<id>-1440.webp`, `<id>-720.webp`,
   `manifest.json`. Check every file by eye (names blurred), then commit.
3. The next release attaches `site-screenshots.zip` (all of `media/screenshots/`) to its GitHub Release (WS-D picks it
   up for the website).

`manifest.json` (v1): `{version, app, appVersion, flavour, game, generated, shots: [{id, title, alt, files: {"1440",
"720"}, width, height, capturedAt, source}]}`. [AFKLAR: align with the window app's screenshot manifest when WS-C
publishes one – none is in wowboxer-layouts yet.]
