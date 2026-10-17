#!/usr/bin/env bash
#
# uninstall.sh - Remove everything ai-setup.sh created (OpenCode + REA + extras).
#
# Default mode is a DRY RUN: it prints what it would remove and changes nothing.
# Re-run with --yes to actually apply it.
#
# It uses the install record written by ai-setup.sh
#   ${XDG_STATE_HOME:-$HOME/.local/state}/ai-setup/state.env
# and falls back to detection when that record is missing.
#
set -euo pipefail

ORIGINAL_PATH="$PATH"
export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
APPLY=0
PURGE_DATA=0
PURGE_PACKAGES=0
KEEP_RC=0
KEEP_GHIDRA=0

usage() {
  cat <<'EOF'
Usage: bash uninstall.sh [options]

Without --yes this is a dry run: nothing is changed, it only prints a plan.

Options:
  -y, --yes          Apply the removals (required to change anything).
      --purge-data   Also delete tool config/state/cache:
                     OpenCode config, data, cache and service files, plus ~/.rea.
                     WARNING: this deletes unrelated OpenCode configuration too.
      --purge-packages
                     Also remove system packages: jadx, openjdk-21-jdk, and
                     nodejs/npm + the NodeSource repository (only when ai-setup.sh
                     installed Node that way).
      --all            Shorthand for --purge-data --purge-packages.
      --keep-rc        Leave the shell rc lines ai-setup.sh added untouched.
      --keep-ghidra    Leave the downloaded Ghidra directory in place.
  -h, --help         Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)          APPLY=1 ;;
    --dry-run)         APPLY=0 ;;
    --purge-data)      PURGE_DATA=1 ;;
    --purge-packages)  PURGE_PACKAGES=1 ;;
    --all)             PURGE_DATA=1; PURGE_PACKAGES=1 ;;
    --keep-rc)         KEEP_RC=1 ;;
    --keep-ghidra)     KEEP_GHIDRA=1 ;;
    -h|--help)         usage; exit 0 ;;
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

step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '     %s\n' "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Act on a command: apply it, or print it in dry-run mode.
act_cmd() {
  local desc="$1"; shift
  if [ "$APPLY" -eq 1 ]; then
    if "$@"; then
      printf '%s  removed%s %s\n' "$C_GREEN" "$C_RESET" "$desc"
    else
      warn "could not remove: $desc"
    fi
  else
    printf '  would remove: %s\n' "$desc"
  fi
}

rm_path() {
  local p="$1"
  [ -n "$p" ] || return 0
  if [ -e "$p" ] || [ -L "$p" ]; then
    act_cmd "$p" rm -rf -- "$p"
  fi
}

# ---------------------------------------------------------------------------
# Install record from ai-setup.sh
# ---------------------------------------------------------------------------
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/ai-setup/state.env"
if [ -r "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE"
  HAVE_RECORD=1
else
  HAVE_RECORD=0
fi
: "${NODE_FROM:=unknown}"
: "${NPM_PREFIX_BEFORE:=}"
: "${NPM_PREFIX_CHANGED:=unknown}"
: "${OPENCODE_BIN:=}"
: "${OPENCODE_CREATED:=unknown}"
: "${GHIDRA_INSTALL_DIR:=}"
: "${GHIDRA_SERIES:=12.1}"
: "${PACKAGES_INSTALLED:=}"
: "${REA_GLOBAL:=unknown}"
: "${REA_CREATED:=unknown}"

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------
opencode_bin() {
  if have opencode; then
    command -v opencode
    return 0
  fi
  local c
  for c in "$HOME/.local/bin/opencode" "$HOME/.opencode/bin/opencode" \
           "/usr/local/bin/opencode" "/usr/bin/opencode"; do
    if [ -e "$c" ] || [ -L "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

rea_bin() {
  if have rea; then
    command -v rea
    return 0
  fi
  local c
  for c in "$HOME/.local/bin/rea" "/usr/local/bin/rea" "/usr/bin/rea"; do
    if [ -e "$c" ] || [ -L "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

xdg_path() { # xdg_path <var> <subdir>
  case "$1" in
    config) printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/$2" ;;
    data)   printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/$2" ;;
    cache)  printf '%s' "${XDG_CACHE_HOME:-$HOME/.cache}/$2" ;;
    state)  printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/$2" ;;
  esac
}

# ---------------------------------------------------------------------------
# Removal steps
# ---------------------------------------------------------------------------
remove_rea() {
  step "REA"

  if rea_bin >/dev/null; then
    local rea; rea="$(rea_bin)"
    if [ "$PURGE_DATA" -eq 1 ]; then
      act_cmd "REA agent registrations and skill (rea uninstall --purge-data)" \
        "$rea" uninstall --purge-data
    else
      act_cmd "REA agent registrations and skill (rea uninstall)" \
        "$rea" uninstall
    fi
    info "note: 'rea uninstall' removes REA from every configured agent, not only OpenCode"
    info "      (unrelated MCP servers and other skills are preserved by REA)"
  elif [ "$REA_GLOBAL" != "yes" ]; then
    info "no 'rea' command found (already removed?)"
  fi

  # Global npm package (idempotent; also covers the case where 'rea' was gone
  # but the package remained).
  if [ "$REA_CREATED" = "no" ]; then
    info "the rea-agents package predates ai-setup.sh; leaving the package and binary"
    return 0
  fi

  if have npm; then
    if npm ls -g --depth=0 2>/dev/null | grep -q 'rea-agents'; then
      act_cmd "npm global package rea-agents" npm uninstall --global rea-agents
    else
      info "npm global package 'rea-agents' not present"
    fi
  else
    info "npm not installed; skipping the global rea-agents package"
  fi

  rm_path "$HOME/.local/bin/rea"
  rm_path "/usr/local/bin/rea"
}

remove_opencode() {
  step "OpenCode"

  local bin=""
  bin="$(opencode_bin || true)"

  if [ "$OPENCODE_CREATED" = "no" ]; then
    info "OpenCode was already installed before ai-setup.sh; leaving it in place"
    if [ -n "$bin" ]; then
      info "  binary: $bin"
    fi
    return 0
  fi

  if [ -n "$bin" ]; then
    act_cmd "OpenCode binary ($bin)" rm -f -- "$bin"
  else
    info "no OpenCode binary found"
  fi
  if [ -n "$OPENCODE_BIN" ] && [ "$OPENCODE_BIN" != "$bin" ]; then
    rm_path "$OPENCODE_BIN"
  fi

  # ~/.opencode is the curl installer's private directory; remove it only when
  # it actually holds an OpenCode install.
  if [ -d "$HOME/.opencode" ] && { [ -e "$HOME/.opencode/bin/opencode" ] || [ -e "$HOME/.opencode/bin" ]; }; then
    rm_path "$HOME/.opencode"
  fi

  # Versioned binaries the installer may keep alongside the main one.
  local extra
  for extra in "$HOME/.local/bin/opencode-"*; do
    if [ -e "$extra" ]; then
      rm_path "$extra"
    fi
  done
  return 0
}

remove_data() {
  step "Tool data and configuration (--purge-data)"
  warn "this deletes OpenCode configuration, which may contain unrelated settings"

  if [ "$OPENCODE_CREATED" = "no" ]; then
    warn "OpenCode predates ai-setup.sh; leaving its config/data/cache untouched:"
    info "  $(xdg_path config opencode)"
    info "  $(xdg_path data opencode)"
    info "  $(xdg_path cache opencode)"
  else
    rm_path "$(xdg_path config opencode)"
    rm_path "$(xdg_path data opencode)"
    rm_path "$(xdg_path cache opencode)"
    rm_path "$(xdg_path state opencode)"
  fi

  if [ "$REA_CREATED" = "no" ]; then
    info "~/.rea predates ai-setup.sh; leaving it in place"
  else
    rm_path "$HOME/.rea"
  fi

  local unit
  for unit in "$(xdg_path config systemd/user)"/opencode*.service \
              "$(xdg_path config systemd/user)"/opencode*.socket; do
    if [ -e "$unit" ]; then
      rm_path "$unit"
    fi
  done

  # REA skill copies that may survive if 'rea uninstall' could not run.
  rm_path "$HOME/.agents/skills/reverse-engineer-anything"
  return 0
}

remove_ghidra() {
  step "Ghidra"

  if [ "$KEEP_GHIDRA" -eq 1 ]; then
    info "--keep-ghidra given; leaving Ghidra in place"
    return 0
  fi

  local dir found=0
  if [ -n "$GHIDRA_INSTALL_DIR" ] && [ -d "$GHIDRA_INSTALL_DIR" ]; then
    rm_path "$GHIDRA_INSTALL_DIR"
    found=1
  fi
  for dir in "$HOME/tools"/ghidra_"${GHIDRA_SERIES}"*_PUBLIC; do
    if [ -d "$dir" ]; then
      rm_path "$dir"
      found=1
    fi
  done
  [ "$found" -eq 1 ] || info "no downloaded Ghidra directory found"

  # Remove ~/tools only when ai-setup.sh's download was its last content.
  if [ -d "$HOME/tools" ] && [ -z "$(ls -A "$HOME/tools" 2>/dev/null)" ]; then
    act_cmd "$HOME/tools (now empty)" rmdir -- "$HOME/tools"
  fi
  return 0
}

remove_rc_lines() {
  step "Shell rc lines"

  if [ "$KEEP_RC" -eq 1 ]; then
    info "--keep-rc given; leaving shell rc files untouched"
    return 0
  fi

  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -q '^# ai-setup: ' "$rc" 2>/dev/null || { info "$rc: nothing to remove"; continue; }

    if have python3; then
      if [ "$APPLY" -eq 1 ]; then
        python3 - "$rc" <<'PY'
import re, sys
path = sys.argv[1]
with open(path) as fh:
    text = fh.read()
# Remove each '# ai-setup: ...' marker, the line that follows it, and the
# single blank line ai-setup.sh inserted before the block.
new = re.sub(r'\n?# ai-setup: [^\n]*\n[^\n]*\n', '\n', text)
with open(path, 'w') as fh:
    fh.write(new)
PY
        printf '%s  removed%s ai-setup lines from %s\n' "$C_GREEN" "$C_RESET" "$rc"
      else
        printf '  would remove: ai-setup lines from %s\n' "$rc"
      fi
    else
      act_cmd "ai-setup lines from $rc (sed fallback)" \
        sed -i -e '/^# ai-setup: /{N;d;}' "$rc"
    fi
  done
}

restore_npm_prefix() {
  step "npm prefix"

  if ! have npm; then
    info "npm not installed; nothing to restore"
    return 0
  fi

  local current
  current="$(npm config get prefix 2>/dev/null || echo '')"

  if [ -n "$NPM_PREFIX_BEFORE" ] && [ "$NPM_PREFIX_BEFORE" != "$current" ]; then
    act_cmd "npm prefix -> $NPM_PREFIX_BEFORE" npm config set prefix "$NPM_PREFIX_BEFORE"
    return 0
  fi
  if [ "$NPM_PREFIX_CHANGED" = "yes" ]; then
    act_cmd "npm prefix setting added by ai-setup.sh" npm config delete prefix
    return 0
  fi
  if [ "$NPM_PREFIX_CHANGED" = "no" ]; then
    info "ai-setup.sh did not change the npm prefix"
    return 0
  fi

  # No install record: only act on the exact value ai-setup.sh uses.
  if [ "$current" = "$HOME/.local" ]; then
    warn "no install record; npm prefix is '$HOME/.local' (the value ai-setup.sh sets)"
    info "remove it with: npm config delete prefix   (only if you do not rely on it)"
  else
    info "npm prefix is '$current'; leaving it alone"
  fi
}

remove_packages() {
  step "System packages (--purge-packages)"

  if ! have apt-get; then
    warn "apt-get not found; skipping package removal"
    return 0
  fi

  local pkgs=() pkg
  if [ -n "$PACKAGES_INSTALLED" ]; then
    read -r -a pkgs <<<"$PACKAGES_INSTALLED"
  else
    warn "no install record; will only remove packages detected below"
    for pkg in jadx openjdk-21-jdk; do
      if dpkg -s "$pkg" >/dev/null 2>&1; then
        warn "  $pkg is installed; it may not have come from ai-setup.sh"
        pkgs+=("$pkg")
      fi
    done
  fi

  if [ "${#pkgs[@]}" -eq 0 ]; then
    info "no ai-setup.sh-installed packages recorded"
  fi
  for pkg in "${pkgs[@]}"; do
    [ -n "$pkg" ] || continue
    act_cmd "apt package $pkg" sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y "$pkg"
  done

  # Node.js / NodeSource repository, only when ai-setup.sh installed it that way.
  if [ "$NODE_FROM" = "nodesource" ]; then
    act_cmd "apt package nodejs (NodeSource install)" \
      sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y nodejs
    rm_path_sudo "/etc/apt/sources.list.d/nodesource.list"
    rm_path_sudo "/etc/apt/sources.list.d/nodesource.sources"
    rm_path_sudo "/usr/share/keyrings/nodesource.gpg"
    if [ "$APPLY" -eq 1 ]; then
      sudo apt-get update -y >/dev/null 2>&1 || true
    fi
  elif [ "$NODE_FROM" = "apt" ]; then
    info "Node.js came from the Kali apt repository; leaving nodejs/npm in place"
    info "  (other tools may depend on them; remove manually if you want:"
    info "   sudo apt-get purge nodejs npm)"
  else
    info "Node.js was preinstalled or is unknown; not touching nodejs/npm"
  fi
  return 0
}

rm_path_sudo() {
  local p="$1"
  [ -n "$p" ] || return 0
  [ -e "$p" ] || return 0
  act_cmd "$p" sudo rm -f -- "$p"
}

remove_state_record() {
  if [ "$PURGE_PACKAGES" -eq 1 ] || [ "$PURGE_DATA" -eq 1 ]; then
    step "Install record"
    rm_path "$(xdg_path state ai-setup)"
  fi
}

report_leftovers() {
  step "Leftovers check"
  local rc line found=0
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$rc" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '  %s:%s\n' "$rc" "$line"
      found=1
    done < <(grep -n 'opencode\|rea\b' "$rc" 2>/dev/null || true)
  done
  if [ "$found" -eq 1 ]; then
    warn "the lines above mention opencode/rea; remove them yourself if unwanted"
  else
    ok "no opencode/rea references left in shell rc files"
  fi
  if have npm && npm ls -g --depth=0 2>/dev/null | grep -q 'rea-agents'; then
    warn "'rea-agents' is still installed globally in npm"
  fi
  return 0
}

# ---------------------------------------------------------------------------
main() {
  if [ "$(id -u)" -eq 0 ]; then
    die "Do not run this as root. Run it as your normal user; it uses sudo when needed."
  fi

  printf '%s\n' "AI setup uninstaller (OpenCode + REA)"
  if [ "$APPLY" -eq 1 ]; then
    printf '%sAPPLYING%s changes\n' "$C_RED" "$C_RESET"
  else
    printf '%sDRY RUN%s - nothing will be changed. Re-run with --yes to apply.\n' \
      "$C_YELLOW" "$C_RESET"
  fi
  if [ "$HAVE_RECORD" -eq 1 ]; then
    info "install record: $STATE_FILE"
  else
    warn "no install record found; falling back to detection (some steps may be skipped)"
  fi

  if [ "$APPLY" -eq 1 ] && [ "$PURGE_PACKAGES" -eq 1 ]; then
    sudo -v || die "sudo is required to remove system packages."
  fi

  remove_rea
  remove_opencode
  remove_ghidra
  remove_rc_lines
  restore_npm_prefix
  if [ "$PURGE_DATA" -eq 1 ]; then
    remove_data
  else
    step "Tool data and configuration"
    info "kept (use --purge-data to remove): $(xdg_path config opencode), $(xdg_path data opencode), $HOME/.rea"
  fi
  if [ "$PURGE_PACKAGES" -eq 1 ]; then
    remove_packages
  else
    step "System packages"
    info "kept base packages (procps, curl, git, ...) - removing procps breaks Kali"
    info "kept extras: use --purge-packages for jadx/openjdk-21-jdk/nodejs"
  fi
  remove_state_record
  report_leftovers

  step "Done"
  if [ "$APPLY" -eq 1 ]; then
    ok "removal complete"
    info "open a new shell so PATH changes take effect"
  else
    info "re-run with --yes to apply the plan above"
  fi
}

main "$@"
