#!/usr/bin/env python3
"""Upload a packaged zip to Wago Addons. Used by .github/workflows/release.yml after the CurseForge upload.

Usage: python3 tools/wago_upload.py [--dry-run] dist/WoWBoxer-<ver>.zip <ver> [changelog.md]
       python3 tools/wago_upload.py --selftest
Env:   WAGO_API_TOKEN (secret), WAGO_PROJECT_ID (repo variable). Without them it prints "skip" and exits 0.

POST https://addons.wago.io/api/projects/<id>/version, Authorization: Bearer <token>, multipart "file" (the zip)
and "metadata" (JSON: label, stability, changelog, supported_<game>_patches). Game versions come from the
"## Interface:" list of the TOC inside the zip (so an older tag uploads with its own TOC): 16001 -> forever 1.60.1,
11509 -> classic 1.15.9, 20506 -> bc 2.5.6. Each patch is checked against https://addons.wago.io/api/data/game;
unknown ones are reported and left out. --dry-run does everything except the upload (no token needed).
Standard library only. A Wago failure exits 1 with a message; the workflow step has continue-on-error, so it
never fails the CurseForge upload (which runs first).
"""
import json, os, re, sys, urllib.error, urllib.request, uuid, zipfile

API = "https://addons.wago.io/api"
UA = {"User-Agent": "wowboxer-release", "Accept": "application/json"}

# release_type (CurseForge's rule, docs/release.md) -> Wago stability
STABILITY = {"release": "stable", "beta": "beta", "alpha": "alpha"}


def release_type(ver):
    """Same rule as tools/cf_upload.py: plain = release, -beta/-rc = beta, -alpha = alpha, anything else refused."""
    if "-" not in ver:
        return "release"
    suffix = ver.split("-", 1)[1].lower()
    if suffix.startswith(("beta", "rc")):
        return "beta"
    if suffix.startswith("alpha"):
        return "alpha"
    sys.exit("refusing to upload %s: only plain, -beta, -rc and -alpha tags go to Wago" % ver)


def toc_interfaces(text):
    m = re.search(r"^## Interface:\s*(.+)$", text, re.M)
    return [int(x) for x in re.findall(r"\d+", m.group(1))] if m else []


def zip_interfaces(zip_path):
    with zipfile.ZipFile(zip_path) as z:
        return toc_interfaces(z.read("WoWBoxer/WoWBoxer.toc").decode("utf-8-sig"))


def version_name(iface):
    """11509 -> '1.15.9', 16001 -> '1.60.1', 20506 -> '2.5.6'."""
    major, rest = divmod(iface, 10000)
    minor, patch = divmod(rest, 100)
    return "%d.%d.%d" % (major, minor, patch)


def wago_game(iface):
    """Wago's game key for an interface number (keys from /api/data/game)."""
    major, minor = iface // 10000, (iface // 100) % 100
    if major == 1:
        return "forever" if minor >= 60 else "classic"
    return {2: "bc", 3: "wotlk", 4: "cata", 5: "mop"}.get(major, "retail")


def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def supported_patches(ifaces, game_data):
    """{'supported_forever_patches': ['1.60.1'], ...} for the interfaces Wago knows."""
    known = game_data.get("patches", {})
    out = {}
    for iface in ifaces:
        game, name = wago_game(iface), version_name(iface)
        if name in known.get(game, []):
            out.setdefault("supported_%s_patches" % game, []).append(name)
            print("game version %s %s (interface %d)" % (game, name, iface))
        else:
            print("WARNING: Wago has no %s patch %s (interface %d) yet - left out" % (game, name, iface))
    return out


def metadata(ver, changelog, patches):
    meta = {"label": ver, "stability": STABILITY[release_type(ver)], "changelog": changelog}
    meta.update(patches)
    return meta


def multipart(fields, file_field, file_path):
    b = uuid.uuid4().hex
    out = []
    for k, v in fields.items():
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (b, k, v)).encode("utf-8"))
    with open(file_path, "rb") as f:
        payload = f.read()
    out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n"
                "Content-Type: application/zip\r\n\r\n" % (b, file_field, os.path.basename(file_path))).encode("utf-8"))
    out.append(payload + b"\r\n")
    out.append(("--%s--\r\n" % b).encode("utf-8"))
    return b"".join(out), "multipart/form-data; boundary=" + b


def main(argv):
    dry = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if len(args) < 2:
        sys.exit(__doc__)
    zip_path, ver = args[0], args[1]
    changelog = "WoWBoxer " + ver
    if len(args) > 2 and os.path.exists(args[2]):
        with open(args[2], encoding="utf-8") as f:
            changelog = f.read().strip() or changelog
    token, project = os.environ.get("WAGO_API_TOKEN", ""), os.environ.get("WAGO_PROJECT_ID", "")
    if not dry and (not token or not project):
        print("skip Wago upload (WAGO_API_TOKEN secret / WAGO_PROJECT_ID variable not set)")
        return
    stability = STABILITY[release_type(ver)]  # refuses -test/-dev before any network call
    ifaces = zip_interfaces(zip_path)
    patches = supported_patches(ifaces, get_json(API + "/data/game"))
    if not patches:
        sys.exit("no Wago game version found for %s" % ifaces)
    meta = metadata(ver, changelog, patches)
    if dry:
        shown = dict(meta, changelog="<%d chars>" % len(changelog))
        print("dry run, no upload. project %s, %s (%s), metadata: %s"
              % (project or "<unset>", os.path.basename(zip_path), stability, json.dumps(shown)))
        return
    body, ctype = multipart({"metadata": json.dumps(meta)}, "file", zip_path)
    h = dict(UA, Authorization="Bearer " + token)
    h["Content-Type"] = ctype
    req = urllib.request.Request("%s/projects/%s/version" % (API, project), data=body, headers=h, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            text = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        sys.exit("Wago upload failed: HTTP %d %s" % (e.code, e.read().decode("utf-8", "replace")[:500]))
    print("uploaded to Wago: %s (%s) %s" % (ver, stability, text[:300]))


def selftest():
    assert version_name(16001) == "1.60.1" and version_name(11509) == "1.15.9" and version_name(20506) == "2.5.6"
    assert wago_game(16001) == "forever" and wago_game(11509) == "classic" and wago_game(20506) == "bc"
    assert wago_game(30405) == "wotlk" and wago_game(120105) == "retail"
    assert STABILITY[release_type("1.0.0")] == "stable" and STABILITY[release_type("1.1.0-beta.1")] == "beta"
    assert STABILITY[release_type("1.0.0-rc1")] == "beta" and STABILITY[release_type("1.1.0-alpha.2")] == "alpha"
    for bad in ("1.0.0-test.1", "1.0.0-dev"):
        try:
            release_type(bad)
            raise AssertionError("uploaded " + bad)
        except SystemExit:
            pass
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(root, "WoWBoxer", "WoWBoxer.toc"), encoding="utf-8-sig") as f:
        toc = f.read()
    assert toc_interfaces(toc) == [16001, 11509, 20506], toc_interfaces(toc)
    assert re.search(r"^## X-Wago-ID: rNkgpzNa$", toc, re.M), "TOC lacks ## X-Wago-ID"
    game = {"patches": {"forever": ["1.60.1"], "classic": ["1.15.9", "1.15.8"], "bc": ["2.5.6"]}}
    p = supported_patches([16001, 11509, 20506, 120105], game)
    assert p == {"supported_forever_patches": ["1.60.1"], "supported_classic_patches": ["1.15.9"],
                 "supported_bc_patches": ["2.5.6"]}, p
    m = metadata("1.0.0", "notes", p)
    assert m["label"] == "1.0.0" and m["stability"] == "stable" and m["changelog"] == "notes"
    print("wago_upload selftest ok")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--selftest"]:
        selftest()
    else:
        main(sys.argv[1:])
