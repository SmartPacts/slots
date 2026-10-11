#!/usr/bin/env python3
# Fetch the deployed code of one module from a Kadena node. Read-only: this sends no transaction,
# needs no key, and costs nothing.
#
#   python3 .github/scripts/fetch-onchain.py slots > /tmp/onchain-slots.pact
#   python3 .github/scripts/fetch-onchain.py drand    > /tmp/onchain-drand.pact
#
# A raw curl cannot do this: a Pact command carries its own hash, the node checks that the hash
# matches the exact command BYTES, and re-serialising the JSON changes those bytes. So the command
# string is built once, hashed as-is (blake2b-256, base64url, unpadded — Pact's envelope hash),
# and sent unmodified.
#
# `--hash` prints the module hash the chain reports instead of the code. That number is worth
# reading for `drand` and worth nothing for `slots` — VERIFY.md §3 says why.
import base64, hashlib, json, sys, urllib.request

args   = [a for a in sys.argv[1:] if not a.startswith("--")]
WANT   = "hash" if "--hash" in sys.argv[1:] else "code"
MODULE = args[0] if args else "slots"
NODE   = args[1] if len(args) > 1 else "https://api.chainweb-community.org"
NS     = "n_48867b242317a0216a67f8c7ca26696b5878e0e3"
CHAIN  = "2"

if MODULE not in ("slots", "drand"):
    sys.exit("this repository publishes two modules: slots and drand")

code = f"""(at '{WANT} (describe-module "{NS}.{MODULE}"))"""
cmd = json.dumps({
    "payload": {"exec": {"code": code, "data": {}}},
    "nonce": "verify", "signers": [],
    "meta": {"gasLimit": 150000, "gasPrice": 1e-8, "sender": "",
             "ttl": 900, "creationTime": 0, "chainId": CHAIN},
    "networkId": "mainnet01",
}, separators=(",", ":"))
digest = hashlib.blake2b(cmd.encode(), digest_size=32).digest()
envelope = {"cmd": cmd, "hash": base64.urlsafe_b64encode(digest).decode().rstrip("="), "sigs": []}

url = f"{NODE}/chainweb/0.0/mainnet01/chain/{CHAIN}/pact/api/v1/local"
req = urllib.request.Request(url, data=json.dumps(envelope).encode(),
                             headers={"Content-Type": "application/json"})
res = json.load(urllib.request.urlopen(req))["result"]
if res["status"] != "success":
    sys.exit(f"the node refused the read: {json.dumps(res.get('error'))[:300]}")
sys.stdout.write(res["data"] + ("\n" if WANT == "hash" else ""))
