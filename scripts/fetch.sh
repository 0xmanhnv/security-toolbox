#!/bin/sh
# Image build step (Dockerfile, one fetch stage per tool): download one pinned tool,
# check it against the checksum its own release publishes, and install it into /out
# (binaries in /out/bin, which the image copies to /usr/local/bin). The build fails on
# a missing or mismatched checksum.
#
#   fetch.sh <tool>              tool: nuclei httpx subfinder katana ffuf dalfox jq rg
#                                      sqlmap nuclei-templates
#
# Versions come from the stage's build args (NUCLEI_VERSION, ...); the defaults live
# at the top of the Dockerfile and must match manifest.json.
set -eu

base="https://github.com"
arch="${TARGETARCH:?TARGETARCH is not set}"
mkdir -p /out/bin

# A cache-cold rebuild fetches every asset at once, and the release CDN answers a
# burst with the occasional transient 504/5xx (or a secondary rate-limit) that -f
# turns into a failed build. Retry with backoff so a blip rides out; a genuinely
# missing asset still fails after the retries (fail-closed) and
# scripts/tools-verify.sh catches a bad pin before a deploy.
fetch() { curl -fsSL --connect-timeout 30 --retry 8 --retry-all-errors --retry-connrefused "$1" -o "$2"; }
verify() {
  file="$1"; want="$2"
  [ -n "$want" ] || { echo "no published checksum for $file" >&2; exit 1; }
  got="$(sha256sum "$file" | cut -d' ' -f1)"
  [ "$got" = "$want" ] || { echo "checksum mismatch for $file: want $want got $got" >&2; exit 1; }
}
sum_for() { awk -v a="$1" '{f=$2; sub(/^\*/, "", f)} f == a {print $1}' "$2"; }
install_from() {
  dir="$1"; name="$2"
  find "$dir" -type f -name "$name" -exec install -m 0755 {} /out/bin/ \;
  rm -rf "$dir"
  [ -x "/out/bin/$name" ] || { echo "$name not found in its release archive" >&2; exit 1; }
}
# pd_fetch: a ProjectDiscovery release zip and its checksums file.
pd_fetch() {
  repo="$1"; ver="$2"; name="$3"; sums="$4"; nov="${ver#v}"
  asset="${name}_${nov}_linux_${arch}.zip"
  fetch "$base/$repo/releases/download/$ver/$asset" /tmp/t.zip
  fetch "$base/$repo/releases/download/$ver/$sums" /tmp/sums.txt
  verify /tmp/t.zip "$(sum_for "$asset" /tmp/sums.txt)"
  unzip -o -q /tmp/t.zip -d /tmp/td; rm -f /tmp/t.zip /tmp/sums.txt
  install_from /tmp/td "$name"
}
# tgz_fetch: a tar.gz release whose checksum is either a line in a sums file
# (sums_mode=list) or the first field of a per-asset .sha256 file (sums_mode=single).
tgz_fetch() {
  url="$1"; sums_url="$2"; sums_mode="$3"; asset="$4"; name="$5"
  fetch "$url" /tmp/t.tgz
  fetch "$sums_url" /tmp/sums.txt
  if [ "$sums_mode" = list ]; then
    verify /tmp/t.tgz "$(sum_for "$asset" /tmp/sums.txt)"
  else
    verify /tmp/t.tgz "$(awk '{print $1; exit}' /tmp/sums.txt)"
  fi
  mkdir -p /tmp/td && tar -xzf /tmp/t.tgz -C /tmp/td; rm -f /tmp/t.tgz /tmp/sums.txt
  install_from /tmp/td "$name"
}

case "$arch" in
  amd64) FFUF_ARCH=amd64; DALFOX_ARCH=x86_64; RG_TRIPLE=x86_64-unknown-linux-musl ;;
  arm64) FFUF_ARCH=arm64; DALFOX_ARCH=aarch64; RG_TRIPLE=aarch64-unknown-linux-musl ;;
  *) echo "unsupported TARGETARCH $arch" >&2; exit 1 ;;
esac

tool="${1:?usage: fetch.sh <tool>}"
case "$tool" in
  nuclei)
    pd_fetch projectdiscovery/nuclei "$NUCLEI_VERSION" nuclei "nuclei_${NUCLEI_VERSION#v}_checksums.txt"
    /out/bin/nuclei -version -duc >/dev/null 2>&1 ;;
  httpx)
    pd_fetch projectdiscovery/httpx "$HTTPX_VERSION" httpx "httpx_${HTTPX_VERSION#v}_checksums.txt"
    /out/bin/httpx -version -duc >/dev/null 2>&1 ;;
  subfinder)
    pd_fetch projectdiscovery/subfinder "$SUBFINDER_VERSION" subfinder "subfinder_${SUBFINDER_VERSION#v}_checksums.txt"
    /out/bin/subfinder -version -duc >/dev/null 2>&1 ;;
  katana)
    pd_fetch projectdiscovery/katana "$KATANA_VERSION" katana "katana-${KATANA_VERSION#v}-checksums.txt"
    /out/bin/katana -version -duc >/dev/null 2>&1 ;;
  ffuf)
    asset="ffuf_${FFUF_VERSION#v}_linux_${FFUF_ARCH}.tar.gz"
    rel="$base/ffuf/ffuf/releases/download/$FFUF_VERSION"
    tgz_fetch "$rel/$asset" "$rel/ffuf_${FFUF_VERSION#v}_checksums.txt" list "$asset" ffuf
    /out/bin/ffuf -V >/dev/null ;;
  dalfox)
    asset="dalfox-${DALFOX_VERSION}-linux-${DALFOX_ARCH}-musl.tar.gz"
    rel="$base/hahwul/dalfox/releases/download/$DALFOX_VERSION"
    tgz_fetch "$rel/$asset" "$rel/$asset.sha256" single "$asset" dalfox
    /out/bin/dalfox --version >/dev/null ;;
  jq)
    asset="jq-linux-${arch}"
    rel="$base/jqlang/jq/releases/download/jq-$JQ_VERSION"
    fetch "$rel/$asset" /tmp/jq
    fetch "$rel/sha256sum.txt" /tmp/sums.txt
    verify /tmp/jq "$(sum_for "$asset" /tmp/sums.txt)"
    install -m 0755 /tmp/jq /out/bin/jq; rm -f /tmp/jq /tmp/sums.txt
    /out/bin/jq --version ;;
  rg)
    asset="ripgrep-${RIPGREP_VERSION}-${RG_TRIPLE}.tar.gz"
    rel="$base/BurntSushi/ripgrep/releases/download/$RIPGREP_VERSION"
    tgz_fetch "$rel/$asset" "$rel/$asset.sha256" single "$asset" rg
    /out/bin/rg --version ;;
  sqlmap)
    # No release binaries: a checkout of the tag, which must resolve to the pinned
    # commit, linked into PATH.
    git clone --quiet --depth 1 --branch "$SQLMAP_VERSION" https://github.com/sqlmapproject/sqlmap /out/opt/sqlmap
    commit="$(git -C /out/opt/sqlmap rev-parse HEAD)"
    [ "$commit" = "$SQLMAP_COMMIT" ] || { echo "sqlmap commit mismatch: want $SQLMAP_COMMIT got $commit" >&2; exit 1; }
    rm -rf /out/opt/sqlmap/.git
    ln -s /opt/sqlmap/sqlmap.py /out/bin/sqlmap
    python3 /out/opt/sqlmap/sqlmap.py --version >/dev/null ;;
  nuclei-templates)
    # One pinned release, checked against the checksum the release publishes for its
    # source archive, cut down by scripts/nuclei-templates-prune.py (installed next to
    # this script as /usr/local/bin/nuclei-templates-prune) to the HTTP template
    # subset the image ships.
    v="$NUCLEI_TEMPLATES_VERSION"
    rel="$base/projectdiscovery/nuclei-templates/releases/download/v${v}"
    asset="nuclei-templates-${v}.tar.gz"
    fetch "$rel/nuclei-templates-${v}_checksums.txt" /tmp/sums.txt
    fetch "$base/projectdiscovery/nuclei-templates/archive/refs/tags/v${v}.tar.gz" /tmp/nt.tgz
    want="$(awk -v a="$asset" '$2 == a {print $1}' /tmp/sums.txt)"
    [ -n "$want" ] && [ "$(sha256sum /tmp/nt.tgz | cut -d' ' -f1)" = "$want" ] \
      || { echo "nuclei-templates checksum mismatch" >&2; exit 1; }
    mkdir -p /tmp/nt /out/opt && tar -xzf /tmp/nt.tgz -C /tmp/nt
    python3 -I /usr/local/bin/nuclei-templates-prune "/tmp/nt/nuclei-templates-${v}" /out/opt/nuclei-templates
    echo "$v" > /out/opt/nuclei-templates/VERSION
    rm -rf /tmp/nt /tmp/nt.tgz /tmp/sums.txt
    chmod -R a+rX,go-w /out/opt/nuclei-templates ;;
  *) echo "unknown tool: $tool" >&2; exit 1 ;;
esac
