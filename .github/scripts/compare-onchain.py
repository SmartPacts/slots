#!/usr/bin/env python3
# Is the code on chain the code in deploy-bytes/?
#
#   python3 .github/scripts/fetch-onchain.py slots > /tmp/onchain-slots.pact
#   python3 .github/scripts/compare-onchain.py slots /tmp/onchain-slots.pact
#
# WHAT IS COMPARED. `describe-module` returns the `(module …)` form exactly as the engine sliced
# it out of the deploy transaction's source — comments intact, nothing normalised, the namespace
# line and the create-table footer excluded. deploy-bytes/<module>.pact is that same slice, taken
# from the deploy transaction's own `cmd`. So this is a character-for-character equality, not a
# containment test and not a hash comparison.
#
# FAILS CLOSED. An empty or truncated fetch must never read as a pass, and a check that inspected
# nothing reporting PASS is worse than no check at all. So the size is asserted first, against the
# smallest thing each module could plausibly be.
import sys, pathlib

FLOOR = {"slots": 44000, "drand": 8000}        # slots is ~49.1k on chain, drand ~10.3k

if len(sys.argv) < 3:
    sys.exit("usage: compare-onchain.py <slots|drand> <fetched-file> [deploy-bytes-file]")
module = sys.argv[1]
if module not in FLOOR:
    sys.exit("this repository publishes two modules: slots and drand")

onchain = pathlib.Path(sys.argv[2]).read_text()
bytes_path = pathlib.Path(sys.argv[3] if len(sys.argv) > 3 else f"deploy-bytes/{module}.pact")
published = bytes_path.read_text()

if len(onchain) < FLOOR[module]:
    sys.exit(f"REFUSING to compare: the fetched code is {len(onchain)} characters, under the "
             f"{FLOOR[module]} floor for {module}. The fetch failed; this is not a mismatch, it is "
             f"nothing to compare.")

if onchain == published:
    print(f"IDENTICAL: the {len(onchain)} characters mainnet runs for `{module}` are, character "
          f"for character,")
    print(f"           {bytes_path}.")
    sys.exit(0)

# Say WHERE it first diverges, so a real difference is actionable rather than a bare False.
n = min(len(onchain), len(published))
at = next((i for i in range(n) if onchain[i] != published[i]), n)
print(f"MISMATCH: the code mainnet runs for `{module}` is NOT {bytes_path}.")
print(f"  on chain: {len(onchain)} characters   here: {len(published)} characters")
print(f"  first difference at character {at}")
print(f"  on chain: {onchain[at:at+80]!r}")
print(f"  here:     {published[at:at+80]!r}")
print("  TRUST THE CHAIN, NOT THIS REPOSITORY.")
sys.exit(1)
