# Pharos Allowance Revoker

> Audit a Pharos wallet for risky ERC-20 approvals and print the exact `cast send` command to revoke them — without ever touching your private key.

[![foundry](https://img.shields.io/badge/built%20with-Foundry-orange)]()
[![bash](https://img.shields.io/badge/script-bash-blue)]()
[![license](https://img.shields.io/badge/license-MIT-green)]()
[![pharos](https://img.shields.io/badge/network-Pharos-blueviolet)]()
[![ai-agent](https://img.shields.io/badge/callable%20by-AI%20agent-purple)]()

## What it is

This is a **skill built for the Pharos network** — a self-contained, deterministic bash script that runs on top of the [Pharos](https://pharos.network) EVM chains. It is **not** an AI agent itself, and not a chatbot. It is a single bash script that:

- takes input from the caller via CLI flags,
- reads live on-chain data from Pharos via `cast` (Foundry),
- runs its own risk scoring in pure bash + `jq`,
- prints a structured report (text or JSON) to stdout.

Scans a Pharos wallet for ERC-20 token approvals against a list of known tokens and spenders, flags risky ones (UNLIMITED = 2^256-1, LARGE = > 1e30), and prints a copy-paste `cast send` revoke command for each. Reads live on-chain data via `cast` (Foundry).

## Use it from an AI agent

This skill is designed to be **called by an AI agent** (a Claude Code / Codex / Cursor agent, the Pharos Agent Center, or any custom LLM agent). The agent reads `SKILL.md` to discover the skill's flags, fills them in based on the user's request, and runs the bash script in its sandbox. The agent's job is just to translate "audit this wallet for risky approvals" into `bash scripts/revoke.sh scan --address 0x...`.

The skill is **non-custodial**: it never sees, stores, or transmits a private key. It reads allowances via `cast call` and prints a `cast send ... approve(spender, 0)` command that the user (or the agent) signs separately with their own key. The agent should never paste a raw private key into a chat — use the keystore pattern (`cast wallet import --keystore-dir ~/.foundry/keystore --private-key $YOUR_KEY` then `cast send ... --keystore <name>`).

Typical agent-side flow:

```text
User -> Agent: "Audit wallet 0xabc... for risky ERC-20 approvals on Pharos"
Agent -> looks up SKILL.md for Pharos Allowance Revoker
Agent -> picks the right flag combo: --address 0xabc... --chain mainnet
Agent -> runs: bash scripts/revoke.sh scan --address 0xabc... --chain mainnet
Agent -> reads the output, presents the risky approvals + revoke commands to the user
User -> signs each revoke command with their own keystore, broadcasts
```

The script prints structured output to stdout and human-readable progress to stderr, so the agent can parse the stdout cleanly (with `jq`) without being polluted by progress messages.

## Install

You need three things: **Foundry** (for `cast`), **jq** (for JSON pretty-printing), and **git** (to clone the repo).

```bash
# 1. Install Foundry (gives you cast, forge, anvil, chisel)
curl -L https://foundry.paradigm.xyz | bash
foundryup
# Reload your shell so the new commands are on PATH:
exec $SHELL
cast --version   # should print 1.x or higher

# 2. Install jq (required for JSON output)
# macOS:   brew install jq
# Ubuntu:  sudo apt-get install -y jq
# Alpine:  apk add jq
jq --version

# 3. Clone this repo
git clone https://github.com/ruzkypazzy/pharos-allowance-revoker.git
cd pharos-allowance-revoker
chmod +x scripts/*.sh tests/*.sh
```

## Quick test (30 seconds, no API keys needed)

```bash
bash scripts/revoke.sh demo
```

The first time you run this, the script may take a few seconds to fetch token metadata over RPC. Subsequent runs are cached by the RPC provider.

## Usage

```bash
# Scan a wallet for risky ERC-20 approvals on mainnet
bash scripts/revoke.sh scan --address 0xWALLET --chain mainnet

# Scan with custom token and spender lists
bash scripts/revoke.sh scan --address 0xWALLET --tokens 0xTOKEN1,0xTOKEN2 --spenders 0xSP1,0xSP2

# Print a revocation command for one specific (token, spender) pair
bash scripts/revoke.sh revoke --address 0xWALLET --token 0xTOKEN --spender 0xSPENDER

# Run the demo against a known public address
bash scripts/revoke.sh demo

# Output as JSON (for agent consumption)
bash scripts/revoke.sh scan --address 0xWALLET --json
```

### All flags

```
scan|revoke|demo --address 0xWALLET --chain mainnet|testnet --tokens 0xT1,0xT2 --spenders 0xSP1,0xSP2 --json
```

| Flag | Description |
|---|---|
| `scan` | Scan a wallet for active approvals (default mode) |
| `revoke` | Print a revocation command for a specific (token, spender) pair |
| `demo` | Run a scan on a known public address (no args needed) |
| `--address 0xWALLET` | The wallet address to audit (required for `scan` and `revoke`) |
| `--chain mainnet \| testnet` | Which Pharos chain to read from (default: mainnet) |
| `--tokens 0xT1,0xT2` | Comma-separated list of token addresses to scan (overrides default known-tokens list) |
| `--spenders 0xSP1,0xSP2` | Comma-separated list of spender addresses to check (overrides default known-spenders list) |
| `--token 0xTOKEN` | For `revoke`: the token contract holding the approval |
| `--spender 0xSPENDER` | For `revoke`: the spender address whose approval you want to revoke |
| `--json` | Output as JSON (for agent consumption) |
| `-h`, `--help` | Show the help text |

## How it works

For every (token, spender) pair in the configured lists, the script:

1. Reads the token's `symbol()` and `decimals()` via `cast call ... symbol()(string)` and `cast call ... decimals()(uint8)`.
2. Reads the live `allowance(owner, spender)` via `cast call ... allowance(address,address)(uint256)`.
3. Skips zero allowances (no active approval).
4. Flags any allowance that equals `2^256-1` as **UNLIMITED** and any value above `1e30` as **LARGE**.
5. Rolls the flags into a 0-100 risk score (80 for UNLIMITED, 30 for LARGE, capped at 100).
6. Prints a human-readable row, plus a ready-to-paste `cast send ... approve(spender, 0)` command for every risky approval.

The risk score is heuristic — treat any non-zero score as "needs a human review", not as a verdict.

## Networks

The skill is built to run against the Pharos EVM chains. The chain config is stored in `assets/networks.json` and read at startup — no hardcoded URLs in the script.

| Network | Chain ID | RPC URL | Default |
|---|---:|---|:---:|
| mainnet (Pacific Ocean) | 1672 | `https://rpc.pharos.xyz` | ✓ |
| atlantic-testnet | 688689 | `https://atlantic.dplabs-internal.com` |  |

The script defaults to mainnet. Pass `--chain testnet` to use the testnet instead. You can also override the RPC URL directly with `--rpc-url https://your-rpc.example.com` (supported when the script's own `--rpc-url` is added in a future version — for now, edit `assets/networks.json` to point at a private node).

## Set it up in an AI agent

Three install paths for any AI agent that wants to call this skill.

### Path A — Pharos Agent Center (for the official Pharos LLM agent)

The Pharos Agent Center is the official agent runtime for the Pharos network. It reads `SKILL.md` from any skill repo to discover capabilities, dependencies, and required flags.

1. **Copy the skill into the Agent Center's skills directory:**
   ```bash
   # After cloning this repo:
   cp -r scripts assets SKILL.md README.md foundry.toml LICENSE \
     ~/.pharos/agent-center/skills/pharos-allowance-revoker/
   ```

2. **Reload the Agent Center's skill registry:**
   ```bash
   pharos-agent reload-skills
   # or restart the Agent Center daemon
   ```

3. **Invoke from the agent's chat UI** (or via the Agent Center's CLI / API):
   ```text
   User: "Audit wallet 0xabc... for risky ERC-20 approvals on Pharos"
   Agent Center: loads Pharos Allowance Revoker, runs:
     bash ~/.pharos/agent-center/skills/pharos-allowance-revoker/scripts/revoke.sh --address 0xWALLET --chain mainnet
   ```

### Path B — `npx skills add` (for Claude Code, Cursor, Codex, generic MCP agents)

```bash
npx skills add https://github.com/ruzkypazzy/pharos-allowance-revoker --skill pharos-allowance-revoker
```

The agent's `skills` plugin will discover the SKILL.md, surface the skill in its tool list, and let the LLM pick the right flags when the user asks.

### Path C — Manual copy (any agent that reads `~/.claude/skills/`)

```bash
mkdir -p ~/.claude/skills/pharos-allowance-revoker
cp -r scripts assets SKILL.md README.md foundry.toml LICENSE ~/.claude/skills/pharos-allowance-revoker/
```

Restart the agent. It will pick up the new skill on next tool discovery.

### Path D — Direct invocation (shell agents, cron jobs, CI pipelines)

```bash
bash scripts/revoke.sh demo
```

No agent needed — just shell + Foundry.

### What the agent says to invoke this skill

| Caller says | Script invocation |
|---|---|
| Audit wallet `0xabc...` for risky ERC-20 approvals on Pharos | `bash scripts/revoke.sh scan --address 0xabc... --chain mainnet` |
| Print the revocation command for USDC against spender `0xdef...` | `bash scripts/revoke.sh revoke --address 0xabc... --token 0xc879c018db60520f4355c26ed1a6d572cdac1815 --spender 0xdef...` |
| Run the allowance revoker demo | `bash scripts/revoke.sh demo` |
| "Run the demo" | `bash scripts/revoke.sh demo` |

The agent should read the script's `--help` output to discover all available flags, then build the right command line for the user's request.

## Security model

This skill is **non-custodial by design**:

- The script never imports, reads, or stores a private key.
- It reads allowances via `eth_call` (read-only RPC) — it cannot move funds.
- The `revoke` subcommand prints a `cast send` command; the user runs that command in their own secure environment with their own key (ideally via a Foundry keystore, not a raw key in shell history).
- The skill does not log to disk. It does not phone home. The only network call is to the user-configured RPC URL.

If you (or your agent) want to broadcast a revocation:

```bash
# Best: import your key into a Foundry keystore once, then sign per-call
cast wallet import --keystore-dir ~/.foundry/keystore --private-key $YOUR_KEY
# Then for each revoke command printed by the skill, replace --private-key with --keystore
cast send $TOKEN "approve(address,uint256)" $SPENDER 0 \
  --rpc-url $RPC_URL --keystore $KEYSTORE_NAME
```

**Never** paste a raw private key into an AI agent's chat window. Use the keystore pattern.

## Framework

| Layer | Tech | Purpose |
|---|---|---|
| Engine | **bash 4+** | Script host (single file per skill) |
| RPC client | **Foundry / cast** | All chain reads — `cast call` for `symbol()`, `decimals()`, `allowance()` |
| Chain config | **JSON** (`assets/networks.json`) | Network endpoints + chain IDs |
| Data format | **JSON** | Cast's native output; `jq` used for pretty-printing and JSON building |
| Runtime | Any POSIX shell, Foundry 1.0+ | Tested on Linux + macOS |

## Dependencies

**Required:**
- [Foundry](https://getfoundry.sh) (gives you `cast`, `forge`, `anvil`)
- `bash` 4+ (preinstalled on macOS, Ubuntu 20+, most Linux)
- `jq` (for `--json` output and pretty-printing)

**Optional:**
- `git` — only required if you're cloning the repo (you already have it)

## Tests

Each repo ships with a bash smoke test that verifies:
1. `--help` works (no cast required)
2. The demo mode works (no cast required for the early-exit path)
3. The help text is human-readable
4. The script rejects invalid addresses (when cast is available)
5. (When cast is installed) The script correctly returns 0 approvals for a clean wallet

```bash
bash tests/test_revoke_smoke.sh
```

The test runs offline — no RPC calls, no API keys. It exercises the help text, arg parser, and the no-cast / no-spenders early-exit paths.

## Repository layout

```
pharos-allowance-revoker/
├── SKILL.md              # Skill contract (Capability Index, Error Handling, Security Reminders)
├── README.md             # This file
├── foundry.toml          # Minimal config so cast can find the project root
├── LICENSE               # MIT
├── assets/
│   └── networks.json     # mainnet + testnet chain config (read by every script)
├── scripts/
│   └── revoke.sh          # The single bash script that does the work
└── tests/
    └── test_revoke_smoke.sh   # Offline smoke test (no cast required)
```

## License

MIT — see `LICENSE`.

---
