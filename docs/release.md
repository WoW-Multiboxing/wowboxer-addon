# Releasing WoWBoxer

A version tag does everything: `git tag v0.9.0 && git push origin v0.9.0` runs `.github/workflows/release.yml` –
all checks, `tools/package.sh` (one `WoWBoxer/` folder, version stamped into the TOC, LICENSE.txt), a GitHub Release
and the CurseForge upload (`tools/cf_upload.py`). `0.x` and `-rc` versions go out as **beta**, from `1.0.0` as
**release**. Changelog: `docs/changes/<version>.md` (short, for players) or, without it, the commit subjects since
the last tag. To upload an existing tag again: Actions → release → Run workflow → tag.

Game versions come from the TOC `## Interface:` list: 11509 → Classic Era 1.15.9, 16001 → Forever 1.60.1.
[AFKLAR: does CurseForge list a "1.60.1" game version for WoW: Forever before launch (4 Nov 2026)? If not, the upload
goes out for Classic Era only and logs a warning; add the ID later in the `CF_GAME_VERSIONS` repo variable.]

## One-time CurseForge setup (the owner, in the browser)
1. https://authors.curseforge.com → **Create project** → World of Warcraft → Addon. Name `WoWBoxer`, summary and
   description below, licence MIT, categories **Action Bars** and **Miscellaneous**, logo: any square image.
2. CurseForge reviews new projects (usually a day). Copy the **Project ID** from the project page (right side).
3. https://legacy.curseforge.com/account/api-tokens → generate a token named `wowboxer-release`.
4. github.com/WoW-Multiboxing/wowboxer-addon → Settings → Secrets and variables → Actions: secret `CF_API_KEY` = the
   token, variable `CF_PROJECT_ID` = the project ID.
   Then tell Claude "CurseForge ready" – Claude tags the release.

## Project page text

**Summary** (≤ 100 characters): Multiboxing companion: the right keys for every character, role and level.

**Description**

WoWBoxer gives each of your characters the keys it needs for its class, role and level – and keeps them up to date
when you level. Made for manual multiboxing in **WoW: Forever** and **Classic Era**.

- **Your keys in a spellbook.** Spells left, party helpers (Follow, Assist, pet keys) right. Drag them onto your bars
  or press *Place all*.
- **Level-up:** changed keys get an orange dot. One click updates them – same buttons, new spells.
- **Sequence keys** for the rotation of your spec, and your own keys in the key editor.
- **Squad:** your characters, their roles and who leads. Send the squad to your other clients; they review it and
  import it with a click.
- **Setup:** recommended settings with backup and restore, and an addon check.
- **Share** a setup as a string with the WoWBoxer website.
- A **?** on every page and a 5-step squad guide.

**One key press = one action on one character.** WoWBoxer never sends input, never broadcasts keys, never follows,
casts or targets on its own. It only writes macros, bars and settings after you click, and never in combat.

`/wbx` opens the book. Talent data: Zephras (zephras.com, CC BY 4.0) and The Forever Era. World of Warcraft names and
icons © Blizzard Entertainment. Free and open source (MIT).
