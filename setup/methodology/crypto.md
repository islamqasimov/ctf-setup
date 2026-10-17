# CRYPTO — процедура

> Команды: `CTF_CHEATSHEET.md` → CRYPTO. Триаж файла: `enum-file <file>`.
> Первым делом всегда CyberChef → Magic / Detect File Type.

## 1. Собрать данные

1. Прочитай условие **дословно**: размер ключа, режим, «same key», «same nonce»,
   «нонс маленький», «p и q близки» — это и есть вектор атаки.
2. Если есть скрипт шифрования (`chall.py`) — он важнее, чем сам шифротекст.
   Читай его целиком, ищи отклонения от нормальной криптографии.
3. Зафиксируй параметры: `n,e,c`, `p,q`, IV, nonce, длина блока.

## 2. Сначала кодировки, не криптография

```bash
enum-file files/cipher.txt
```
- base64/base32/base85/hex/binary/ROT13/Atbash/Morse/URL/HTML entities;
- «человеческие» шифры: Caesar, Vigenère, Rail fence, Affine, Playfair, порченый
  алфавит;
- простое XOR (однобайтовый → перебор 256, многобайтовый → `xortool`).

Правило: если результат «почти текст» — это кодировка, продолжай декодировать.

## 3. XOR

```bash
xortool ciphertext.bin            # угадывает длину ключа
xortool -l 8 -c 20 ciphertext.bin # известная длина ключа
```
```python
for i in range(256):                     # однобайтовый
    pt = bytes(a ^ i for a in ct)
    if b'flag' in pt.lower(): print(pt)
```
Где искать: повторяющиеся байты через 4/8/16 байт → ключ короткий.

## 4. RSA — дерево решений

```
n -> factorint (sympy) / factordb.com
├── N маленькое / p,q близки        → Fermat (gmpy2.isqrt)
├── e=3 и m^3 < n                   → iroot(c,3)
├── НОД(N1,N2) != 1                 → общий множитель (common modulus)
├── два шифра с общим N, e1,e2      → gcdex / расширенный Евклид
├── d маленькое / e огромное        → Wiener (owiener.attack)
├── известны старшие биты p         → Coppersmith (sage) / partial p
└── ничего                          → RsaCtfTool (перебирает всё подряд)
```

```bash
RsaCtfTool.py --publickey key.pub --uncipherfile cipher.txt
RsaCtfTool.py --publickey key.pub --private           # восстановить d
openssl rsa -in key.pem -text -noout                  # параметры ключа
```
Если дают только `n, e, c` — сначала факторизация (factordb быстрее, чем sympy).

## 5. Блочные шифры (AES/DES)

| Признак в условии | Атака |
| --- | --- |
| ECB (одинаковые блоки) | cut-and-paste, byte-at-a-time oracle |
| CBC + модификация IV | bit-flipping первого блока |
| CBC и есть oracle ошибок | padding oracle (`padbuster`) |
| CTR/OFB + повтор nonce | XOR двух шифротекстов → восстановление кейстрима |
| Известный plaintext | XOR с шифротекстом |
| Свой ключ из слабого пароля | `openssl enc` перебор / john |

```bash
padbuster http://target/decrypt <ciphertext> 16 -encoding 0 -cookies "auth=<ct>"
openssl enc -aes-256-cbc -d -in file.enc -out file.dec -k password
```

## 6. Хеши и пароли

```bash
hashid '<hash>'                        # что это вообще
john hash.txt --wordlist=<rockyou>
hashcat -m 0 hash.txt <rockyou>        # 0=MD5, 100=SHA1, 1400=SHA256, 1000=NTLM
```
Особые случаи:
- **length extension** (SHA1/SHA256/MD5, `hash = md5(secret||data)`):
  `hashpump -s '<hash>' -d '<data>' -a '<append>' -k <len(secret)>`;
- **MD5 collisions** (два файла с равными хешами) — fastcoll/hashclash;
- пароли из архива: `zip2john`/`rar2john`/`7z2john` + john.

## 7. Прочее

- **Эллиптические кривые**: малый порядок точки, invalid curve, shared `k`.
- **Диффи-Хеллман**: малый подгрупповой порядок, `g` не генератор.
- **JWT HS256**: секрет из словаря (`jwt_tool`, `hashcat -m 16500`).
- **LSB/stego в «шифре»**: см. `forensics.md`.
- **shamir secret sharing**: собери `k` точек и восстанови полином (Lagrange).

## 8. Свои скрипты

Никогда не считай в столбик — пиши `scripts/solve.py`:

```python
from Crypto.Util.number import long_to_bytes, inverse
from sympy import factorint
p, q = factorint(n).keys()
d = inverse(e, (p-1)*(q-1))
print(long_to_bytes(pow(c, d, n)))
```

bundle: `pycryptodome`, `sympy`, `gmpy2`, `z3-solver`, `owiener`, `pwntools`.
(ставить: `pipx install`/`python3 -m venv`; apt в этом репо не используется)

## Финал

1. Проверь, что флаг читаемый: `long_to_bytes` / декодирование в текст.
2. Запиши на странице задания в Notion точный класс атаки и параметры — в райтапе нужна математика.
3. Сохрани `solve.py` в `scripts/`.
