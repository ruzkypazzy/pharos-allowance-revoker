---
name: pharos-allowance-revoker
description: Security-focused AI Agent skill for auditing and revoking ERC20 token approvals on Pharos blockchain. Check all approved spender allowances, identify risky approvals, and batch revoke unwanted permissions. Essential for wallet security and preventing unauthorized token drains.
author: ruzkypazzy
version: 1.0.0
network: pharos
tags: [security, erc20, approval, revoke, allowance, wallet, pharos, safety]
---

# Pharos Allowance Revoker

AI Agent skill for checking, auditing, and revoking ERC20 token approvals on Pharos blockchain. Protect your wallet from token drain attacks by managing spender allowances.

## Quick Actions

### Check All Approvals for an Address
```
Check all ERC20 token approvals for 0x742d35Cc6634C0532925a3b844Bc9e7595f0a5b1 on Pharos mainnet
```

### Revoke Specific Approval
```
Revoke the USDC approval for 0x1234...5678 spender from 0x742d35Cc6634C0532925a3b844Bc9e7595f0a5b1
```

### Batch Revoke All Approvals
```
Revoke all ERC20 approvals for 0x742d35Cc6634C0532925a3b844Bc9e7595f0a5b1, keeping only essential protocols
```

## Core Commands

### 1. Check All Token Approvals
```bash
# Get all approvals by iterating common tokens and checking allowanceTo events
cast logs --from-block 0 --to-block latest " AllowanceSet(address indexed owner, address indexed spender, uint256 value)" --address 0x<TOKEN_CONTRACT> --rpc-url $PHAROS_RPC
```

### 2. Check Specific Allowance
```bash
# Check how much USDC you've approved for a spender
cast call 0x<USDC_ADDRESS> "allowance(address owner, address spender)(uint256)" \
  0x<YOUR_ADDRESS> 0x<SPENDER_ADDRESS> \
  --rpc-url $PHAROS_RPC
```

### 3. Revoke Approval (Set to 0)
```bash
# Revoke by setting allowance to 0
cast send 0x<TOKEN_ADDRESS> "approve(address spender, uint256 amount)(bool)" \
  0x<SPENDER_ADDRESS> 0 \
  --private-key $PRIVATE_KEY \
  --rpc-url $PHAROS_RPC
```

## Common Tokens on Pharos (Update Contract Addresses)

| Token | Address | Symbol |
|-------|---------|--------|
| PROS | Update with actual | PROS |
| USDC | Update with actual | USDC |
| USDT | Update with actual | USDT |

## Security Alerts

The skill flags these risky patterns:
- **Unlimited approvals** (max uint256)
- **Approvals to unknown contracts**
- **Old approvals to deprecated protocols**
- **Large allowance values to trading bots**

## Usage Examples

### Example 1: Full Security Audit
```
Use the allowance revoker skill to:
1. Scan all ERC20 approvals for my wallet 0x742d35Cc6634C0532925a3b844Bc9e7595f0a5b1
2. Identify any approvals to contracts I no longer use
3. Show me the total value at risk if those contracts are compromised
4. Revoke all suspicious approvals
```

### Example 2: Before Using New Protocol
```
Check my current approvals before connecting to new DeFi protocol:
- Show all current approvals
- Flag any that are unlimited
- Let me decide which to revoke
```

### Example 3: Post-Security Check
```
Run a security check on my wallet 0x742d35Cc6634C0532925a3b844Bc9e7595f0a5b1 and revoke:
- Any USDC approvals older than 6 months
- Any approvals to known exploit contract addresses
- Any unlimited approvals
```

## Implementation

### Using AllowanceRevoker Contract

The `AllowanceRevoker` contract provides:
- `checkApprovals(address owner)` - Returns all active approvals
- `revoke(address token, address spender)` - Revokes single approval
- `revokeAll(address owner, address[] tokens)` - Batch revocation
- `isRisky(address owner)` - Checks for dangerous patterns

### Configuration
```bash
export PHAROS_RPC=https://rpc.pharos.xyz
export PHAROS_TESTNET_RPC=https://atlantic.dplabs-internal.com
export PRIVATE_KEY=<your_private_key>
```

## Supported Networks

| Network | Chain ID | RPC URL |
|---------|----------|---------|
| Pharos Pacific Mainnet | 1672 | https://rpc.pharos.xyz |
| Pharos Atlantic Testnet | 688689 | https://atlantic.dplabs-internal.com |

## Dependencies
- Foundry (cast, forge)
- curl (for API calls)
- Optional: Tenderly API for simulation

## Important Notes
- Always verify spender addresses before revoking
- Some approvals are intentional (liquidity pools, staking)
- Revoking may affect ongoing positions or subscriptions
- Test on testnet first before mainnet operations