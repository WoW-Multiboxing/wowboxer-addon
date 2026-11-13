# Releasing WoWBoxer

## Test first, then live (the owner, 30 Oct 2026 – applies to every change from now on)
Nothing goes live on CurseForge, Wago or the website until the owner has tested it in the game and said **"ship it"**.

1. **Build:** work on `main` as usual, with all checks green. Commits and pushes are fine; **no version tag**.
2. **Test build:** run `powershell -File tools/install.ps1`. The installed addon is a test build:
   - its version reads `0.13.0-test.N (abc1234)`;
   - the window title shows an orange **TEST BUILD** label, so the owner always knows which version he is testing.
   Then write the in-game checklist (max 4 lines) at the top of `docs/backlog.md` and tell the owner what to test.
3. **The owner tests** and answers with feedback or **"ship it"**. Feedback goes back to step 1 and the next test build
   gets `-test.N+1`.
4. **Release only after "ship it"** in the session:
   - write `docs/changes/<version>.md`;
   - tag `vX.Y.Z` and push the tag; the workflow uploads it to CurseForge as **Release**;
   - update the website version (below) and the `[WS-E]` LOG block.
5. **Optional public beta** for other players, only when the owner asks: tag `vX.Y.Z-beta.N`. It goes out as **Beta**,
   which only players who chose Beta in their CurseForge app get.

Release types (`tools/cf_upload.py`): a plain tag = **release**, `-beta`/`-rc` = **beta**, `-alpha` = **alpha**. The
version number went to 1.0.0 on 2 Nov 2026 (the owner: "the actual version that we're going live with").

## How a tag publishes
A version tag does everything: `git tag v0.9.0 && git push origin v0.9.0` runs `.github/workflows/release.yml` –
all checks, `tools/package.sh` (one `WoWBoxer/` folder, version stamped into the TOC, LICENSE.txt), a GitHub Release,
the CurseForge upload (`tools/cf_upload.py`) and the Wago upload (`tools/wago_upload.py`, see "Wago Addons"). Release type: see "Test first" above. Changelog: `docs/changes/<version>.md` (short, for players) or, without it, the commit subjects since
the last tag. To upload an existing tag again: Actions → release → Run workflow → tag.

Game versions come from the TOC `## Interface:` list: 11509 → Classic Era 1.15.9, 16001 → Forever 1.60.1,
20506 → TBC Anniversary 2.5.6 (since 1.0.0).
CurseForge knows both (checked 2026-10-28: 1.60.1 = id 17053, 1.15.9 = id 16630). Project ID 1771228.

## Last step of every release: the version on the website (the owner, 2026-10-29)
After the tag is pushed and the release is live on CurseForge, wowboxer.com/addon/ (and so Google) must show it:
1. Website repo `WoW-Multiboxing/wowboxer-site` in `%USERPROFILE%\wowboxer-site` (clone it if missing, else
   `git pull --rebase`).
2. In `content/pages/addon.md` set `version:` to the new version in the same form, e.g. `version: 'v0.9.8 beta'`
   (no "beta" once the release is stable), and `updated:` to today's date (`YYYY-MM-DD`). Change nothing else.
3. `npm ci && npm run build` – it must end with "✓ output ok".
4. Commit as `WoW-Multiboxing <348792173+WoW-Multiboxing@users.noreply.github.com>` with the message
   `content: AddOn version vX.Y.Z`, `git pull --rebase`, push to main.
5. Check that the Vercel deployment for that commit is READY and that https://wowboxer.com/addon/ shows the version.
6. Mention it in the `[WS-E]` block in LOG.md.

If `%USERPROFILE%\wowboxer-site` has local commits from another session (`git status` says "ahead") or the pull hits
conflicts: `git rebase --abort`, never resolve someone else's work. Make the change in a throw-away worktree instead:
`git worktree add --detach ../wowboxer-site-version origin/main`, edit + build + commit there, `git push origin
HEAD:main`, then `git worktree remove --force ../wowboxer-site-version`. (Locally the build's output check reports the
canonical URLs with `\` on Windows only; Vercel's build on Linux is the gate.)

## One-time CurseForge setup (the owner, in the browser)
1. https://authors.curseforge.com → **Create project** → World of Warcraft → Addon. Name `WoWBoxer`, summary and
   description below, licence MIT, categories **Action Bars** and **Miscellaneous**, logo: any square image.
2. CurseForge reviews new projects (usually a day). Copy the **Project ID** from the project page (right side).
3. https://legacy.curseforge.com/account/api-tokens → generate a token named `wowboxer-release`.
4. github.com/WoW-Multiboxing/wowboxer-addon → Settings → Secrets and variables → Actions: secret `CF_API_KEY` = the
   token, variable `CF_PROJECT_ID` = the project ID.
   Then tell Claude "CurseForge ready" – Claude tags the release.

## Wago Addons (created 3 Nov 2026)
- Project "WoWBoxer - Multibox Companion", **project ID `rNkgpzNa`**, owner WoW-Multiboxing (GitHub sign-in),
  created as a Custom Addon: no repo link, uploads go through the API from the release workflow.
- GitHub: secret `WAGO_API_TOKEN` (API key from addons.wago.io/account/apikeys), variable `WAGO_PROJECT_ID` = `rNkgpzNa`.
- TOC: `## X-Wago-ID: rNkgpzNa`. Game versions: Wago's keys forever 1.60.1, classic 1.15.9, bc 2.5.6 (list at
  https://addons.wago.io/api/data/game).
- Upload: `tools/wago_upload.py`, the last step of `release.yml` (after CurseForge). It sends the same zip with
  label = version, stability from the tag (same rule as CurseForge: plain = stable, -beta/-rc = beta, -alpha = alpha),
  the changelog and the game versions from the zip's TOC `## Interface:` list, each checked against Wago's patch list.
  Without the secret/variable it prints "skip"; the step has `continue-on-error`, so Wago can never fail a release.
- Manual run (Actions → release → Run workflow): `curseforge` on/off (off for a tag already on CurseForge) and
  `wago` = upload / dry-run / skip. The upload scripts come from the workflow's commit, so older tags work too.
  CI runs a Wago dry run on every push (selftests + `--dry-run` on a packaged zip, no upload).
- **Live since 3 Nov 2026:** v1.0.0 (already on CurseForge) uploaded once via Run workflow (tag v1.0.0, curseforge
  off, wago upload; run 41666187120, after dry run 41665510973). addons.wago.io/addons/rNkgpzNa shows 1.0.0 stable for
  Forever 1.60.1, Classic 1.15.9 and TBC (bc) 2.5.6. From the next tag on, every release goes to both automatically.

## Discord (WS-H, added 13 Nov 2026)
The last step of `release.yml` runs `tools/discord-announce.mjs` (a copy of the master in the project folder's
`99_Noter/discord-setup/announcer/` – update it there first, then copy it here unchanged), only on a real tag push:
- plain tag `vX.Y.Z` → #announcements with an @Updates ping (CurseForge + wowboxer.com/addon/ links);
- `-beta`/`-rc` tag → #beta with an @Beta testers ping (how to pick Beta in the CurseForge app);
- `-alpha`/`-test` tags are never posted; a manual run (workflow_dispatch) never posts, so a re-run can't post twice.
Secrets `DISCORD_WEBHOOK_ANNOUNCEMENTS`, `DISCORD_WEBHOOK_BETA`, `DISCORD_WEBHOOK_TEST` and variables
`DISCORD_ROLE_UPDATES`, `DISCORD_ROLE_BETA` come from the owner's one-time `Connect-Announcer.cmd`. Until they exist the
step prints a notice and is skipped; it never fails a release (`continue-on-error`).
The post's 3–5 lines come from `dist/CHANGELOG.md` (= `docs/changes/<version>.md`): start the bullets that matter with a
**bold** lead. To check the webhooks: Actions → discord-test → Run workflow (posts to the private #bot-test, no pings;
the log must say "posted to DISCORD_WEBHOOK_TEST").

## Project page text

**Summary** (≤ 100 characters): Multiboxing in the game: the right keys for every character, role and level.

**Description**

> The live description is edited on CurseForge (authors.curseforge.com → Description) and has moved on from the draft
> below. Keep its links line under "Type /wbx to open the book" (added 29 Oct 2026 for search, WS-S):
> **Step-by-step multiboxing guides, the free WoWBoxer window app for Windows and help:** wowboxer.com ·
> AddOn guide (wowboxer.com/guides/addon/) · Discord. The project's Social Links (General tab) are Website
> https://wowboxer.com/ and Discord https://discord.gg/Q5xwbqhKzQ.

WoWBoxer gives each of your characters the keys it needs for its class, role and level – and keeps them up to date
when you level. Made for manual multiboxing in **WoW: Forever** and **Classic Era**.

- **Your keys in a spellbook.** Spells left, party helpers (Follow, Assist, pet keys) right. Drag them onto your bars
  or press *Place all*.
- **Level-up:** changed keys get an orange dot. One click updates them – same buttons, new spells.
- **Sequence keys** for the rotation of your spec, and your own keys in the key editor.
- **Squad:** your characters, their roles and who leads. Send the squad to your other clients; they review it and
  import it with a click.
- **Setup:** recommended settings with backup and restore, and an addon check.
- **Share** your squad with your other characters as a string.
- A **?** on every page and a 3-step squad guide.

**No input broadcasting: one key press is one action on one character. WoWBoxer automates the boring parts (invites, quests, dialogs, vendor, loot) with WoW's own addon API.** It only writes macros, bars and settings after you click, and never in combat.

`/wbx` opens the book. Talent data: Zephras (zephras.com, CC BY 4.0) and The Forever Era. World of Warcraft names and
icons © Blizzard Entertainment. Free and open source (MIT).
