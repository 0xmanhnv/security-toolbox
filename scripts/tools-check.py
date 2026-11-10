"""Image build check: the image matches manifest.json.

    python3 -I tools-check.py <manifest.json>

Runs as the last step of the image build. Fails the build when a listed tool is missing
or its probe reports another version, a Python library is missing or another version, a
system program is missing, an "absent" program is present after all, or the nuclei
template set is not the pinned release. manifest.json is the single source of truth for
what the image ships, so the build and any downstream consumer can check against it.
"""
import importlib
import importlib.metadata
import json
import os
import re
import shutil
import subprocess
import sys


def version_ok(want, got):
    if got is None:
        return False
    if want.endswith(".x"):
        return got.startswith(want[:-1]) or got == want[:-2]
    return got == want


def probe(argv, match):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=60,
                           env=dict(os.environ, HOME="/tmp/itc-home"))
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, str(e)
    out = p.stdout + p.stderr
    m = re.search(match, out)
    return (m.group(1) if m else None), out.strip()[-300:]


def main():
    with open(sys.argv[1]) as f:
        m = json.load(f)
    bad = []
    for t in m["tools"]:
        if not shutil.which(t["probe"][0]):
            bad.append("%s: not on PATH" % t["name"])
            continue
        got, tail = probe(t["probe"], t["match"])
        if not version_ok(t["version"], got):
            bad.append("%s: manifest says %s, probe found %r (%s)" % (t["name"], t["version"], got, tail))
        else:
            print("ok  %-18s %s" % (t["name"], got))
    for py in m.get("python", []):
        try:
            importlib.import_module(py["import"])
            got = importlib.metadata.version(py["name"])
        except Exception as e:  # noqa: BLE001
            bad.append("python %s: %s" % (py["name"], e))
            continue
        if got != py["version"]:
            bad.append("python %s: manifest says %s, installed %s" % (py["name"], py["version"], got))
        else:
            print("ok  python %-11s %s" % (py["name"], got))
    for name in m.get("system", []):
        if not shutil.which(name):
            bad.append("system %s: not on PATH" % name)
    for a in m.get("absent", []):
        if shutil.which(a["name"]):
            bad.append("%s is listed as absent but is on PATH (%s)" % (a["name"], shutil.which(a["name"])))
    tpl = m.get("nuclei_templates")
    if tpl:
        try:
            with open(os.path.join(tpl["dir"], "VERSION")) as f:
                got = f.read().strip()
        except OSError as e:
            got = str(e)
        if got != tpl["version"]:
            bad.append("nuclei templates: manifest says %s, image has %s" % (tpl["version"], got))
        else:
            print("ok  nuclei-templates   %s" % got)
    if bad:
        print("image does not match manifest.json:", file=sys.stderr)
        for b in bad:
            print("  " + b, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
