#!/usr/bin/env python3
"""jwt-secret-check: test HMAC-signed JWTs (HS256/384/512) against a list of weak secrets.

    jwt-secret-check <token> [<token> ...]
    jwt-secret-check -f tokens.txt -w extra-words.txt --words vampi,api --mutate

Offline: it never sends a request. The signature is recomputed locally for every
candidate, so a hit is proof the secret signs the token. Candidates, in order: the empty
secret, the bundled list of common and framework-default secrets, -w files, --words, and
with --mutate the --words in common spellings (case, separators, year and "secret"/"key"
suffixes). Prints one JSON line per token; exit 0 when a secret was found, 1 when none
was, 2 on bad input.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import sys

VERSION = "1"
DEFAULT_LIST = os.environ.get("JWT_SECRETS_LIST", "/usr/local/share/toolbox/jwt-secrets.txt")
ALGS = {"HS256": hashlib.sha256, "HS384": hashlib.sha384, "HS512": hashlib.sha512}


def b64d(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def parse(token):
    parts = token.strip().split(".")
    if len(parts) != 3:
        raise ValueError("not a JWS compact token (want header.payload.signature)")
    header = json.loads(b64d(parts[0]))
    return header, (parts[0] + "." + parts[1]).encode(), b64d(parts[2])


def read_list(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if line and not line.startswith("#"):
                yield line


def mutations(word):
    seps = ["", "_", "-", "."]
    bases = {word, word.lower(), word.upper(), word.capitalize()}
    for b in sorted(bases):
        yield b
        for sep in seps:
            for suffix in ("secret", "key", "jwt", "token", "secretkey", "secret_key", "123", "2024", "2025", "2026"):
                for s in {suffix, suffix.capitalize(), suffix.upper()}:
                    yield b + sep + s
                    yield s + sep + b


def candidates(args):
    seen = set()

    def fresh(items):
        for c in items:
            if c not in seen:
                seen.add(c)
                yield c

    yield from fresh([""])
    if not args.no_default and os.path.exists(DEFAULT_LIST):
        yield from fresh(read_list(DEFAULT_LIST))
    for w in args.wordlist or []:
        yield from fresh(read_list(w))
    words = [w for w in (args.words or "").split(",") if w]
    yield from fresh(words)
    if args.mutate:
        for w in words:
            yield from fresh(mutations(w))


def check(token, args):
    try:
        header, signing_input, sig = parse(token)
    except Exception as e:  # noqa: BLE001
        return {"token": token[:24] + "...", "error": str(e)}
    alg = str(header.get("alg", ""))
    out = {"token": token[:24] + "...", "alg": alg}
    if alg not in ALGS:
        out["error"] = "alg %r is not HMAC; nothing to guess (try alg confusion or none by hand)" % alg
        return out
    h = ALGS[alg]
    tried = 0
    for c in candidates(args):
        tried += 1
        if hmac.compare_digest(hmac.new(c.encode(), signing_input, h).digest(), sig):
            out.update(found=True, secret=c, tried=tried)
            return out
    out.update(found=False, tried=tried)
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("tokens", nargs="*", help="JWTs")
    p.add_argument("-f", "--file", help="file with one token per line")
    p.add_argument("-w", "--wordlist", action="append", help="extra candidate list (repeatable)")
    p.add_argument("--words", help="comma-separated extra candidates, e.g. the app or host name")
    p.add_argument("--mutate", action="store_true", help="also try common spellings of --words")
    p.add_argument("--no-default", action="store_true", help="skip the bundled list")
    p.add_argument("--version", action="version", version="jwt-secret-check " + VERSION)
    args = p.parse_args()
    tokens = list(args.tokens)
    if args.file:
        tokens += list(read_list(args.file))
    if not tokens:
        p.print_usage(sys.stderr)
        return 2
    found, bad = False, False
    for t in tokens:
        r = check(t, args)
        print(json.dumps(r), flush=True)
        found = found or r.get("found", False)
        bad = bad or "error" in r
    if found:
        return 0
    return 2 if bad and len(tokens) == 1 else 1


if __name__ == "__main__":
    sys.exit(main())
