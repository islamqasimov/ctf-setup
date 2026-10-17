#!/usr/bin/env bash
#
# enum-web — web recon: fingerprint -> low-hanging files -> dirsearch
# (+ optional vhost fuzz and subdomain pass). Results go to
# loot/<host>/web/port-<port>/<timestamp>/.
#
#   enum-web http://10.10.10.10
#   enum-web http://10.10.10.10:8080 --wordlist /usr/share/wordlists/dirb/big.txt
#   enum-web http://target --vhost target.htb
#   enum-web http://target --subs target.htb
#
set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
. "$(dirname "$SELF")/_common.sh"

usage() {
  cat <<'EOF'
Usage: enum-web <url> [options]

Options:
  --wordlist FILE   wordlist for content discovery (default: autodetect)
  --ext LIST        extensions to append (default: php,txt,html,bak,zip,old,git)
  --vhost DOMAIN    also fuzz Host: FUZZ.DOMAIN with ffuf/gobuster
  --subs DOMAIN     also enumerate subdomains (subfinder -> httpx)
  -h, --help        this help
EOF
}

URL=""; WL=""; EXT="php,txt,html,bak,zip,old,git"; VHOST=""; SUBS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --wordlist) shift; WL="${1:?}" ;;
    --ext)      shift; EXT="${1:?}" ;;
    --vhost)    shift; VHOST="${1:?}" ;;
    --subs)     shift; SUBS="${1:?}" ;;
    -h|--help)  usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) URL="$1" ;;
  esac
  shift
done
[ -n "$URL" ] || { usage >&2; exit 2; }

case "$URL" in http://*|https://*) : ;; *) URL="http://$URL" ;; esac

# host / port / base
HOSTPORT="${URL#*://}"; HOSTPORT="${HOSTPORT%%/*}"
HOST="${HOSTPORT%%:*}"
PORT="${HOSTPORT##*:}"
if [ "$PORT" = "$HOST" ]; then
  case "$URL" in https://*) PORT=443 ;; *) PORT=80 ;; esac
fi

DIR="$(new_loot "$HOST" "web/port-$PORT")"
# resolve a relative --wordlist against the invocation directory (we cd below)
START_PWD="$PWD"
case "$WL" in
  ""|/*) : ;;
  *) WL="$START_PWD/$WL" ;;
esac
cd "$DIR"
{
  echo "# Web: $URL"
  echo
  echo "- дата: $(date -Is)"
  echo "- хост: $HOST:$PORT"
  echo
  echo "## Команда"
  echo '```'
  echo "$0 $*"
  echo '```'
  echo "## Находки"
} >SUMMARY.md

# ---------------------------------------------------------------------------
step "1/5 Fingerprint"
run_log headers.txt timeout 20 curl -sS -I -L "$URL" || true
if have whatweb; then
  run_log whatweb.txt timeout 120 whatweb -a 3 "$URL" || true
else
  warn "whatweb not installed (apt install whatweb)"
fi
if have wafw00f; then run_log wafw00f.txt timeout 60 wafw00f "$URL" || true; fi
echo "- заголовки: headers.txt, технологии: whatweb.txt" >>SUMMARY.md

# ---------------------------------------------------------------------------
step "2/5 Low-hanging files"
for p in robots.txt sitemap.xml .git/config .env .htaccess server-status \
         .well-known/security.txt backup.zip .DS_Store phpinfo.php; do
  safe="$(printf '%s' "$p" | tr '/.' '__')"
  code="$(probe "$URL/$p" "${safe}.body" | awk '{print $1}')"
  info "$code  /$p"
  case "$code" in
    200|301|302|401|403) echo "- \`/$p\` -> HTTP $code (${safe}.body)" >>SUMMARY.md ;;
  esac
done

# ---------------------------------------------------------------------------
step "3/5 Content discovery"
if [ -z "$WL" ]; then
  WL="$(pick_wordlist_web || true)"
fi
if [ -n "$WL" ]; then
  info "wordlist: $WL"
  echo "- wordlist: \`$WL\`" >>SUMMARY.md
else
  warn "no wordlist found — run setup/install.sh --with-wordlists"
fi

if have dirsearch && [ -n "$WL" ]; then
  run_log dirsearch.log timeout 1800 dirsearch -u "$URL" -w "$WL" -e "$EXT" \
    -t 40 --random-agent || true
  echo "- dirsearch: dirsearch.log" >>SUMMARY.md
elif have feroxbuster && [ -n "$WL" ]; then
  warn "dirsearch not found — using feroxbuster"
  run_log feroxbuster.log timeout 1800 feroxbuster -u "$URL" -w "$WL" -x "$EXT" -q || true
  echo "- feroxbuster: feroxbuster.log" >>SUMMARY.md
elif have ffuf && [ -n "$WL" ]; then
  warn "using ffuf"
  run_log ffuf.log timeout 1800 ffuf -u "$URL/FUZZ" -w "$WL" -mc all -fc 404 || true
  echo "- ffuf: ffuf.log" >>SUMMARY.md
else
  warn "no content-discovery tool found (dirsearch/feroxbuster/ffuf)"
fi

# ---------------------------------------------------------------------------
if [ -n "$VHOST" ]; then
  step "4/5 vhost fuzz (Host: FUZZ.$VHOST)"
  DW="$(pick_wordlist_dns || true)"
  if [ -z "$DW" ]; then
    warn "no subdomain wordlist found — skipping vhost fuzz"
  elif have ffuf; then
    FFUF_WL="$DW"
    # ffuf on a vhost needs the base host size to filter it out
    base_size="$(curl -sS -o /dev/null -w '%{size_download}' -H "Host: nothing.$VHOST" "$URL" || echo 0)"
    run_log vhost_ffuf.log timeout 900 ffuf -u "$URL" -H "Host: FUZZ.$VHOST" \
      -w "$FFUF_WL" -fs "$base_size" || true
    echo "- vhost fuzz (ffuf): vhost_ffuf.log" >>SUMMARY.md
  elif have gobuster; then
    run_log vhost_gobuster.log timeout 900 gobuster vhost -u "$URL" -w "$DW" || true
    echo "- vhost fuzz (gobuster): vhost_gobuster.log" >>SUMMARY.md
  else
    warn "ffuf/gobuster not found — skipping vhost fuzz"
  fi
fi

# ---------------------------------------------------------------------------
if [ -n "$SUBS" ]; then
  step "5/5 Subdomains ($SUBS)"
  if have subfinder; then
    run_log subdomains.txt timeout 600 subfinder -d "$SUBS" -silent || true
    if have httpx && [ -s subdomains.txt ]; then
      timeout 600 httpx -l subdomains.txt -silent -o alive.txt 2>/dev/null || true
      info "живые: $(wc -l <alive.txt 2>/dev/null || echo 0)"
      echo "- живые хосты: alive.txt" >>SUMMARY.md
    fi
  else
    warn "subfinder not installed (setup/install.sh --only recon)"
  fi
fi

step "Готово"
ok "результаты: $DIR"
info "сводка:    $DIR/SUMMARY.md"
