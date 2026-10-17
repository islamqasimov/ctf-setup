#!/usr/bin/env bash
#
# enum-bin — binary triage for RE/pwn challenges.
#
# Produces loot/<name>/bin/<ts>/report.md with: file type, security
# protections (checksec or readelf-derived), interpreter/libc, UPX detection,
# interesting strings, dynamic imports and a "next steps" list.
#
#   enum-bin ./chall
#   enum-bin ./chall --decompile     # also try r2 -A pdc / ghidra headless
#
# Safety: never runs `ldd` on the target (it can execute code); uses readelf.
#
set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
. "$(dirname "$SELF")/_common.sh"

usage() {
  cat <<'EOF'
Usage: enum-bin <file> [--decompile]

Options:
  --decompile   additionally attempt decompilation:
                radare2 (r2 -A -c 'pdc') if installed, else Ghidra headless
                when GHIDRA_INSTALL_DIR is set.
  -h, --help    this help
EOF
}

BIN=""; DO_DECOMP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --decompile) DO_DECOMP=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) BIN="$1" ;;
  esac
  shift
done
[ -n "$BIN" ] || { usage >&2; exit 2; }
[ -f "$BIN" ] || die "not a file: $BIN"
BIN="$(readlink -f "$BIN")"

NAME="$(basename "$BIN")"
DIR="$(new_loot "$NAME" bin)"
cd "$DIR"
REPORT="report.md"

{
  echo "# Triage: $NAME"
  echo
  echo "- путь: \`$(readlink -f "$BIN")\`"
  echo "- дата: $(date -Is)"
  echo "- sha256: \`$(sha256sum "$BIN" | awk '{print $1}')\`"
  echo
} >"$REPORT"

fence() { echo '```' >>"$REPORT"; cat >>"$REPORT"; echo '```' >>"$REPORT"; }

step "1/6 Тип файла"
file "$BIN" | tee file.txt
echo "## file" >>"$REPORT"; cat file.txt | fence

step "2/6 Защиты (checksec / readelf)"
if have checksec; then
  checksec --file="$BIN" >checksec.txt 2>&1 || true
  cat checksec.txt
  echo "## checksec" >>"$REPORT"; cat checksec.txt | fence
else
  warn "checksec not installed — deriving protections from readelf"
fi

{
  echo "## protections (readelf-вывод)"
  echo
  if readelf -h "$BIN" >/dev/null 2>&1; then
    et="$(readelf -h "$BIN" | awk -F: '/Type:/{print $2}' | xargs)"
    case "$et" in
      *DYN*) echo "- PIE: **включён** (ELF type DYN)" ;;
      *)     echo "- PIE: выключен (ELF type $et) -> адреса функций фиксированы" ;;
    esac
    stack_flags="$(readelf -lW "$BIN" 2>/dev/null | awk '$1=="GNU_STACK"{print $7; exit}')"
    case "$stack_flags" in
      *E*) echo "- NX: **выключен** (GNU_STACK=$stack_flags) -> shellcode на стеке возможен" ;;
      "")  echo "- NX: не определить (нет сегмента GNU_STACK)" ;;
      *)   echo "- NX: включён (GNU_STACK=$stack_flags)" ;;
    esac
    has_relro=0; has_bindnow=0
    readelf -lW "$BIN" 2>/dev/null | grep -q 'GNU_RELRO' && has_relro=1
    readelf -d "$BIN" 2>/dev/null | grep -q 'BIND_NOW' && has_bindnow=1
    if [ "$has_relro" -eq 1 ] && [ "$has_bindnow" -eq 1 ]; then
      echo "- RELRO: **полный** (GNU_RELRO + BIND_NOW) -> перезапись GOT закрыта"
    elif [ "$has_relro" -eq 1 ]; then
      echo "- RELRO: частичный (есть GNU_RELRO, нет BIND_NOW)"
    else
      echo "- RELRO: отсутствует"
    fi
    readelf -s "$BIN" 2>/dev/null | grep -q '__stack_chk_fail' \
      && echo "- Canary: **есть** (\`__stack_chk_fail\`)" \
      || echo "- Canary: не найден"
    interp="$(readelf -l "$BIN" 2>/dev/null | awk -F': ' '/interpreter/{print $2}' | sed -e 's/\]$//' | xargs | head -n1)"
    [ -n "$interp" ] && echo "- interpreter: \`$interp\` -> нужен родной libc/ld (patchelf/pwninit)"
    echo
  else
    echo "- не ELF (см. file.txt) — вероятно PE/.NET/Java/APK; см. шаг 5"
  fi
} >>"$REPORT"
awk '/^## protections/{f=1} f{print}' "$REPORT" | sed -n '1,15p'

step "3/6 Строки, UPX, интересное"
strings -n 6 "$BIN" >strings.txt 2>/dev/null || true
if grep -qi upx strings.txt || file "$BIN" | grep -qi upx; then
  warn "бинарник упакован UPX — распакуй: upx -d $BIN"
  echo "- **UPX упакован** -> \`upx -d $BIN\` перед анализом" >>"$REPORT"
fi
grep -iE 'flag|passw|correct|secret|key|license|admin|/bin/sh|win' strings.txt \
  | sort -u | head -n 40 >interesting.txt || true
if [ -s interesting.txt ]; then
  cat interesting.txt
  echo "## интересные строки" >>"$REPORT"; cat interesting.txt | fence
fi

step "4/6 Импорты / секции"
if readelf -h "$BIN" >/dev/null 2>&1; then
  readelf -d "$BIN" 2>/dev/null | grep NEEDED >libs.txt || true
  objdump -T "$BIN" 2>/dev/null | grep -E '\*UND\*' | awk '{print $NF}' | sort -u >imports.txt || true
  objdump -R "$BIN" 2>/dev/null >relocs.txt || true
  echo "## NEEDED" >>"$REPORT"; cat libs.txt | fence
  echo "## imports (первые 40)" >>"$REPORT"; head -n 40 imports.txt | fence
  echo "## секции" >>"$REPORT"; readelf -S "$BIN" 2>/dev/null | grep -E '\] \.' | awk '{print $2}' | fence
fi

step "5/6 Подсказки по типу файла"
case "$(file -b "$BIN")" in
  *PE32*|*PE32+*|*MS-DOS*)
    echo "- Windows PE: попробуй \`frida-trace\`, \`strings -el\` (UTF-16), Ghidra, для .NET — dnSpy/ilspycmd" | tee -a "$REPORT" >/dev/null ;;
  *Java*|*.class*)
    echo "- Java: \`jadx\`, \`jd-gui\`, \`cfr\`" | tee -a "$REPORT" >/dev/null ;;
  *Zip*|*Android*)
    echo "- APK/zip: \`jadx -d out app.apk\`, \`apktool d app.apk\`" | tee -a "$REPORT" >/dev/null ;;
  *ELF*)
    echo "- ELF: Ghidra/radare2 для статики, gdb+pwndbg для динамики, \`checksec\` уже снят выше" | tee -a "$REPORT" >/dev/null ;;
esac
grep -q 'ELF' <<<"$(file -b "$BIN")" && {
  if have r2; then
    info "быстрый статический разбор: r2 -A -q -c 'afl' '$BIN'"
  fi
}

step "6/6 Итог и следующие шаги"
{
  echo
  echo "## Следующие шаги"
  echo "- статика: Ghidra / \`r2 -A\`; ищи \`main\`, сравнение введённого ввода с константой"
  echo "- динамика: \`ltrace\`, \`strace\`, \`gdb\` + pwndbg (break на strcmp/strncmp)"
  echo "- pwn: посчитай оффсет (\`cyclic\`), глянь гаджеты (\`ROPgadget --only 'pop|ret'\`)"
  echo "- если рядом есть libc.so.6/ld-linux: \`pwninit\` (патчит интерпретатор и генерит шаблон)"
  echo "- документация по шагам: \`setup/methodology/rev.md\` и \`pwn.md\`"
} >>"$REPORT"

if [ "$DO_DECOMP" -eq 1 ]; then
  step "Дополнительно: декомпиляция"
  if have r2; then
    info "r2 -A -c 'pdc' (нужен плагин r2dec)"
    timeout 600 r2 -A -q -c 'pdc' -c 'q' "$BIN" >decompiled.c 2>/dev/null || true
    if [ -s decompiled.c ]; then
      ok "декомпилированный псевдо-C: $(pwd)/decompiled.c"
      echo "- декомпиляция: \`decompiled.c\`" >>"$REPORT"
    else
      warn "r2 не дал псевдо-C (нет r2dec?) — попробуй: r2 -A '$BIN'"
    fi
  elif [ -n "${GHIDRA_INSTALL_DIR:-}" ] && [ -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ]; then
    info "Ghidra headless: импорт + авто-анализ (открой проект в Ghidra GUI для декомпиляции)"
    timeout 1800 "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" "$PWD" ctfproj \
      -import "$(readlink -f "$BIN")" -deleteProject || warn "ghidra headless завершился с ошибкой"
  else
    warn "нет r2 и GHIDRA_INSTALL_DIR не задан — пропускаю декомпиляцию"
  fi
fi

step "Готово"
ok "отчёт: $DIR/$REPORT"
