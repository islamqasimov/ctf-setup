# privcheat — jeopardy CTF swiss knife

Repo for a **fresh Kali Linux** machine handed to you at a jeopardy-style CTF:
pinned tool binaries, one-command setup, enumerators that write write-up-ready
output, and the team runbooks.

## What's here

| Path | What |
| --- | --- |
| [`setup/`](setup/README.md) | installers: pinned binaries (no apt), offline bundle, enum scripts, methodology |
| [`setup/scripts/`](setup/scripts) | `ctf-init`, `enum-net`, `enum-web`, `enum-bin`, `enum-file`, `pwn-new`, `listen` |
| [`setup/methodology/`](setup/methodology) | runbooks (RU) per category: web, pwn, rev, crypto, forensics, network, osint, misc |
| [`setup/ai-setup.sh`](setup/ai-setup.md) | OpenCode + REA (Ghidra/JADX) AI RE workstation |
| [`CTF_CHEATSHEET.md`](CTF_CHEATSHEET.md) | copy-paste command cheatsheet per category (RU) |

## 60-second start

```bash
./setup/install.sh -y            # pinned binaries -> ~/.local/bin
./setup/install.sh --check       # what Kali already has / what is missing
./setup/install.sh --with-wordlists

ctf-init web-login && cd web-login
enum-web http://10.10.10.10
enum-net 10.10.10.10 --udp
```

Offline CTF box:

```bash
./setup/bundle.sh --with-wordlists        # on a networked machine
# copy setup/dist/ctf-bundle-*.tar.zst over, unpack, then:
./install.sh --offline . --with-wordlists
```

## How to work a challenge

1. `ctf-init <name>` — one folder per task (`files/ loot/ scripts/ notes.md`).
   Live notes go on the team's Notion page for the challenge; `notes.md` is the
   offline buffer.
2. Read `setup/methodology/00-start.md` (first 10 minutes checklist).
3. Triage with the matching `enum-*` script; it saves raw output + a summary
   under `loot/` automatically.
4. Follow the category runbook in `setup/methodology/` and the commands in
   `CTF_CHEATSHEET.md`.
5. Keep the solve script in `scripts/` and the chain on the challenge's page in
   the shared Notion space — the write-up writes itself.

## Principles

- **Binaries only:** no `apt` from these scripts; Kali tools are detected and
  reported, never silently changed.
- **Pinned + SHA256-verified:** see `setup/manifest.tsv`; versions do not drift
  mid-competition.
- **Nothing destructive:** no config overwrites, no secrets stored, temp
  workspaces cleaned up.
