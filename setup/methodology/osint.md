# OSINT — процедура

> Команды: `CTF_CHEATSHEET.md` → OSINT. Правило: **фиксируй каждый шаг** —
> в OSINT райтап проверяем по цепочке источников.

## 1. Зафиксируй исходные данные

- nickname / handle / email / телефон;
- фото (в т.ч. «внутри» другого фото), видео, скриншот;
- домен / IP / организация / «сотрудник»;
- геолокация по описанию, время, событие.

Заведи секцию **Источники** на странице задания в Notion — ссылка + что нашёл + время доступа.

## 2. Никнейм / человек

1. Поиск в нескольких движках (Google, Bing, Yandex, DuckDuckGo) с кавычками:
   `"nickname"`, `nickname filetype:pdf`, `nickname site:github.com`.
2. Агрегаторы: `sherlock nickname`, `maigret nickname` — профили по сайтам.
3. Архивы: `web.archive.org/web/*/url`, Google Cache.
4. Специфика платформ: GitHub (коммиты, `git log`, email в commits), Twitter/X, Reddit,
   Steam, форумы. Ищи реиспользование ника/аватара.
5. Email: `holehe`, `epieos.com`, проверка утечек (`haveibeenpwned`).
6. Телефон: определяешь страну/оператора, мессенджеры (номера в WhatsApp/Telegram —
   через веб-проверки, без спама).

## 3. Домен / инфраструктура

```bash
whois domain.com
dig domain.com ANY +noall +answer
dig domain.com MX
dnsrecon -d domain.com
theHarvester -d domain.com -b all
```
- `crt.sh` → поддомены из сертификатов; `dnsx`/`subfinder` → живые;
- `web.archive.org` → старая версия сайта (иногда с комментариями/секретами);
- `shodan.io` / `censys.io` / `fofa` → открытые порты, баннеры, версии;
- robots.txt, sitemap.xml, `/.well-known/`.

## 4. Фото / видео

1. Обратный поиск: Google Images, Yandex, TinEye, Bing Visual Search, PimEyes (лица).
2. `exiftool -a -G1 photo.jpg` → камера, ПО, дата, GPS.
   - GPS есть → координаты в Google Maps / OpenStreetMap, ищи ориентиры на снимке.
3. Метаданные в соцсетях обычно стёрты (платформа удаляет EXIF) — тогда работаем по
   содержимому: вывески, языки, номера, погода, тени (определение времени/сторон света).
4. Видео: `ffprobe`, покадрово (`ffmpeg`), субтитры, фон в отражениях.

## 5. Геолокация (geolocation)

Порядок:
1. Язык/надписи → страна/регион.
2. Тип растительности, архитектура, дорожная разметка, столбы, номера домов.
3. Солнце/тени → время суток и направление (hats: SunCalc).
4. Уникальные объекты (памятники, вывески сетей) → поиск по картинке/картам.
5. Финальная проверка: Google Street View / Mapillary/ Yandex Panoramas.

## 6. Утечки и публичные данные

- GitHub/GitLab: `github.com/search?q=`, `gitleaks`, `trufflehog org:<org>`;
- pastebin/gist, форумы, объявления;
- документы: `site:*.edu filetype:xlsx <фамилия>`;
- публичные шареные Google Docs/Drive/Figma/Notion (ищи по названию).

## 7. Правила и этика

- Только открытые источники и только в рамках правил CTF; никакого доступа к чужим
  аккаунтам, никакого социального инжиниринга людей вне сценария.
- Не «докси» реальных людей: если задание про реальную персону — ищи только нужный флаг.
- Все запросы логировать (URL + время) — это часть райтапа.

## 8. Инструменты (держать под рукой)

```bash
sherlock username          # профили по сайтам
maigret username
holehe email@example.com
exiftool -a -G1 file
theHarvester -d domain -b all
whois / dig / dnsrecon
```

Веб: Google/Yandex/Bing, images.google.com, tineye.com, web.archive.org,
crt.sh, shodan.io, haveibeenpwned.com, epieos.com, suncalc.org, mapillary.com.

## 9. Финал

1. Флаг — почти всегда следствие цепочки «данные → источник → вывод».
2. На странице задания в Notion собери таблицу: **шаг → инструмент → результат → ссылка**.
3. Если нашли несколько кандидатов-флагов, проверь формат и отправь самый
   обоснованный.
