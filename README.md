# Pharos Allowance Revoker

**Security-focused AI Agent skill for auditing and revoking ERC20 token approvals on Pharos blockchain.**

![Pharos Network](https://img.shields.io/badge/Pharos-Network-4F46E5)
![Foundry](https://img.shields.io/badge/Built%20with-Foundry-F06522)
![License](https://img.shields.io/badge/License-MIT-green)

## Overview

Pharos Allowance Revoker is an AI Agent skill that helps you:
- **Check** all ERC20 token approvals for any wallet
- **Audit** approval history and identify risky patterns
- **Revoke** unwanted or dangerous spender permissions
- **Protect** your wallet from unauthorized token drains

## Why This Matters

Every time you approve a DeFi protocol to spend your tokens, you're granting access to your funds. Unused or unlimited approvals are security risks.

### Common Risks
- **Unlimited approvals** - Protocol can drain your entire balance
- **Forgotten approvals** - Old protocols you no longer use
- **Compromised protocols** - Hacked protocols with your approval
- **Unknown spenders** - Malicious contracts disguised as legitimate

## Features

### 1. Approval Scanner
- Scan all ERC20 approvals for any wallet address
- Filter by token, spender, amount, or age
- Identify unlimited approvals (max uint256)

### 2. Risk Assessment
- Flag high-value allowances
- Detect unlimited approvals automatically
- Score risk levels for each approval

### 3. Batch Revocation
- Revoke multiple approvals in one transaction
- Keep essential approvals (whitelisted)
- One-click "revoke all unknown"

### 4. Onchain History
- All revocation transactions recorded on Pharos
- Full audit trail for security reviews
- Transparent and verifiable

## Installation

### Prerequisites
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify installation
cast --version
```

### Clone the Repository
```bash
git clone https://github.com/ruzkypazzy/pharos-allowance-revoker.git
cd pharos-allowance-revoker
```

### Build Contract
```bash
forge build
```

## Usage

### Quick Security Check

```bash
# Check all USDC approvals for your wallet
cast call 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
  "allowance(address,address)(uint256)" \
  YOUR_WALLET_ADDRESS KNOWN_SPENDER \
  --rpc-url https://rpc.pharos.xyz
```

### Revoke Approval

```bash
# Revoke USDC approval for a spender
cast send 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
  "approve(address,uint256)(bool)" \
  SPENDER_ADDRESS 0 \
  --private-key YOUR_PRIVATE_KEY \
  --rpc-url https://rpc.pharos.xyz
```

### Check Multiple Tokens

```bash
# Script to check approvals for multiple tokens
for TOKEN in USDC USDT DAI; do
  echo "Checking $TOKEN approvals..."
  cast call $TOKEN_ADDRESS "allowance()(uint256)" \
    --rpc-url https://rpc.pharos.xyz
done
```

## AI Agent Commands

### Example 1: Full Security Audit
```
Use pharos-allowance-revoker to:
1. Scan my wallet 0x742d35Cc6634C0532925a3b844Bc9e7595f0a5b1 for all ERC20 approvals
2. Flag any approvals to unknown contracts
3. Show me the total value at risk
4. Revoke all high-risk approvals after confirmation
```

### Example 2: Before Using New Protocol
```
Check my current approvals and flag any unlimited ones before I connect to new DeFi protocol.
```

### Example 3: Regular Security Check
```
Run a weekly security check on my wallet. Revoke any approvals older than 90 days.
```

## Configuration

### Environment Variables
```bash
export PHAROS_RPC=https://rpc.pharos.xyz
export PHAROS_TESTNET_RPC=https://atlantic.dplabs-internal.com
export PRIVATE_KEY=your_private_key
```

### Using .env file
Create a `.env` file:
```
PHAROS_RPC=https://rpc.pharos.xyz
PHAROS_TESTNET_RPC=https://atlantic.dplabs-internal.com
PRIVATE_KEY=your_private_key
```

## Supported Networks

| Network | Chain ID | RPC URL |
|---------|----------|---------|
| Pharos Pacific Mainnet | 1672 | https://rpc.pharos.xyz |
| Pharos Atlantic Testnet | 688689 | https://atlantic.dplabs-internal.com |

## Smart Contract

The `AllowanceRevoker` contract provides:
- `checkApprovals(address owner)` - Get all approvals for a wallet
- `checkRiskyApprovals(address owner)` - Identify dangerous patterns
- `revoke(address token, address spender)` - Revoke single approval
- `revokeBatch(address[] tokens, address[] spenders)` - Batch revocation

## Security Best Practices

1. **Always verify spender addresses** before revoking
2. **Test on testnet first** before mainnet operations
3. **Keep essential approvals** (liquidity pools, staking)
4. **Review approvals regularly** - monthly recommended
5. **Use limited approvals** when possible (exact amounts)

## Demo

Live demo available at: https://xoyo9d43sete.space.minimax.io

## License

MIT License - See LICENSE file

## Author

ruzkypazzy

## Contributing

Contributions welcome! Please submit pull requests or open issues for:
- New token support
- Additional security checks
- Integration improvements

## Related Skills

- [pharos-batch-transfer](https://github.com/ruzkypazzy) - Batch token transfers
- [pharos-token-creator](https://github.com/ruzkypazzy) - Deploy ERC20 tokens
- [pharos-skill-engine](https://github.com/PharosNetwork/pharos-skill-engine) - Pharos Skill Engine

---

**Protect your wallet. Revoke risky approvals. Stay safe on Pharos.**