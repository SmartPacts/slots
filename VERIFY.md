# Verify this yourself

Five checks and one warning, in increasing order of what they prove. None of them needs a key, an
account, or our permission, and none of them sends a transaction.

If any of this disagrees with what you read elsewhere in this repository — **trust the chain, not
this repository.**

---

## 1. The chain is running this code

This is the one that matters. Two commands per module. Read both scripts first — they are short,
and they only make a read-only `/local` request. Pass any node URL you trust as a second argument;
the default is a public community node.

```bash
python3 .github/scripts/fetch-onchain.py slots > /tmp/onchain-slots.pact
python3 .github/scripts/compare-onchain.py slots /tmp/onchain-slots.pact

python3 .github/scripts/fetch-onchain.py drand > /tmp/onchain-drand.pact
python3 .github/scripts/compare-onchain.py drand /tmp/onchain-drand.pact
```

Expected output, measured against mainnet on 2026-10-11, from `https://api.chainweb-community.org`
and again from `https://chainweb.eckowallet.com`:

```
IDENTICAL: the 49105 characters mainnet runs for `slots` are, character for character,
           deploy-bytes/slots.pact.
IDENTICAL: the 10324 characters mainnet runs for `drand` are, character for character,
           deploy-bytes/drand.pact.
```

**Why it is two scripts and not a `curl`.** A Pact command carries its own hash, the node checks
that hash against the exact command *bytes*, and re-serialising the JSON changes those bytes — so
the request has to be built and hashed in one place. `fetch-onchain.py` does that (blake2b-256,
base64url, unpadded) and nothing else.

**The comparison fails closed.** A truncated or failed fetch must never read as a pass, so
`compare-onchain.py` refuses to compare anything under a per-module size floor and says so. You
can check that yourself: run it against an empty file and it must refuse, and change one character
of the fetched file and it must report the character position where they diverge.

## 2. The annotated file you are reading is those bytes

`deploy-bytes/` is the `(module …)` region of what the deploy transactions sent. For `slots`, the
deploy transaction's code was `pact/modules/slots.pact` itself, byte for byte: a header, a
`namespace` line, a load-time check on the governance keyset, the module, and a `create-table`
footer. Only the module is stored on chain; the lines around it ran once, at deploy. This proves
the module in the file you read is the published bytes, so §1 reaches that file:

```bash
python3 .github/scripts/module-region.py --check
(cd deploy-bytes && sha256sum -c SHA256SUMS)
```

```
   ok   pact/modules/slots.pact's (module …) form IS deploy-bytes/slots.pact (49105 characters)
   ok   pact/modules/drand.pact's (module …) form IS deploy-bytes/drand.pact (10324 characters)
```

The slice is taken the way the engine takes it: from `(module <name>` to its matching close paren,
skipping parens inside strings and `;` comments. Comments are **inside** that region, which is why
they are on chain and why nothing inside the module form of either file is ever scrubbed —
including by this repository's own publication-hygiene check, which exempts both files by exact
path. (One line of `drand.pact`'s header, outside its module form and never stored on chain, named
an internal document and is rewritten here; the check above is unaffected by it.)

## 3. 🔴 For `slots`, do NOT verify by comparing module hashes — for `drand`, do

A Pact 5 module hash covers the module's **dependencies' hashes**, not only its own code.

- **`slots` depends on `coin`.** The test suite loads a vendored `coin` snapshot; mainnet runs a
  different `coin`. So a hash computed locally will **never** equal the hash mainnet reports, and a
  mismatch tells you nothing about the code. The hash on chain is
  `Ahc4KT2wIf17_U0WhoCRp2zNxFnHXpeh5T1VYk5awzs`; compare it with what `describe-module` reports if
  you like, but §1 is the check that means something.
- **`drand` depends on nothing.** It uses no other module, holds no table, and every function in
  it is pure. Its hash is therefore reproducible, and this one is worth running: build it in the
  REPL and you get `Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ`, which is exactly what mainnet
  reports **and** the literal `slots` pins in its `use`. `run-tests.sh` does this on every run.

To read either hash from the chain, add `--hash`:

```bash
python3 .github/scripts/fetch-onchain.py drand --hash
```

## 4. The tests pass on your machine, not just ours

Install [Pact 5.4ce](https://github.com/kda-community/pact-5), then:

```bash
cd pact/tests && ./run-tests.sh
```

Every suite is scored by **exit code**. This matters more than it sounds: a later hard error in a
Pact REPL suppresses earlier `FAILURE` lines, so a broken assertion can leave a transcript that
looks clean. Grepping for `FAILURE` is not a test result; an exit code is.

The runner also fails if `or`, `and` or `+` is ever given more than two operands, if any
`expect-failure` in the suites was written with too few arguments to say *why* it expected the
failure (that checker tests itself on a known sample first, so it cannot pass by scanning
nothing), if the frozen-module fixture is anything other than `slots` with its governance body
replaced, if the retuned-module fixture is anything other than `slots` with one machine's maximum
moved and its `create-table` footer removed, if the `drand` hash built here is not the one `slots`
pins, or if the published player terms leave out one of the figures §5 lists.

And it runs three files that **must exit 1, each for a named reason**. Exit code alone would not
be enough — any typo also exits 1 — so the refusal message is required too.

- `slots-pin-must-fail.repl` plants an impostor `drand` whose `verified-seed` accepts any
  signature and returns a seed the attacker chooses — and with it every reel — and `slots` must
  refuse to load with `hash not blessed`.
- `slots-open-round-must-fail.repl` defines a module that calls `slots.open-round`. A round is
  opened inside `bet`, so no such export exists, and loading must fail with
  `has no such member: open-round`. If the export ever came back, that file would load and the
  row would turn red.
- `slots-load-gate-must-fail.repl` loads `slots.pact` with no governance signature in scope, and
  it must stop at the file's own load-time check with `Keyset failure`. Every other suite loads the
  module with that key, so this is the only place the check is seen to bite.

## 5. The descriptions match the contract

[`docs/SLOTS-PLAYER-TERMS.md`](docs/SLOTS-PLAYER-TERMS.md) states numbers.
[`.github/scripts/check-player-terms.sh`](.github/scripts/check-player-terms.sh), which CI runs on
every push, checks 92 of its statements against `pact/modules/slots.pact`: the launch dials and
their floors and ceilings, the betting window, the beacon wait, the refund grace and the spin
limit, read straight out of the contract's constants; the rule that a board plays one machine,
read from the forms that enforce it, with the words a refused board is given; and, for each of the
six machines, its strip, its paytable, its return and house edge, how often it wins, its top prize,
its smallest win and its share of the table — **recomputed by the script** from the machine table
the contract holds: the line and wild machines by weighting every combination of three symbols,
tumble by playing all 262,144 windows, and free-spins from the exact fraction the contract pins
(which `slots-rules-testing.repl` reproduces). None of those figures is a number typed into the
script. If one of them changes in the source and the page does not, CI fails. It reads the source,
not the live chain: a setting the operator has changed since launch is not checked there, and the
two measurements on that page (the block-gap replay, the bankroll simulation) are pinned as
literals and are ours to keep right.

[`docs/SLOTS-WHAT-IT-DOES.md`](docs/SLOTS-WHAT-IT-DOES.md) is **generated**, not written by hand,
by a script in our private repository that reads the contract source, the verifier, the test
results and a manifest of which test backs which promise. That generator is not published, so from
here its ✅ marks are our claim rather than something you can re-run. Its header names the
generator and its source for exactly that reason. The checkable version is the player terms above,
plus the suites themselves. The copy here was regenerated on 2026-10-11, after the deployment, from
the same tagged source; its one remaining "not built" item is the lock (the contract is upgradeable by
design, as the terms say). For where it runs, trust
[`deployments/mainnet01-chain-2.md`](deployments/mainnet01-chain-2.md).

Read all of it against the module and tell us if you find a sentence the code does not support.

---

## What was deployed, and who holds the keys

Every transaction, with its request key, its gas and the on-chain reading that confirmed it, is in
[`deployments/mainnet01-chain-2.md`](deployments/mainnet01-chain-2.md).

Two keysets matter, and both are readable from any node:

```lisp
(describe-keyset "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots.get-params)
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots.pot-status)
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots.machines)
(at 'hash (describe-module "n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand"))
```

`n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov` is `slots`'s GOVERNANCE, predicate `keys-2`
over three keys — **two of the three governance keys** sign anything it gates: an upgrade, the
freeze, `initialize`, `set-params`, and withdrawing the pot's spare capital. There is no one-key
path to any of them. The same keyset also governs the namespace, so nobody else can ever define a
module under these names.

`get-params` returns the dials, where the fee goes, the round counter and the newest beacon the
contract has seen. `pot-status` returns the pot's balance, what is reserved against open rounds,
what is spare, the fee scale right now, the minimum per spin, the most spins a board may hold, and
`max-stakes`: for each machine, the largest board total `bet` accepts at that moment. `machines`
returns every machine as it is played — strip, paytable, exact return and edge, top prize. `drand`
has no keyset at all: its governance is `(enforce false)`.

**The exception to everything above.** While `slots` is not frozen, those same two keys hold
*module admin*, so one transaction can move the pot or rewrite any stored record — a round's
terms, a board, where the fee goes — with no new code. Such a transaction leaves the module hash
and the §1 check unchanged; it is visible only as a transaction signed by two of those keys.
Freezing ends it permanently, and `pact/tests/slots-frozen-testing.repl` runs the whole lifecycle
against a frozen copy to prove the freeze changes that and nothing else.

---

## What none of this proves

- **Not that the contract is correct.** It proves the code you can read is the code that runs, and
  that its own tests pass. Tests encode what their author believed.
- **Not that the tests are strong.** A green suite is a floor, not a ceiling. Read them.
- **Not that drand is honest.** It proves the contract verifies a real drand signature for a round
  it pinned before betting closed, and spins the reels from it by the rules the suites check.
  drand's own threshold assumptions are drand's.
- **Not that the operators are trustworthy.** It proves what the *code* can and cannot do. While
  `slots` is not frozen, its 2-of-3 keyset can replace it or override it directly, and §1
  cannot see a direct override — it changes records, not code. That is stated in the README rather
  than hidden, and freezing is what ends it.
- **Not anything about a chain you did not query.** If you use our node URL and we lie to you, you
  have verified our lie. Use a node you trust, or run one.
