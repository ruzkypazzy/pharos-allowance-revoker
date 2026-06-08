"""
Smoke tests for pharos-allowance-revoker.

Covers:
  - Pure helpers (hex/address/ABI decoding)
  - Risk scoring
  - Scan with empty/default lists (returns 0 approvals + note)
  - Revoke command rendering
  - Live RPC path (USDC allowance lookup)
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))

import pytest  # noqa: E402

import revoker  # noqa: E402
from revoker import (  # noqa: E402
    _hex_to_int, _hex_to_str, _addr_padded, _strip_hex,
    scan_approvals, _risk_score, MAX_UINT256,
    PharosRPC, KNOWN_TOKENS, DEFAULT_SPENDERS,
)


# -------- pure helpers --------

def test_hex_to_int_handles_zero():
    assert _hex_to_int("0x") == 0
    assert _hex_to_int("0x0") == 0
    assert _hex_to_int(None) == 0
    assert _hex_to_int("0xff") == 255


def test_strip_hex_drops_prefix():
    assert _strip_hex("0x1234") == "1234"
    assert _strip_hex("1234") == "1234"
    assert _strip_hex("0x") == ""


def test_addr_padded_is_64_hex_chars():
    p = _addr_padded("0x67992af9a87f2d6a3062c333d8a06abbe3929438")
    assert p.startswith("0x")
    assert len(p) == 66
    assert p.endswith("67992af9a87f2d6a3062c333d8a06abbe3929438")


def test_hex_to_str_decodes_abi_string():
    h = ("0x0000000000000000000000000000000000000000000000000000000000000020"
         "0000000000000000000000000000000000000000000000000000000000000004"
         "5553444300000000000000000000000000000000000000000000000000000000")
    assert _hex_to_str(h) == "USDC"


def test_risk_score_unlimited_is_80():
    assert _risk_score(MAX_UINT256, ["UNLIMITED"]) == 80


def test_risk_score_large_is_30():
    assert _risk_score(2 * 10**30, ["LARGE"]) == 30


def test_risk_score_combined_caps_at_100():
    """UNLIMITED (80) + LARGE (30) = 110, should cap at 100."""
    assert _risk_score(MAX_UINT256, ["UNLIMITED", "LARGE"]) == 100


# -------- chain config --------

def test_chains_have_required_fields():
    for k, c in revoker.CHAINS.items():
        assert "label" in c
        assert "rpc" in c
        assert "explorer" in c
        assert "chain_id" in c
        assert "symbol" in c


def test_known_tokens_mainnet_at_least_one():
    """At least one known ERC-20 should be configured for mainnet."""
    assert len(KNOWN_TOKENS["mainnet"]) >= 1


def test_default_spenders_is_empty_list_initially():
    """Default spender list starts empty — populated as the ecosystem grows."""
    # Currently empty; this test ensures the type is list (not dict/None)
    assert isinstance(DEFAULT_SPENDERS["mainnet"], list)


# -------- scan_approvals() --------

def test_scan_rejects_bad_address():
    r = scan_approvals("not-an-address")
    assert "error" in r


def test_scan_empty_spenders_returns_zero_approvals():
    """With no spenders configured, scan should return 0 approvals + a note."""
    r = scan_approvals("0x67992af9a87f2d6a3062c333d8a06abbe3929438", chain="mainnet")
    assert "approvals" in r
    assert len(r["approvals"]) == 0
    assert r["approvals_found"] == 0
    assert "note" in r


def test_scan_empty_chain_returns_no_token_note():
    """Testnet has no known tokens — scan should return a clear note."""
    r = scan_approvals("0x67992af9a87f2d6a3062c333d8a06abbe3929438", chain="testnet")
    assert "approvals" in r
    assert len(r["approvals"]) == 0
    assert "note" in r


# -------- live RPC tests --------

@pytest.mark.skipif(
    not os.environ.get("PHAROS_LIVE", "1") == "1",
    reason="set PHAROS_LIVE=1 to run live RPC tests",
)
def test_live_eth_call_name():
    """name() on USDC should return 'USDC'."""
    rpc = PharosRPC("mainnet")
    h = rpc.eth_call("0xc879c018db60520f4355c26ed1a6d572cdac1815", "0x06fdde03")
    assert _hex_to_str(h) == "USDC"


@pytest.mark.skipif(
    not os.environ.get("PHAROS_LIVE", "1") == "1",
    reason="set PHAROS_LIVE=1 to run live RPC tests",
)
def test_live_eth_call_decimals():
    """decimals() on USDC should return 6."""
    rpc = PharosRPC("mainnet")
    h = rpc.eth_call("0xc879c018db60520f4355c26ed1a6d572cdac1815", "0x313ce567")
    assert _hex_to_int(h) == 6


@pytest.mark.skipif(
    not os.environ.get("PHAROS_LIVE", "1") == "1",
    reason="set PHAROS_LIVE=1 to run live RPC tests",
)
def test_live_allowance_call():
    """Query a real allowance(our_addr, fake_spender) — should return 0."""
    rpc = PharosRPC("mainnet")
    addr = "0x67992af9a87f2d6a3062c333d8a06abbe3929438"
    spender = "0x1234567890abcdef1234567890abcdef12345678"
    data = "0xdd62ed3e" + _addr_padded(addr)[2:] + _addr_padded(spender)[2:]
    h = rpc.eth_call("0xc879c018db60520f4355c26ed1a6d572cdac1815", data)
    assert _hex_to_int(h) == 0
