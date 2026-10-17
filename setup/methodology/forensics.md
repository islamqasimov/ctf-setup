# FORENSICS — процедура

> Команды: `CTF_CHEATSHEET.md` → FORENSICS. Первый проход: `enum-file <file>`.

## 1. Определи тип и ничего не запускай

```bash
enum-file files/suspect.bin
```
Что смотрим: `file`, магические байты (`xxd | head`), хвост файла (`xxd | tail`) —
дописанные данные после EOF встречаются постоянно, метаданные (`exiftool -a -G1`),
`strings`, `binwalk`.

## 2. Дерево по типу

### 2.1 Изображение (png/jpg/gif/bmp/webp)
1. Метаданные: `exiftool` (комментарии, GPS, «Artist»).
2. `pngcheck -v img.png` — проверка структуры PNG (битые чанки = правленые данные).
3. LSB: `zsteg -a img.png` (PNG), `stegsolve.jar` (bit planes), `stegseek img.jpg rockyou.txt`
   (bruteforce пароля steghide), `steghide extract -sf img.jpg`.
4. `binwalk -e` — что дописано в конец.
5. Проверь палитру: `convert img.png -unique-colors txt: | head`.
6. Аудио-спектрограмма не нужна — но для GIF проверь все кадры (`ffmpeg -i a.gif frame%03d.png`).

### 2.2 Аудио (wav/mp3/flac)
1. `sox audio.wav -n spectrogram -o spec.png` или Sonic Visualiser — ищи текст в спектре.
2. `strings`, хвост файла, `binwalk`.
3. LSB в PCM: `python3 -c` c numpy, либо `wav2png`.
4. Morse/DTMF/стенография по паузам.

### 2.3 Архив (zip/rar/7z/tar/gz)
1. Листинг без распаковки: `7z l`, `unzip -l`.
2. Скрытые внутри архивы: `binwalk -e`, «zip в zip».
3. Пароль: `zip2john`, `rar2john`, `7z2john` → `john --wordlist=rockyou.txt` / `hashcat -m 17200`.
4. ZipCrypto known-plaintext: `bkcrack`.

### 2.4 PDF
1. `pdftotext out.txt`, `pdfimages -all`, `qpdf --decrypt`.
2. `strings | grep -i flag`, скрытый текст (белым по белому — меняешь цвет/копируешь текст).
3. `pdf-parser`, `pdfid` — вложения и JS.

### 2.5 Документы Office
`olevba`/`oletools` (макросы), `unzip -l doc.docx` (XML внутри), метаданные автора.

### 2.6 PCAP
```bash
tshark -r cap.pcap -q -z io,phs              # протоколы
tshark -r cap.pcap -q -z conv,tcp            # сессии
tshark -r cap.pcap -Y http                   # HTTP
tshark -r cap.pcap --export-objects http,out/    # файлы из трафика
```
1. Следуй TCP-стримам (`Follow TCP Stream`) — ищи креды и флаги в открытом виде.
2. DNS-туннель: длинные поддомены, `tshark -Y dns -T fields -e dns.qry.name`.
3. USB HID (если pcap с USB): извлечь нажатия клавиш (`usbhid-dump`, `ctf-usb-keyboard-parser`).
4. Wi-Fi: рукопожатия → `aircrack-ng`.

### 2.7 Дамп памяти
```bash
volatility3 -f dump.raw windows.info
volatility3 -f dump.raw windows.pslist
volatility3 -f dump.raw windows.cmdline
volatility3 -f dump.raw windows.filescan | grep -i flag
volatility3 -f dump.raw windows.dumpfiles --pid <PID>
volatility3 -f dump.raw windows.netscan
```
Порядок: `info` → определить профиль → процессы → командные строки → файлы → реестр
(`printkey`) → сеть. Ищи `mimikatz`, браузерные артефакты, `strings` по дампу.

### 2.8 Образ диска
```bash
mmls disk.img                # разделы и смещения
fls -r -o <offset> disk.img  # файлы, включая удалённые
icat -o <offset> disk.img <inode> > recovered
mount -o ro,loop,offset=$((512*<start>)) disk.img /mnt
foremost/photorec            # карвинг
```
Проверь: `$MFT`, корзину, историю браузера, `.bash_history`, `crontab`, `/etc/passwd`.

### 2.9 Git-репозиторий
```bash
git log --all --oneline
git fsck --unreachable          # висячие коммиты
git stash list; git reflog
git cat-file -p <hash>
```
Секреты в истории: `trufflehog git file://.`, `gitleaks`.

## 3. Работа с «многослойными» заданиями

Формат типичного forensics-таска: файл → архив → пароль из метаданных → внутри
картинка → LSB → base64 → флаг. Записывай **цепочку** сразу на странице задания в Notion,
иначе потеряешь порядок слоёв.

## 4. Стеганография: шпаргалка по выбору инструмента

| Тип | Инструмент |
| --- | --- |
| PNG/JPEG + пароль | `steghide`, `stegseek` |
| PNG LSB | `zsteg`, `stegsolve` |
| Аудио-спектр | `sox`, Sonic Visualiser |
| Дописанные данные | `binwalk -e`, `foremost`, `xxd tail` |
| Текст/пробелы | whitespace stego, `cat -A` |
| PDF/Office | макросы, метаданные, скрытый текст |

## 5. Финал

1. Флаг может быть и в метаданных, и в «странном» имени файла — проверяй всё.
2. Опиши цепочку слоёв — именно этого ждут в райтапе.
3. Скрипты карвинга/декодирования — в `scripts/`.
