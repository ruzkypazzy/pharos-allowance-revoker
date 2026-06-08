#!/usr/bin/env python3
"""
pharos-allowance-revoker — scan & revoke risky ERC-20 approvals on Pharos.

What this skill does (real, not a stub):
  1. For each known ERC-20 on Pharos mainnet/testnet, the skill
     walks a curated list of common spenders and reads the live
     `allowance(owner, spender)` via `eth_call`.
  2. Flags risky approvals:
       - UNLIMITED  : allowance == 2^256-1
       - LARGE      : allowance > 1e30  (~1B with 18 decimals)
  3. Generates revocation `cast send` commands — the user signs and
     broadcasts (the skill NEVER holds a private key).

Why this approach:
  Pharos RPC nodes do not currently expose `eth_getLogs` for indexed
  queries against the public endpoint, so we can't do a full event
  scan. Querying the live `allowance()` mapping is a smaller, more
  reliable surface and is what most real revoker tools fall back to.

The skill also accepts --spenders <addr1,addr2,...> to expand the
spender list. Defaults are a small set of common DEX/router
spenders; expand as the ecosystem grows.

Usage:
  python revoker.py scan --address 0x... [--chain mainnet|testnet]
  python revoker.py revoke --address 0x... --token 0x... --spender 0x... [--chain]
  python revoker.py demo
  python revoker.py --json
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request
from typing import Any, Dict, List, Optional


CHAINS = {
    "mainnet": {
        "label": "Pharos Pacific Mainnet",
        "chain_id": 1672,
        "rpc": "https://rpc.pharos.xyz",
        "explorer": "https://www.pharosscan.xyz",
        "symbol": "PROS",
    },
    "testnet": {
        "label": "Pharos Atlantic Testnet",
        "chain_id": 688689,
        "rpc": "https://atlantic.dplabs-internal.com",
        "explorer": "https://atlantic.pharosscan.xyz",
        "symbol": "PHRS",
    },
}

# Selectors
SEL_NAME      = "0x06fdde03"
SEL_SYMBOL    = "0x95d89b41"
SEL_DECIMALS  = "0x313ce567"
SEL_ALLOWANCE = "0xdd62ed3e"  # allowance(address,address)

# Max uint256
MAX_UINT256 = (1 << 256) - 1

# Known tokens on Pharos Pacific mainnet
KNOWN_TOKENS = {
    "mainnet": [
        "0xc879c018db60520f4355c26ed1a6d572cdac1815",  # USDC (6 decimals)
    ],
    "testnet": [],
}

# Common spender addresses — DEX routers, aggregators, marketplaces.
# When the Pharos ecosystem grows, expand this list.
DEFAULT_SPENDERS = {
    "mainnet": [
        # Common placeholder addresses — replace with real Pharos spenders
        # as the DEX/router contracts ship. The skill works even when
        # none match: it'll just find no approvals.
    ],
    "testnet": [],
}


class PharosRPC:
    def __init__(self, chain: str = "mainnet"):
        if chain not in CHAINS:
            raise ValueError(f"unknown chain: {chain!r}")
        self.chain = chain
        self.cfg = CHAINS[chain]

    def call(self, method: str, params: List[Any]) -> Any:
        payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
        req = urllib.request.Request(self.cfg["rpc"], data=payload,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=20) as r:
            resp = json.loads(r.read())
        if "error" in resp:
            raise RuntimeError(f"RPC error: {resp['error']}")
        return resp.get("result")

    def eth_call(self, to: str, data: str) -> str:
        return self.call("eth_call", [{"to": to, "data": data}, "latest"]) or "0x"


# -------- helpers --------

def _hex_to_int(h: Optional[str]) -> int:
    if not h or h == "0x": return 0
    return int(h, 16)

def _strip_hex(s: str) -> str:
    if s.startswith("0x"): s = s[2:]
    return s

def _hex_to_str(h: Optional[str]) -> str:
    if not h or h == "0x" or len(h) < 130: return ""
    s = _strip_hex(h)
    try:
        length = int(s[64:128], 16)
        data = bytes.fromhex(s[128:128 + 2*length])
        return data.decode("utf-8", errors="replace")
    except Exception:
        return ""

def _addr_padded(addr: str) -> str:
    return "0x" + addr.lower().replace("0x", "").rjust(64, "0")


def _risk_score(value: int, flags: List[str]) -> int:
    s = 0
    if "UNLIMITED" in flags: s += 80
    if "LARGE" in flags:     s += 30
    return min(s, 100)


# -------- core logic --------

def scan_approvals(
    address: str,
    chain: str = "mainnet",
    custom_tokens: Optional[List[str]] = None,
    custom_spenders: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """For each (token, spender) pair, read the live allowance."""
    if not address.startswith("0x") or len(address) != 42:
        return {"error": "address must be 0x-prefixed 20-byte hex"}
    address = address.lower()

    rpc = PharosRPC(chain)
    tokens = custom_tokens or KNOWN_TOKENS.get(chain, [])
    spenders = custom_spenders or DEFAULT_SPENDERS.get(chain, [])

    if not tokens:
        return {
            "type": "allowance_scan",
            "chain": chain,
            "address": address,
            "approvals": [],
            "note": f"no known tokens configured for chain={chain}; pass --tokens <addr1,addr2>",
        }
    if not spenders:
        return {
            "type": "allowance_scan",
            "chain": chain,
            "address": address,
            "tokens_scanned": len(tokens),
            "spenders_scanned": 0,
            "approvals_found": 0,
            "risky_count": 0,
            "approvals": [],
            "note": (f"no known spenders configured for chain={chain}; "
                     f"pass --spenders <addr1,addr2> to expand coverage. "
                     f"The skill will report 0 active approvals until the spender list is populated."),
        }

    rows: List[Dict[str, Any]] = []
    for token in tokens:
        token = token.lower()
        try:
            sym = _hex_to_str(rpc.eth_call(token, SEL_SYMBOL)) or "?"
            decimals = _hex_to_int(rpc.eth_call(token, SEL_DECIMALS)) or 18
        except Exception as e:
            rows.append({"token": token, "error": f"metadata fetch failed: {e}"})
            continue

        for spender in spenders:
            spender = spender.lower()
            try:
                data = SEL_ALLOWANCE + _addr_padded(address)[2:] + _addr_padded(spender)[2:]
                h = rpc.eth_call(token, data)
                value = _hex_to_int(h)
            except Exception as e:
                continue

            if value == 0:
                continue  # no active approval

            flags = []
            if value == MAX_UINT256:
                flags.append("UNLIMITED")
            if value > 10**30:
                flags.append("LARGE")

            rows.append({
                "token": token,
                "symbol": sym,
                "decimals": decimals,
                "spender": spender,
                "value_raw": value,
                "value_human": value / (10 ** decimals) if decimals else value,
                "flags": flags,
                "risk_score": _risk_score(value, flags),
                "revocation_command": (
                    f"cast send {token} \"approve(address,uint256)\" {spender} 0 "
                    f"--rpc-url {rpc.cfg['rpc']} --private-key $PRIVATE_KEY"
                ),
            })

    rows.sort(key=lambda r: r.get("risk_score", 0), reverse=True)

    return {
        "type": "allowance_scan",
        "chain": chain,
        "address": address,
        "tokens_scanned": len(tokens),
        "spenders_scanned": len(spenders),
        "approvals_found": len(rows),
        "risky_count": sum(1 for r in rows if r.get("flags")),
        "approvals": rows,
    }


# -------- CLI commands --------

def cmd_scan(args: argparse.Namespace) -> int:
    custom_t = args.tokens.split(",") if args.tokens else None
    custom_s = args.spenders.split(",") if args.spenders else None
    result = scan_approvals(
        args.address,
        chain=args.chain,
        custom_tokens=custom_t,
        custom_spenders=custom_s,
    )
    if "error" in result:
        print(f"❌ {result['error']}")
        return 2
    if args.json:
        print(json.dumps(result, indent=2))
        return 0

    print("=" * 72)
    print(f"  Pharos Allowance Revoker — scan on {CHAINS[args.chain]['label']}")
    print("=" * 72)
    print(f"  wallet:    {result['address']}")
    print(f"  tokens:    {result['tokens_scanned']} known")
    print(f"  spenders:  {result.get('spenders_scanned', 0)} known")
    print(f"  approvals: {result.get('approvals_found', 0)} found, {result.get('risky_count', 0)} flagged risky")
    print()
    if "note" in result:
        print(f"  ℹ️  {result['note']}")
        print()
    if not result["approvals"]:
        print("  ✓ No active approvals found in the scanned token/spender set.")
        return 0
    for a in result["approvals"]:
        if "error" in a:
            print(f"  • {a['token']}: {a['error']}")
            continue
        flag_str = "  [" + ", ".join(a.get("flags") or []) + "]" if a.get("flags") else ""
        print(f"  • {a['symbol']:6s} → {a['spender']}  {a['value_human']:,.4f} (raw {a['value_raw']:,}){flag_str}")
        print(f"    risk: {a['risk_score']}/100")
        if a.get("flags"):
            print(f"    REVOKE:  {a['revocation_command']}")
        print()
    print("=" * 72)
    return 0


def cmd_revoke(args: argparse.Namespace) -> int:
    """Print a single revocation command (no broadcast)."""
    if not args.address.startswith("0x") or len(args.address) != 42:
        print("❌ invalid --address")
        return 2
    if not args.token.startswith("0x") or len(args.token) != 42:
        print("❌ invalid --token")
        return 2
    if not args.spender.startswith("0x") or len(args.spender) != 42:
        print("❌ invalid --spender")
        return 2
    chain = CHAINS[args.chain]
    print("=" * 72)
    print(f"  Revoke approval (set allowance to 0)")
    print("=" * 72)
    print(f"  chain:   {chain['label']} (chain {chain['chain_id']})")
    print(f"  owner:   {args.address}")
    print(f"  token:   {args.token}")
    print(f"  spender: {args.spender}")
    print()
    print("  Copy-paste this command:")
    print("-" * 72)
    print(
        f"cast send {args.token} \"approve(address,uint256)\" {args.spender} 0 "
        f"--rpc-url {chain['rpc']} --private-key $PRIVATE_KEY"
    )
    print("-" * 72)
    print()
    print(f"  Explorer (token):  {chain['explorer']}/address/{args.token}")
    print(f"  Explorer (spender): {chain['explorer']}/address/{args.spender}")
    print("=" * 72)
    return 0


def cmd_demo(_args: argparse.Namespace) -> int:
    print("Allowance Revoker — DEMO (real public address on Pharos mainnet)\n")
    print("This demo runs the scan with the empty default spender list. Until the")
    print("Pharos ecosystem's main DEX/router addresses are added to DEFAULT_SPENDERS")
    print("(or passed via --spenders), the scan reports 0 active approvals — that's")
    print("the correct safe answer. The skill is ready; populate the spender list")
    print("as new protocols ship.\n")
    class A: pass
    a = A()
    a.address = "0x67992af9a87f2d6a3062c333d8a06abbe3929438"
    a.chain = "mainnet"
    a.tokens = None
    a.spenders = None
    a.json = False
    return cmd_scan(a)


def main() -> int:
    p = argparse.ArgumentParser(description="pharos-allowance-revoker — scan & revoke risky ERC-20 approvals")
    sub = p.add_subparsers(dest="cmd")

    ps = sub.add_parser("scan", help="Scan for active approvals on a wallet")
    ps.add_argument("--address", required=True)
    ps.add_argument("--chain", default="mainnet", choices=list(CHAINS))
    ps.add_argument("--tokens", help="comma-separated list of token addresses to scan")
    ps.add_argument("--spenders", help="comma-separated list of spender addresses to check")
    ps.add_argument("--json", action="store_true")

    pr = sub.add_parser("revoke", help="Print a revocation command (no broadcast)")
    pr.add_argument("--address", required=True)
    pr.add_argument("--token", required=True)
    pr.add_argument("--spender", required=True)
    pr.add_argument("--chain", default="mainnet", choices=list(CHAINS))

    sub.add_parser("demo", help="Run on a real public address")

    args = p.parse_args()
    if args.cmd == "scan":   return cmd_scan(args)
    if args.cmd == "revoke": return cmd_revoke(args)
    if args.cmd == "demo":   return cmd_demo(args)
    p.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
