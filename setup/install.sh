#!/usr/bin/env bash
#
# install.sh - CTF swiss-knife installer (BINARIES ONLY, no apt).
#
# Reads manifest.tsv, downloads each pinned tool archive, verifies its SHA256,
# extracts the binary into ~/.local/bin (with a .<tool>.version sidecar), and
# links setup/scripts/* into ~/.local/bin so `enum-net`, `ctf-init`, ... are on PATH.
#
# Nothing is installed with apt. Kali-native tools (nmap, dirsearch, checksec,
# ghidra, ...) are only *checked*: use `install.sh --check` to see what is
# missing and the exact apt command to fix it.
#
# Idempotent: a tool whose installed version matches the manifest is skipped.
#
#   ./install.sh                 # install everything, skip what is current
#   ./install.sh -y              # unattended
#   ./install.sh --only recon    # one group (recon|web|pwn), repeatable
#   ./install.sh --with-wordlists
#   ./install.sh --offline dist/ctf-bundle-20261017
#   ./install.sh --check         # doctor: report versions / missing tools
#   ./install.sh --force         # reinstall even if version matches
#
set -euo pipefail

SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SETUP_DIR/manifest.tsv"
SCRIPTS_DIR="$SETUP_DIR/scripts"

BIN_DIR="${CTF_BIN_DIR:-$HOME/.local/bin}"
CACHE_DIR="${CTF_CACHE_DIR:-$HOME/.cache/ctf-tools}"
WL_DIR="${CTF_WORDLISTS_DIR:-$HOME/.local/share/wordlists/SecLists}"
SECLISTS_TAG="${CTF_SECLISTS_TAG:-2026.1}"

ORIGINAL_PATH="$PATH"
export PATH="$BIN_DIR:$PATH"

ASSUME_YES=0
DO_CHECK=0
FORCE=0
WITH_WORDLISTS=0
OFFLINE_DIR=""
ONLY_GROUPS=()

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""
fi

step()  { printf '\n%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$C_GREEN"   "$C_RESET" "$*"; }
skip()  { printf '%s  --%s %s\n' "$C_DIM"     "$C_RESET" "$*"; }
info()  { printf '     %s\n' "$*"; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW"  "$C_RESET" "$*" >&2; }
die()   { printf '%sfail%s %s\n' "$C_RED"     "$C_RESET" "$*" >&2; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Options:
  -y, --yes            Non-interactive (never prompts; this is already the default).
      --only GROUP     Install only this group: recon | web | pwn (repeatable).
      --with-wordlists Clone pinned SecLists (Web-Content/DNS/Common-Credentials)
                       into ~/.local/share/wordlists/SecLists.
      --offline DIR    Install from an unpacked offline bundle directory instead
                       of downloading (see bundle.sh).
      --check          Doctor mode: report every tool's status, install nothing.
      --force          Reinstall even when the installed version matches.
  -h, --help           Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)          ASSUME_YES=1 ;;
    --only)            shift; ONLY_GROUPS+=("${1:?--only needs a group}") ;;
    --with-wordlists)  WITH_WORDLISTS=1 ;;
    --offline)         shift; OFFLINE_DIR="${1:?--offline needs a directory}" ;;
    --check)           DO_CHECK=1 ;;
    --force)           FORCE=1 ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -r "$MANIFEST" ] || die "manifest not found: $MANIFEST"

# ---------------------------------------------------------------------------
# Temp workspace with guaranteed cleanup
# ---------------------------------------------------------------------------
TMPDIR_RUN=""
cleanup() { [ -n "$TMPDIR_RUN" ] && [ -d "$TMPDIR_RUN" ] && rm -rf "$TMPDIR_RUN"; }
trap cleanup EXIT INT TERM
mk_tmp() {
  TMPDIR_RUN="$(mktemp -d "${TMPDIR:-/tmp}/ctf-setup.XXXXXX")"
  printf '%s' "$TMPDIR_RUN"
}

# ---------------------------------------------------------------------------
# Shell rc: keep ~/.local/bin on PATH
# ---------------------------------------------------------------------------
append_rc_line() {
  local line="$1" marker="$2" rc added=0
  local rc_files=("$HOME/.bashrc")
  [ -f "$HOME/.zshrc" ] && rc_files+=("$HOME/.zshrc")
  for rc in "${rc_files[@]}"; do
    [ -f "$rc" ] || touch "$rc"
    grep -qF -- "$marker" "$rc" 2>/dev/null && continue
    printf '\n# %s\n%s\n' "$marker" "$line" >>"$rc"
    added=1
  done
  [ "$added" -eq 0 ] || ok "updated shell rc with PATH entry"
}

ensure_local_bin_on_path() {
  case ":$ORIGINAL_PATH:" in
    *":$BIN_DIR:"*) return 0 ;;
  esac
  append_rc_line "export PATH=\"$BIN_DIR:\$PATH\"" 'ctf-setup: user-local binaries'
}

# ---------------------------------------------------------------------------
# Manifest handling
# ---------------------------------------------------------------------------
# Sets the global variables below for one manifest row.
parse_row() {
  local row="$1"
  IFS=$'\t' read -r M_NAME M_VERSION M_GROUP M_KIND M_BIN M_URL M_SHA <<<"$row"
}

# manifest_rows -> prints only non-comment, non-empty rows
manifest_rows() {
  grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" | tail -n +2
}

group_wanted() {
  [ "${#ONLY_GROUPS[@]}" -eq 0 ] && return 0
  local g
  for g in "${ONLY_GROUPS[@]}"; do
    [ "$g" = "$1" ] && return 0
  done
  return 1
}

installed_version() {
  local name="$1"
  [ -r "$BIN_DIR/.$name.version" ] && cat "$BIN_DIR/.$name.version" || true
}

url_basename() { printf '%s' "${1##*/}"; }

verify_sha() {
  local file="$1" want="$2" got
  [ -f "$file" ] || return 1
  got="$(sha256sum "$file" | awk '{print $1}')"
  [ "$got" = "$want" ]
}

# resolve_offline <url> <name> <version> -> prints the path a bundle should have
resolve_offline() {
  local url="$1" name="$2" version="$3" base cand
  base="$(url_basename "$url")"
  for cand in "$OFFLINE_DIR/$base" "$OFFLINE_DIR/downloads/$base" \
              "$OFFLINE_DIR/$name-$version-$base"; do
    if [ -f "$cand" ]; then
      printf '%s' "$cand"
      return 0
    fi
  done
  printf '%s' "$OFFLINE_DIR/downloads/$base"
}

fetch_archive() {
  # fetch_archive <url> <sha> <dest>  -> 0 ok, dies on checksum mismatch
  local url="$1" sha="$2" dest="$3"
  if verify_sha "$dest" "$sha"; then
    return 0
  fi
  if [ -n "$OFFLINE_DIR" ]; then
    die "offline bundle is missing a valid '$dest' (expected in $OFFLINE_DIR)"
  fi
  mkdir -p "$CACHE_DIR"
  info "downloading $(url_basename "$url")"
  curl -fsSL --retry 3 --connect-timeout 20 -o "$dest.part" "$url" \
    || die "download failed: $url"
  mv -f "$dest.part" "$dest"
  verify_sha "$dest" "$sha" \
    || die "SHA256 mismatch for $(url_basename "$url") — refusing to install (manifest drift? re-run bundle.sh --verify)"
}

extract_binary() {
  # extract_binary <kind> <archive> <binname> <dest>
  local kind="$1" archive="$2" binname="$3" dest="$4"
  local tmp found inner
  if [ "$kind" = "raw" ]; then
    install -m 0755 "$archive" "$dest"
    return 0
  fi
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctf-extract.XXXXXX")"
  case "$kind" in
    tgz) tar -xzf "$archive" -C "$tmp" ;;
    zip) unzip -q -o "$archive" -d "$tmp" ;;
    zip+tgz)
      unzip -q -o "$archive" -d "$tmp"
      inner="$(find "$tmp" -maxdepth 1 -name '*.tar.gz' | head -n1)"
      [ -n "$inner" ] || { rm -rf "$tmp"; die "no inner .tar.gz in $(url_basename "$archive")"; }
      tar -xzf "$inner" -C "$tmp"
      ;;
    *) rm -rf "$tmp"; die "unknown archive kind: $kind" ;;
  esac
  found="$(find "$tmp" -type f -name "$binname" -perm -u+x | head -n1)"
  [ -n "$found" ] || found="$(find "$tmp" -type f -name "$binname" | head -n1)"
  if [ -z "$found" ]; then
    rm -rf "$tmp"
    die "binary '$binname' not found after unpacking $(url_basename "$archive")"
  fi
  install -m 0755 "$found" "$dest"
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# Kali-native prerequisites that this script deliberately does NOT apt-install
# ---------------------------------------------------------------------------
# Shown by --check when missing, with the exact command to run manually.
KALI_TOOLS="nmap dirsearch whatweb gobuster nikto sqlmap john hashcat binwalk exiftool strings objdump readelf gdb strace ltrace checksec steghide zsteg tshark volatility3 searchsploit wpscan chisel python3 nc socat"

check_mode() {
  step "CTF tools doctor"
  local row
  printf '     %-14s %-9s %s\n' TOOL PINNED STATUS
  while IFS= read -r row; do
    parse_row "$row"
    group_wanted "$M_GROUP" || continue
    local iv status
    iv="$(installed_version "$M_NAME")"
    if [ -x "$BIN_DIR/$M_NAME" ] && [ "$iv" = "$M_VERSION" ]; then
      status="${C_GREEN}ok${C_RESET}"
    elif [ -x "$BIN_DIR/$M_NAME" ]; then
      status="${C_YELLOW}outdated (have ${iv:-?})${C_RESET}"
    else
      status="${C_RED}missing${C_RESET}"
    fi
    printf '     %-14s %-9s %b\n' "$M_NAME" "$M_VERSION" "$status"
  done < <(manifest_rows)

  step "Kali-native tools (not installed by this script)"
  local missing=()
  local t
  for t in $KALI_TOOLS; do
    if have "$t"; then
      printf '     %-14s %s\n' "$t" "${C_GREEN}ok${C_RESET}"
    else
      printf '     %-14s %s\n' "$t" "${C_RED}missing${C_RESET}"
      missing+=("$t")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    printf '\n     Install the missing ones with:\n'
    printf '       sudo apt-get update && sudo apt-get install -y %s\n' "${missing[*]}"
  fi

  step "Wordlists"
  if [ -f "$WL_DIR/Discovery/Web-Content/common.txt" ]; then
    ok "curated SecLists subset present: $WL_DIR (tag $SECLISTS_TAG)"
  elif [ -d /usr/share/seclists ]; then
    ok "system SecLists present: /usr/share/seclists"
  elif [ -d /usr/share/wordlists ]; then
    info "/usr/share/wordlists present; run with --with-wordlists for the pinned SecLists subset"
  else
    warn "no wordlists found — run: ./install.sh --with-wordlists"
  fi
}

# ---------------------------------------------------------------------------
# Wordlists (optional, pinned)
# ---------------------------------------------------------------------------
# Curated SecLists subset: the wordlists the enum scripts actually use.
# Sparse-cloned as individual files (~5 MB) instead of whole directories
# (Web-Content + Passwords alone are >1.5 GB). Keep in sync with bundle.sh.
SECLISTS_FILES=(
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

install_wordlists() {
  step "Wordlists (pinned SecLists $SECLISTS_TAG, curated subset)"
  if [ -f "$WL_DIR/Discovery/Web-Content/common.txt" ]; then
    ok "already present: $WL_DIR"
    return 0
  fi
  if [ -n "$OFFLINE_DIR" ] && [ -d "$OFFLINE_DIR/wordlists/SecLists/Discovery" ]; then
    mkdir -p "$(dirname "$WL_DIR")"
    cp -a "$OFFLINE_DIR/wordlists/SecLists" "$WL_DIR"
    ok "installed bundled SecLists into $WL_DIR"
    return 0
  fi
  have git || die "git is required for --with-wordlists"
  mkdir -p "$(dirname "$WL_DIR")"
  if [ -d "$WL_DIR/.git" ]; then
    info "updating existing clone to $SECLISTS_TAG"
    git -C "$WL_DIR" -c advice.detachedHead=false fetch --depth 1 origin \
      "refs/tags/$SECLISTS_TAG:refs/tags/$SECLISTS_TAG" || true
    git -C "$WL_DIR" -c advice.detachedHead=false checkout -q "$SECLISTS_TAG" || true
  else
    info "sparse-cloning ${#SECLISTS_FILES[@]} wordlist files (not whole directories)"
    rm -rf "$WL_DIR"
    git clone -q --filter=blob:none --no-checkout --depth 1 --branch "$SECLISTS_TAG" \
      https://github.com/danielmiessler/SecLists.git "$WL_DIR" \
      || die "could not clone SecLists at tag $SECLISTS_TAG"
    git -C "$WL_DIR" sparse-checkout init --no-cone >/dev/null 2>&1 || true
  fi
  git -C "$WL_DIR" sparse-checkout set --no-cone "${SECLISTS_FILES[@]}" \
    || die "could not select the SecLists subset"
  git -C "$WL_DIR" -c advice.detachedHead=false checkout -q || true
  ok "SecLists ready at $WL_DIR"
}

# ---------------------------------------------------------------------------
# Script symlinks
# ---------------------------------------------------------------------------
link_scripts() {
  step "Linking setup/scripts into $BIN_DIR"
  local f base linked=0
  mkdir -p "$BIN_DIR"
  for f in "$SCRIPTS_DIR"/*.sh; do
    [ -f "$f" ] || continue
    base="$(basename "$f" .sh)"
    [ "$base" = "_common" ] && continue
    chmod +x "$f" 2>/dev/null || true
    ln -sf "$f" "$BIN_DIR/$base"
    linked=$((linked + 1))
  done
  ok "$linked command(s) linked into $BIN_DIR"
  info "commands: $(cd "$SCRIPTS_DIR" && ls *.sh | sed -e 's/\.sh$//' | grep -v '^_common$' | tr '\n' ' ')"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
preflight() {
  step "Preflight"
  [ "$(id -u)" -eq 0 ] && die "Do not run as root. Run as your normal user."
  info "user: $(id -un)  host: $(hostname)"
  [ -r /etc/os-release ] && { . /etc/os-release; info "os:   ${PRETTY_NAME:-unknown}"; }

  local need=() t
  for t in curl tar unzip sha256sum install; do
    have "$t" || need+=("$t")
  done
  if [ "${#need[@]}" -gt 0 ]; then
    warn "missing base tools: ${need[*]}"
    info "this script does not use apt; install them yourself, e.g.:"
    info "  sudo apt-get install -y ${need[*]}"
    die "cannot continue without: ${need[*]}"
  fi
  mkdir -p "$BIN_DIR"
  command -v sha256sum >/dev/null || die "sha256sum required (coreutils)"
}

install_tools() {
  step "Pinned tools (binaries only)"
  local row installed=0 skipped=0
  while IFS= read -r row; do
    parse_row "$row"
    group_wanted "$M_GROUP" || continue

    local dest="$BIN_DIR/$M_NAME" archive
    archive="$CACHE_DIR/$(url_basename "$M_URL")"
    if [ -n "$OFFLINE_DIR" ]; then
      archive="$(resolve_offline "$M_URL" "$M_NAME" "$M_VERSION")"
    fi

    if [ "$FORCE" -eq 0 ] && [ -x "$dest" ] && [ "$(installed_version "$M_NAME")" = "$M_VERSION" ]; then
      skip "$M_NAME $M_VERSION already installed"
      skipped=$((skipped + 1))
      continue
    fi

    fetch_archive "$M_URL" "$M_SHA" "$archive"
    extract_binary "$M_KIND" "$archive" "$M_BIN" "$dest"
    printf '%s' "$M_VERSION" > "$BIN_DIR/.$M_NAME.version"
    ok "installed $M_NAME $M_VERSION  ($M_GROUP)"
    installed=$((installed + 1))
  done < <(manifest_rows)

  info "$installed installed, $skipped already current"
}

summary() {
  step "Done"
  local row count=0
  while IFS= read -r row; do
    parse_row "$row"; group_wanted "$M_GROUP" || continue
    count=$((count + 1))
  done < <(manifest_rows)
  printf '     binary dir : %s\n' "$BIN_DIR"
  printf '     cache      : %s\n' "$CACHE_DIR"
  printf '     tools      : %s pinned entries selected\n' "$count"
  cat <<EOF

  Next steps
    1. Open a new shell (or: source ~/.bashrc) so PATH updates apply.
    2. Run: install.sh --check      # see what Kali already provides
    3. Start a challenge workspace:
         ctf-init mychallenge
       then, inside it:
         enum-net 10.10.10.10
         enum-web http://10.10.10.10
         enum-bin ./chall
         enum-file ./suspect.bin

  Offline box
    On a networked machine:  ./bundle.sh --with-wordlists
    Copy dist/ctf-bundle-*.tar.zst here, unpack, then:
      ./install.sh --offline dist/ctf-bundle-YYYYMMDD --with-wordlists
EOF
}

main() {
  if [ "$DO_CHECK" -eq 1 ]; then
    check_mode
    return 0
  fi
  printf '%s\n' "CTF swiss-knife installer (binaries only) — Kali Linux"
  preflight
  install_tools
  [ "$WITH_WORDLISTS" -eq 1 ] && install_wordlists
  link_scripts
  ensure_local_bin_on_path
  summary
}

main "$@"
