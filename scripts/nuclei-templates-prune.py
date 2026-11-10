"""Cut an unpacked nuclei-templates release down to the set the image ships.

    python3 -I nuclei-templates-prune.py <unpacked release dir> <dest dir>

Runs at image build time on a release whose archive was already checked against the
release's published checksum. It copies a conservative, HTTP-only subset of the
templates and writes PRUNED.txt into dest with the counts and the rules. The image
ships this subset so the bundled scanner has a usable default set without any download.

What is kept: HTTP templates. Everything else is dropped because it needs a protocol
or capability outside the scope of a plain HTTP request (dns, ssl, network, javascript,
headless), local code execution or files (code, file), or the fuzzing engine (dast).

What is dropped from http/, by directory, tag or shape:
  intrusive, dos, fuzz, brute force   state changes, load, or credential guessing
  default-login, credential-stuffing  logins with guessed credentials
  osint                               look up people's handles on third-party sites (PII)
  token-spray, self-contained         talk to fixed third-party APIs, never the target
  oast                                need the interaction server, which -ni turns off
  workflows                           reference templates by path, some of them dropped

A downstream image or caller can ship the full template set instead if it needs the
dropped categories; this is only a safe default.
"""
import os
import re
import shutil
import sys

KEEP_DIRS = ("http",)
DROP_SUBDIRS = {"credential-stuffing", "default-logins", "fuzzing", "osint", "token-spray"}
DROP_TAGS = {
    "intrusive", "dos", "fuzz", "fuzzing", "bruteforce", "brute-force", "default-login",
    "creds-stuffing", "token-spray", "osint", "oast",
}
DROP_TAG_PREFIXES = ("osint-",)

TAGS_RE = re.compile(r"^\s+tags:\s*(.*)$")
SELF_CONTAINED_RE = re.compile(r"^\s*self-contained:\s*true\b", re.M)
DAST_RE = re.compile(r"^\s+fuzzing:\s*$", re.M)


def tags_of(text):
    for line in text.splitlines():
        m = TAGS_RE.match(line)
        if m:
            raw = m.group(1).strip().strip("'\"")
            return {t.strip().strip("'\"").lower() for t in raw.split(",") if t.strip()}
    return set()


def why_dropped(rel, text):
    parts = rel.split(os.sep)
    if len(parts) > 1 and parts[1] in DROP_SUBDIRS:
        return "dir:" + parts[1]
    tags = tags_of(text)
    for t in sorted(tags):
        if t in DROP_TAGS or t.startswith(DROP_TAG_PREFIXES):
            return "tag:" + (t if t in DROP_TAGS else t.split("-")[0])
    if SELF_CONTAINED_RE.search(text):
        return "self-contained"
    if DAST_RE.search(text):
        return "fuzzing"
    return ""


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dest = sys.argv[1], sys.argv[2]
    if not os.path.isdir(os.path.join(src, "http")):
        sys.exit("%s does not look like a nuclei-templates release (no http/)" % src)
    kept, dropped = 0, {}
    for top in KEEP_DIRS:
        for root, dirs, files in os.walk(os.path.join(src, top)):
            dirs.sort()
            for name in sorted(files):
                if not name.endswith(".yaml"):
                    continue
                path = os.path.join(root, name)
                rel = os.path.relpath(path, src)
                with open(path, encoding="utf-8", errors="replace") as f:
                    text = f.read()
                why = why_dropped(rel, text)
                if why:
                    dropped[why] = dropped.get(why, 0) + 1
                    continue
                out = os.path.join(dest, rel)
                os.makedirs(os.path.dirname(out), exist_ok=True)
                shutil.copyfile(path, out)
                kept += 1
    # helpers/ holds the payload and wordlist files some kept templates read
    if os.path.isdir(os.path.join(src, "helpers")):
        shutil.copytree(os.path.join(src, "helpers"), os.path.join(dest, "helpers"), dirs_exist_ok=True)
    for name in ("LICENSE.md",):
        if os.path.exists(os.path.join(src, name)):
            shutil.copyfile(os.path.join(src, name), os.path.join(dest, name))
    if kept < 1000:
        sys.exit("only %d templates kept: the release layout changed, check the prune rules" % kept)
    lines = ["kept %d http templates" % kept]
    lines += ["dropped %d (%s)" % (n, why) for why, n in sorted(dropped.items())]
    lines += ["excluded tags: " + ",".join(sorted(DROP_TAGS)) + ",osint-*",
              "excluded dirs: http/" + ",http/".join(sorted(DROP_SUBDIRS)),
              "kept protocols: " + ",".join(KEEP_DIRS)]
    with open(os.path.join(dest, "PRUNED.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
