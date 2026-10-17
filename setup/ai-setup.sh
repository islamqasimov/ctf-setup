#!/usr/bin/env bash
#
# ai-setup.sh - Install an AI setup (OpenCode + REA) on a fresh Kali Linux box.
#
# Installs:
#   * base packages (procps, curl, git, unzip, ...)
#   * Node.js (Kali apt first, NodeSource 24.x fallback when too old for REA)
#   * OpenCode V2 CLI  (https://opencode.ai)
#   * REA              (https://github.com/morluto/rea) + OpenCode MCP registration
#
# Optional extras (prompted, or via flags):
#   * Ghidra 12.1.x + JDK 21  (native binary analysis for REA)
#   * JADX                    (Android APK analysis for REA)
#
# The script is idempotent: re-running it is a fast no-op for completed steps.
# It never asks for or stores API keys / provider logins.
#
set -euo pipefail

# Always be able to find user-local binaries installed by this script.
# ORIGINAL_PATH remembers the invoking shell's PATH for the rc-file checks below.
ORIGINAL_PATH="$PATH"
export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
ASSUME_YES=0
WITH_GHIDRA=0
WITH_JADX=0
SKIP_APT=0
GHIDRA_SERIES="${GHIDRA_SERIES:-12.1}"

usage() {
  cat <<'EOF'
Usage: bash ai-setup.sh [options]

Options:
  -y, --yes            Non-interactive. Skips the extras prompt (extras then
                       require an explicit --with-* flag).
      --with-ghidra    Install Ghidra 12.1.x + JDK 21 (native binary analysis).
      --with-jadx      Install JADX (Android APK analysis).
      --skip-apt       Skip all apt package steps (assume deps are present).
      --ghidra-series  Ghidra release series to install (default: 12.1).
  -h, --help           Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)        ASSUME_YES=1 ;;
    --with-ghidra)   WITH_GHIDRA=1 ;;
    --with-jadx)     WITH_JADX=1 ;;
    --skip-apt)      SKIP_APT=1 ;;
    --ghidra-series) shift; GHIDRA_SERIES="${1:?--ghidra-series needs a value}" ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'
else
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

step()  { printf '\n%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$C_GREEN"   "$C_RESET" "$*"; }
info()  { printf '     %s\n' "$*"; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW"  "$C_RESET" "$*" >&2; }
die()   { printf '%sfail%s %s\n' "$C_RED"     "$C_RESET" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Temp workspace with guaranteed cleanup, nothing left behind.
TMPDIR_RUN=""
cleanup() {
  if [ -n "$TMPDIR_RUN" ] && [ -d "$TMPDIR_RUN" ]; then
    rm -rf "$TMPDIR_RUN"
  fi
}
trap cleanup EXIT INT TERM

mk_tmp() {
  TMPDIR_RUN="$(mktemp -d "${TMPDIR:-/tmp}/ai-setup.XXXXXX")"
  printf '%s' "$TMPDIR_RUN"
}

# ---------------------------------------------------------------------------
# Install state manifest
# ai-uninstall.sh reads this to remove exactly what was installed, including
# values that cannot be re-derived later (e.g. the previous npm prefix).
# ---------------------------------------------------------------------------
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ai-setup"
STATE_FILE="$STATE_DIR/state.env"

state_read() {
  local key="$1" line value
  [ -f "$STATE_FILE" ] || return 0
  line="$(sed -n "s/^${key}=//p" "$STATE_FILE")"
  [ -n "$line" ] || return 0
  # The stored right-hand side is shell-quoted (KEY='value'), so evaluate it
  # as a single shell word to recover the original value exactly.
  eval "value=$line"
  printf '%s' "$value"
}

state_set() {
  local key="$1" value="$2" esc tmp
  mkdir -p "$STATE_DIR"
  esc="$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
  tmp="$STATE_FILE.tmp"
  if [ -f "$STATE_FILE" ]; then
    grep -v "^${key}=" "$STATE_FILE" >"$tmp" || true
  else
    : >"$tmp"
    printf 'SETUP_VERSION=1\nINSTALLED_AT=%s\n' "$(date -Is 2>/dev/null || date)" >>"$tmp"
  fi
  printf "%s='%s'\n" "$key" "$esc" >>"$tmp"
  mv "$tmp" "$STATE_FILE"
}

# state_add KEY VALUE  -> space-separated list, values added only once
state_add() {
  local key="$1" value="$2" current
  current="$(state_read "$key")"
  if [ -n "$current" ]; then
    case " $current " in
      *" $value "*) : ;;
      *) current="$current $value" ;;
    esac
  else
    current="$value"
  fi
  state_set "$key" "$current"
}

# ---------------------------------------------------------------------------
# Shell rc helpers
# ---------------------------------------------------------------------------
RC_FILES=()
collect_rc_files() {
  [ -f "$HOME/.bashrc" ] || touch "$HOME/.bashrc"
  RC_FILES=("$HOME/.bashrc")
  if [ -f "$HOME/.zshrc" ]; then
    RC_FILES+=("$HOME/.zshrc")
  fi
}

# append_rc_line <line> <marker>  -> adds the line to rc files lacking the marker
append_rc_line() {
  local line="$1" marker="$2" rc added=0
  collect_rc_files
  for rc in "${RC_FILES[@]}"; do
    if [ -f "$rc" ] && grep -qF -- "$marker" "$rc" 2>/dev/null; then
      continue
    fi
    printf '\n# %s\n%s\n' "$marker" "$line" >>"$rc"
    added=1
  done
  [ "$added" -eq 0 ] || ok "updated shell rc: ${RC_FILES[*]}"
}

ensure_local_bin_on_path() {
  case ":$ORIGINAL_PATH:" in
    *":$HOME/.local/bin:"*) return 0 ;;
  esac
  append_rc_line 'export PATH="$HOME/.local/bin:$PATH"' 'ai-setup: user-local binaries'
}

# ---------------------------------------------------------------------------
# Step 1 - Preflight
# ---------------------------------------------------------------------------
preflight() {
  step "Preflight"

  if [ "$(id -u)" -eq 0 ]; then
    die "Do not run this script as root. Run it as your normal user; it uses sudo when needed."
  fi
  info "user: $(id -un)  host: $(hostname)"

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    info "os:   ${PRETTY_NAME:-unknown}"
    case "${ID:-}${ID_LIKE:-}" in
      *debian*|*kali*) : ;;
      *) warn "This does not look like a Debian/Kali system; apt steps may fail." ;;
    esac
  else
    warn "/etc/os-release not found; cannot identify the distribution."
  fi

  if [ "$SKIP_APT" -eq 0 ]; then
    have apt-get || die "apt-get not found (use --skip-apt if this is intentional)."
    if ! sudo -n true 2>/dev/null; then
      info "sudo may ask for your password now."
      sudo -v || die "sudo is required for package installation."
    fi
  fi
}

apt_base_packages() {
  if [ "$SKIP_APT" -eq 1 ]; then
    warn "skipping apt package installation"
    return 0
  fi

  step "Base packages"
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    procps curl git ca-certificates unzip gnupg xz-utils
  state_set PACKAGES_BASE "procps curl git ca-certificates unzip gnupg xz-utils"
  ok "base packages present (procps provides the 'ps' REA requires on Linux)"
}

# ---------------------------------------------------------------------------
# Step 2 - Node.js (apt first, NodeSource fallback)
# ---------------------------------------------------------------------------
# REA requires Node 22.x (>=22.19), 24.x (>=24.11), or 26+.
node_version_ok() {
  have node || return 1
  local v major minor
  v="$(node -v 2>/dev/null)" || return 1
  v="${v#v}"
  major="${v%%.*}"
  minor="$(printf '%s' "$v" | cut -d. -f2)"
  case "$major" in ''|*[!0-9]*) return 1 ;; esac
  case "$minor" in ''|*[!0-9]*) return 1 ;; esac
  if [ "$major" -ge 26 ]; then return 0; fi
  if [ "$major" -eq 22 ] && [ "$minor" -ge 19 ]; then return 0; fi
  if [ "$major" -eq 24 ] && [ "$minor" -ge 11 ]; then return 0; fi
  return 1
}

install_node() {
  step "Node.js"

  if node_version_ok && have npm; then
    ok "Node.js $(node -v) and npm $(npm -v) already satisfy REA's requirement"
    state_set NODE_FROM preinstalled
    return 0
  fi

  if [ "$SKIP_APT" -eq 1 ]; then
    die "Node.js is missing or too old and --skip-apt was given."
  fi

  info "trying Debian/Kali nodejs + npm from apt"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs npm || true
  hash -r

  if node_version_ok && have npm; then
    ok "installed Node.js $(node -v) from apt"
    state_set NODE_FROM apt
    return 0
  fi

  warn "apt Node.js is missing or too old for REA (need 22.19+/24.11+/26+)."
  info "falling back to NodeSource Node.js 24.x LTS"

  sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y nodejs npm || true
  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
  hash -r

  node_version_ok || die "Node.js still does not meet REA's requirement after NodeSource install."
  state_set NODE_FROM nodesource
  ok "installed Node.js $(node -v) from NodeSource"
}

# ---------------------------------------------------------------------------
# Step 3 - OpenCode
# ---------------------------------------------------------------------------
opencode_bin() {
  if have opencode; then
    command -v opencode
    return 0
  fi
  local c
  for c in "$HOME/.local/bin/opencode" "$HOME/.opencode/bin/opencode"; do
    if [ -x "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

install_opencode() {
  step "OpenCode"

  local created=no
  if opencode_bin >/dev/null; then
    ok "OpenCode already installed: $("$(opencode_bin)" --version 2>/dev/null || echo present)"
  else
    created=yes
    info "running the official installer (https://opencode.ai/v2/install)"
    curl -fsSL https://opencode.ai/v2/install | bash
    hash -r
    opencode_bin >/dev/null || die "OpenCode binary not found after installation."
    ok "installed OpenCode $("$(opencode_bin)" --version 2>/dev/null || echo '')"
  fi

  state_set OPENCODE_BIN "$(opencode_bin)"
  state_set OPENCODE_CREATED "$created"
  ensure_local_bin_on_path
}

# ---------------------------------------------------------------------------
# Step 4 - REA
# ---------------------------------------------------------------------------
rea_bin() {
  if have rea; then
    command -v rea
    return 0
  fi
  local c
  for c in "$HOME/.local/bin/rea" "/usr/local/bin/rea" "/usr/bin/rea"; do
    if [ -x "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

# Keep npm globals user-owned (~/.local) so `rea update` works without sudo.
configure_npm_prefix() {
  local current
  current="$(npm config get prefix 2>/dev/null || echo '')"
  state_set NPM_PREFIX_BEFORE "$current"
  case "$current" in
    "$HOME"/*)
      state_set NPM_PREFIX_CHANGED no
      return 0
      ;;
  esac
  state_set NPM_PREFIX_CHANGED yes
  info "setting user-level npm prefix to $HOME/.local (global installs stay user-owned)"
  npm config set prefix "$HOME/.local"
}

install_rea() {
  step "REA (morluto/rea)"

  configure_npm_prefix

  local created=no
  if rea_bin >/dev/null; then
    ok "REA already installed: $("$(rea_bin)" --version 2>/dev/null || echo present)"
  else
    created=yes
    info "npm install --global rea-agents"
    npm install --global rea-agents
    hash -r
    rea_bin >/dev/null || die "rea command not found after installation."
    ok "installed REA $("$(rea_bin)" --version 2>/dev/null || echo '')"
  fi
  state_set REA_GLOBAL yes
  state_set REA_CREATED "$created"
  state_set REA_VERSION "$("$(rea_bin)" --version 2>/dev/null || echo unknown)"

  step "Registering REA with OpenCode"
  info "rea setup --yes --client opencode  (adds the MCP server + REA skill)"
  "$(rea_bin)" setup --yes --client opencode
  ok "REA registered with OpenCode (existing config backed up automatically)"
}

check_rea() {
  step "REA readiness check (report only)"
  "$(rea_bin)" doctor --client opencode --json >/dev/null 2>&1 \
    && ok "rea doctor reports the OpenCode registration is healthy" \
    || warn "rea doctor reported issues; run 'rea doctor --client opencode' for details"
}

# ---------------------------------------------------------------------------
# Step 5 - Optional extras
# ---------------------------------------------------------------------------
resolve_ghidra_url() {
  local series="$1"
  curl -fsSL 'https://api.github.com/repos/NationalSecurityAgency/ghidra/releases?per_page=100' \
    | python3 -c '
import json, sys
series = sys.argv[1]
try:
    releases = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for rel in releases:
    tag = rel.get("tag_name", "")
    if not tag.startswith("Ghidra_" + series):
        continue
    for asset in rel.get("assets", []):
        name = asset.get("name", "")
        if name.endswith(".zip") and "PUBLIC" in name:
            print(asset.get("browser_download_url", ""))
            sys.exit(0)
' "$series"
}

install_ghidra() {
  step "Ghidra $GHIDRA_SERIES.x + JDK 21 (REA native analysis)"

  if [ "$SKIP_APT" -eq 0 ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jdk
    state_add PACKAGES_INSTALLED openjdk-21-jdk
  fi

  local tools_dir="$HOME/tools" install_dir url tmp zip top
  mkdir -p "$tools_dir"

  install_dir="$(find "$tools_dir" -maxdepth 1 -type d -name "ghidra_${GHIDRA_SERIES}*_PUBLIC" 2>/dev/null | sort | tail -n1)"
  if [ -n "$install_dir" ]; then
    ok "Ghidra already extracted: $install_dir"
  else
    have python3 || die "python3 is required to resolve the Ghidra download URL."
    info "resolving the newest Ghidra $GHIDRA_SERIES.x release"
    url="$(resolve_ghidra_url "$GHIDRA_SERIES" || true)"
    [ -n "$url" ] || die "Could not find a Ghidra $GHIDRA_SERIES.x release asset. Check https://github.com/NationalSecurityAgency/ghidra/releases"

    tmp="$(mk_tmp)"; zip="$tmp/ghidra.zip"
    info "downloading $(basename "$url") (large download)"
    curl -fL --retry 3 -o "$zip" "$url"
    info "extracting to $tools_dir"
    unzip -q -o "$zip" -d "$tmp"
    top=""
    for d in "$tmp"/*/; do
      top="${d%/}"
      break
    done
    [ -n "$top" ] || die "unexpected Ghidra archive layout."
    rm -rf "$tools_dir/$(basename "$top")"
    mv "$top" "$tools_dir/"
    install_dir="$tools_dir/$(basename "$top")"
    ok "extracted Ghidra to $install_dir"
  fi

  export GHIDRA_INSTALL_DIR="$install_dir"
  state_set GHIDRA_SERIES "$GHIDRA_SERIES"
  state_set GHIDRA_INSTALL_DIR "$install_dir"
  append_rc_line "export GHIDRA_INSTALL_DIR=\"$install_dir\"" 'ai-setup: Ghidra for REA'

  info "refreshing the REA registration with GHIDRA_INSTALL_DIR"
  GHIDRA_INSTALL_DIR="$install_dir" "$(rea_bin)" setup --yes --client opencode
  "$(rea_bin)" doctor --provider ghidra --json >/dev/null 2>&1 \
    && ok "rea doctor accepts the Ghidra installation" \
    || warn "Ghidra check failed; run 'rea doctor --provider ghidra' for details"
}

install_jadx() {
  step "JADX (REA Android APK analysis)"
  if [ "$SKIP_APT" -eq 1 ]; then
    warn "skipping JADX (apt is disabled)"
    return 0
  fi
  if have jadx; then
    ok "jadx already installed: $(jadx --version 2>/dev/null || echo present)"
    return 0
  fi
  if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y jadx; then
    state_add PACKAGES_INSTALLED jadx
    ok "installed jadx: $(jadx --version 2>/dev/null || echo present)"
  else
    warn "jadx was not installed (package may be unavailable in this release)"
  fi
}

maybe_install_extras() {
  if [ "$WITH_GHIDRA" -eq 0 ] && [ "$WITH_JADX" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
    printf '\nInstall REA analysis engines (Ghidra for native binaries, JADX for APKs)? [y/N] '
    local answer=""
    read -r answer || true
    case "$answer" in
      [yY]|[yY][eE][sS]) WITH_GHIDRA=1; WITH_JADX=1 ;;
    esac
  fi

  if [ "$WITH_GHIDRA" -eq 1 ]; then
    install_ghidra
  fi
  if [ "$WITH_JADX" -eq 1 ]; then
    install_jadx
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Step 6 - Summary
# ---------------------------------------------------------------------------
summary() {
  step "Done"
  printf '     opencode : %s\n' "$(opencode_bin >/dev/null && "$(opencode_bin)" --version 2>/dev/null || echo 'not found')"
  printf '     node     : %s\n' "$(have node && node -v || echo 'not found')"
  printf '     npm      : %s\n' "$(have npm && npm -v || echo 'not found')"
  printf '     rea      : %s\n' "$(rea_bin >/dev/null && "$(rea_bin)" --version 2>/dev/null || echo 'not found')"
  if [ -n "${GHIDRA_INSTALL_DIR:-}" ]; then
    printf '     ghidra   : %s\n' "$GHIDRA_INSTALL_DIR"
  fi

  cat <<'EOF'

  Next steps
    1. Open a new shell (or: source ~/.bashrc) so PATH updates apply.
    2. Run: opencode
       Then connect your AI provider with the /connect command (or an
       OpenCode Console account). Logins are yours to do; nothing is stored
       by this script.
    3. Ask OpenCode to use REA, e.g.
         "Use REA to explain how this binary validates its license."

  Maintenance
    opencode update      # update OpenCode
    rea update           # update REA
    rea doctor           # health check

  Removal
    bash ai-uninstall.sh --dry-run   # preview removal of everything installed here
    bash ai-uninstall.sh --yes       # apply it
EOF

  if [ -f "$STATE_FILE" ]; then
    info "install record: $STATE_FILE"
  fi
}

# ---------------------------------------------------------------------------
main() {
  printf '%s\n' "AI setup installer (OpenCode + REA) for fresh Kali Linux"
  preflight
  apt_base_packages
  install_node
  install_opencode
  install_rea
  maybe_install_extras
  check_rea
  summary
}

main "$@"
