#!/usr/bin/env bash
# run-tests.sh — everything this repository claims about the two contracts, in one command.
#
#   cd pact/tests && ./run-tests.sh
#
# This is the same command CI runs, with no reduced subset: a CI that runs less than you do
# teaches you to trust a green tick that means less than you think.
#
# SCORED BY EXIT CODE, NEVER BY GREPPING THE TRANSCRIPT. A later hard error in a Pact REPL
# suppresses earlier FAILURE lines, so a mutation that breaks an early assertion can leave a
# transcript with no FAILURE in it at all. Only the exit code is trustworthy — and one file here
# is an INVERTED CONTROL that must FAIL, which grepping cannot score at all.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PACT="${PACT:-pact}"
BAD=0

echo "== engine"
"$PACT" --version || { echo "no pact on PATH — set PACT=/path/to/pact"; exit 2; }
python3 --version || { echo "the gates fail closed without python3"; exit 2; }

echo
echo "== static gate (every .pact and .repl under pact/, loaded through the engine and scanned)"
# ENUMERATED, never hand-listed: a new suite is picked up automatically instead of being silently
# left outside the gate, and the count is asserted so a broken enumeration FAILS rather than
# reporting clean on nothing.
#
# Two things are outside it, on purpose, and neither is unchecked:
#   * deploy-bytes/ — a bare `(module …)` form with no `namespace` line, so it cannot load on its
#     own. It is checked instead by `module-region.py --check`, which proves it is character for
#     character the module in pact/modules/ that the gate DOES load.
#   * slots-pin-must-fail.repl, slots-open-round-must-fail.repl and slots-load-gate-must-fail.repl
#     — the inverted controls. The gate's first tier asks "does it load", and those three files are
#     required NOT to.
(
  cd ../..
  mapfile -t SFILES < <(find pact \( -name '*.pact' -o -name '*.repl' \) -type f \
                        | grep -v 'slots-pin-must-fail\.repl' \
                        | grep -v 'slots-open-round-must-fail\.repl' \
                        | grep -v 'slots-load-gate-must-fail\.repl' | sort)
  n=${#SFILES[@]}
  [ "$n" -ge 21 ] || { echo "   BAD: only $n files enumerated — the enumeration broke"; exit 1; }
  ./.github/scripts/pact-static-check.sh "${SFILES[@]}"
) || BAD=$((BAD+1))

echo
# ONE CALL PER FILE, and the count is checked: a gate that inspected zero files must FAIL, never
# pass quietly. In Pact 5 `or`, `and` and `+` take exactly TWO operands: a three-operand form
# loads, passes the static gate, and only throws when that line runs.
echo "== binary forms (or / and / + take exactly two operands in Pact 5)"
(
  cd ../..
  nf=$(find pact -name '*.pact' -o -name '*.repl' | wc -l)
  ar=$(find pact -name '*.pact' -o -name '*.repl' | sort | while read -r f; do python3 .github/scripts/pact-arity-check.py "$f" 2>&1; done)
  na=$(echo "$ar" | grep -c 'forms,')
  bad3=$(echo "$ar" | grep -E 'forms,' | grep -vc ' 0 with 3+ operands')
  echo "   files on disk: $nf   reported on: $na   with a 3+ operand form: $bad3"
  [ "$na" -eq "$nf" ] || { echo "   BAD: the checker reported on $na of $nf files"; exit 1; }
  [ "$bad3" -eq 0 ] || { echo "$ar" | grep -E 'forms,' | grep -v ' 0 with 3+ operands' | sed 's/^/   /'; exit 1; }
) || BAD=$((BAD+1))

# A two-argument `expect-failure` matches ANY failure, so it asserts nothing about WHY the call
# failed — an arity error or a typo would pass it. The checker self-tests before scanning and
# fails if it can parse no file, so it cannot certify an empty scan as clean.
echo "== expect-failure arity (a two-argument expect-failure asserts nothing about WHY)"
( cd ../.. && python3 .github/scripts/expect-failure-arity.py pact/tests/*.repl ) || BAD=$((BAD+1))

# The annotated module and the bytes that were deployed must be the same program. If this row
# fails, everything VERIFY.md says about the file you are reading is about a different file.
echo "== the annotated modules ARE the published deploy bytes"
( cd ../.. && python3 .github/scripts/module-region.py --check ) || BAD=$((BAD+1))

# The frozen-module suite runs the whole lifecycle against a copy of slots whose GOVERNANCE can
# never pass again. That copy must be THIS module with only that one substitution, or the suite
# proves the freeze behaviour of some other contract. Re-derived here and compared with what is
# committed, so a stale fixture is loud rather than silent.
echo "== the frozen fixture is this module with governance replaced, and nothing else"
KEEP=$(mktemp -d)
cp fixtures/slots-frozen.pact fixtures/frozen-init.repl "$KEEP/" 2>/dev/null \
  || { echo "   BAD: the committed fixture is missing"; BAD=$((BAD+1)); }
( cd ../.. && ./.github/scripts/build-frozen-fixture.sh ) || BAD=$((BAD+1))
if diff -q "$KEEP/slots-frozen.pact" fixtures/slots-frozen.pact > /dev/null 2>&1 \
   && diff -q "$KEEP/frozen-init.repl" fixtures/frozen-init.repl > /dev/null 2>&1; then
  echo "   the committed fixture is exactly what the generator produces"
else
  echo "   BAD: the committed fixture is NOT what build-frozen-fixture.sh produces"; BAD=$((BAD+1))
fi

# The upgrade suite loads a RETUNED copy between a bet and its claim, to prove a board releases
# exactly the reserve it booked whatever an upgrade does. Same rule: re-derived and compared.
echo "== the retuned fixture is this module with one machine's maximum moved, and nothing else"
cp fixtures/slots-retuned.pact "$KEEP/" 2>/dev/null \
  || { echo "   BAD: the committed retuned fixture is missing"; BAD=$((BAD+1)); }
( cd ../.. && ./.github/scripts/build-retuned-fixture.sh ) || BAD=$((BAD+1))
if diff -q "$KEEP/slots-retuned.pact" fixtures/slots-retuned.pact > /dev/null 2>&1; then
  echo "   the committed fixture is exactly what the generator produces"
else
  echo "   BAD: the committed fixture is NOT what build-retuned-fixture.sh produces"; BAD=$((BAD+1))
fi
rm -rf "$KEEP"

# slots pins the beacon verifier BY HASH, so it refuses to load against any other code under
# that name. drand has no dependencies, so its hash can be computed locally and compared — which
# is exactly what this does, against the literal in the module.
echo "== the drand hash pinned in slots is the drand in this repository"
RH=$(mktemp /tmp/drand-hash-XXXXXX.repl)
{ echo "(load \"$PWD/drand-test-init.repl\")"
  echo '(print (format "DRANDHASH {}" [(at "hash" (describe-module "n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand"))]))'
} > "$RH"
H=$("$PACT" "$RH" 2>/dev/null | grep -oE 'DRANDHASH [A-Za-z0-9_-]+' | awk '{print $2}')
if [ -n "$H" ] && grep -q "$H" ../modules/slots.pact; then
  echo "   $H — built here and pinned in slots.pact"
else
  echo "   BAD: built=${H:-<unreadable>}, which slots.pact does not pin"; BAD=$((BAD+1))
fi
rm -f "$RH"

# The published terms state numbers. They must BE the contract's constants, read out of the module
# or recomputed from its machine table. The checker's stderr is kept apart: a shell error inside it
# (a bad substitution, a failed read) prints there and can skip checks while it still exits 0, so
# any stderr at all fails the row.
echo "== the player terms state the contract's own numbers"
TERR=$(mktemp)
TOUT=$( cd ../.. && ./.github/scripts/check-player-terms.sh 2> "$TERR" ); TRC=$?
grep -E '  BAD|terms OK' <<< "$TOUT" | sed 's/^ */   /'
if [ "$TRC" = 0 ] && [ ! -s "$TERR" ]; then
  :
else
  [ -s "$TERR" ] && sed 's/^/   stderr: /' "$TERR" | head -5
  echo "   BAD: the terms drifted from slots.pact, or the checker failed"; BAD=$((BAD+1))
fi
rm -f "$TERR"

echo
echo "== suites (every one must exit 0)"
for f in drand-unit-testing.repl \
         slots-unit-testing.repl slots-rules-testing.repl slots-attacks-testing.repl \
         slots-capfloor-testing.repl slots-internals-testing.repl \
         slots-oracle-testing.repl slots-payout-testing.repl \
         slots-crank-interface.repl slots-frozen-testing.repl \
         slots-upgrade-testing.repl; do
  "$PACT" -t "$f" > "/tmp/$f.out" 2>&1
  rc=$?
  n=$(grep -c 'Expect' "/tmp/$f.out" 2>/dev/null || echo 0)
  if [ $rc -eq 0 ]; then printf '   ok   %-38s exit=0  %s assertions printed\n' "$f" "$n"
  else printf '   FAIL %-38s exit=%s  (see /tmp/%s.out)\n' "$f" "$rc" "$f"; BAD=$((BAD+1)); fi
done

echo
echo "== the inverted controls (each must exit 1, AND for the stated reason)"
# 🔴 Exit code alone is not enough here. ANY unrelated failure — a typo, a missing fixture, an
# unset keyset — also exits 1, and the row would print ok while proving nothing. Require the
# MESSAGE as well. What it proves: plant an impostor `drand` that "verifies" every signature and
# returns chosen reels, and slots REFUSES TO LOAD, because it pins the verifier by hash.
PINOUT=$("$PACT" slots-pin-must-fail.repl 2>&1); PINRC=$?
# 🔴 MATCHED FROM A HERE-STRING, NOT THROUGH A PIPE. Under `set -o pipefail`, `printf … | grep -q`
# reports the PIPE: grep exits the moment it matches, printf dies of SIGPIPE, and the pipeline
# returns 141 — so a successful match reads as a failure, intermittently, depending on how much of
# the 80 KB transcript fitted in the pipe buffer. This row is the one place where a false negative
# would be a false alarm and a false positive would hide a broken pin, so it does not use a pipe.
if grep -q "hash not blessed" <<< "$PINOUT"; then WHY=present; else WHY=ABSENT; fi
if [ "$PINRC" = 1 ] && [ "$WHY" = present ]; then
  printf '   ok   %-38s exit=1 and refused for the right reason\n' "slots-pin-must-fail.repl"
else
  printf '   FAIL %-38s exit=%s, "hash not blessed" %s\n' "slots-pin-must-fail.repl" "$PINRC" "$WHY"
  BAD=$((BAD+1))
fi

# The module defines no `open-round` export: the round opener is inlined in `bet`, so there is no
# separate door for anyone to find. A module that names the export must FAIL TO LOAD with the
# engine's "has no such member". If the export ever comes back, that module loads clean and this
# row turns red. Matched from a here-string for the same reason as the row above, and it must not
# print UNEXPECTED, which the file uses to announce that the forbidden call went through.
OROUT=$("$PACT" slots-open-round-must-fail.repl 2>&1); ORRC=$?
if grep -q "has no such member: open-round" <<< "$OROUT"; then WHY=present; else WHY=ABSENT; fi
if grep -q "UNEXPECTED" <<< "$OROUT"; then WHY="$WHY, UNEXPECTED printed"; fi
if [ "$ORRC" = 1 ] && [ "$WHY" = present ]; then
  printf '   ok   %-38s exit=1 and refused for the right reason\n' "slots-open-round-must-fail.repl"
else
  printf '   FAIL %-38s exit=%s, "has no such member: open-round" %s\n' "slots-open-round-must-fail.repl" "$ORRC" "$WHY"
  BAD=$((BAD+1))
fi

# slots.pact opens with a load-time check on the governance keyset, so only the admin keys can
# install or upgrade it. Every suite loads it WITH that key, so no suite can see the line go. This
# control loads it with NO signature in scope and must fail at slots.pact's own keyset check, never
# reach its final print. If the load-time check is ever removed, the module loads and the row turns red.
LGOUT=$("$PACT" slots-load-gate-must-fail.repl 2>&1); LGRC=$?
if grep -qE '(^|/)slots\.pact:[0-9]+:[0-9]+: Keyset failure' <<< "$LGOUT"; then WHY=present; else WHY=ABSENT; fi
if grep -q "UNEXPECTED" <<< "$LGOUT"; then WHY="$WHY, UNEXPECTED printed"; fi
if [ "$LGRC" = 1 ] && [ "$WHY" = present ]; then
  printf '   ok   %-38s exit=1 and refused for the right reason\n' "slots-load-gate-must-fail.repl"
else
  printf '   FAIL %-38s exit=%s, "Keyset failure" at slots.pact %s\n' "slots-load-gate-must-fail.repl" "$LGRC" "$WHY"
  BAD=$((BAD+1))
fi

echo
if [ "$BAD" -eq 0 ]; then echo "SUITE RESULT: PASS"; else echo "SUITE RESULT: FAIL ($BAD)"; fi
exit $((BAD > 0))
