#!/usr/bin/env bash
# pharos-allowance-revoker — bash + cast + jq (Foundry port).
#
# Scans Pharos mainnet/testnet for risky ERC-20 approvals on a given
# owner address. For each (token, spender) pair, reads the live
# `allowance(owner, spender)` via cast, flags risky approvals
# (UNLIMITED = 2^256-1, LARGE = > 1e30), and prints a cast-send
# revocation command the user can sign and broadcast themselves
# (the skill NEVER holds a private key).
#
# Usage:
#   bash scripts/revoke.sh scan   --address 0xWALLET [--chain mainnet|testnet]
#   bash scripts/revoke.sh revoke --address 0xWALLET --token 0xTOKEN --spender 0xSPENDER
#   bash scripts/revoke.sh demo
#   bash scripts/revoke.sh --help

set -euo pipefail

# -------- Foundry required (after arg parsing so --help works offline) --------
FOUNDRY_CONFIG_NONE_DONE=0
ensure_cast() {
  if ! command -v cast >/dev/null 2>&1; then
    echo "Error: 'cast' not found. Install Foundry:" >&2
    echo "  curl -L https://foundry.paradigm.xyz | bash && foundryup" >&2
    exit 1
  fi
}

# -------- selectors --------
SEL_NAME="0x06fdde03"
SEL_SYMBOL="0x95d89b41"
SEL_DECIMALS="0x313ce567"
SEL_ALLOWANCE="0xdd62ed3e"  # allowance(address,address)

# MAX_UINT256 = 2^256 - 1
MAX_UINT256_HEX="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

# LARGE threshold: > 1e30 (with 18 decimals that's 1B tokens)
LARGE_THRESHOLD="1000000000000000000000000000000"  # 1e30

# -------- known tokens on Pharos (extend as the ecosystem grows) --------
KNOWN_TOKENS_MAINNET=(
  "0xc879c018db60520f4355c26ed1a6d572cdac1815"  # USDC (6 decimals)
)

# Common DEX/router spender addresses on Pharos. Empty by default
# — populate as new protocols ship. The skill works with an empty
# list (returns 0 approvals) and lets the user pass --spenders
# to expand coverage.
DEFAULT_SPENDERS_MAINNET=(
)

# -------- helpers --------

# Pad an address to 32 bytes (for ABI encoding)
addr_padded() {
  local addr="$1"
  addr="${addr#0x}"
  addr="${addr,,}"
  printf '0x%064s' "$addr"
}

# Decode a uint256 hex value (0x...) to decimal
hex_to_dec() {
  local h="${1#0x}"
  if [ -z "$h" ]; then
    echo "0"
    return
  fi
  # Strip leading zeros
  h="${h#0}"
  if [ -z "$h" ]; then
    echo "0"
    return
  fi
  # Use cast to do the conversion
  cast --to-dec "0x$h" 2>/dev/null || python3 -c "print(int('$h', 16))" 2>/dev/null || echo "$h"
}

# Decode a string from ABI-encoded (string) return data
hex_to_str() {
  local h="$1"
  h="${h#0x}"
  if [ -z "$h" ] || [ "${#h}" -lt 130 ]; then
    echo ""
    return
  fi
  # The format is: 64 hex (offset) | 64 hex (length) | length * 64 hex (data, padded)
  local length=$((16#${h:64:64}))
  if [ "$length" -eq 0 ]; then
    echo ""
    return
  fi
  local data_hex="${h:128:$((length * 2))}"
  # Convert to bytes then UTF-8
  echo -n "$data_hex" | xxd -r -p 2>/dev/null || echo ""
}

# Risk score: 80 for UNLIMITED, 30 for LARGE, max 100
risk_score() {
  local value="$1"
  local flags="$2"
  local score=0
  if [[ "$flags" == *"UNLIMITED"* ]]; then
    score=$((score + 80))
  fi
  if [[ "$flags" == *"LARGE"* ]]; then
    score=$((score + 30))
  fi
  if [ "$score" -gt 100 ]; then
    score=100
  fi
  echo "$score"
}

# Render a single allowance row as a human-readable string
render_row() {
  local token="$1" symbol="$2" decimals="$3" spender="$4" value_raw="$5" risk="$6" flags="$7" rpc="$8"
  local value_human="0"
  if [ -n "$decimals" ] && [ "$decimals" -gt 0 ] 2>/dev/null; then
    # Convert raw to human (value / 10^decimals)
    # cast --to-unit takes wei, decimals
    value_human=$(cast --to-unit "$value_raw" "$decimals" 2>/dev/null || echo "$value_raw")
  else
    value_human="$value_raw"
  fi

  local flag_str=""
  if [ -n "$flags" ]; then
    flag_str="  [$flags]"
  fi

  echo "  • $symbol → $spender  $value_human (raw $value_raw)$flag_str"
  echo "    risk: $risk/100"
  if [ -n "$flags" ]; then
    echo "    REVOKE:  cast send $token \"approve(address,uint256)\" $spender 0 \\"
    echo "              --rpc-url $rpc --private-key \$PRIVATE_KEY"
  fi
  echo ""
}

# -------- arg parsing --------
CMD=""
ADDRESS=""
TOKEN=""
SPENDER=""
CHAIN="mainnet"
TOKENS_CSV=""
SPENDERS_CSV=""
JSON=0
PRINT_HELP=0
PREV=""

while [[ $# -gt 0 ]]; do
  case "$PREV" in
    --chain)    CHAIN="$2"; PREV=""; shift 2; continue ;;
    --address)  ADDRESS="$2"; PREV=""; shift 2; continue ;;
    --token)    TOKEN="$2"; PREV=""; shift 2; continue ;;
    --spender)  SPENDER="$2"; PREV=""; shift 2; continue ;;
    --tokens)   TOKENS_CSV="$2"; PREV=""; shift 2; continue ;;
    --spenders) SPENDERS_CSV="$2"; PREV=""; shift 2; continue ;;
  esac
  case "$1" in
    scan|revoke|demo) CMD="$1"; shift ;;
    --chain)    PREV="--chain" ;;
    --address)  PREV="--address" ;;
    --token)    PREV="--token" ;;
    --spender)  PREV="--spender" ;;
    --tokens)   PREV="--tokens" ;;
    --spenders) PREV="--spenders" ;;
    --json)     JSON=1; shift ;;
    -h|--help)  PRINT_HELP=1; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done
[ -n "$PREV" ] && { echo "Error: $PREV requires a value" >&2; exit 1; }

if [ "$PRINT_HELP" = "1" ]; then
  cat <<'USAGE'
pharos-allowance-revoker — scan & revoke risky ERC-20 approvals on Pharos

Usage:
  bash scripts/revoke.sh scan   --address 0xWALLET [--chain mainnet|testnet]
                                  [--tokens addr1,addr2] [--spenders addr1,addr2]
                                  [--json]
  bash scripts/revoke.sh revoke --address 0xWALLET --token 0xTOKEN --spender 0xSPENDER
                                  [--chain mainnet|testnet]
  bash scripts/revoke.sh demo

Networks: mainnet (Pacific Ocean, chain 1672) and testnet (Atlantic, chain 688689).

Prerequisites:
  - Foundry installed (cast/forge): curl -L https://foundry.paradigm.xyz | bash
USAGE
  exit 0
fi

if [ -z "$CMD" ]; then
  echo "Usage: bash scripts/revoke.sh {scan|revoke|demo} [args...]"
  exit 1
fi

# -------- load network config from assets/networks.json --------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NET_JSON="$SCRIPT_DIR/../assets/networks.json"
[ ! -f "$NET_JSON" ] && { echo "Error: $NET_JSON not found"; exit 1; }

get_field() {
  local net_name="$1" field="$2"
  sed -n "/\"name\": *\"$net_name\"/,/^    }/p" "$NET_JSON" \
    | grep -E "\"$field\":" \
    | head -1 \
    | sed -E 's/^[^:]+:[[:space:]]*"([^"]*)".*/\1/' \
    | sed -E 's/,$//'
}

case "$CHAIN" in
  mainnet)
    RPC_URL=$(get_field "mainnet" "rpcUrl")
    EXPLORER_URL=$(get_field "mainnet" "explorerUrl")
    CHAIN_ID=1672
    NATIVE=$(get_field "mainnet" "nativeToken")
    DEFAULT_TOKENS=("${KNOWN_TOKENS_MAINNET[@]}")
    DEFAULT_SPENDERS=("${DEFAULT_SPENDERS_MAINNET[@]}")
    ;;
  testnet)
    RPC_URL=$(get_field "atlantic-testnet" "rpcUrl")
    EXPLORER_URL=$(get_field "atlantic-testnet" "explorerUrl")
    CHAIN_ID=688689
    NATIVE=$(get_field "atlantic-testnet" "nativeToken")
    DEFAULT_TOKENS=()
    DEFAULT_SPENDERS=()
    ;;
  *) echo "Unknown chain: $CHAIN (use 'mainnet' or 'testnet')"; exit 1 ;;
esac

# Custom tokens/spenders from CSV
if [ -n "$TOKENS_CSV" ]; then
  IFS=',' read -ra CUSTOM_TOKENS <<< "$TOKENS_CSV"
else
  CUSTOM_TOKENS=()
fi
if [ -n "$SPENDERS_CSV" ]; then
  IFS=',' read -ra CUSTOM_SPENDERS <<< "$SPENDERS_CSV"
else
  CUSTOM_SPENDERS=()
fi

# Use custom if provided, else default.
# The ${X[@]:-${Y[@]}} pattern is broken when both arrays are empty
# (bash creates a single-element array with one empty string),
# so we use explicit length checks instead.
TOKENS=()
if [ ${#CUSTOM_TOKENS[@]} -gt 0 ]; then
  TOKENS=("${CUSTOM_TOKENS[@]}")
elif [ ${#DEFAULT_TOKENS[@]} -gt 0 ]; then
  TOKENS=("${DEFAULT_TOKENS[@]}")
fi
SPENDERS=()
if [ ${#CUSTOM_SPENDERS[@]} -gt 0 ]; then
  SPENDERS=("${CUSTOM_SPENDERS[@]}")
elif [ ${#DEFAULT_SPENDERS[@]} -gt 0 ]; then
  SPENDERS=("${DEFAULT_SPENDERS[@]}")
fi

# -------- demo mode --------
if [ "$CMD" = "demo" ]; then
  ADDRESS="0x67992af9a87f2d6a3062c333d8a06abbe3929438"
  CMD="scan"
  echo "Allowance Revoker — DEMO (real public address on Pharos mainnet)"
  echo ""
  echo "This demo runs the scan with the configured token/spender set."
  echo "If the result is 0 approvals, that's the correct safe answer — the skill"
  echo "is ready; populate the spender list as the Pharos ecosystem grows."
  echo ""
fi

# -------- scan mode --------
if [ "$CMD" = "scan" ]; then
  if [ -z "$ADDRESS" ]; then
    echo "Error: --address required" >&2
    exit 1
  fi
  if [[ ! "$ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "Error: --address must be 0x-prefixed 20-byte hex" >&2
    exit 1
  fi
  ADDRESS="${ADDRESS,,}"

  if [ ${#TOKENS[@]} -eq 0 ]; then
    if [ "$JSON" = "1" ]; then
      echo "{\"type\":\"allowance_scan\",\"chain\":\"$CHAIN\",\"address\":\"$ADDRESS\",\"approvals\":[],\"note\":\"no tokens configured; pass --tokens\"}"
    else
      echo "========================================================================"
      echo "  Pharos Allowance Revoker — scan on $CHAIN"
      echo "========================================================================"
      echo "  wallet: $ADDRESS"
      echo ""
      echo "  ℹ️  no known tokens configured for chain=$CHAIN"
      echo "     Pass --tokens 0xTOKEN1,0xTOKEN2 to expand coverage."
      echo "========================================================================"
    fi
    exit 0
  fi

  if [ ${#SPENDERS[@]} -eq 0 ]; then
    if [ "$JSON" = "1" ]; then
      echo "{\"type\":\"allowance_scan\",\"chain\":\"$CHAIN\",\"address\":\"$ADDRESS\",\"tokens_scanned\":${#TOKENS[@]},\"spenders_scanned\":0,\"approvals_found\":0,\"risky_count\":0,\"approvals\":[],\"note\":\"no known spenders; pass --spenders 0xSP1,0xSP2\"}"
    else
      echo "========================================================================"
      echo "  Pharos Allowance Revoker — scan on $CHAIN"
      echo "========================================================================"
      echo "  wallet:    $ADDRESS"
      echo "  tokens:    ${#TOKENS[@]} known"
      echo "  spenders:  0 known"
      echo "  approvals: 0 found"
      echo ""
      echo "  ℹ️  no known spenders configured for chain=$CHAIN"
      echo "     Pass --spenders 0xSP1,0xSP2 to expand coverage."
      echo "     The skill will report 0 active approvals until the spender list is populated."
      echo "========================================================================"
    fi
    exit 0
  fi

  # Cast is required from here on
  ensure_cast

  # Walk every (token, spender) pair
  ADDRESS_PAD=$(addr_padded "$ADDRESS")
  ROWS=()
  RISKY_COUNT=0

  for token in "${TOKENS[@]}"; do
    token="${token,,}"

    # Fetch token metadata
    SYM_HEX=$(cast call --rpc-url "$RPC_URL" "$token" "symbol()(string)" 2>/dev/null || echo "")
    DEC_HEX=$(cast call --rpc-url "$RPC_URL" "$token" "decimals()(uint8)" 2>/dev/null || echo "")
    SYMBOL=$(hex_to_str "$SYM_HEX")
    [ -z "$SYMBOL" ] && SYMBOL="?"
    DECIMALS=$(hex_to_dec "$DEC_HEX")
    [ -z "$DECIMALS" ] || [ "$DECIMALS" = "0" ] && DECIMALS=18

    for spender in "${SPENDERS[@]}"; do
      spender="${spender,,}"

      # Encode allowance(address,address) call
      SPENDER_PAD=$(addr_padded "$spender")
      ALLOWANCE_DATA="0xdd62ed3e${ADDRESS_PAD#0x}${SPENDER_PAD#0x}"
      ALLOWANCE_HEX=$(cast call --rpc-url "$RPC_URL" "$token" "$ALLOWANCE_DATA" 2>/dev/null || echo "")

      # cast call ... "approve(address,uint256)" returns the decoded value as a number string
      # Use the explicit ABI signature to get decoded output
      VALUE=$(cast call --rpc-url "$RPC_URL" "$token" "allowance(address,address)(uint256)" "$ADDRESS" "$spender" 2>/dev/null || echo "0")
      VALUE=$(echo "$VALUE" | tr -d '[:space:]')
      [ -z "$VALUE" ] && VALUE="0"

      # Skip zero allowances
      if [ "$VALUE" = "0" ] || [ "$VALUE" = "0x0" ]; then
        continue
      fi

      # Convert to hex for MAX_UINT256 comparison
      VALUE_HEX=$(cast --to-hex "$VALUE" 2>/dev/null || echo "0x0")
      VALUE_HEX="${VALUE_HEX#0x}"
      # Pad to 64 chars
      while [ "${#VALUE_HEX}" -lt 64 ]; do
        VALUE_HEX="0$VALUE_HEX"
      done
      VALUE_HEX="0x$VALUE_HEX"

      # Determine flags
      FLAGS=""
      if [ "$VALUE_HEX" = "$MAX_UINT256_HEX" ]; then
        FLAGS="UNLIMITED"
      fi
      if [ -n "$VALUE" ] && [ "$VALUE" -gt "$LARGE_THRESHOLD" ] 2>/dev/null; then
        [ -n "$FLAGS" ] && FLAGS="$FLAGS,LARGE" || FLAGS="LARGE"
      fi

      RISK=$(risk_score "$VALUE" "$FLAGS")
      [ -n "$FLAGS" ] && RISKY_COUNT=$((RISKY_COUNT + 1))

      if [ "$JSON" = "1" ]; then
        # Build JSON entry
        FLAGS_JSON="[]"
        if [ -n "$FLAGS" ]; then
          FLAGS_JSON=$(echo "$FLAGS" | tr ',' '\n' | jq -R . | jq -s .)
        fi
        ROWS+=("$(jq -n \
          --arg token "$token" \
          --arg symbol "$SYMBOL" \
          --argjson decimals "$DECIMALS" \
          --arg spender "$spender" \
          --argjson value "$VALUE" \
          --argjson risk "$RISK" \
          --argjson flags "$FLAGS_JSON" \
          '{token: $token, symbol: $symbol, decimals: $decimals, spender: $spender, value_raw: $value, risk_score: $risk, flags: $flags}')")
      else
        render_row "$token" "$SYMBOL" "$DECIMALS" "$spender" "$VALUE" "$RISK" "$FLAGS" "$RPC_URL"
      fi
    done
  done

  if [ "$JSON" = "1" ]; then
    # Build final JSON
    ROWS_JSON=$(printf '%s\n' "${ROWS[@]:-}" | jq -s '.')
    jq -n \
      --arg type "allowance_scan" \
      --arg chain "$CHAIN" \
      --arg address "$ADDRESS" \
      --argjson tokens ${#TOKENS[@]} \
      --argjson spenders ${#SPENDERS[@]} \
      --argjson found ${#ROWS[@]} \
      --argjson risky "$RISKY_COUNT" \
      --argjson rows "$ROWS_JSON" \
      '{type: $type, chain: $chain, address: $address, tokens_scanned: $tokens, spenders_scanned: $spenders, approvals_found: $found, risky_count: $risky, approvals: $rows}'
  else
    echo "========================================================================"
    echo "  Pharos Allowance Revoker — scan on $CHAIN"
    echo "========================================================================"
    echo "  wallet:    $ADDRESS"
    echo "  tokens:    ${#TOKENS[@]} known"
    echo "  spenders:  ${#SPENDERS[@]} known"
    echo "  approvals: ${#ROWS[@]} found, $RISKY_COUNT flagged risky"
    echo "========================================================================"
  fi
  exit 0
fi

# -------- revoke mode --------
if [ "$CMD" = "revoke" ]; then
  if [ -z "$ADDRESS" ] || [ -z "$TOKEN" ] || [ -z "$SPENDER" ]; then
    echo "Error: --address, --token, --spender are all required" >&2
    exit 1
  fi
  if [[ ! "$ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]] || \
     [[ ! "$TOKEN" =~ ^0x[0-9a-fA-F]{40}$ ]] || \
     [[ ! "$SPENDER" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "Error: --address, --token, --spender must be 0x-prefixed 20-byte hex" >&2
    exit 1
  fi

  echo "========================================================================"
  echo "  Revoke approval (set allowance to 0)"
  echo "========================================================================"
  echo "  chain:   $CHAIN (chain $CHAIN_ID)"
  echo "  owner:   $ADDRESS"
  echo "  token:   $TOKEN"
  echo "  spender: $SPENDER"
  echo ""
  echo "  Copy-paste this command (DO NOT paste your private key in chat):"
  echo "------------------------------------------------------------------------"
  echo "cast send $TOKEN \"approve(address,uint256)\" $SPENDER 0 \\"
  echo "  --rpc-url $RPC_URL --private-key \$PRIVATE_KEY"
  echo "------------------------------------------------------------------------"
  echo ""
  echo "  Explorer (token):  $EXPLORER_URL/address/$TOKEN"
  echo "  Explorer (spender): $EXPLORER_URL/address/$SPENDER"
  echo "========================================================================"
  exit 0
fi

echo "Unknown command: $CMD"
exit 1
