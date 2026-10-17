#!/usr/bin/env bash
#
# enum-file — first-pass forensics / crypto triage for an unknown file.
#
#   enum-file files/suspect.bin
#   enum-file files/capture.pcap
#   enum-file files/chall.png
#
# Writes loot/<name>/file/<ts>/ with per-tool raw output plus report.md and a
# list of concrete next steps chosen from the detected file type.
#
set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
. "$(dirname "$SELF")/_common.sh"

usage() {
  cat <<'EOF'
Usage: enum-file <file>

Runs the standard forensic triage chain (file, xxd, exiftool, strings, binwalk)
and then type-specific checks (pcap -> tshark, image -> stego, archive -> john
hashes, pdf -> text, hashes -> hashid).
EOF
}

FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) FILE="$1" ;;
  esac
  shift
done
[ -n "$FILE" ] || { usage >&2; exit 2; }
[ -f "$FILE" ] || die "not a file: $FILE"
FILE="$(readlink -f "$FILE")"

NAME="$(basename "$FILE")"
DIR="$(new_loot "$NAME" file)"
cd "$DIR"
REPORT="report.md"
FT="$(file -b "$FILE")"

{
  echo "# Triage файла: $NAME"
  echo
  echo "- тип: \`$FT\`"
  echo "- размер: $(stat -c '%s' "$FILE") байт"
  echo "- sha256: \`$(sha256sum "$FILE" | awk '{print $1}')\`"
  echo "- дата: $(date -Is)"
  echo
} >"$REPORT"

step "1/5 Базовый осмотр"
file "$FILE" | tee file.txt
info "первые 256 байт:"
hex_head "$FILE" 16 | tee head.hex || true
info "последние 256 байт (ищи дописанные данные после EOF):"
hex_tail "$FILE" 16 | tee tail.hex || true

step "2/5 Метаданные"
if have exiftool; then
  run_log exiftool.txt timeout 60 exiftool -a -G1 -s "$FILE" || true
  info "GPS: $(grep -iE '^\[.*\]\s+GPS' exiftool.txt 2>/dev/null | head -n3 | tr '\n' ' ')"
else
  warn "exiftool не установлен (apt install libimage-exiftool-perl)"
fi

step "3/5 Строки и известные шаблоны флагов"
strings -n 6 "$FILE" >strings.txt 2>/dev/null || true
FLAGRE='(flag|FLAG|ctf|CTF|picoCTF|HTB|THM|DUCTF|ictf|corctf|uiuctf|n1ctf|asis|hitcon)\{[^}]{0,80}\}'
grep -aoE "$FLAGRE" strings.txt | sort -u | tee flags.txt || true
if [ -s flags.txt ]; then
  ok "возможные флаги: $(tr '\n' ' ' <flags.txt)"
  echo "## Возможные флаги" >>"$REPORT"; cat flags.txt >>"$REPORT"
fi
grep -aoE '[A-Za-z0-9+/]{20,}={0,2}' strings.txt | sort -u | head -n 20 >b64_candidates.txt || true
[ -s b64_candidates.txt ] && echo "- длинные base64-подобные строки: \`b64_candidates.txt\`" >>"$REPORT"

step "4/5 Встроенные файлы (binwalk)"
if have binwalk; then
  run_log binwalk.txt timeout 300 binwalk "$FILE" || true
  grep -qE '^DECIMAL' binwalk.txt && info "есть сигнатуры — распаковать: binwalk -eM '$FILE'"
else
  warn "binwalk не установлен (apt install binwalk)"
fi
if have foremost; then
  info "карвинг: foremost -i '$FILE' -o carved/ (запусти вручную, если нужно)"
fi

step "5/5 Проверки по типу файла"
{
  echo
  echo "## Следующие шаги"
} >>"$REPORT"

case "$FT" in
  *pcap*|*tcpdump*)
    if have tshark; then
      run_log tshark_protocols.txt timeout 300 tshark -r "$FILE" -q -z io,phs || true
      run_log tshark_convs.txt timeout 300 tshark -r "$FILE" -q -z conv,tcp || true
      run_log tshark_http.txt timeout 300 tshark -r "$FILE" -Y http || true
      mkdir -p exported
      timeout 300 tshark -r "$FILE" --export-objects http,exported 2>/dev/null || true
      info "экспортированные объекты: exported/ ($(ls exported 2>/dev/null | wc -l) шт.)"
      echo "- pcap: tshark_protocols.txt, tshark_convs.txt, tshark_http.txt, exported/" >>"$REPORT"
      echo "- ищи креды: \`tshark -r $FILE -Y 'ftp||http.request.method==POST' -T fields -e text\`" >>"$REPORT"
    else
      warn "tshark не установлен (apt install tshark)"
    fi
    ;;
  *PNG*)
    have zsteg && run_log zsteg.txt timeout 300 zsteg -a "$FILE" || warn "zsteg не установлен (gem install zsteg)"
    have steghide && timeout 60 steghide info "$FILE" 2>&1 | tee steghide.txt || true
    echo "- PNG: проверь \`pngcheck -v\`, zsteg (lsb), \`binwalk -e\`, разные bit planes (stegsolve)" >>"$REPORT"
    ;;
  *JPEG*)
    have steghide && timeout 60 steghide info "$FILE" 2>&1 | tee steghide.txt || true
    have stegseek && info "stegseek '$FILE' rockyou.txt  (брут пароля steghide)"
    echo "- JPEG: steghide (пароль?), binwalk -e, exiftool (комментарии/GPS)" >>"$REPORT"
    ;;
  *GIF*|*BMP*)
    echo "- изображение без сжатия: посмотри младшие биты, \`stegsolve\`, \`zsteg\`" >>"$REPORT"
    ;;
  *Zip*|*archive*|*RAR*|*7-zip*|*gzip*|*tar*)
    if have 7z; then
      7z l "$FILE" >archive_list.txt 2>&1 || true
      sed -n '1,40p' archive_list.txt
    else
      warn "7z не установлен (apt install p7zip-full)"
      if have unzip; then unzip -l "$FILE" >archive_list.txt 2>&1 || true; sed -n '1,20p' archive_list.txt; fi
    fi
    echo "- архив: листинг в archive_list.txt; пароль -> \`zip2john/rar2john/7z2john\` + john/hashcat" >>"$REPORT"
    echo "- вложенные файлы: \`7z x '$NAME' -oout/\`" >>"$REPORT"
    ;;
  *PDF*)
    have pdftotext && timeout 60 pdftotext "$FILE" out.txt 2>/dev/null && info "текст: out.txt"
    have pdfimages && mkdir -p imgs && timeout 120 pdfimages -all "$FILE" imgs/ 2>/dev/null || true
    echo "- PDF: \`pdftotext\`, \`pdfimages -all\`, \`qpdf --decrypt\`, \`pdfid/pdf-parser\`" >>"$REPORT"
    ;;
  *[Aa]udio*|*WAVE*|*MPEG*|*FLAC*|*Ogg*)
    echo "- аудио: \`sonic-visualiser\` (спектрограмма), \`audacity\`; проверь дописанные данные в конце (tail.hex)" >>"$REPORT"
    echo "- быстрый тест: \`python3 -c \"import wave;print(wave.open('$NAME').getparams())\"\`" >>"$REPORT"
    ;;
esac

# hash-like: single short line of hex/base64
if [ "$(stat -c '%s' "$FILE")" -le 256 ] && [ "$(wc -l <"$FILE" 2>/dev/null || echo 9)" -le 2 ]; then
  trimmed="$(tr -d '[:space:]' <"$FILE" 2>/dev/null | head -c 128)"
  case "$trimmed" in
    *[!a-zA-Z0-9+/=]*) : ;;
    *)
      if [ -n "$trimmed" ] && have hashid; then
        info "похоже на хеш — hashid:"
        hashid "$trimmed" 2>&1 | tee hashid.txt | head -n 8
        echo "- хеш \`$trimmed\`: см. hashid.txt -> john/hashcat по формату" >>"$REPORT"
      fi
      ;;
  esac
fi

if [ "$(stat -c '%s' "$FILE")" -le 100000 ]; then
  echo "- если это кодирование: \`base64 -d\`, \`xxd -r -p\`, ROT13, XOR (CyberChef Magic)" >>"$REPORT"
fi

step "Готово"
ok "результаты: $DIR"
info "отчёт:    $DIR/$REPORT"
