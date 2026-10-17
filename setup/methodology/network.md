# NETWORK — процедура (живые сервисы, не pcap)

> Задание вида «подключись к `host:port`» / «в сети есть сервис». Для pcap
> смотри `forensics.md`. Команды: `CTF_CHEATSHEET.md` → NETWORK.

## 1. Понять правила сети

- Диапазон таргетов (обычно выдан) — **никогда** не скань ничего вне него.
- Есть ли ограничения на скорость сканирования (`-T4` может быть слишком шумным).
- Формат: один сервис или целый хост с несколькими.

## 2. Разведка портов

```bash
enum-net 10.10.10.10            # rustscan -> nmap -sC -sV -> подсказки
enum-net 10.10.10.10 --udp
```
Далее смотри `loot/<target>/net/<ts>/SUMMARY.md`: открытые порты, версии, ссылки на
эксплойты из `searchsploit`.

Если скан «пустой», но сервис точно есть:
- проверь UDP (`--udp`), icmp/arp-фильтры (`-Pn`), нестандартные порты (`-p-`);
- попробуй конкретный порт руками: `nc -nv 10.10.10.10 <port>`;
- IPv6 / другой интерфейс / VPN-маршрут (`ip a`, `ip route`).

## 3. Баннер и протокол

```bash
nc -nv host port
curl -v telnet://host:port
openssl s_client -connect host:port      # TLS-сервис
```
Поймал текст? Запиши его дословно на странице задания в Notion — часто в баннере подсказка
(«send me 3 bytes», «format: user:pass», версия софта).

## 4. Ветки по сервису

### 4.1 HTTP(S)
→ полностью `web.md` (плюс `enum-web http://host:port`).

### 4.2 SSH
```bash
ssh-audit host            # алгоритмы, баннер
ssh -v user@host          # проверить аутентификацию
```
Ключ в задании? `chmod 600 key && ssh -i key user@host`. Passphrase → `ssh2john` + john.

### 4.3 SMB
```bash
enum4linux-ng -A host
smbmap -H host -u '' -p ''
smbclient -N -L //host
nxc smb host -u '' -p '' --shares
```
Ищи анонимный доступ, список пользователей, шары с флагом/ключами.

### 4.4 FTP
```bash
ftp host        # anonymous / anonymous
hydra -l anonymous -P rockyou.txt ftp://host
```

### 4.5 DNS
```bash
dig axfr @host domain.com        # зона transfer
dnsrecon -d domain.com -a -t axfr
```
Зона transfer отдаёт все имена — ищи «hidden»/«flag»/«admin».

### 4.6 Базы данных
```bash
redis-cli -h host                # INFO, CONFIG GET dir, ключи с флагом
mysql -h host -u root -p
psql -h host -U postgres
mongo host:27017
```

### 4.7 SMTP / POP3 / IMAP
`smtp-user-enum`, `VRFY user`, проверь письма (`swaks`, `telnet`).

### 4.8 Неизвестный самописный сервис
Это чаще pwn (см. `pwn.md`). Порядок: `nc` → понять протокол → проверить
переполнение/форматную строку → написать `pwntools`-клиент.

## 5. Брутфорс и креды (когда уместно)

```bash
hydra -L users.txt -P rockyou.txt ssh://host
hydra -l admin -P rockyou.txt http-post-form "/login:user=^USER^&pass=^PASS^:Invalid"
```
Правила: сначала словарь из задания (имена, бренды, слова из описания), и только потом
rockyou. Не бруть сервисы, которые кладутся от нагрузки.

## 6. Аккуратность

- Не используй деструктивные проверки (DoS, `DROP`, wipe).
- Логируй всё: `enum-net` уже пишет лог в `loot/`; добавь свои команды на страницу задания в Notion.
- ncat-реверсы: `listen 4444`.

## 7. Финал

1. Флаг обычно читается с сервиса (`flag.txt` в шаре, ключ в Redis и т.п.).
2. Опиши путь: порт → сервис → версия → доступ → флаг.
3. Скрипты-клиенты — в `scripts/`.
