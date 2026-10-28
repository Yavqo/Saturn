#!/usr/bin/env python3
"""Check and package Saturn extensions.

  scripts/saturn-ext.py validate <folder>...      check one or more extension folders (same rules as Saturn itself)
  scripts/saturn-ext.py build-store               validate store/extensions/*, write store/packages/*.zip and store/index.json

Standard library only. Exit status is 1 when anything fails, so it can run in CI.
"""
import hashlib
import json
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(ROOT, "store")

MAX_TOTAL, MAX_FILE, MAX_FILES = 5 * 1024 * 1024, 1024 * 1024, 200
ALLOWED_TYPES = {"json", "js", "css", "html", "svg", "png", "jpg", "jpeg", "gif", "webp", "ico", "woff", "woff2", "txt", "md"}
PERMISSIONS = {"storage", "activeTab", "clipboardWrite", "tabs"}
RUN_AT = {"document_start", "document_end", "document_idle"}
ID_RE = re.compile(r"^[a-z0-9]+([.-][a-z0-9]+)*$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
PATTERN_RE = re.compile(r"^(\*|https?)://(\*|\*\.[^/*:]+|[^/*:]+)(/.*)$")


def rel_ok(p):
    return isinstance(p, str) and 0 < len(p) <= 200 and not p.startswith("/") and ".." not in p and "\\" not in p and not p.startswith(".")


def pattern_ok(p):
    return isinstance(p, str) and (p == "<all_urls>" or bool(PATTERN_RE.match(p)))


def is_broad(p):
    return p == "<all_urls>" or bool(re.match(r"^(\*|https?)://\*/", p))


def validate(folder, store=False):
    """Returns (errors, warnings, manifest)."""
    errors, warnings = [], []
    manifest_path = os.path.join(folder, "manifest.json")
    if not os.path.isfile(manifest_path):
        return ["manifest.json is missing."], warnings, None
    try:
        with open(manifest_path, encoding="utf-8") as f:
            m = json.load(f)
    except ValueError as e:
        return [f"manifest.json is not valid JSON: {e}"], warnings, None
    if not isinstance(m, dict):
        return ["manifest.json must be an object."], warnings, None

    total = files = 0
    for dirpath, _, names in os.walk(folder):
        for n in names:
            if n == ".DS_Store":
                continue
            full = os.path.join(dirpath, n)
            rel = os.path.relpath(full, folder)
            if os.path.islink(full):
                errors.append(f"{rel} is a link. Links are not allowed.")
                continue
            size = os.path.getsize(full)
            files += 1
            total += size
            if size > MAX_FILE:
                errors.append(f"{rel} is larger than 1 MB.")
            if n.rsplit(".", 1)[-1].lower() not in ALLOWED_TYPES:
                errors.append(f"{rel} has a file type extensions can't include.")
    if files > MAX_FILES or total > MAX_TOTAL:
        errors.append("The extension is larger than 5 MB or has more than 200 files.")

    if m.get("manifest_version") != 1:
        errors.append("manifest_version must be 1.")
    ext_id = m.get("id")
    if not (isinstance(ext_id, str) and 3 <= len(ext_id) <= 64 and ID_RE.match(ext_id)):
        errors.append("id must be 3-64 lowercase letters, numbers, dots or dashes, like yourname.my-extension.")
        ext_id = None
    name = m.get("name")
    if not (isinstance(name, str) and 0 < len(name) <= 45):
        errors.append("name is required (up to 45 characters).")
    if not (isinstance(m.get("version"), str) and VERSION_RE.match(m["version"])):
        errors.append("version must look like 1.0.0.")
    desc = m.get("description", "")
    if not isinstance(desc, str) or len(desc) > 200:
        errors.append("description must be text of up to 200 characters.")
    author = m.get("author", "")
    if not isinstance(author, str) or len(author) > 60:
        errors.append("author must be text of up to 60 characters.")

    perms = m.get("permissions", [])
    if not isinstance(perms, list) or any(p not in PERMISSIONS for p in perms):
        errors.append("permissions must be a list of: " + ", ".join(sorted(PERMISSIONS)) + ".")
        perms = []

    scripts = m.get("content_scripts", [])
    if not isinstance(scripts, list) or len(scripts) > 10:
        errors.append("content_scripts must be a list of up to 10 entries.")
        scripts = []
    for i, e in enumerate(scripts):
        tag = f"content_scripts[{i}]"
        if not isinstance(e, dict):
            errors.append(f"{tag} must be an object.")
            continue
        matches = e.get("matches")
        if not isinstance(matches, list) or not 1 <= len(matches) <= 20 or not all(pattern_ok(p) for p in matches):
            errors.append(f"{tag}: matches needs 1-20 valid patterns, like https://example.com/* or <all_urls>.")
            matches = []
        for p in e.get("exclude_matches", []):
            if not pattern_ok(p):
                errors.append(f"{tag}: {p!r} is not a valid exclude pattern.")
        for key in ("js", "css"):
            lst = e.get(key, [])
            if not isinstance(lst, list):
                errors.append(f"{tag}: {key} must be a list of files.")
                continue
            for f in lst:
                if not rel_ok(f) or not f.lower().endswith("." + key) or not os.path.isfile(os.path.join(folder, f)):
                    errors.append(f"{tag}: can't find {key} file {f!r}.")
        if not e.get("js") and not e.get("css"):
            errors.append(f"{tag} needs at least one js or css file.")
        if e.get("run_at", "document_idle") not in RUN_AT:
            errors.append(f"{tag}: run_at must be document_start, document_end or document_idle.")
        if any(is_broad(p) for p in matches):
            warnings.append(f"{tag} runs on all websites. Reviewers will ask why that is needed.")

    action = m.get("action") if isinstance(m.get("action"), dict) else {}
    popup = action.get("popup")
    if popup is not None and (not rel_ok(popup) or not popup.lower().endswith(".html") or not os.path.isfile(os.path.join(folder, popup))):
        errors.append(f"Can't find popup page {popup!r}.")
    icon = m.get("icon")
    if icon is not None and (not rel_ok(icon) or not os.path.isfile(os.path.join(folder, icon))):
        errors.append(f"Can't find icon {icon!r}.")
    for w in m.get("web_accessible_resources", []):
        if not rel_ok(w) or not os.path.isfile(os.path.join(folder, w)):
            errors.append(f"web_accessible_resources: can't find {w!r}.")
    if not scripts and popup is None:
        errors.append("The extension does nothing: add content_scripts or an action with a popup.")

    if store:
        if ext_id and ext_id.startswith("local."):
            errors.append('Store extensions can\'t use an id that starts with "local." (that prefix is for your own copies).')
        if ext_id and os.path.basename(os.path.normpath(folder)) != ext_id:
            errors.append(f"The folder must be named after the id ({ext_id}).")
        if not desc:
            errors.append("A store listing needs a description.")
        if not author:
            errors.append("A store listing needs an author.")
        if not icon:
            warnings.append("No icon. A listing looks better with one.")
        if "storage" not in perms and any("storage." in open(os.path.join(folder, f), encoding="utf-8", errors="ignore").read() for f in _all_js(folder)):
            warnings.append("The code uses saturn.storage but the manifest doesn't list the 'storage' permission.")
        for f in _all_js(folder) + _all_html(folder):
            text = open(os.path.join(folder, f), encoding="utf-8", errors="ignore").read()
            if re.search(r"\beval\s*\(|new\s+Function\s*\(", text):
                errors.append(f"{f}: eval() and new Function() aren't allowed in store extensions.")
            if f.endswith(".html") and re.search(r"<script(?![^>]*\bsrc=)[^>]*>\s*\S", text, re.I):
                errors.append(f"{f}: inline scripts don't run in popups. Move the code into a .js file.")
            if f.endswith(".html") and re.search(r"<script[^>]+src=[\"']https?://", text, re.I):
                errors.append(f"{f}: remote scripts aren't allowed. Include the code in the extension.")
    return errors, warnings, m


def _walk(folder, ext):
    out = []
    for dirpath, _, names in os.walk(folder):
        for n in names:
            if n.lower().endswith(ext):
                out.append(os.path.relpath(os.path.join(dirpath, n), folder))
    return sorted(out)


def _all_js(folder):
    return _walk(folder, ".js")


def _all_html(folder):
    return _walk(folder, ".html")


def package(folder, out_zip):
    """Deterministic zip: sorted entries, fixed timestamps, manifest.json at the root."""
    entries = []
    for dirpath, _, names in os.walk(folder):
        for n in names:
            if n == ".DS_Store":
                continue
            entries.append(os.path.relpath(os.path.join(dirpath, n), folder))
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in sorted(entries):
            info = zipfile.ZipInfo(rel.replace(os.sep, "/"), date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(os.path.join(folder, rel), "rb") as f:
                z.writestr(info, f.read())
    with open(out_zip, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def cmd_validate(folders):
    bad = 0
    for folder in folders:
        folder = folder.rstrip("/")
        store = os.path.abspath(folder).startswith(os.path.join(STORE, "extensions"))
        errors, warnings, _ = validate(folder, store=store)
        status = "FAIL" if errors else "ok"
        print(f"{status:4} {folder}")
        for w in warnings:
            print(f"     warning: {w}")
        for e in errors:
            print(f"     error:   {e}")
        bad += bool(errors)
    return 1 if bad else 0


def cmd_build_store():
    ext_dir = os.path.join(STORE, "extensions")
    pkg_dir = os.path.join(STORE, "packages")
    os.makedirs(pkg_dir, exist_ok=True)
    listing, failed = [], False
    seen = set()
    for name in sorted(os.listdir(ext_dir)):
        folder = os.path.join(ext_dir, name)
        if not os.path.isdir(folder) or name.startswith("."):
            continue
        errors, warnings, m = validate(folder, store=True)
        for w in warnings:
            print(f"{name}: warning: {w}")
        if errors:
            failed = True
            for e in errors:
                print(f"{name}: error: {e}")
            continue
        if m["id"] in seen:
            print(f"{name}: error: duplicate id {m['id']}")
            failed = True
            continue
        seen.add(m["id"])
        zip_name = f"{m['id']}-{m['version']}.zip"
        digest = package(folder, os.path.join(pkg_dir, zip_name))
        sites = sorted({p for e in m.get("content_scripts", []) for p in e["matches"]})
        listing.append({
            "id": m["id"], "name": m["name"], "version": m["version"], "description": m.get("description", ""), "author": m.get("author", ""),
            "tags": [t for t in m.get("tags", []) if isinstance(t, str)][:5], "permissions": m.get("permissions", []), "sites": sites,
            "download": f"packages/{zip_name}", "sha256": digest,
        })
        print(f"built {zip_name}")
    if failed:
        return 1
    # Remove packages that no listing points to (old versions, deleted extensions).
    keep = {os.path.basename(i["download"]) for i in listing}
    for f in os.listdir(pkg_dir):
        if f.endswith(".zip") and f not in keep:
            os.remove(os.path.join(pkg_dir, f))
    with open(os.path.join(STORE, "index.json"), "w", encoding="utf-8") as f:
        json.dump({"version": 1, "extensions": listing}, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote store/index.json with {len(listing)} extension(s)")
    return 0


def main(argv):
    if len(argv) >= 3 and argv[1] == "validate":
        return cmd_validate(argv[2:])
    if len(argv) == 2 and argv[1] == "build-store":
        return cmd_build_store()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
