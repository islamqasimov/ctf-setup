# REVERSE — процедура

> Команды: `CTF_CHEATSHEET.md` → REVERSE. Триаж: `enum-bin`.
> Динамика: `gdb` + pwndbg/gef, `ltrace`/`strace`, `frida-trace`.
> Статика: Ghidra / radare2 / rizin; для APK — JADX.

## 0. Гигиена

1. Никогда не запускай незнакомый бинарь как root и без песочницы/VM.
2. Сначала статика (`file`, `strings`, `readelf`), только потом запуск.
3. `sha256sum files/*` — зафиксировать то, что анализируешь.

## 1. Триаж (1 минута)

```bash
enum-bin files/chall
```
Смотри:
- `file` — ELF/PE/.NET/Java/APK/Python-exe/Go/Rust;
- упакован ли (`UPX` → `upx -d`);
- протекции (`checksec`) — важно и для реверса: анти-dbg, PIE;
- интересные строки: «wrong password», «Correct», названия функций, форматы.

## 2. Быстрые проверки поведения

```bash
chmod +x files/chall
./files/chall                # что просит на входе?
ltrace -f -s 200 ./files/chall     # сравнения строк/математика
strace -f ./files/chall            # какие файлы/сеть трогает
strings -n 8 files/chall | less
```

Если это Go/Rust — бинарь огромный, ищи сразу по своим строкам и иди в Ghidra
с фильтром по `main.` (Go) или найдя `main` через `afl` в r2.

## 3. Статика: найти проверку

1. Ghidra → авто-анализ → обычный сценарий: `main` → функция проверки ввода.
2. r2 быстрее для мелочей:
   ```
   r2 -A files/chall
   afl                       # список функций
   pdf @ main                # дизасм main
   iz                        # строки
   pdc @ sym.check          # псевдо-C (r2dec)
   ```
3. Ключевые паттерны:
   - `strcmp`/`strncmp`/`memcmp` с константой → ищи константу в `.rodata`;
   - XOR-циклы (r2: `px`, Ghidra: смотри размер ключа);
   - `%`/`*` над символами (крипто-преобразование входа);
   - таблицы S-box → AES/кастомный шифр;
   - `ptrace`/`rdtsc` — анти-отладка.

## 4. Динамика

```bash
gdb -q ./chall
> b *main+0x...        # или b strcmp
> run
> x/s $rdi             # что сравнивают
> x/20i $rip
> info registers
```
- `frida-trace -i "strcmp" -i "strncmp" ./chall` — без gdb, очень быстро.
- Пропустить проверку проще, чем её ломать: патчим ветвление.

## 5. Патчинг

```
r2 -w ./chall
> s 0x<addr>
> wx 9090                # NOP 2 байта
> wa jmp 0x<addr>        # или безусловный переход
> wa ret
```
Ghidra: `Ctrl+Shift+G` → изменить инструкцию; затем `Export Program` (часто достаточно
изменить условие `JNE` → `JE`/`JMP`).

## 6. Специфичные форматы

### 6.1 Python (PyInstaller)
```bash
pyinstxtractor-ng app.exe          # или pyinstxtractor.py
decompyle3/uncompyle6 main.pyc     # по версии Python
python3 -m dis main.pyc            # если декомпилятор ругается
```

### 6.2 .NET
`dnSpy`, `ilspycmd app.exe` (`dotnet tool install -g ilspycmd`), `de4dot` (обфускация).

### 6.3 Java / Android
```bash
jadx -d out app.apk          # читаемый Java
apktool d app.apk            # ресурсы + smali
d2j-dex2jar classes.dex      # затем jd-gui
```
Android: смотри `AndroidManifest.xml`, нативные `lib/*.so` (тогда Ghidra + Frida).

### 6.4 WASM / Lua / Unity
- WASM: `wasm2wat`, `wasm-decompile`;
- Unity: `AssetRipper`, `il2cppdumper` для `libil2cpp.so`;
- Lua: `luadec`, `unluac`.

## 7. Автоматизация

- **z3** для constraint-based crackme: выпиши условия из декомпилятора как формулы.
- **angr** для «чёрного ящика»: `find`/`avoid` адреса и `simgr.explore()`.
- **Ghidra + AI**: `ai-setup.sh` в этом репо ставит OpenCode + REA (MCP-сервер для
  Ghidra/JADX) — можно попросить агента разобрать функцию.

## 8. Финал

1. Флаг — обычно строка, которую бинарь ожидает, либо преобразование от неё.
2. Проверь гипотезу полным запуском с найденным вводом.
3. Запиши на странице задания в Notion: адреса, функции, применённый патч, скрипт.

## Грабли

- Декомпилятор врёт: проверяй ассемблер руками (`pdf`, Ghidra listing).
- `UPX -d` иногда не работает из-за модифицированных секций — ищи версию UPX и правь
  заголовки или ломай анти-UPX вручную.
- Не запускай «crackme», который похож на малварь, без изоляции.
