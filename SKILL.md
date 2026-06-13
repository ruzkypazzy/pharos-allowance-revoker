---
name: pharos-allowance-revoker
description: Security-focused AI agent skill for auditing and revoking risky ERC-20 token approvals on Pharos blockchain. Reads live allowances via cast (Foundry), flags UNLIMITED and LARGE approvals, and prints copy-paste cast-send revoke commands. Non-custodial — never holds a private key.
author: ruzkypazzy
version: 2.0.0
network: pharos
tags: [security, erc20, approval, revoke, allowance, wallet, pharos, foundry, bash, non-custodial]
---

# Pharos Allowance Revoker

A bash + cast (Foundry) skill that scans a Pharos wallet for risky ERC-20 token approvals and prints the exact `cast send` command needed to revoke each one. The skill is **non-custodial**: it reads allowances via `eth_call` and prints commands — it never holds a private key.

## What it does

For a given wallet address, the skill:

1. Reads each known token's `symbol()` and `decimals()` via `cast call`.
2. Walks every (token, spender) pair in the configured lists.
3. Queries the live `allowance(owner, spender)` via `cast call`.
4. Flags risky approvals:
   - **UNLIMITED** — value equals `2^256-1` (max uint256)
   - **LARGE** — value greater than `1e30` (configurable threshold)
5. Prints a `cast send ... approve(spender, 0)` command for each risky approval.

## Quick Actions

### Scan a wallet for risky approvals
```
Audit ERC-20 approvals for 0xYOUR_WALLET on Pharos mainnet
```

### Revoke a specific approval
```
Print the revocation command for USDC approval to 0xSPENDER from 0xYOUR_WALLET
```

### Scan with custom token and spender lists
```
Scan 0xYOUR_WALLET for approvals against tokens 0xT1,0xT2 and spenders 0xSP1,0xSP2 on Pharos testnet
```

## Invocation

```bash
# Default scan on mainnet
bash scripts/revoke.sh scan --address 0xWALLET --chain mainnet

# Demo mode (uses a known public address)
bash scripts/revoke.sh demo

# Print a revocation command (no broadcast)
bash scripts/revoke.sh revoke \
  --address 0xWALLET \
  --token 0xTOKEN \
  --spender 0xSPENDER
```

## Flags

| Flag | Description |
|---|---|
| `scan` | Scan a wallet for active approvals (default mode) |
| `revoke` | Print a revocation command for a specific (token, spender) pair |
| `demo` | Run a scan on a known public address (no args needed) |
| `--address 0xWALLET` | The wallet address to audit (required for `scan` and `revoke`) |
| `--chain mainnet \| testnet` | Which Pharos chain to read from (default: mainnet) |
| `--tokens 0xT1,0xT2` | Comma-separated list of token addresses to scan |
| `--spenders 0xSP1,0xSP2` | Comma-separated list of spender addresses to check |
| `--token 0xTOKEN` | For `revoke`: the token contract holding the approval |
| `--spender 0xSPENDER` | For `revoke`: the spender address whose approval you want to revoke |
| `--json` | Output as JSON (for agent consumption) |

## Networks

| Network | Chain ID | RPC URL |
|---|---:|---|
| mainnet (Pacific Ocean) | 1672 | `https://rpc.pharos.xyz` |
| atlantic-testnet | 688689 | `https://atlantic.dplabs-internal.com` |

Chain config is read from `assets/networks.json` at startup. Edit that file to add private RPC endpoints.

## Dependencies

- **Foundry** (gives you `cast`, `forge`, `anvil`) — install with `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- **bash 4+** — preinstalled on macOS, Ubuntu 20+, most Linux
- **jq** — install with `brew install jq` / `apt install jq` / `apk add jq`

## Security model

The skill is **non-custodial by design**:

- The script never imports, reads, or stores a private key.
- It reads allowances via `eth_call` (read-only RPC) — it cannot move funds.
- The `revoke` subcommand prints a `cast send` command; the user signs and broadcasts that command in their own secure environment with their own key.
- The skill does not log to disk. It does not phone home. The only network call is to the user-configured RPC URL.

**Never** paste a raw private key into an AI agent's chat window. Use the Foundry keystore pattern:

```bash
cast wallet import --keystore-dir ~/.foundry/keystore --private-key $YOUR_KEY
# Then for each revoke command printed by the skill, replace --private-key with --keystore
cast send $TOKEN "approve(address,uint256)" $SPENDER 0 \
  --rpc-url $RPC_URL --keystore $KEYSTORE_NAME
```

## Error handling

- Missing cast → "Error: 'cast' not found. Install Foundry..."
- Invalid address format → "Error: --address must be 0x-prefixed 20-byte hex"
- RPC unreachable → script prints the cast error and exits non-zero
- No known tokens/spenders configured → prints a clear "no X configured" message with a hint to pass `--tokens` / `--spenders`

## Repository layout

```
pharos-allowance-revoker/
├── SKILL.md              # This file
├── README.md             # Full documentation
├── foundry.toml          # Minimal config so cast can find the project root
├── LICENSE               # MIT
├── assets/
│   └── networks.json     # mainnet + testnet chain config
├── scripts/
│   └── revoke.sh         # The single bash script that does the work
└── tests/
    └── test_revoke_smoke.sh   # Offline smoke test
```
