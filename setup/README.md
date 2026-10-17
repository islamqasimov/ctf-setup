# setup/ — CTF swiss knife

Everything needed to turn a **fresh Kali Linux** box into a ready-to-play
jeopardy-CTF workstation, plus the enumerators and the team methodology.

Design rules:

- **Binaries only.** This folder never runs `apt`. Kali-native tools (nmap,
  dirsearch, ghidra, checksec, tshark, …) are *checked*, not installed;
  `install.sh --check` tells you exactly what is missing and how to add it.
- **Pinned + verified.** Every download is a pinned GitHub release asset with a
  SHA256 verified before use (`manifest.tsv`). No `curl | bash`, no drift
  mid-competition.
- **Hybrid delivery.** On a networked box the installer downloads on demand; for
  an air-gapped CTF box `bundle.sh` packs a verified offline tarball.
- **Idempotent.** Re-running is a no-op for everything already current.

## Layout

```
setup/
├── install.sh        main installer (pinned binaries + link scripts)
├── bundle.sh         build / verify an offline bundle
├── manifest.tsv      the pinned tool list (name, version, group, url, sha256)
├── README.md         this file
├── ai-setup.sh       OpenCode + REA (Ghidra/JADX) installer
├── ai-uninstall.sh   exact removal of what ai-setup.sh installed
├── ai-setup.md       AI-setup documentation
├── scripts/          enumerators, symlinked into ~/.local/bin
│   ├── _common.sh        shared library (sourced, not executed)
│   ├── ctf-init.sh       scaffold a per-challenge workspace
│   ├── enum-net.sh       rustscan -> nmap -sC -sV -> service hints -> searchsploit
│   ├── enum-web.sh       fingerprint -> low-hanging files -> dirsearch -> vhost/subs
│   ├── enum-bin.sh       binary triage report (RE/pwn)
│   ├── enum-file.sh      forensics/crypto file triage
│   ├── pwn-new.sh        pwntools solve skeleton
│   └── listen.sh         reverse-shell listener + payloads
└── methodology/      runbooks (RU): 00-start, web, pwn, rev, crypto,
                      forensics, network, osint, misc
```

## Quickstart (networked Kali)

```bash
# 1. pinned binaries + shell completion of PATH + script symlinks
./setup/install.sh -y

# 2. optional: pinned SecLists — a curated 10-file subset (~8 MB, sparse clone)
./setup/install.sh --with-wordlists

# 3. what does Kali already provide?
./setup/install.sh --check
```

Open a new shell (or `source ~/.bashrc`), then:

```bash
ctf-init web-login && cd web-login
enum-web http://10.10.10.10
enum-net 10.10.10.10 --udp
enum-bin files/chall
enum-file files/capture.pcap
```

Every script writes raw output **and** a `SUMMARY.md`/`report.md` into
`./loot/<target>/<category>/<timestamp>/`, so the write-up is collected as you go.

## Air-gapped CTF box

```bash
# on a machine with internet + the same repo
./setup/bundle.sh --with-wordlists
# -> setup/dist/ctf-bundle-YYYYMMDD.tar.zst (+ .sha256)

# copy over, then on the offline box
tar xf ctf-bundle-YYYYMMDD.tar.zst && cd ctf-bundle-YYYYMMDD
./install.sh --offline . --with-wordlists
```

`bundle.sh --verify` re-downloads everything and reports manifest drift
(use it after bumping a version).

## Flags

### install.sh

| Flag | Meaning |
| --- | --- |
| `-y, --yes` | non-interactive (default anyway) |
| `--only recon\|web\|pwn` | install one group (repeatable) |
| `--with-wordlists` | pinned SecLists **curated subset** (~8 MB: 2.3-medium/small, common, raft, quickhits, big, DNS top-5000) into `~/.local/share/wordlists/SecLists` |
| `--offline DIR` | install from an unpacked bundle, no network |
| `--check` | doctor: tool versions + missing Kali tools with the apt command |
| `--force` | reinstall even if the version matches |

### bundle.sh

| Flag | Meaning |
| --- | --- |
| `--with-wordlists` | bundle the pinned SecLists subset |
| `--verify` | only re-check manifest hashes, pack nothing |
| `--out DIR` | bundle root (default `setup/dist`) |

## Pinned tools

| Group | Tools |
| --- | --- |
| recon | rustscan, naabu, subfinder, httpx, katana |
| web | ffuf, feroxbuster, nuclei, gau |
| pwn | pwninit |

Everything else is expected from Kali (`--check` lists it).

## Wordlists

`--with-wordlists` sparse-clones a **curated 10-file subset** of SecLists
(tag `CTF_SECLISTS_TAG`, default `2026.1`) instead of whole directories
(`Discovery/Web-Content` + `Passwords/` alone exceed 1.5 GB):

```
Discovery/Web-Content/DirBuster-2007_directory-list-2.3-{medium,small}.txt
Discovery/Web-Content/{common,quickhits,big}.txt
Discovery/Web-Content/raft-{small,medium}-directories.txt
Discovery/Web-Content/raft-small-files.txt
Discovery/DNS/subdomains-top1million-5000.txt
Discovery/DNS/namelist.txt
```

Total ≈ 8 MB. The enum scripts resolve wordlists in this order:
`$CTF_SECLISTS` → `/usr/share/seclists` → `/usr/share/wordlists/seclists` →
`~/.local/share/wordlists/SecLists` → Kali's `dirb`/`dirbuster` lists.
`rockyou` is taken from `/usr/share/wordlists/rockyou.txt` if present.

## Adding or bumping a tool

1. Edit `manifest.tsv` (tab-separated; `kind` is one of `tgz`, `zip`, `zip+tgz`, `raw`).
2. Compute the new hash and confirm downstream:
   ```bash
   ./setup/bundle.sh --verify      # reports stale hashes
   ```
3. `./setup/install.sh -y` picks up the new version (per-tool `.version` sidecars
   in `~/.local/bin` make this exact).

## Environment variables

| Variable | Default | Used by |
| --- | --- | --- |
| `CTF_BIN_DIR` | `~/.local/bin` | install.sh (where binaries/links go) |
| `CTF_CACHE_DIR` | `~/.cache/ctf-tools` | download cache |
| `CTF_WORDLISTS_DIR` | `~/.local/share/wordlists/SecLists` | --with-wordlists |
| `CTF_SECLISTS_TAG` | `2026.1` | pinned SecLists tag |
| `CTF_LOOT_DIR` | `./loot` | all enum-*.sh |
| `CTF_SECLISTS` | autodetect | wordlist lookup |

## Requirements

`bash`, `curl`, `tar`, `unzip`, `sha256sum`/coreutils, `git` (only for
`--with-wordlists`), plus the individual Kali-native tools each enumerator
wants (each script warns and continues instead of dying).

## Notes

- Scripts never run `ldd` on challenge binaries (it can execute code).
- `nuclei` needs its templates from the internet (`nuclei -update-templates`);
  treat it as an online-only tool.
- Methodology files are in Russian; scripts and this README are in English.
- Team notes and knowledge sharing live on a **Notion page per challenge** in the
  shared team space; `notes.md` (scaffolded by `ctf-init`) is only the offline
  buffer for when Notion is unreachable. The repo ships no Notion tooling — it is
  a docs-only convention.
