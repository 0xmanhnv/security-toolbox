# security-toolbox

A container base image with common web and security tooling, a headless browser and two
non-root sandbox users. It is meant to be used as a base (`FROM`) for a downstream
application image, which adds its own code and any extra dependencies on top.

The image bundles only open-source software. It contains **no application code and no
secrets** — just tools, their dependencies and the users to run them as.

> **Name.** `security-toolbox` is a default. The name is used only in this README, in the
> image `LABEL`, and in the CI workflow's package path; rename it freely when you build or
> publish (and update those three places to match).

## What's inside

- **Base OS & runtimes** — Debian (bookworm, via `python:3.12-slim`), Python 3.12,
  Node.js 22.x (from NodeSource).
- **Python libraries** (installed into the image's `python3`, pinned with hashes):
  `requests`, `httpx`, `PyJWT`, `cryptography`, `Werkzeug`.
- **Scanners & utilities** (pinned release binaries, each verified against the checksum
  published in its own release): nuclei, httpx (the ProjectDiscovery prober), subfinder,
  katana, ffuf, dalfox, sqlmap, jq, ripgrep.
- **nuclei templates** — one pinned release, pruned to a conservative HTTP-only subset
  (`scripts/nuclei-templates-prune.py`), baked read-only at `/opt/nuclei-templates`. The
  sandbox user's nuclei config points at it, so templates resolve with nothing downloaded.
- **Headless browser** — Playwright's Chromium (full + headless-shell builds) plus the
  Playwright browser MCP server and CLI, pinned to one Playwright build.
- **jwt-secret-check** — a small offline utility that tests HMAC-signed JWTs
  (HS256/384/512) against a bundled list of weak/default secrets. It never sends a
  request; the signature is recomputed locally.
- **Two non-root users** — `runner` (uid 10001, a primary/service process) and `sandbox`
  (uid 10002, for running the bundled tools). No setuid binaries remain in the image.

Everything the image ships is described in [`manifest.json`](manifest.json). The final
build step (`scripts/tools-check.py`) fails the build if the image and the manifest
disagree, so the two can't drift apart.

## Build

```sh
docker build -f Dockerfile -t security-toolbox .
```

The build fetches pinned tool releases from GitHub and installs the Playwright browser,
so it needs network access. Tool versions are build args at the top of the `Dockerfile`
and must match `manifest.json`.

## Use as a base image

```dockerfile
FROM ghcr.io/0xmanhnv/security-toolbox:latest
# ... add your application code and any extra dependencies here ...
# Run as a non-root user, e.g.:
USER sandbox
```

A downstream image is where application-specific dependencies belong (for example, Node
or Python packages a particular workload needs). This base image deliberately ships only
the common tooling above.

## Scrub gate

`./scrub-check.sh` is a committed check that scans every file for terms that would tie
this generic image to any private project it might have been extracted from. It must pass
with zero hits; CI runs it on every push and pull request.

## License & credits

This repository's own packaging code is under the [MIT License](LICENSE). The bundled
third-party tools keep their own licenses — see [CREDITS.md](CREDITS.md).
