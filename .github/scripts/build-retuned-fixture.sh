#!/usr/bin/env bash
# Build the RETUNED fixture: pact/modules/slots.pact with machine 5's max-units 563 -> 600 and
# without its trailing (create-table ...) forms — what a governance upgrade that retunes a machine
# before the freeze would send. slots-upgrade-testing.repl loads it between a bet and its claim, to
# prove a board releases exactly the reserve it booked whatever an upgrade does.
#
# Committed under pact/tests/fixtures/ so a reader can read it, and RE-DERIVED here on every run:
# run-tests.sh calls this script and diffs the committed copy against what it produced.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p pact/tests/fixtures
python3 - <<'PY'
src = open('pact/modules/slots.pact').read()
old = '"pays": [7 18 35 80 0 0 0 0], "max-units": 563, "div": 5'
assert src.count(old) == 1, "machine 5's entry not found exactly once"
out = src.replace(old, old.replace('563', '600'))
lines = out.rstrip('\n').split('\n')
while lines and lines[-1].startswith('(create-table '): lines.pop()
assert not any(l.startswith('(create-table ') for l in lines)
open('pact/tests/fixtures/slots-retuned.pact', 'w').write('\n'.join(lines) + '\n')
print("   retuned fixture built: machine 5 max-units 600, no create-table forms")
PY
