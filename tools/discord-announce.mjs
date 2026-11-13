#!/usr/bin/env node
// discord-announce.mjs – the WoWBoxer Discord announcer (WS-H). One file, Node 18+, no dependencies.
// Master copy: project folder 99_Noter/discord-setup/announcer/. Copies live in each repo (tools/ or scripts/);
// change the master and re-copy, never fork it. Version: 1.0.0 (2026-11-02).
//
// Commands
//   release  --product window-app|addon --tag vX.Y.Z[-beta.N] [--notes-file F | --changelog CHANGELOG.md] [--url U]
//            Stable tag -> #announcements and pings "Updates"; a tag with "-beta"/"-rc" -> #beta and pings "Beta testers".
//            "-alpha"/"-test" tags are never announced.
//   site     [--repo-dir .] [--head SHA] [--base SHA] [--state F]
//            New or updated pages under content/ between two production deploys -> one batched post in #site-updates.
//            A file counts only if it is new, or its front matter "updated:" (or "status:") changed. Pure fixes are
//            skipped. Each page must answer 200 on wowboxer.com (unreleased pages are skipped). Commit trailers:
//            "Announce: <text>" adds a line, "[no-announce]" skips the deploy.
//   youtube  [--channel-id UC…] [--state F]
//            New videos and Shorts from the channel's RSS feed -> #videos. First run only remembers what exists.
//
// Options for every command
//   --dry-run   print what would be posted (JSON), send nothing, change no state
//   --test      send everything to DISCORD_WEBHOOK_TEST (#bot-test) with no role pings; state is not changed
//
// Environment (GitHub secrets / variables – never in files)
//   DISCORD_WEBHOOK_ANNOUNCEMENTS, DISCORD_WEBHOOK_BETA, DISCORD_WEBHOOK_SITE, DISCORD_WEBHOOK_VIDEOS, DISCORD_WEBHOOK_TEST
//   DISCORD_ROLE_UPDATES, DISCORD_ROLE_BETA (role ids, not secret)
//   A missing webhook makes the command print a notice and exit 0, so a release never fails because of Discord.

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const SITE = "https://wowboxer.com";
const YT_CHANNEL = "UC6wibf5z-8XknzMAgTZj-FA"; // @WoWBoxerHQ
const AVATAR = `${SITE}/logo.png`;
const COLORS = { stable: 0xc9a227, beta: 0x5b8def, site: 0x3fa66b, video: 0xe03a3a };

const PRODUCTS = {
  "window-app": {
    name: "WoWBoxer",
    what: "the multibox app for Windows",
    repo: "WoW-Multiboxing/wowboxer-layouts",
    stableLinks: [["Download", `${SITE}/window-app/`]],
    betaLinks: (tag) => [
      ["Beta download", `https://github.com/WoW-Multiboxing/wowboxer-layouts/releases/tag/${tag}`],
    ],
    betaHow: "Already installed? Settings › Updates › Update channel: **Beta**.",
  },
  addon: {
    name: "WoWBoxer AddOn",
    what: "the in-game AddOn",
    repo: "WoW-Multiboxing/wowboxer-addon",
    stableLinks: [["CurseForge", "https://www.curseforge.com/wow/addons/wowboxer"], ["About the AddOn", `${SITE}/addon/`]],
    betaLinks: () => [["CurseForge (Files)", "https://www.curseforge.com/wow/addons/wowboxer/files"]],
    betaHow: "In the CurseForge app: right-click WoWBoxer › Release Type › **Beta**.",
  },
};

// Lines we never post (house rules: hover to activate is the method; no safety claims).
const BLOCKED = [/alt\s*\+?\s*tab/i, /gr[ae]y\s*zone/i, /100\s*%\s*safe/i, /(approved|allowed)\s+by\s+blizzard/i];
const isClean = (s) => !BLOCKED.some((re) => re.test(s));

// ---------- small helpers ----------
export function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const k = a.slice(2);
      const v = argv[i + 1];
      if (v === undefined || v.startsWith("--")) out[k] = true;
      else { out[k] = v; i++; }
    } else out._.push(a);
  }
  return out;
}

const clip = (s, n) => (s.length <= n ? s : s.slice(0, n - 1).replace(/\s+\S*$/, "") + "…");

export function releaseKind(tag) {
  const t = String(tag).toLowerCase();
  if (/-(alpha|test|dev)/.test(t)) return "skip";
  if (/-(beta|rc|pre)/.test(t) || t.includes("-")) return "beta";
  return "stable";
}

/** The CHANGELOG section for a tag ("## vX.Y.Z …" up to the next "## "), else null. */
export function changelogSection(md, tag) {
  const v = String(tag).replace(/^v/, "");
  const lines = md.split(/\r?\n/);
  const want = [v, `v${v}`, v.replace(/-.*$/, ""), `v${v.replace(/-.*$/, "")}`];
  for (const w of want) {
    const start = lines.findIndex((l) => new RegExp(`^##\\s+(WoWBoxer\\s+)?${w.replace(/[.+]/g, "\\$&")}(\\s|$)`, "i").test(l));
    if (start === -1) continue;
    let end = lines.findIndex((l, i) => i > start && /^##\s/.test(l));
    if (end === -1) end = lines.length;
    return { heading: lines[start].replace(/^##\s+/, ""), body: lines.slice(start + 1, end).join("\n") };
  }
  return null;
}

/** 3–5 short lines from release notes: an optional lead line, then the first sentence of each top-level bullet. */
export function summarize(body, max = 5) {
  const lines = body.split(/\r?\n/);
  const bullets = [];
  let lead = null;
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (/^[-*]\s+/.test(l)) {
      let text = l.replace(/^[-*]\s+/, "");
      while (i + 1 < lines.length && /^\s{2,}\S/.test(lines[i + 1]) && !/^\s+[-*]\s/.test(lines[i + 1])) text += " " + lines[++i].trim();
      bullets.push(text);
    } else if (!lead && !bullets.length && l.trim() && !/^#/.test(l)) {
      lead = l.trim();
      while (i + 1 < lines.length && lines[i + 1].trim() && !/^[-*#]\s/.test(lines[i + 1])) lead += " " + lines[++i].trim();
      const m = lead.match(/^(.+?[.!?])(\s|$)/);
      if (m) lead = m[1];
    }
  }
  const firstSentence = (t) => {
    let s;
    const bold = t.match(/^\*\*(.+?)\*\*/);
    if (bold && /[.!?]$/.test(bold[1])) s = bold[0];
    else {
      const m = t.match(/^(.+?[.!?])(\s|$)/);
      s = m && m[1].length > 25 ? m[1] : t;
    }
    s = clip(s.replace(/:\*\*$/, "**").replace(/:$/, ""), 170);
    if ((s.match(/\*\*/g) || []).length % 2) s += "**";
    return s;
  };
  const out = [];
  if (lead && isClean(lead) && lead.length <= 200) out.push(lead);
  // Bullets that open with a bold lead ("**Window swap hotkeys** …") are the headline items: they go first.
  const ranked = [...bullets.filter((b) => b.startsWith("**")), ...bullets.filter((b) => !b.startsWith("**"))];
  for (const b of ranked) {
    const s = firstSentence(b);
    if (isClean(s)) out.push("• " + s);
    if (out.length >= max) break;
  }
  return out;
}

export function releasePayload({ product, tag, notes, url, test }) {
  const p = PRODUCTS[product];
  if (!p) throw new Error(`unknown --product ${product} (window-app | addon)`);
  const kind = releaseKind(tag);
  if (kind === "skip") return null;
  const version = String(tag).replace(/^v/, "");
  const lines = notes ? summarize(notes) : [];
  const links = (kind === "beta" ? p.betaLinks(tag) : p.stableLinks).slice();
  if (url && kind === "stable") links.push(["Full release notes", url]);
  const desc = [
    ...lines,
    "",
    ...(kind === "beta" ? [p.betaHow] : []),
    links.map(([label, href]) => `[${label}](${href})`).join(" · "),
  ].join("\n").trim();
  const role = kind === "beta" ? process.env.DISCORD_ROLE_BETA : process.env.DISCORD_ROLE_UPDATES;
  const ping = !test && role ? `<@&${role}> ` : "";
  return {
    route: kind === "beta" ? "BETA" : "ANNOUNCEMENTS",
    body: {
      content: `${ping}${kind === "beta" ? `**${p.name} ${version}** beta is out for testers.` : `**${p.name} ${version}** is out.`}`,
      embeds: [{
        title: kind === "beta" ? `${p.name} ${version} (beta)` : `${p.name} ${version}`,
        url: kind === "beta" ? p.betaLinks(tag)[0][1] : p.stableLinks[0][1],
        description: clip(desc, 3900),
        color: kind === "beta" ? COLORS.beta : COLORS.stable,
        footer: { text: `${p.name} – ${p.what}${kind === "beta" ? " · beta channel" : ""}` },
      }],
      allowed_mentions: { parse: [], roles: ping ? [role] : [] },
    },
  };
}

// ---------- site ----------
export function contentUrl(file) {
  const f = file.replace(/\\/g, "/");
  let m;
  if ((m = f.match(/^content\/guides\/([a-z0-9-]+)\.md$/))) return `/guides/${m[1]}/`;
  if ((m = f.match(/^content\/squads\/([a-z0-9-]+)\.md$/))) return `/squad-builder/${m[1]}/`;
  if ((m = f.match(/^content\/pages\/([a-z0-9-]+)\.md$/))) return m[1] === "home" ? "/" : `/${m[1]}/`;
  return null; // _data, _parked, _notes, README …
}

export function frontMatter(md) {
  const m = String(md || "").match(/^---\r?\n([\s\S]*?)\r?\n---/);
  const fm = {};
  if (!m) return fm;
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([A-Za-z][\w-]*):\s*(.*)$/);
    if (kv) fm[kv[1]] = kv[2].replace(/^['"]|['"]$/g, "").trim();
  }
  return fm;
}

/** Decide what a deploy should announce. files: [{status:'A'|'M'|'D'|'R', path, before, after}] */
export function siteItems(files, trailers = []) {
  const items = [];
  for (const f of files) {
    const url = contentUrl(f.path);
    if (!url || path.basename(f.path).startsWith("_")) continue;
    if (f.status === "D") continue;
    const a = frontMatter(f.after);
    const b = frontMatter(f.before);
    let kind = null;
    if (f.status === "A" || (b.status === "draft" && a.status === "published")) kind = "New";
    else if (a.updated && a.updated !== b.updated) kind = "Updated";
    if (!kind) continue;
    if (a.announce === "false" || a.announce === "no") continue;
    items.push({ kind, url, title: a.title || url, description: a.description || "" });
  }
  for (const t of trailers) if (isClean(t)) items.push({ kind: "Note", url: null, title: t, description: "" });
  return items;
}

export function sitePayload(items) {
  if (!items.length) return null;
  const sorted = [...items].sort((x, y) => ["New", "Updated", "Note"].indexOf(x.kind) - ["New", "Updated", "Note"].indexOf(y.kind));
  const shown = sorted.slice(0, 8);
  const lines = shown.map((it) =>
    it.url ? `**${it.kind}:** [${it.title}](${SITE}${it.url})${it.description ? ` – ${clip(it.description, 110)}` : ""}` : `• ${it.title}`
  );
  if (sorted.length > shown.length) lines.push(`…and ${sorted.length - shown.length} more on ${SITE}`);
  return {
    route: "SITE",
    body: {
      content: "",
      embeds: [{ title: "New on wowboxer.com", url: SITE, description: clip(lines.join("\n"), 3900), color: COLORS.site }],
      allowed_mentions: { parse: [] },
    },
  };
}

function git(dir, args) {
  return execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
}
function gitShow(dir, rev, file) {
  try { return git(dir, ["show", `${rev}:${file}`]); } catch { return ""; }
}

export function collectSiteChanges(dir, base, head) {
  const raw = git(dir, ["diff", "--name-status", "-M", `${base}`, `${head}`, "--", "content"]).trim();
  const files = [];
  for (const line of raw ? raw.split("\n") : []) {
    const parts = line.split("\t");
    const st = parts[0][0];
    const p = parts[parts.length - 1];
    const before = st === "A" ? "" : gitShow(dir, base, parts[1]);
    const after = st === "D" ? "" : gitShow(dir, head, p);
    files.push({ status: st === "R" ? "M" : st, path: p, before, after });
  }
  const log = git(dir, ["log", "--format=%B%x00", `${base}..${head}`]);
  const skip = /\[no-announce\]/i.test(log);
  const trailers = [...log.matchAll(/^Announce:\s*(.+)$/gim)].map((m) => m[1].trim());
  return { files, trailers, skip };
}

async function isLive(url) {
  try {
    const r = await fetch(SITE + url, { method: "GET", redirect: "manual" });
    return r.status === 200;
  } catch { return false; }
}

// ---------- youtube ----------
export function parseFeed(xml) {
  const out = [];
  for (const m of xml.matchAll(/<entry>([\s\S]*?)<\/entry>/g)) {
    const e = m[1];
    const get = (re) => (e.match(re) || [])[1];
    const id = get(/<yt:videoId>([^<]+)<\/yt:videoId>/);
    if (!id) continue;
    const title = (get(/<title>([^<]*)<\/title>/) || "").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
    out.push({ id, title, published: get(/<published>([^<]+)<\/published>/) || "" });
  }
  return out;
}

async function isShort(id) {
  try {
    const r = await fetch(`https://www.youtube.com/shorts/${id}`, { method: "HEAD", redirect: "manual" });
    return r.status === 200;
  } catch { return false; }
}

export function videoPayload(v, short) {
  const link = short ? `https://www.youtube.com/shorts/${v.id}` : `https://www.youtube.com/watch?v=${v.id}`;
  return {
    route: "VIDEOS",
    // A plain link makes Discord show its own YouTube player; no ping for videos.
    body: { content: `${short ? "New Short" : "New video"}: **${v.title}**\n${link}`, allowed_mentions: { parse: [] } },
  };
}

// ---------- state (a small JSON file the workflow keeps in the Actions cache) ----------
function readState(f) { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return null; } }
function writeState(f, s) { fs.mkdirSync(path.dirname(path.resolve(f)), { recursive: true }); fs.writeFileSync(f, JSON.stringify(s, null, 2)); }

// ---------- sending ----------
export async function send(msg, { dryRun, test }) {
  if (!msg) return "nothing";
  const body = { username: "WoWBoxer", avatar_url: AVATAR, ...msg.body };
  const envName = test ? "DISCORD_WEBHOOK_TEST" : `DISCORD_WEBHOOK_${msg.route}`;
  if (dryRun) {
    console.log(`--- would post to ${envName} ---\n${JSON.stringify(body, null, 2)}`);
    return "dry-run";
  }
  const hook = (process.env[envName] || "").trim();
  if (!hook) { console.log(`::notice::${envName} is not set – skipped the Discord post.`); return "no-webhook"; }
  if (!/^https:\/\/(discord\.com|discordapp\.com|ptb\.discord\.com|canary\.discord\.com)\/api\/webhooks\//.test(hook) && !process.env.DISCORD_ALLOW_ANY_HOOK) {
    throw new Error(`${envName} does not look like a Discord webhook URL`);
  }
  for (let attempt = 0; attempt < 4; attempt++) {
    const r = await fetch(`${hook}?wait=true`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    if (r.status === 429) {
      const j = await r.json().catch(() => ({}));
      await new Promise((res) => setTimeout(res, Math.ceil((j.retry_after || 2) * 1000) + 250));
      continue;
    }
    if (!r.ok) throw new Error(`Discord answered ${r.status}: ${(await r.text()).slice(0, 300)}`);
    console.log(`posted to ${envName}`);
    return "posted";
  }
  throw new Error("Discord kept rate-limiting; gave up");
}

// ---------- commands ----------
async function cmdRelease(a) {
  let notes = "";
  if (a["notes-file"] && fs.existsSync(a["notes-file"])) notes = fs.readFileSync(a["notes-file"], "utf8");
  else if (a.changelog && fs.existsSync(a.changelog)) notes = changelogSection(fs.readFileSync(a.changelog, "utf8"), a.tag)?.body || "";
  notes = notes.replace(/^##[^\n]*\n/, "");
  const msg = releasePayload({ product: a.product, tag: a.tag, notes, url: a.url, test: a.test });
  if (!msg) { console.log(`${a.tag}: alpha/test tag – not announced.`); return; }
  await send(msg, { dryRun: a["dry-run"], test: a.test });
}

async function cmdSite(a) {
  const dir = a["repo-dir"] || ".";
  const head = a.head || git(dir, ["rev-parse", "HEAD"]).trim();
  const stateFile = a.state || ".discord-state/site.json";
  const state = readState(stateFile) || {};
  let base = a.base || state.lastSha;
  if (!base) { try { base = git(dir, ["rev-parse", `${head}^1`]).trim(); } catch { base = null; } }
  if (!base || base === head) { console.log("Nothing to compare."); }
  else {
    try { git(dir, ["cat-file", "-e", `${base}^{commit}`]); } catch { console.log(`Base ${base} not in the clone – using ${head}^1.`); base = git(dir, ["rev-parse", `${head}^1`]).trim(); }
    const { files, trailers, skip } = collectSiteChanges(dir, base, head);
    if (skip) console.log("[no-announce] in a commit – skipped.");
    else {
      const items = [];
      for (const it of siteItems(files, trailers)) {
        if (!it.url || a["no-live-check"] || (await isLive(it.url))) items.push(it);
        else console.log(`${it.url} is not live (yet) – left out.`);
      }
      const msg = sitePayload(items);
      if (!msg) console.log(`No new or updated pages between ${base.slice(0, 7)} and ${head.slice(0, 7)}.`);
      else await send(msg, { dryRun: a["dry-run"], test: a.test });
    }
  }
  if (!a["dry-run"] && !a.test) writeState(stateFile, { ...state, lastSha: head });
}

async function cmdYoutube(a) {
  const stateFile = a.state || ".discord-state/youtube.json";
  const channel = a["channel-id"] || YT_CHANNEL;
  const xml = a["feed-file"] ? fs.readFileSync(a["feed-file"], "utf8")
    : await (await fetch(`https://www.youtube.com/feeds/videos.xml?channel_id=${channel}`)).text();
  const videos = parseFeed(xml);
  if (!videos.length) { console.log("Feed has no videos (or YouTube did not answer) – nothing to do."); return; }
  const state = readState(stateFile);
  if (!state) {
    console.log(`First run: remembering ${videos.length} existing video(s), posting none.`);
    if (!a["dry-run"] && !a.test) writeState(stateFile, { seen: videos.map((v) => v.id) });
    return;
  }
  const seen = new Set(state.seen || []);
  const fresh = videos.filter((v) => !seen.has(v.id)).reverse(); // oldest first
  for (const v of fresh) {
    const short = a["no-short-check"] ? false : await isShort(v.id);
    await send(videoPayload(v, short), { dryRun: a["dry-run"], test: a.test });
    seen.add(v.id);
  }
  if (!fresh.length) console.log("No new videos.");
  if (!a["dry-run"] && !a.test) writeState(stateFile, { seen: [...seen].slice(-300) });
}

async function main() {
  const a = parseArgs(process.argv.slice(2));
  const cmd = a._[0];
  if (cmd === "release") return cmdRelease(a);
  if (cmd === "site") return cmdSite(a);
  if (cmd === "youtube") return cmdYoutube(a);
  console.log("usage: discord-announce.mjs release|site|youtube [--dry-run] [--test] … (see the header of this file)");
  process.exitCode = 2;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("discord-announce.mjs")) {
  main().catch((e) => { console.error(`::error::${e.message}`); process.exitCode = 1; });
}
