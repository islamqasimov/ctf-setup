#!/usr/bin/env bash
#
# pwn-new — generate a pwntools solve skeleton for a challenge binary.
#
#   pwn-new files/chall
#   pwn-new files/chall --remote 10.10.10.10:1337 --name babyheap
#
# Writes scripts/solve_<name>.py (checksec result + libc/loader hints baked in)
# and prints the local libc-patching recipe (pwninit / patchelf).
#
set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
. "$(dirname "$SELF")/_common.sh"

usage() {
  cat <<'EOF'
Usage: pwn-new <binary> [--name NAME] [--remote HOST:PORT]

Options:
  --name NAME        output file is scripts/solve_<NAME>.py (default: binary name)
  --remote H:P       pre-fill the remote() call
  -h, --help         this help
EOF
}

BIN=""; NAME=""; REMOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)   shift; NAME="${1:?}" ;;
    --remote) shift; REMOTE="${1:?}" ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) BIN="$1" ;;
  esac
  shift
done
[ -n "$BIN" ] || { usage >&2; exit 2; }
[ -f "$BIN" ] || die "not a file: $BIN"

[ -z "$NAME" ] && NAME="$(basename "$BIN")"
SAFE="$(printf '%s' "$NAME" | tr -c 'A-Za-z0-9._-' '_')"
mkdir -p scripts
OUT="scripts/solve_$SAFE.py"
[ -e "$OUT" ] && die "$OUT already exists"

SEC=""
have checksec && SEC="$(checksec --file="$BIN" 2>/dev/null || true)"

R_HOST=""; R_PORT=""
if [ -n "$REMOTE" ]; then R_HOST="${REMOTE%%:*}"; R_PORT="${REMOTE##*:}"; fi

LIBC_NOTE=""
[ -f "$(dirname "$BIN")/libc.so.6" ] && LIBC_NOTE="$(dirname "$BIN")/libc.so.6"
[ -f "$(dirname "$BIN")/ld-linux-x86-64.so.2" ] && LIBC_NOTE="$LIBC_NOTE $(dirname "$BIN")/ld-linux-x86-64.so.2"

cat >"$OUT" <<EOF
#!/usr/bin/env python3
# solve_$SAFE.py — pwntools skeleton (сгенерирован pwn-new)
#
# checksec:
$(printf '%s\n' "$SEC" | sed 's/^/#   /')
from pwn import *

context.binary = elf = ELF('$(readlink -f "$BIN")', checksec=False)
context.log_level = 'info'
# context.arch = 'amd64'

HOST = '${R_HOST:-target}'
PORT = ${R_PORT:-1337}

def start():
    if args.REMOTE:
        return remote(HOST, PORT)
    if args.GDB:
        return gdb.debug(elf.path, gdbscript='''
            b main
            continue
        ''')
    return process(elf.path)

io = start()

# ---- разведка -------------------------------------------------------------
# ELF:      elf.sym['win'], elf.got['puts'], elf.plt['puts']
# смещение: offset = cyclic_find(0x61616161)   # или pwndbg: pattern offset
# гаджеты:  ROP(elf).find_gadget(['pop rdi', 'ret'])
# libc:     libc = ELF('./libc.so.6'); libc.address = leak - libc.sym['puts']
#           one_gadget ./libc.so.6
# printf:   fmtstr_payload(offset, {elf.got['exit']: elf.sym['win']})

# ---- payload --------------------------------------------------------------
offset = 0          # TODO
payload = flat(
    b'A' * offset,
    # p64(elf.sym['win']),
)

io.sendline(payload)
io.interactive()
EOF

ok "создан $OUT"
cat <<EOF

  Дальше:
    python3 $OUT                    # локально
    python3 $OUT REMOTE             # удалённо ($R_HOST${R_PORT:+:$R_PORT})
    python3 $OUT GDB                # под gdb + pwndbg
EOF

if [ -n "$LIBC_NOTE" ]; then
  info "рядом лежит libc/loader: $LIBC_NOTE"
fi
cat <<EOF

  Локальный запуск с чужим libc (patchelf):
    pwninit                                  # сам патчит и генерит шаблон (если установлен)
    patchelf --set-interpreter ./ld-linux-x86-64.so.2 --replace-needed libc.so.6 ./libc.so.6 $BIN
    # либо: LD_PRELOAD=./libc.so.6 ./$BIN  (иногда достаточно, но интерпретатор должен совпадать)
EOF
