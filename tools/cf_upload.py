#!/usr/bin/env python3
"""Upload a packaged zip to CurseForge (WoW upload API). Used by .github/workflows/release.yml.

Usage: python3 tools/cf_upload.py dist/WoWBoxer-<ver>.zip <ver> [changelog.md]
Env:   CF_API_KEY (secret), CF_PROJECT_ID (repo variable). Without them it prints "skip" and exits 0.
       CF_GAME_VERSIONS optional: comma-separated CurseForge game version IDs, overrides the lookup.

Game versions come from the TOC's "## Interface:" list (11509 -> 1.15.9, 16001 -> 1.60.1, 20506 -> 2.5.6 TBC Anniversary). Interfaces CurseForge does
not know yet are reported and left out; with none found it fails. Standard library only.
"""
import json, os, re, sys, urllib.request, uuid

API = "https://wow.curseforge.com/api"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def interfaces(toc_path=os.path.join(ROOT, "WoWBoxer", "WoWBoxer.toc")):
    with open(toc_path, encoding="utf-8") as f:
        m = re.search(r"^## Interface:\s*(.+)$", f.read(), re.M)
    return [int(x) for x in re.findall(r"\d+", m.group(1))] if m else []


def version_name(iface):
    """11509 -> '1.15.9', 16001 -> '1.60.1', 120105 -> '12.1.5'."""
    major, rest = divmod(iface, 10000)
    minor, patch = divmod(rest, 100)
    return "%d.%d.%d" % (major, minor, patch)


def release_type(ver):
    """Plain tags (0.13.0, 1.0.0) are a release, -beta/-rc a beta, -alpha an alpha (docs/release.md). Local test
    builds (-test.N) and unknown suffixes are never uploaded."""
    if "-" not in ver:
        return "release"
    suffix = ver.split("-", 1)[1].lower()
    if suffix.startswith(("beta", "rc")):
        return "beta"
    if suffix.startswith("alpha"):
        return "alpha"
    sys.exit("refusing to upload %s: only plain, -beta, -rc and -alpha tags go to CurseForge" % ver)


def request(path, key, data=None, headers=None):
    h = {"X-Api-Token": key, "User-Agent": "wowboxer-release"}
    h.update(headers or {})
    req = urllib.request.Request(API + path, data=data, headers=h, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def game_versions(key):
    override = os.environ.get("CF_GAME_VERSIONS", "").strip()
    if override:
        return [int(x) for x in override.split(",") if x.strip()]
    known = request("/game/versions", key)
    ids = []
    for iface in interfaces():
        name = version_name(iface)
        hits = [v["id"] for v in known if v.get("name") == name]
        if hits:
            ids.append(hits[0])
            print("game version %s (interface %d) -> id %d" % (name, iface, hits[0]))
        else:
            print("WARNING: CurseForge has no game version %s (interface %d) yet - left out" % (name, iface))
    if not ids:
        sys.exit("no CurseForge game version found for %s" % interfaces())
    return ids


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


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    zip_path, ver = sys.argv[1], sys.argv[2]
    changelog = "WoWBoxer " + ver
    if len(sys.argv) > 3 and os.path.exists(sys.argv[3]):
        with open(sys.argv[3], encoding="utf-8") as f:
            changelog = f.read().strip() or changelog
    key, project = os.environ.get("CF_API_KEY", ""), os.environ.get("CF_PROJECT_ID", "")
    if not key or not project:
        print("skip CurseForge upload (CF_API_KEY secret / CF_PROJECT_ID variable not set)")
        return
    meta = {"changelog": changelog, "changelogType": "markdown", "displayName": "WoWBoxer " + ver,
            "gameVersions": game_versions(key), "releaseType": release_type(ver)}
    body, ctype = multipart({"metadata": json.dumps(meta)}, "file", zip_path)
    res = request("/projects/%s/upload-file" % project, key, body, {"Content-Type": ctype})
    print("uploaded to CurseForge: file id %s (%s)" % (res.get("id"), meta["releaseType"]))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        assert version_name(11509) == "1.15.9" and version_name(16001) == "1.60.1" and version_name(120105) == "12.1.5"
        assert version_name(20506) == "2.5.6"
        assert release_type("0.13.0") == "release" and release_type("1.0.0") == "release"
        assert release_type("0.13.0-beta.1") == "beta" and release_type("1.0.0-rc1") == "beta"
        assert release_type("0.13.0-alpha.2") == "alpha"
        for bad in ("0.13.0-test.1", "0.13.0-dev"):
            try:
                release_type(bad)
                raise AssertionError("uploaded " + bad)
            except SystemExit:
                pass
        assert interfaces() == [16001, 11509, 20506], interfaces()
        print("cf_upload selftest ok")
    else:
        main()
