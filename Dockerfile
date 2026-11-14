# syntax=docker/dockerfile:1
#
# security-toolbox: a container base image with common web and security tooling, a
# headless browser and two non-root sandbox users. It is meant to be used as a base
# (FROM) for a downstream application image, which adds its own code and any extra
# dependencies on top. It bundles only open-source tools: Debian packages, Node, a set
# of Python libraries, a pinned set of scanners, a pruned nuclei template set, the
# browser (Playwright + Chromium) and an offline JWT secret checker.
#
# It changes less often than a typical application, so it is built and published on its
# own. Its contents are described by manifest.json, and the build fails if the image and
# the manifest disagree (scripts/tools-check.py, the last build step).
#
#   docker build -f Dockerfile -t security-toolbox .
#
# The image name is a default; rename it freely when you build or publish.

# Tools: pinned release binaries, each checked against the checksum published in the
# same GitHub release (scripts/fetch.sh). sqlmap has no release binaries: it is a
# checkout of a tag that must resolve to the pinned commit. Every version here is also
# in manifest.json; the build fails when the two disagree.
ARG NUCLEI_VERSION=v3.11.1
ARG HTTPX_VERSION=v1.12.0
ARG SUBFINDER_VERSION=v2.17.0
ARG KATANA_VERSION=v1.8.0
ARG FFUF_VERSION=v2.3.0
ARG DALFOX_VERSION=v3.2.4
ARG JQ_VERSION=1.8.2
ARG RIPGREP_VERSION=15.2.0
ARG SQLMAP_VERSION=1.10.11
ARG SQLMAP_COMMIT=6faa9bb929347189a62c046d7d02349140e9933d
# jsluice has no releases or tags: it is built from a pinned module version (a commit
# pseudo-version) whose module hash must equal JSLUICE_SUM, the hash the Go checksum
# database records for it; every dependency is checked against that database too.
# It parses JavaScript with tree-sitter (cgo), so it is built on the same Debian release
# as the image.
ARG JSLUICE_VERSION=v0.0.0-20240110145140-0ddfab153e06
ARG JSLUICE_SUM=h1:xa/dJgg1qpWdIyr7tQcTV2TUPgBK/f0TTMLMmD5GqjQ=
ARG GO_BUILD_IMAGE=golang:1.27.3-bookworm
# nuclei templates: one pinned release, cut down by scripts/nuclei-templates-prune.py to
# a conservative HTTP-only subset (no intrusive, DoS, fuzzing, brute force, default-login,
# OSINT/PII, token-spray, OAST or third-party templates). Ship the full set instead by
# adjusting the prune rules if you need the dropped categories.
ARG NUCLEI_TEMPLATES_VERSION=10.5.1
# The browser MCP and playwright-cli. Pinned versions (never @latest): a new release
# can't change the image underneath us.
ARG PLAYWRIGHT_MCP_VERSION=0.0.84
ARG PLAYWRIGHT_CLI_VERSION=0.1.23
# Debian packages and the python base image are not pinned by version. Bump this date
# to rebuild the image with the current security updates when nothing else changed.
ARG TOOLBOX_REFRESH=2026-11-09

# ------------------------------------------------------------------ fetch ---
# Downloads happen in their own stages: they run in parallel, a version bump refetches
# only that tool, and the download tools (unzip, git for the sqlmap checkout) stay out
# of the final image unless it needs them itself.
FROM python:3.12-slim-bookworm AS fetch-base
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip
COPY scripts/fetch.sh /usr/local/bin/toolbox-fetch

FROM fetch-base AS fetch-nuclei
ARG TARGETARCH
ARG NUCLEI_VERSION
RUN toolbox-fetch nuclei

FROM fetch-base AS fetch-httpx
ARG TARGETARCH
ARG HTTPX_VERSION
RUN toolbox-fetch httpx

FROM fetch-base AS fetch-subfinder
ARG TARGETARCH
ARG SUBFINDER_VERSION
RUN toolbox-fetch subfinder

FROM fetch-base AS fetch-katana
ARG TARGETARCH
ARG KATANA_VERSION
RUN toolbox-fetch katana

FROM fetch-base AS fetch-small
ARG TARGETARCH
ARG FFUF_VERSION
ARG DALFOX_VERSION
ARG JQ_VERSION
ARG RIPGREP_VERSION
RUN toolbox-fetch ffuf && toolbox-fetch dalfox && toolbox-fetch jq && toolbox-fetch rg

FROM fetch-base AS fetch-sqlmap
ARG TARGETARCH
ARG SQLMAP_VERSION
ARG SQLMAP_COMMIT
RUN toolbox-fetch sqlmap

FROM fetch-base AS fetch-templates
ARG TARGETARCH
ARG NUCLEI_TEMPLATES_VERSION
COPY scripts/nuclei-templates-prune.py /usr/local/bin/nuclei-templates-prune
RUN toolbox-fetch nuclei-templates

# jsluice: URLs, paths, parameters and secrets out of JavaScript, read offline from
# files. Built, not downloaded (see JSLUICE_VERSION above).
FROM ${GO_BUILD_IMAGE} AS build-jsluice
ARG JSLUICE_VERSION
ARG JSLUICE_SUM
ENV GOFLAGS=-mod=mod GOSUMDB=sum.golang.org GOTOOLCHAIN=local CGO_ENABLED=1
RUN set -eu; \
    got="$(go mod download -json "github.com/BishopFox/jsluice@${JSLUICE_VERSION}" | sed -n 's/.*"Sum": "\(.*\)".*/\1/p')"; \
    [ "$got" = "$JSLUICE_SUM" ] || { echo "jsluice module hash mismatch: want $JSLUICE_SUM got $got" >&2; exit 1; }; \
    GOBIN=/out/bin go install -trimpath -ldflags='-s' "github.com/BishopFox/jsluice/cmd/jsluice@${JSLUICE_VERSION}"; \
    /out/bin/jsluice --help >/dev/null 2>&1 || [ $? -le 2 ]

# Everything fetched, laid out as it lands in the image.
FROM scratch AS tools
COPY --from=fetch-nuclei /out/bin/ /usr/local/bin/
COPY --from=fetch-httpx /out/bin/ /usr/local/bin/
COPY --from=fetch-subfinder /out/bin/ /usr/local/bin/
COPY --from=fetch-katana /out/bin/ /usr/local/bin/
COPY --from=fetch-small /out/bin/ /usr/local/bin/
COPY --from=fetch-sqlmap /out/bin/ /usr/local/bin/
COPY --from=fetch-sqlmap /out/opt/ /opt/
COPY --from=fetch-templates /out/opt/ /opt/
COPY --from=build-jsluice /out/bin/ /usr/local/bin/

# ---------------------------------------------------------------- toolbox ---
FROM python:3.12-slim-bookworm AS toolbox
ARG TARGETARCH
ARG TOOLBOX_REFRESH
LABEL org.opencontainers.image.source="https://github.com/0xmanhnv/security-toolbox" \
      org.opencontainers.image.description="Base image with common web and security tooling, a headless browser and sandbox users"
# Base tools from Debian. Node 22.x comes from NodeSource: bookworm's apt nodejs is 18,
# Playwright requires >=20, and 20 is end-of-life. 22 matches the CI and release workflows.
# dig and nc stay for an interactive root shell. NodeSource's setup installs gnupg only
# to unpack its key; apt verifies with gpgv, so gnupg is removed again once nodejs is in.
# Node's C headers (65 MB) are only for compiling native addons, which nothing here does:
# every npm install in the image runs with --ignore-scripts.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'path-exclude=/usr/include/node/*' > /etc/dpkg/dpkg.cfg.d/toolbox-no-node-headers \
    && apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git \
      dnsutils netcat-openbsd \
      nftables \
    && curl -fsSL --connect-timeout 30 --retry 8 --retry-all-errors --retry-connrefused https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get purge -y --auto-remove gnupg \
    && node --version && npm --version
# Python libraries commonly imported by scripts (requests, httpx, PyJWT, cryptography,
# Werkzeug), into the image's python3 so they work for every user. Pinned with hashes;
# the build fails on anything not in the file. The httpx library installs an `httpx`
# command into /usr/local/bin, the same name as the ProjectDiscovery scanner: it is
# removed here, before the scanner is copied in. jwt-secret-check is the offline HMAC
# JWT secret checker with its bundled candidate list.
COPY scripts/jwt-secret-check.py /usr/local/bin/jwt-secret-check
COPY scripts/jwt-secrets.txt /usr/local/share/toolbox/jwt-secrets.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=bind,source=scripts/python-requirements.txt,target=/tmp/py-req.txt \
    pip install --require-hashes --only-binary=:all: -r /tmp/py-req.txt \
    && rm /usr/local/bin/httpx \
    && chmod 0755 /usr/local/bin/jwt-secret-check && chmod -R a+rX /usr/local/share/toolbox \
    && python3 -c "import requests, httpx, jwt, cryptography, werkzeug" \
    && jwt-secret-check --help >/dev/null

# The fetched tools (/usr/local/bin), sqlmap (/opt/sqlmap) and the nuclei template subset
# (/opt/nuclei-templates, read-only; the sandbox user's nuclei config points there, so
# `nuclei -id ...` and `-tags ...` work without -t and nothing is downloaded).
COPY --link --from=tools / /
RUN nuclei -version -duc >/dev/null 2>&1 && httpx -version -duc && subfinder -version -duc && katana -version -duc \
    && ffuf -V >/dev/null && dalfox --version >/dev/null && sqlmap --version >/dev/null && jq --version && rg --version \
    && printf 'fetch("/api/v1/users?id=1")' > /tmp/j.js && jsluice urls /tmp/j.js | grep -q '/api/v1/users' && rm /tmp/j.js

# Browsers live outside root's home so the non-root users find them.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
# The browser MCP (@playwright/mcp, `playwright-mcp`) and playwright-cli are global
# installs, so nothing is fetched with npx at run time. Both pin the same Playwright
# build, and Chromium is installed by that build's own installer: a browser from any
# other Playwright release has another revision, which they do not find. Both default
# to Google Chrome, which the image does not ship; PLAYWRIGHT_MCP_BROWSER=chromium
# points them at this Chromium.
#
# Playwright installs two Chromium builds and both are kept: the full one (Playwright's
# chrome-for-testing channel, headless or not) and the headless shell. Playwright's
# dependency list also brings xvfb for headed runs under a virtual display; nothing in
# the image starts an X server, so xvfb and what only it needs (Mesa, LLVM, the X server)
# are removed again. The ldd check fails the build if either browser is left missing a
# library.
ARG PLAYWRIGHT_MCP_VERSION
ARG PLAYWRIGHT_CLI_VERSION
ENV PLAYWRIGHT_MCP_BROWSER=chromium
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/root/.npm \
    set -eux; \
    npm install -g --no-audit --no-fund "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}"; \
    core() { node -p "require.resolve('playwright-core/package.json', {paths: ['$1']})"; }; \
    mcp_core="$(core /usr/lib/node_modules/@playwright/mcp)"; cli_core="$(core /usr/lib/node_modules/@playwright/cli)"; \
    [ "$(node -p "require('$mcp_core').version")" = "$(node -p "require('$cli_core').version")" ] \
      || { echo "@playwright/mcp and @playwright/cli pin different Playwright builds" >&2; exit 1; }; \
    node "$(dirname "$mcp_core")/cli.js" install --with-deps chromium; \
    apt-get purge -y --auto-remove xvfb; \
    for d in /usr/lib/node_modules/@playwright/mcp /usr/lib/node_modules/@playwright/cli; do \
      node -e "const pw=require(require.resolve('playwright-core',{paths:['$d']})); \
        if(!require('fs').existsSync(pw.chromium.executablePath())){console.error('$d: no '+pw.chromium.executablePath());process.exit(1)}"; \
    done; \
    chrome="$(ls -d /opt/ms-playwright/chromium-*/chrome-linux*/chrome)"; \
    shell="$(ls -d /opt/ms-playwright/chromium_headless_shell-*/chrome-*/chrome-headless-shell)"; \
    for b in "$chrome" "$shell"; do \
      if ldd "$b" | grep -q 'not found'; then ldd "$b" | grep 'not found' >&2; exit 1; fi; \
    done; \
    ln -s "$chrome" /usr/local/bin/chromium; \
    chmod -R a+rX /opt/ms-playwright; \
    playwright-cli --version; playwright-mcp --version; chromium --version; "$shell" --version
# A downstream application image adds its own extra dependencies on top of this base
# (for example, Node or Python packages a particular workload needs). This base image
# ships only the common tooling above; it installs no application-specific packages.

# Two non-root users (runner / sandbox), no setuid binaries. The sandbox user's nuclei
# config points at the baked template subset.
RUN --mount=type=bind,source=scripts/users.sh,target=/tmp/users.sh \
    sh /tmp/users.sh \
    && mkdir -p /home/sandbox/.config/nuclei \
    && printf '{"nuclei-templates-directory":"/opt/nuclei-templates","nuclei-latest-templates-version":"v%s"}\n' \
       "$(cat /opt/nuclei-templates/VERSION)" > /home/sandbox/.config/nuclei/.templates-config.json \
    && ln -s /opt/nuclei-templates /home/sandbox/nuclei-templates \
    && chown -R sandbox:sandbox /home/sandbox/.config
# Every program, library and the template set must match manifest.json.
RUN --mount=type=bind,source=manifest.json,target=/tmp/itc/manifest.json \
    --mount=type=bind,source=scripts/tools-check.py,target=/tmp/itc/tools-check.py \
    python3 -I /tmp/itc/tools-check.py /tmp/itc/manifest.json
