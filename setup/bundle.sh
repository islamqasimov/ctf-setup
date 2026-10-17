#!/usr/bin/env bash
#
# bundle.sh - build an offline bundle for an air-gapped CTF box.
#
# Downloads every pinned tool from manifest.tsv, verifies its SHA256, and packs
# it together with this setup/ tree into:
#
#   dist/ctf-bundle-YYYYMMDD/
#   ├── install.sh  bundle.sh  manifest.tsv  README.md  ai-setup.sh
#   ├── scripts/  methodology/
#   ├── downloads/            # verified tool archives
#   └── wordlists/            # optional, with --with-wordlists
#
# and a tarball dist/ctf-bundle-YYYYMMDD.tar.zst (+ .sha256).
#
# On the offline machine:
#   tar xf ctf-bundle-YYYYMMDD.tar.zst
#   cd ctf-bundle-YYYYMMDD
#   ./install.sh --offline . --with-wordlists
#
#   ./bundle.sh                     # fetch everything, pack it
#   ./bundle.sh --with-wordlists    # also bundle pinned SecLists
#   ./bundle.sh --verify            # re-download and check manifest hashes (drift report)
#   ./bundle.sh --out /media/usb    # write the bundle somewhere else
#
set -euo pipefail

SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SETUP_DIR/manifest.tsv"
CACHE_DIR="${CTF_CACHE_DIR:-$HOME/.cache/ctf-tools}"
SECLISTS_TAG="${CTF_SECLISTS_TAG:-2026.1}"
SECLISTS_REPO="https://github.com/danielmiessler/SecLists.git"
# Curated subset — keep in sync with install.sh (SECLISTS_FILES).
SECLISTS_PATHS=(
  "Discovery/Web-Content/DirBuster-2007_directory-list-2.3-medium.txt"
  "Discovery/Web-Content/DirBuster-2007_directory-list-2.3-small.txt"
  "Discovery/Web-Content/common.txt"
  "Discovery/Web-Content/quickhits.txt"
  "Discovery/Web-Content/raft-small-directories.txt"
  "Discovery/Web-Content/raft-medium-directories.txt"
  "Discovery/Web-Content/raft-small-files.txt"
  "Discovery/Web-Content/big.txt"
  "Discovery/DNS/subdomains-top1million-5000.txt"
  "Discovery/DNS/namelist.txt"
)

WITH_WORDLISTS=0
VERIFY_ONLY=0
OUT_ROOT="$SETUP_DIR/dist"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'
else
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi
step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '     %s\n' "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: bundle.sh [options]

Options:
      --with-wordlists   Also bundle a pinned sparse SecLists clone.
      --verify           Only check manifest hashes (download + compare), pack nothing.
      --out DIR          Bundle root directory (default: setup/dist).
  -h, --help             Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with-wordlists) WITH_WORDLISTS=1 ;;
    --verify)         VERIFY_ONLY=1 ;;
    --out)            shift; OUT_ROOT="${1:?--out needs a directory}" ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -r "$MANIFEST" ] || die "manifest not found: $MANIFEST"
have curl || die "curl is required"
have sha256sum || die "sha256sum is required"

manifest_rows() { grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" | tail -n +2; }
url_basename() { printf '%s' "${1##*/}"; }

verify_sha() {
  local file="$1" want="$2" got
  [ -f "$file" ] || return 1
  got="$(sha256sum "$file" | awk '{print $1}')"
  [ "$got" = "$want" ]
}

# fetch <url> <sha> <dest> ; uses cache, downloads, verifies
fetch() {
  local url="$1" sha="$2" dest="$3"
  if verify_sha "$dest" "$sha"; then
    info "cached: $(url_basename "$url")"
    return 0
  fi
  mkdir -p "$CACHE_DIR"
  local cache="$CACHE_DIR/$(url_basename "$url")"
  if ! verify_sha "$cache" "$sha"; then
    info "downloading $(url_basename "$url")"
    curl -fsSL --retry 3 --connect-timeout 20 -o "$cache.part" "$url" || die "download failed: $url"
    mv -f "$cache.part" "$cache"
  fi
  verify_sha "$cache" "$sha" || die "SHA256 mismatch: $(url_basename "$url")"
  if [ "$dest" != "$cache" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -f "$cache" "$dest"
  fi
}

verify_manifest() {
  step "Verifying manifest hashes against upstream"
  local row rc=0
  while IFS= read -r row; do
    IFS=$'\t' read -r name version group kind bin url sha <<<"$row"
    local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/ctf-verify.XXXXXX")"
    if curl -fL --retry 2 -sS -o "$tmp" "$url" && [ "$(sha256sum "$tmp" | awk '{print $1}')" = "$sha" ]; then
      printf '%s  ok%s  %s %s\n' "$C_GREEN" "$C_RESET" "$name" "$version"
    else
      printf '%sfail%s  %s %s (manifest hash is stale — bump it)\n' "$C_RED" "$C_RESET" "$name" "$version"
      rc=1
    fi
    rm -f "$tmp"
  done < <(manifest_rows)
  return "$rc"
}

if [ "$VERIFY_ONLY" -eq 1 ]; then
  verify_manifest || exit 1
  exit 0
fi

# ---------------------------------------------------------------------------
STAMP="$(date +%Y%m%d)"
BUNDLE="$OUT_ROOT/ctf-bundle-$STAMP"
[ -e "$BUNDLE" ] && die "$BUNDLE already exists — remove it or wait for a new day (--out to change)"
mkdir -p "$BUNDLE/downloads"

step "Packing setup/ tree"
cp -f "$SETUP_DIR/install.sh" "$SETUP_DIR/bundle.sh" "$SETUP_DIR/manifest.tsv" "$BUNDLE/"
[ -f "$SETUP_DIR/README.md" ] && cp -f "$SETUP_DIR/README.md" "$BUNDLE/"
[ -f "$SETUP_DIR/ai-setup.sh" ] && cp -f "$SETUP_DIR/ai-setup.sh" "$BUNDLE/"
[ -f "$SETUP_DIR/ai-uninstall.sh" ] && cp -f "$SETUP_DIR/ai-uninstall.sh" "$BUNDLE/"
[ -f "$SETUP_DIR/ai-setup.md" ] && cp -f "$SETUP_DIR/ai-setup.md" "$BUNDLE/"
cp -a "$SETUP_DIR/scripts" "$BUNDLE/scripts"
[ -d "$SETUP_DIR/methodology" ] && cp -a "$SETUP_DIR/methodology" "$BUNDLE/methodology"
ok "setup tree copied"

step "Fetching pinned tools"
count=0
while IFS= read -r row; do
  IFS=$'\t' read -r name version group kind bin url sha <<<"$row"
  fetch "$url" "$sha" "$BUNDLE/downloads/$(url_basename "$url")"
  printf '%s  ok%s  %s %s\n' "$C_GREEN" "$C_RESET" "$name" "$version"
  count=$((count + 1))
done < <(manifest_rows)
ok "$count archive(s) in $BUNDLE/downloads"

if [ "$WITH_WORDLISTS" -eq 1 ]; then
  step "Bundling wordlists (SecLists $SECLISTS_TAG, curated subset)"
  have git || die "git is required for --with-wordlists"
  wl="$BUNDLE/wordlists/SecLists"
  mkdir -p "$(dirname "$wl")"
  rm -rf "$wl"
  git clone -q --filter=blob:none --no-checkout --depth 1 --branch "$SECLISTS_TAG" \
    "$SECLISTS_REPO" "$wl" || die "could not clone SecLists at tag $SECLISTS_TAG"
  git -C "$wl" sparse-checkout init --no-cone >/dev/null 2>&1 || true
  git -C "$wl" sparse-checkout set --no-cone "${SECLISTS_PATHS[@]}" \
    || die "could not select the SecLists subset"
  git -C "$wl" -c advice.detachedHead=false checkout -q || true
  ok "wordlists bundled: $wl ($(du -sh "$wl" | awk '{print $1}'))"
fi

step "Writing checksums"
( cd "$BUNDLE" && find . -type f ! -name 'BUNDLE.sha256' -print0 | sort -z \
    | xargs -0 sha256sum >BUNDLE.sha256 )
ok "$BUNDLE/BUNDLE.sha256"

step "Creating archive"
if have zstd; then
  tar -C "$OUT_ROOT" -cf "$BUNDLE.tar" "ctf-bundle-$STAMP"
  zstd -q -T0 --rm -f "$BUNDLE.tar" -o "$BUNDLE.tar.zst"
  ARCHIVE="$BUNDLE.tar.zst"
else
  warn "zstd not found, using gzip"
  tar -C "$OUT_ROOT" -czf "$BUNDLE.tar.gz" "ctf-bundle-$STAMP"
  ARCHIVE="$BUNDLE.tar.gz"
fi
sha256sum "$ARCHIVE" | tee "$ARCHIVE.sha256"
ok "bundle ready: $ARCHIVE"
info "copy it to the offline box, unpack, then: ./install.sh --offline . --with-wordlists"
