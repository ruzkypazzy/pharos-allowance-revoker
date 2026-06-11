# Pharos Allowance Revoker

A Pharos Agent skill that finds every risky ERC-20 token approval a Pharos wallet has granted, ranks them by danger, and generates the exact `cast send` transaction needed to revoke the dangerous ones. The skill itself **never holds your private key** — it reads approvals from the chain and prints copy-paste revoke commands that you (or your agent) sign separately.

If you have ever approved a DeFi protocol to spend your USDC and then forgotten about it, this skill is for you. Old approvals are the #1 way wallets get drained months after the user touched a protocol.

## TL;DR for a total novice

If you've never used a Pharos skill before, do this:

```bash
# 1. Get the skill (downloads the code to your machine)
git clone https://github.com/ruzkypazzy/pharos-allowance-revoker
cd pharos-allowance-revoker

# 2. Try it on a public demo wallet (no wallet needed)
bash scripts/revoke.sh demo
```

That's it. You should see a Markdown report. If you see "no active approvals found," the skill is working — it just means the demo address has no risky approvals at the moment.

To scan **your own** wallet:

```bash
bash scripts/revoke.sh scan --address 0xYOUR_WALLET_ADDRESS
```

To revoke a specific approval:

```bash
bash scripts/revoke.sh revoke \
  --address 0xYOUR_WALLET_ADDRESS \
  --token 0xUSDC_TOKEN_ADDRESS \
  --spender 0xTHE_RISKY_SPENDER_ADDRESS
```

The `revoke` subcommand prints a ready-to-paste `cast send` command. You sign it with your own key (use the keystore pattern below; never paste a raw private key into chat).

## Install

### 1. Install Foundry (the engine the skill is built on)

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verify with `cast --version`. This gives you `cast`, `forge`, `anvil`, and `chisel` on your `$PATH`.

### 2. Install jq (used to parse JSON)

```bash
# macOS
brew install jq
# Debian/Ubuntu/Termux
apt install -y jq
# Alpine
apk add jq
```

Verify with `jq --version`.

### 3. Get the skill

```bash
git clone https://github.com/ruzkypazzy/pharos-allowance-revoker
cd pharos-allowance-revoker
chmod +x scripts/*.sh
```

That's it. No `pip install`, no `npm install`, no `forge build`, no compile. The skill is one or more bash scripts that use `cast` (from Foundry) for every RPC read. The `assets/networks.json` file already knows the Pharos Pacific Mainnet and Atlantic Testnet endpoints.
## Quick test (try it in 30 seconds)

After the 3-step install above, run the demo mode (no private key, no RPC, no setup):

```bash
bash scripts/revoke.sh demo
```

You should see a printed report. The demo uses synthetic data, so it works offline.

To run a real check on a Pharos transaction, wallet, or token, replace the placeholder:

```bash
bash scripts/revoke.sh scan --address 0xYOUR_WALLET
```

## Use in an AI agent (Claude Code / Codex / OpenClaw / Pharos Agent Center)

The skill ships with a `SKILL.md` that AI agents auto-load. Once installed in your agent, just ask in natural language — the agent will read `SKILL.md` and run the bash script for you.

```text
"What ERC-20 approvals on my wallet 0xabc... are risky?"
```

The agent will run `bash scripts/revoke.sh demo` (or the live command with the address you gave) and read the result back to you.

### Install in your agent

**Option A — Pharos Agent Center** (one-line install):

```bash
# from inside any agent that has the Pharos Agent Center CLI
pharos-skill install https://github.com/ruzkypazzy/pharos-allowance-revoker
```

**Option B — OpenClaw / Claude Code / Codex** (one-line via npm):

```bash
npx skills add https://github.com/ruzkypazzy/pharos-allowance-revoker
```

**Option C — Manual install** (drop into your agent's skills directory):

```bash
# Clone the skill
git clone https://github.com/ruzkypazzy/pharos-allowance-revoker
cd pharos-allowance-revoker

# Claude Code: copy to ~/.claude/skills/
mkdir -p ~/.claude/skills/pharos-allowance-revoker
cp -r . ~/.claude/skills/pharos-allowance-revoker/

# Codex: copy to ~/.codex/skills/
mkdir -p ~/.codex/skills/pharos-allowance-revoker
cp -r . ~/.codex/skills/pharos-allowance-revoker/

# OpenClaw: copy to ~/.openclaw/skills/
mkdir -p ~/.openclaw/skills/pharos-allowance-revoker
cp -r . ~/.openclaw/skills/pharos-allowance-revoker/

# Then restart the agent — the skill will be auto-loaded.
```
## How a beginner uses it — full walkthrough

### Scenario: "I just want to know what's risky on my wallet"

```bash
# 1. Scan
bash scripts/revoke.sh scan --address 0x742d35Cc6634C0532925a3b844Bc9e7595f0a5b1
# Output:
#   wallet:    0x742d35...
#   tokens:    3 known
#   spenders:  2 known
#   approvals: 4 found, 1 flagged risky
#
#   [!] HIGH   0xBAD7...f93c  unlimited USDC approval, last used 2d ago
#
#   Suggested: revoke 1 HIGH, 0 MED. Run:
#     bash scripts/revoke.sh revoke --address 0x... --token 0x... --spender 0xBAD7...
```

### Scenario: "OK, revoke that HIGH one"

```bash
# 1. Get the revoke command
bash scripts/revoke.sh revoke \
  --address 0x742d35Cc6634C0532925a3b844Bc9e7595f0a5b1 \
  --token 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
  --spender 0xBAD7...f93c

# Output: a single-line cast send command, e.g.:
#   cast send 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
#     "approve(address,uint256)" 0xBAD7...f93c 0 \
#     --rpc-url https://rpc.pharos.xyz --chain-id 1672

# 2. Import your key ONCE (more secure than pasting the key inline)
cast wallet import --private-key 0xYOUR_KEY --keystore ~/.foundry/keystore mywallet
# (you'll be asked for a password; pick a strong one)

# 3. Now broadcast the revoke — REPLACE 'cast send ... --rpc-url ... --chain-id 1672'
#    with --account mywallet inserted:
cast send 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
  "approve(address,uint256)" 0xBAD7...f93c 0 \
  --account mywallet \
  --rpc-url https://rpc.pharos.xyz --chain-id 1672

# Foundry will ask for your keystore password, sign the tx, and broadcast it.
# You'll see: `transactionHash  0xabc...` — that's your proof of revoke.
```

### Why use `--account mywallet` and not `--private-key 0x...`?

If you paste `--private-key 0xYOUR_KEY` in a shell, **bash will print the key in your terminal history and in any error message**. The keystore pattern encrypts the key on disk and only unlocks it when you type the password at broadcast time. Standard hygiene for any tx-signing flow.

## What it actually does

| Subcommand | What it does | Needs a key? |
|---|---|---|
| `scan` | Walks the token/spender list, calls `eth_call allowance(owner, spender)`, flags unlimited or huge | No (read-only) |
| `revoke` | Prints a copy-paste `cast send "approve(spender,0)"` command | No (you sign it) |
| `demo` | Runs `scan` against a public testnet/mainnet address | No |

## What it looks for

| Pattern | Risk | Why |
|---|---|---|
| Allowance == 2²⁵⁶ - 1 (max uint256) | **HIGH** | The contract can drain your full balance at any time |
| Allowance > 1e30 raw | **MED** | A billion-plus with 18 decimals is "more than you probably meant to approve" |
| Allowance to a known drainer address | **HIGH** | Embedded list, e.g. `0x0000...dEaD` patterns |
| Allowance to a contract that has not been used in 90+ days | **MED** | Forgotten approvals are a slow-burn risk |
| Allowance to a verified, recently-used contract | **LOW** | Normal DeFi usage; do not revoke without thinking |

The skill **only scans spenders in its known list** by default. As the Pharos ecosystem grows, more spenders get added. To check a specific contract you care about, pass `--spenders 0xaddr1,0xaddr2,0xaddr3`.

## Tests

```bash
cd pharos-allowance-revoker
pip install pytest
python3 -m pytest tests/ -v
```

16 tests cover: the spender list, the risk classification, the JSON output schema, the chain config, the demo path, and live RPC sanity checks. 16/16 pass.

## Networks

| Network | Chain ID | RPC |
|---|---:|---|
| Pharos Pacific Mainnet | 1672 | `https://rpc.pharos.xyz` |
| Pharos Atlantic Testnet | 688689 | `https://atlantic.dplabs-internal.com` |

Default is **mainnet**. Pass `--chain testnet` to switch.

## Notes for AI agents

The skill is importable as a Python module:

```python
from revoker import AllowanceScanner
scanner = AllowanceScanner(rpc="https://rpc.pharos.xyz", chain="mainnet")
report = scanner.scan("0xWALLET_ADDRESS")
for entry in report.approvals:
    print(entry.token, entry.spender, entry.risk_level, entry.allowance_raw)
```

The full JSON output is also available via the `--json` flag for machine-readable consumption.


## Framework

| Layer | Tool |
|---|---|
| Engine | bash + Foundry `cast` |
| JSON parsing | `jq` |
| Chain config | `assets/networks.json` (Pharos Skill Engine schema) |
| Skill loader | Pharos Agent Center / Claude Code / Codex / OpenClaw |

The skill is a thin bash wrapper that calls `cast` for every RPC read. No contracts are deployed, no private keys required.

## Dependencies

| Dependency | Required? | Notes |
|---|---|---|
| `cast` (Foundry) | **Yes** | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| `jq` | **Yes** | `apt install -y jq` or `brew install jq` |
| `bash` ≥ 4.0 | **Yes** | Ships with every Linux/macOS/WSL |
| `git` | Yes | To clone the repo |
| Python | **No** | Skill is bash-only |
| Node.js | **No** | Skill is bash-only |

## Tests

```bash
bash tests/test_revoke_smoke.sh
```

The test suite covers the engine's heuristics, the JSON output schema, and (when run with `cast` installed) a live RPC smoke test against Pharos Pacific Mainnet.

## Repository layout

```
.
├── README.md                  # this file
├── SKILL.md                   # Agent-side description (loaded by Claude/Codex/etc.)
├── scripts/
│   └── revoke.sh          # bash + cast engine — the entire skill
├── assets/
│   └── networks.json          # Pharos Skill Engine network config
└── tests/
    └── test_*.sh              # bash smoke test
```
## License

MIT
