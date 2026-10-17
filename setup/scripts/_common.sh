#!/usr/bin/env bash
# _common.sh — shared helpers for the CTF swiss-knife scripts.
# Sourced, never executed. Provides output helpers, loot paths, wordlist and
# tool detection, and a summary/notes writer.

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""
fi

step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '     %s\n' "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
ts()   { date +%Y%m%d-%H%M%S; }

# Run a command, tee its output to a log file, never abort the caller.
#   run_log <logfile> <cmd...>
run_log() {
  local log="$1"; shift
  info "$ $*"
  { "$@" 2>&1 || true; } | tee "$log"
}

# ---------------------------------------------------------------------------
# Loot
# ---------------------------------------------------------------------------
# CTF_LOOT_DIR overrides the loot root (default: ./loot in the current workspace,
# which ctf-init creates).
loot_root() { printf '%s' "${CTF_LOOT_DIR:-$PWD/loot}"; }

# new_loot <target> <category> [timestamp] -> prints and creates the loot dir
new_loot() {
  local target="$1" category="$2" stamp="${3:-$(ts)}"
  local dir; dir="$(loot_root)/$target/$category/$stamp"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# summarize <dir> <line>  — appends a line to <dir>/SUMMARY.md
summarize() {
  local dir="$1"; shift
  printf -- '- %s\n' "$*" >>"$dir/SUMMARY.md"
}

# hex_head <file> <lines> — portable hex view (xxd -> hexdump -> od)
hex_head() {
  local f="$1" n="${2:-16}"
  if have xxd; then
    xxd "$f" | head -n "$n"
  elif have hexdump; then
    hexdump -C "$f" | head -n "$n"
  elif have od; then
    od -Ax -tx1z -v "$f" | head -n "$n"
  else
    printf '(нет xxd/hexdump/od — установи vim-common или bsdextrautils)\n'
  fi
}

# hex_tail <file> <lines> — last bytes (appended-data / EOF tricks)
hex_tail() {
  local f="$1" n="${2:-16}"
  if have xxd; then
    xxd "$f" | tail -n "$n"
  elif have hexdump; then
    hexdump -C "$f" | tail -n "$n"
  elif have od; then
    od -Ax -tx1z -v "$f" | tail -n "$n"
  else
    printf '(нет xxd/hexdump/od)\n'
  fi
}

# gnmap_ports <file.gnmap> -> "22,80,443"
gnmap_ports() {
  awk '/Ports:/{print $2}' "$1" 2>/dev/null \
    | tr ',' '\n' | sed -e 's|/.*||' -e 's/[^0-9]//g' \
    | grep -E '^[0-9]+$' | sort -n -u | tr '\n' ',' | sed 's/,$//'
}

# ---------------------------------------------------------------------------
# Wordlists
# ---------------------------------------------------------------------------
seclists_root() {
  local c
  for c in "${CTF_SECLISTS:-}" /usr/share/seclists /usr/share/wordlists/seclists \
           "$HOME/.local/share/wordlists/SecLists"; do
    [ -n "$c" ] && [ -d "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# pick_wordlist_web -> path of a usable web-content wordlist, or fails
pick_wordlist_web() {
  local root c
  if root="$(seclists_root)"; then
    for c in "$root/Discovery/Web-Content/DirBuster-2007_directory-list-2.3-medium.txt" \
             "$root/Discovery/Web-Content/directory-list-2.3-medium.txt" \
             "$root/Discovery/Web-Content/common.txt" \
             "$root/Discovery/Web-Content/raft-medium-directories.txt" \
             "$root/Discovery/Web-Content/raft-small-directories.txt" \
             "$root/Discovery/Web-Content/DirBuster-2007_directory-list-2.3-small.txt" \
             "$root/Discovery/Web-Content/directory-list-2.3-small.txt"; do
      [ -f "$c" ] && { printf '%s' "$c"; return 0; }
    done
  fi
  for c in /usr/share/wordlists/dirb/common.txt \
           /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt \
           /usr/share/wordlists/dirb/big.txt; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# pick_wordlist_dns -> subdomain wordlist, or fails
pick_wordlist_dns() {
  local root c
  if root="$(seclists_root)"; then
    for c in "$root/Discovery/DNS/subdomains-top1million-5000.txt" \
             "$root/Discovery/DNS/subdomains-top1million-110000.txt" \
             "$root/Discovery/DNS/bitquark-subdomains-top100000.txt" \
             "$root/Discovery/DNS/namelist.txt"; do
      [ -f "$c" ] && { printf '%s' "$c"; return 0; }
    done
  fi
  for c in /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
           /usr/share/wordlists/amass/subdomains-top1mil-5000.txt; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# pick_wordlist_pass -> password wordlist, or fails
pick_wordlist_pass() {
  local c
  for c in /usr/share/wordlists/rockyou.txt /usr/share/wordlists/rockyou.txt.gz \
           "$HOME/.local/share/wordlists/SecLists/Passwords/Common-Credentials/10-million-password-list-top-1000000.txt"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# ---------------------------------------------------------------------------
# Tool helpers
# ---------------------------------------------------------------------------
# need <tool> [hint] — warn (once) instead of dying; caller should guard usage
need() {
  local tool="$1" hint="${2:-}"
  if have "$tool"; then return 0; fi
  warn "missing tool: $tool${hint:+ ($hint)}"
  return 1
}

# probe <url> <outfile> [curl args...] — quiet HTTP fetch that records status
probe() {
  local url="$1" out="$2"; shift 2
  local code
  code="$(curl -sS -o "$out" -w '%{http_code}' --max-time 15 "$@" "$url" 2>/dev/null || echo 000)"
  printf '%s  %s\n' "$code" "$url"
  return 0
}

# local_ip — best-effort "my IP as seen by the target" for reverse shells
local_ip() {
  local ip
  ip="$(ip -4 -o addr show 2>/dev/null | awk '$2=="tun0"{print $4}' | cut -d/ -f1 | head -n1)"
  [ -z "$ip" ] && ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
  printf '%s' "${ip:-127.0.0.1}"
}
