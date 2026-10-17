# fast_ai_setup

One-command installer that turns a fresh Kali Linux box into an AI reverse-engineering
workstation: **OpenCode** + **REA** ([morluto/rea](https://github.com/morluto/rea)),
the MCP server that gives your agent binary/app/APK analysis tools.

## Usage

```bash
bash ai-setup.sh                 # interactive; offers the optional engines
bash ai-setup.sh --yes           # unattended core install (minimal)
bash ai-setup.sh --with-ghidra --with-jadx   # add the analysis engines
```

Safe to re-run: finished steps are detected and skipped.

## What it installs

| Step | Source | Notes |
| --- | --- | --- |
| Base packages | Kali apt | `procps` (REA needs a procps `ps`), curl, git, unzip |
| Node.js | Kali apt, else NodeSource 24.x | REA needs 22.19+ / 24.11+ / 26+ |
| OpenCode | `https://opencode.ai/v2/install` | standalone binary in `~/.local/bin` |
| REA | npm `rea-agents` | global install, user-owned (`~/.local`) so `rea update` needs no sudo |
| REA ⇄ OpenCode | `rea setup --client opencode` | registers the MCP server + skill, backs up existing config |
| Ghidra 12.1.x + JDK 21 | official GitHub release + apt | optional (`--with-ghidra`), for native binaries |
| JADX | Kali apt | optional (`--with-jadx`), for Android APKs |

## Flags

- `-y, --yes` — non-interactive; extras then require an explicit `--with-*`.
- `--with-ghidra` / `--with-jadx` — install the optional analysis engines.
- `--ghidra-series 12.1` — Ghidra release series to fetch (REA accepts 12.1.x).
- `--skip-apt` — skip all apt steps (dependencies already installed).

## What it does not do

- No AI provider logins or API keys — run `opencode` and use `/connect` yourself.
- No config overwrites: REA backs up existing agent configuration before editing.
- Nothing is left behind in `/tmp` (the temp workspace is cleaned up on exit).

## After install

```bash
opencode          # start the agent, then /connect your provider
rea doctor        # verify REA and any installed engines
```

Updates later: `opencode update` and `rea update`.

## Uninstall

`ai-setup.sh` writes an install record to
`~/.local/state/ai-setup/state.env` so removal is exact (including things that
cannot be re-derived later, like your previous npm prefix).

```bash
bash ai-uninstall.sh              # dry run: prints the plan, changes nothing
bash ai-uninstall.sh --yes        # apply it
bash ai-uninstall.sh --all --yes  # also purge tool config/state and system packages
bash ai-uninstall.sh --keep-ghidra --yes
```

`ai-uninstall.sh` is a **dry run by default**; nothing happens without `--yes`.

| Flag | Effect |
| --- | --- |
| `--yes` | apply the removals (required to change anything) |
| `--purge-data` | also delete OpenCode config/data/cache, `~/.rea` and leftover skills |
| `--purge-packages` | also remove `jadx`, `openjdk-21-jdk`, and Node.js + the NodeSource repo when ai-setup.sh installed it that way |
| `--all` | shorthand for `--purge-data --purge-packages` |
| `--keep-rc` | leave the shell rc lines alone |
| `--keep-ghidra` | keep the downloaded Ghidra directory |

Removed by default: the OpenCode binary, the `rea-agents` npm package, REA's agent
registration + skill (via `rea uninstall`), the downloaded Ghidra directory, the
shell rc lines, and the npm prefix change.

Left alone by default: base apt packages (`procps`, `curl`, … — removing `procps`
breaks Kali), `nodejs`/`npm` installed from the Kali repo, and any OpenCode or
REA that was **already present before** `ai-setup.sh` ran (the install record tracks
this, so a pre-existing install is never deleted).
