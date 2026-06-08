#!/bin/bash
# pharos-allowance-revoker — bash wrapper.
# Usage:
#   bash scripts/revoke.sh scan --address 0x... [--chain mainnet|testnet]
#   bash scripts/revoke.sh revoke --address 0x... --token 0x... --spender 0x...
#   bash scripts/revoke.sh demo
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."
CMD="${1:-}"
shift || true
if [ -z "$CMD" ]; then
  echo "Usage: bash scripts/revoke.sh {scan|revoke|demo} [args...]"
  exit 1
fi
case "$CMD" in
  demo) python3 revoker.py demo ;;
  scan|revoke) python3 revoker.py "$CMD" "$@" ;;
  *) echo "Unknown: $CMD"; exit 1 ;;
esac
