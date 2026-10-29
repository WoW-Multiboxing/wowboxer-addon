# Releasing WoWBoxer

A version tag does everything: `git tag v0.9.0 && git push origin v0.9.0` runs `.github/workflows/release.yml` –
all checks, `tools/package.sh` (one `WoWBoxer/` folder, version stamped into the TOC, LICENSE.txt), a GitHub Release
and the CurseForge upload (`tools/cf_upload.py`). `0.x` and `-rc` versions go out as **beta**, from `1.0.0` as
**release**. Changelog: `docs/changes/<version>.md` (short, for players) or, without it, the commit subjects since
the last tag. To upload an existing tag again: Actions → release → Run workflow → tag.

Game versions come from the TOC `## Interface:` list: 11509 → Classic Era 1.15.9, 16001 → Forever 1.60.1.
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

**One key press = one action on one character.** WoWBoxer never sends input, never broadcasts keys, never follows,
casts or targets on its own. It only writes macros, bars and settings after you click, and never in combat.

`/wbx` opens the book. Talent data: Zephras (zephras.com, CC BY 4.0) and The Forever Era. World of Warcraft names and
icons © Blizzard Entertainment. Free and open source (MIT).
