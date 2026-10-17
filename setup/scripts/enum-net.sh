#!/usr/bin/env bash
#
# enum-net — host/port recon: RustScan (fast discovery) -> nmap -sC -sV
# -> per-service hints -> searchsploit -> SUMMARY.md
#
#   enum-net 10.10.10.10
#   enum-net 10.10.10.10 --udp
#   enum-net 10.10.10.10 --full          # all 65535 TCP ports (default)
#   enum-net 10.10.10.10 --top 1000      # only the nmap top-1000 ports
#   enum-net 10.10.10.10 --no-rustscan   # nmap-only discovery
#
# Every step is timeout-wrapped and non-fatal: one failing tool never aborts
# the run. All output lands in loot/<target>/net/<timestamp>/.
#
set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
. "$(dirname "$SELF")/_common.sh"
ARGS="$*"

usage() {
  cat <<'EOF'
Usage: enum-net <target> [options]

Options:
  --top N        scan the nmap top-N ports instead of all 65535 (default: 1000)
                 (default behaviour without --top is a full 1-65535 scan)
  --full         force all 65535 TCP ports
  --udp          add a UDP top-100 scan
  --no-rustscan  discover ports with nmap instead of rustscan
  -h, --help     this help
EOF
}

TARGET=""; PORTS_MODE="full"; DO_UDP=0; USE_RUSTSCAN=1
while [ $# -gt 0 ]; do
  case "$1" in
    --top) shift; PORTS_MODE="top:${1:?--top needs a number}" ;;
    --full) PORTS_MODE="full" ;;
    --udp) DO_UDP=1 ;;
    --no-rustscan) USE_RUSTSCAN=0 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { usage >&2; exit 2; }

DIR="$(new_loot "$TARGET" net)"
cd "$DIR"
{
  echo "# Recon сетевой: $TARGET"
  echo
  echo "- дата: $(date -Is)"
  echo "- режим: $PORTS_MODE, udp=$DO_UDP, rustscan=$USE_RUSTSCAN"
  echo
  echo "## Команды"
  echo '```'
  echo "$0 $ARGS"
  echo '```'
  echo "## Результат"
} >SUMMARY.md

PORTS=""

# ---------------------------------------------------------------------------
# 1. Port discovery
# ---------------------------------------------------------------------------
step "1/4 Port discovery ($TARGET)"
case "$PORTS_MODE" in
  full)
    if [ "$USE_RUSTSCAN" -eq 1 ] && have rustscan; then
      run_log rustscan.log timeout 900 rustscan -a "$TARGET" --ulimit 5000 \
        --range 1-65535 --timeout 1500 -g || true
      PORTS="$(grep -oE '\-> .*' rustscan.log | head -n1 | tr -d '[]\r ' | sed -e 's/.*->//' -e 's/[^0-9,]//g' -e 's/^,*//' -e 's/,$//')"
    fi
    if [ -z "$PORTS" ]; then
      have rustscan || warn "rustscan not installed — falling back to nmap -p-"
      run_log nmap_discovery.log timeout 1800 nmap -p- -Pn -T4 --min-rate 2000 \
        -oG nmap_discovery.gnmap "$TARGET" || true
      PORTS="$(gnmap_ports nmap_discovery.gnmap)"
    fi
    ;;
  top:*)
    N="${PORTS_MODE#top:}"
    run_log nmap_discovery.log timeout 900 nmap -Pn -T4 --top-ports "$N" \
      -oG nmap_discovery.gnmap "$TARGET" || true
    PORTS="$(gnmap_ports nmap_discovery.gnmap)"
    ;;
esac

if [ -z "$PORTS" ]; then
  warn "no open TCP ports found (target down, firewalled, or icmp/arp filtered?)"
  echo "- открытых TCP-портов не найдено" >>SUMMARY.md
else
  ok "open TCP ports: $PORTS"
  echo "- открытые TCP-порты: \`$PORTS\`" >>SUMMARY.md
fi

# ---------------------------------------------------------------------------
# 2. Service/version + default scripts
# ---------------------------------------------------------------------------
if [ -n "$PORTS" ]; then
  step "2/4 nmap -sC -sV on discovered ports"
  run_log nmap_services.log timeout 1800 nmap -sC -sV -Pn -p "$PORTS" \
    -oA nmap_services "$TARGET" || true
fi

# ---------------------------------------------------------------------------
# 3. UDP (optional)
# ---------------------------------------------------------------------------
if [ "$DO_UDP" -eq 1 ]; then
  step "3/4 UDP top-100"
  run_log nmap_udp.log timeout 900 nmap -sU --top-ports 100 -Pn "$TARGET" || true
fi

# ---------------------------------------------------------------------------
# 4. Service hints + searchsploit
# ---------------------------------------------------------------------------
step "4/4 Service hints"

add_hint() { echo "- $*" >>SUMMARY.md; }

if [ -n "$PORTS" ]; then
  while read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *http*|*https*) add_hint "HTTP  -> \`enum-web http://$TARGET\` + whatweb/nikto" ;;
      *smb*|*microsoft-ds*|*netbios*) add_hint "SMB   -> enum4linux-ng -A $TARGET ; smbmap -H $TARGET ; nxc smb $TARGET" ;;
      *ssh*) add_hint "SSH   -> ssh-audit $TARGET ; проверь баннер и ключи" ;;
      *ftp*) add_hint "FTP   -> анонимный вход: ftp $TARGET (user: anonymous)" ;;
      *mysql*) add_hint "MySQL -> hydra -l root -P rockyou.txt mysql://$TARGET" ;;
      *redis*) add_hint "Redis -> redis-cli -h $TARGET ; INFO (часто без пароля)" ;;
      *smtp*) add_hint "SMTP  -> smtp-user-enum / VRFY" ;;
      *ldap*) add_hint "LDAP  -> ldapsearch -x -H ldap://$TARGET -b ''" ;;
      *rdp*) add_hint "RDP   -> xfreerdp /v:$TARGET ; nxc rdp $TARGET" ;;
      *domain*|*dns*) add_hint "DNS   -> dnsrecon -d <domain> -a ; зона transfer" ;;
    esac
  done < <(grep -E '^[0-9]+/tcp[[:space:]]+open' nmap_services.log 2>/dev/null | awk '{print $3}' | sort -u)
fi

if have searchsploit && [ -f nmap_services.xml ]; then
  info "searchsploit --nmap (известные эксплойты для версий сервисов)"
  { searchsploit --nmap nmap_services.xml 2>&1 || true; } | tee searchsploit.txt >/dev/null
  echo
  echo "## searchsploit" >>SUMMARY.md
  echo '```' >>SUMMARY.md
  grep -E 'Exploit|Shellcode|Title|^[0-9]' searchsploit.txt | head -n 40 >>SUMMARY.md || true
  echo '```' >>SUMMARY.md
fi

step "Готово"
ok "результаты: $DIR"
info "сводка:    $DIR/SUMMARY.md"
info "детали:    $DIR/nmap_services.log"
