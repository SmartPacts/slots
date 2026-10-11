# Slots — six machines on public reel strips, spun by a number that did not exist when the bets closed

A Pact 5 smart contract for Kadena. Six slot machines share one contract and one pot. A round
opens the moment somebody places the first board, takes boards for a fixed window, and every spin
of every board in it is then decided by one random number produced by the **drand** beacon — a
group of independent organisations **outside Kadena entirely** — whose signature this contract
verifies on chain. **One signed transaction per player:** you place a board — one machine, a stake
per spin and 1 to 77 spins — and that is all you sign. The house sends no transaction inside a
round and holds no secret.

> ## 🟢 DEPLOYED — Kadena mainnet (mainnet01)
>
> - Namespace `n_48867b242317a0216a67f8c7ca26696b5878e0e3`, **chain 2**, two modules:
>   `slots` (hash `Ahc4KT2wIf17_U0WhoCRp2zNxFnHXpeh5T1VYk5awzs`) and the beacon verifier
>   `drand` (hash `Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ`), the same verifier the roulette
>   and baccarat tables already use.
> - The code on chain is **character for character** the files in `deploy-bytes/`, which are in
>   turn the `(module …)` form of the annotated files in `pact/modules/` — comments and all.
>   Check both yourself with [`VERIFY.md`](VERIFY.md); it takes about a minute.
> - 🔴 **`slots` is not frozen.** Until it is, any **2 of the 3 governance keys** hold *module
>   admin*: in one transaction, with no new code and no change to the module hash, they can move
>   the pot and rewrite any record the contract keeps. They can also publish a new version.
>   Freezing ends all of that; it has not happened. **`drand` is already sealed** — its governance
>   is `(enforce false)` and it can never be upgraded.
> - **Nothing is for sale here.** This repository is source code.

Every transaction that built this deployment, with its request key and the reading that confirmed
it, is in [`deployments/mainnet01-chain-2.md`](deployments/mainnet01-chain-2.md).

## Which file am I reading?

| | |
|---|---|
| `pact/modules/slots.pact` | 🔴 **THE DEPLOYED CONTRACT, annotated.** This file, byte for byte, is the code the deploy transaction sent. Its `(module …)` form, comments and all, is the code stored on mainnet. The lines around it — header comments, the `namespace` line, a load-time check on the governance keyset and the `create-table` footer — ran once, in the deploy transaction, and are not stored. |
| `pact/modules/drand.pact` | 🔴 **THE DEPLOYED BEACON VERIFIER**, annotated the same way: its `(module …)` form, comments and all, is the code stored on mainnet. Sealed on chain: it can never be upgraded. It was deployed once, for roulette, and slots uses that same module. One line of its header — outside the module form, never stored on chain — named an internal document and is rewritten here. |
| `deploy-bytes/` | exactly what the deploy transactions sent, sliced out of their own `cmd`. This is what `describe-module` returns today. It is *derived* from the files above, and CI re-derives it. |
| everything else | tests, vendored dependencies, the helper anyone can run, and the documents about all of it |

Nothing else in this repository deploys. `pact/modules/slots.pact` is kept exactly as it was
deployed, comments included, and the module form of both files is never touched, so a comment
inside a module is never corrected in place.

## What is in here

```
pact/modules/     the two contracts
pact/tests/       eleven suites and three inverted controls that must FAIL; run-tests.sh runs
                  everything, including the gates
pact/vendor/      Kadena's coin + fungible interfaces, so the suite runs with no network
                  (not ours — see NOTICE)
deploy-bytes/     the exact bytes the deploy transactions carried, plus their sha256
deployments/      every mainnet transaction, with its request key and what confirmed it
docs/             SLOTS-PLAYER-TERMS.md — the rules and everything that can go wrong, 92 of its
                  statements checked by CI against the contract source (VERIFY.md §5);
                  SLOTS-WHAT-IT-DOES.md — the same in plain language, GENERATED from the contract
                  and the test results (VERIFY.md §5; this copy predates the deployment)
crank/            the helper that settles rounds and pays every board. Permissionless: it holds
                  no privilege, and anyone can run one
verification/     the recorded identity of the deployed artifact
.github/          the static gate, the checkers, and the CI that runs all of it on every push
```

## Run the tests yourself

Needs [Pact 5.4ce](https://github.com/kda-community/pact-5) on your PATH (or `PACT=/path/to/pact`)
and `python3`.

```
cd pact/tests && ./run-tests.sh
```

That is the same command CI runs, with no reduced subset — a CI that runs less than you do teaches
you to trust a green tick that means less than you think. It runs the static gate over every
source file, checks that `or`, `and` and `+` are always given exactly two operands (Pact 5 refuses
more only when the line runs), checks that no `expect-failure` was written with too few arguments
to assert *why* something failed, proves the annotated modules are the published deploy bytes,
proves the frozen-module and retuned-module fixtures are this module with one substitution each,
proves the `drand` hash `slots` pins is the `drand` in this repository, proves the published terms
state the contract's own constants and its machines' own odds — and then runs the eleven suites,
scoring each by **exit code** rather than by grepping the transcript.

It also runs three files that **must fail**, each scored on the exit code *and* on the refusal
message, because any unrelated breakage also exits 1:

- `slots-pin-must-fail.repl` plants an impostor `drand` that "verifies" every signature and
  returns a seed — and so the reels — of the attacker's choosing, and `slots` must refuse to load
  against it.
- `slots-open-round-must-fail.repl` names an `open-round` export. A round is opened by the first
  board and by nothing else, so the module has no such export, and a module that calls one must
  fail to load.
- `slots-load-gate-must-fail.repl` loads the contract with no governance signature, and it must
  stop at the file's own load-time keyset check: only the governance keys can install or upgrade it.

## How the reels stop

When a round opens, the contract computes a drand round number a fixed wait after betting closes
and pins it into the round. That beacon **does not exist while a board can still be placed** —
not to a player, not to a miner, not to the operator. When it is published, **anyone** may submit
it: the contract checks the BN254 pairing itself, so a forged one cannot verify, and drand values
never expire, so there is no capture window to miss and nothing to gain from staying silent.

**Every reel is public arithmetic.** Each machine has one strip of 64 stops, the same on all three
reels, and the strips are constants in the module. A spin's three stops are three 6-bit slices of
one BLAKE2b hash of the round's seed, the board's account and the spin's number, so each stop is
one of the 64 with exactly equal chance, each account's reels are its own, and anyone can
recompute every reel of every board once the beacon is public. A strip shows its true neighbours:
a symbol appears one stop above or below the line exactly as often as it appears on it.

**Why not a Kadena block hash.** Whoever mines the deciding block would see the reels before
publishing it and could throw the block away and keep mining — a free re-roll. Combining several
future blocks does not help, because the first N−1 already exist when the last is mined. drand is
produced off Kadena, so no Kadena miner touches it.

## The machines

Each machine's return is exact — worked out over every possible spin, not estimated — and pays
are gross, stake included. Every win on every machine pays more than the spin's stake.

| machine | what it is | top prize | player return | house edge |
|---|---|---:|---:|---:|
| 0 classic | one line; sevens, bars, bells, cherries, any three high | 40× | 95.9961% | 4.0039% |
| 1 easy | the classic paytable reshaped to win often and small | 18× | 95.9961% | 4.0039% |
| 2 big | the classic paytable reshaped to win rarely and large | 250× | 95.9961% | 4.0039% |
| 3 wild | two wilds that stand in for a symbol and double the win they complete | 40× | 96.0083% | 3.9917% |
| 4 free-spins | four scatters; a scatter in each reel's window awards 8 free spins at 2× their line, retriggering up to 24 | 100× | 96.4789% | 3.5211% |
| 5 tumble | a three-stop window, five lines, winning cells vanish and the strip falls in, up to 5 cascades | 112.6× | 95.9521% | 4.0479% |

The strips, paytables and top prizes are constants: no setting reaches them.
[`docs/SLOTS-PLAYER-TERMS.md`](docs/SLOTS-PLAYER-TERMS.md) has every strip, every paytable and
every hit rate, and CI recomputes all of them from the contract.

## The dials the operator holds, and their bounds

`set-params` is the only setter, it is gated on the governance keyset, and it reaches **future
rounds only**: a round that has opened keeps the share, the minimum, the window and the beacon it
was given. The bounds below are constants in the module and cannot be widened by any call.

| dial | today | bound in the code |
|---|---|---|
| share of the spare pot one round may risk | 2% | greater than 0, at most 100% — a round cannot risk more than the whole spare pot |
| minimum stake per spin | 0.01 KDA | never below 0.001 KDA; no ceiling |
| target float (where the fee stops ramping) | 30,000 KDA | must be positive. The one dial read live: a change moves the fee of later boards in an open round |
| betting window | 30 s | 30 s to 1 hour |
| wait between close and beacon | 120 s | never below 120 s, never above 1 hour |

The dials are day-to-day settings, not upgrade authority: they are gated on a separate
capability from the one a freeze removes, so they stay the operator's after the contract is
frozen, inside the same bounds.

Three things are **not** dials and no key can move them: the machines (their strips, paytables
and top prizes), the 77-spin limit on a board, and the fee ceiling. The fee is paid out of the pot
— it never touches a player's stake — at the machine's own house edge on what was staked on it,
scaled by `min(1, available / target-float)`, so the pot fills to its target and then forwards the
whole edge. The edge is the immutable ceiling, because charging more would give the pot negative
drift.

## What this contract's code does not do

Every line below describes the deployed code. Until `slots` is frozen, the governance keys can
override any of it (the box at the top).

- **It cannot steer a reel.** No function lets anyone choose a stop; every spin comes from a drand
  signature the contract verifies, and a wrong signature does not verify.
- **It cannot settle from a different verifier.** `slots` pins `drand` by hash, so it refuses to
  load against any other code under that name. `slots-pin-must-fail.repl` is that proof.
- **It cannot move a board to another machine.** A board names its machine when it is placed, and
  it is settled on that machine whoever settles it. A board plays one machine, and one account
  places one board a round.
- **It cannot run short.** Before accepting a board it reserves every one of its spins paying its
  machine's top prize, and the round limit counts every board together. It can only refuse a
  board, never fail to pay one; each settled board releases exactly what it reserved, win or lose,
  even across an upgrade.
- **It does not leave a board too heavy to settle.** Every spin of a board is played in its one
  settlement, so the 77-spin limit is set by gas: the heaviest claim the suite can build on any
  machine stays under 110,000, and an upper bound worked out from the heaviest per-spin cost of
  every machine is 114,598 on free-spins, the heaviest — both inside the 150,000 a transaction may use. Proof round 3 on
  mainnet settled a 77-spin free-spins board in one transaction.
- **It does not make a loser send a transaction.** A losing board is settled like any other, and
  its reserve is released by that settlement.
- **It does not strand a round whose beacon never arrives.** After 90 days a round nobody could
  settle can be refunded, and every stake comes back.
- **Settling is nobody's privilege.** Submitting the beacon and settling a board are calls anybody
  can make, and the caller gets no say in the outcome. That is why a bot can do it — see
  [`crank/`](crank/), which is here so that anyone can run one.

## Reporting a problem

See [SECURITY.md](SECURITY.md) — open a **GitHub security advisory** on this repository.

## Licence

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
