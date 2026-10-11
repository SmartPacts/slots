# Deployment — Kadena mainnet01, chain 2

Every line here is on chain. Each request key links to a public explorer; each row says what the
transaction did and the read-only call that confirms it today. Nothing in this file is a claim you
have to take from us — the calls are free, need no key, and can be run against any node.

Where a row says "read back 2026-10-11", we ran that call on that date against **both**
`https://api.chainweb-community.org` and `https://chainweb.eckowallet.com` (both reporting
`nodePackageVersion` 3.2), and the two answers agreed. Every request key's gas, block and result
below was read from both nodes' `/poll` on that date — except the `drand` deploy of 2026-09-22,
which the community node's `/poll` no longer returns; its row is the eckowallet node's answer.

**Who signs.** Everything gated on governance was signed by **two of the three governance keys**
(`n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov`, predicate `keys-2`), plus a separate key
that only pays gas. There is no one-key path to any of it.

---

## 1. The contract

| date | what it did | request key | gas | block | confirmed by |
|---|---|---|---:|---:|---|
| 2026-09-22 | deploy `drand`, the beacon verifier — sealed at deploy, `(enforce false)` governance. Deployed for the roulette table; slots deployed no verifier of its own and uses this one | [`niHtcnxu0iN8eFWCZjAtZ_sK1H6GpNrXc5bCK8hznqI`](https://explorer.chainweb-community.org/mainnet/tx/niHtcnxu0iN8eFWCZjAtZ_sK1H6GpNrXc5bCK8hznqI) | 16,943 | 7252453 | `describe-module` returns exactly `deploy-bytes/drand.pact`, 10,324 characters, module hash `Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ` — the same hash `slots` pins, and the same one you get building `pact/modules/drand.pact` locally. Read back 2026-10-11 |
| 2026-10-11 | deploy `slots` and create its three tables | [`XUYTKgx6t9djEwJbbJVvJ0lIRYRmluxb8MEE_M2T53E`](https://explorer.chainweb-community.org/mainnet/tx/XUYTKgx6t9djEwJbbJVvJ0lIRYRmluxb8MEE_M2T53E) | 81,148 | 7306407 | result `TableCreated`; `describe-module` returns exactly `deploy-bytes/slots.pact`, 49,105 characters, module hash `Ahc4KT2wIf17_U0WhoCRp2zNxFnHXpeh5T1VYk5awzs`, on both nodes — see [VERIFY.md](../VERIFY.md) §1. Read back 2026-10-11 |

The `cmd` of the `slots` deploy transaction carries the code that was sent: it is, byte for byte,
the file `pact/modules/slots.pact`. `deploy-bytes/slots.pact` is the `(module …)` region sliced out
of that `cmd`, and CI proves it is still the module in `pact/modules/`. On 2026-10-11 the code
`describe-module` returned from the community node, the code it returned from the eckowallet node
and `deploy-bytes/slots.pact` had one and the same sha256:

```
a64d3c3d8183344f9a9efc5463f2854db420e167bb8bc37b8dc8f5625b7a9df4  deploy-bytes/slots.pact
```

## 2. Setting it up

| date | what it did | request key | gas | block | confirmed by |
|---|---|---|---:|---:|---|
| 2026-10-11 | `initialize` — names where the fee goes, once, and sets the target float | [`cjrXWhm7xx_b9Q8TY1FcaIVx5rNTFxzYCMs-ALZit40`](https://explorer.chainweb-community.org/mainnet/tx/cjrXWhm7xx_b9Q8TY1FcaIVx5rNTFxzYCMs-ALZit40) | 322 | 7306419 | result `slots initialized`, event `INITIALIZED` naming `m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT:SPT-funding`; `(get-params)` → that `revenue`, `target-float: 30000`. Read back 2026-10-11 |
| 2026-10-11 | `fund-house` — 15,000 KDA into the pot, from `r:n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov` | [`9KAtMeULHxxIITBkOAmbLKoE11ZorJXC77TZHmxOIr8`](https://explorer.chainweb-community.org/mainnet/tx/9KAtMeULHxxIITBkOAmbLKoE11ZorJXC77TZHmxOIr8) | 305 | 7306431 | result `house funded`, event `HOUSE-FUNDED` (`r:…spt-gov`, 15000) |

The pot is `m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots:slots-pot`, a module-guarded
account: no key holds it directly (`(house-account)` returns that name). It was funded from the
company account `r:n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov`.

## 3. Where the capital came from

The pot's 15,000 KDA is SPT sale proceeds, which live on **chain 0**. Moving them to chain 2 took
a 1 KDA rehearsal and then the real transfer, all on 2026-10-11. A cross-chain transfer's request
key names the chain-0 half; its second half lands on chain 2, and both were completed there by the
public cross-chain relayer, which pays that half's gas (`kadena-xchain-gas`). The company account
read 15,000.1 KDA on chain 2 before `fund-house`; it reads 0.1 today (read back 2026-10-11).

| chain | what it did | request key | gas | block | result |
|---|---|---|---:|---:|---|
| 0 | 1 KDA rehearsal withdrawal from the sale proceeds | [`eb6Sr6IuRzsoJ1uxPDP5dz1IPKMTk92ZYyKHzJY_4-k`](https://explorer.chainweb-community.org/mainnet/tx/eb6Sr6IuRzsoJ1uxPDP5dz1IPKMTk92ZYyKHzJY_4-k) | 309 | 7306355 | `proceeds withdrawn` — 1 KDA to `r:…spt-gov` |
| 0 | 1 KDA cross-chain rehearsal, chain 0 → 2 | [`sI4NAzSAAYam244JestWeb9um8CUCYpX0_rSGmhHAH8`](https://explorer.chainweb-community.org/mainnet/tx/sI4NAzSAAYam244JestWeb9um8CUCYpX0_rSGmhHAH8) | 344 | 7306363 | 1 to `r:…spt-gov`, source chain 0, target chain 2 |
| 2 | its second half, completed by the public relayer | [`mYYWG6eTiSneK-oGBRs66EoBMYBqxlwVcfPQzF7X9Aw`](https://explorer.chainweb-community.org/mainnet/tx/mYYWG6eTiSneK-oGBRs66EoBMYBqxlwVcfPQzF7X9Aw) | 319 | 7306367 | `TRANSFER_XCHAIN_RECD` — 1 to `r:…spt-gov` |
| 0 | 14,999 KDA withdrawal from the sale proceeds | [`k22EGeCQFMXSA98tWOnJ_sIhh6pfLdZE0lfoPTUYNFo`](https://explorer.chainweb-community.org/mainnet/tx/k22EGeCQFMXSA98tWOnJ_sIhh6pfLdZE0lfoPTUYNFo) | 309 | 7306374 | `proceeds withdrawn` — 14,999 KDA to `r:…spt-gov` |
| 0 | 14,999 KDA cross-chain, chain 0 → 2 | [`GHlHoT_wkM8-PWLH4LC2O7vrRxUdQaDcVrPm96vDKvc`](https://explorer.chainweb-community.org/mainnet/tx/GHlHoT_wkM8-PWLH4LC2O7vrRxUdQaDcVrPm96vDKvc) | 344 | 7306382 | 14,999 to `r:…spt-gov`, source chain 0, target chain 2 |
| 2 | its second half, completed by the public relayer | [`e9DnSXY-3YsTKw0QvGycMduQft4W-wBv_emq846w8RE`](https://explorer.chainweb-community.org/mainnet/tx/e9DnSXY-3YsTKw0QvGycMduQft4W-wBv_emq846w8RE) | 320 | 7306386 | `TRANSFER_XCHAIN_RECD` — 14,999 to `r:…spt-gov` |

**The helper accounts.** Two bot accounts were funded 5 KDA each, on chain 2, both in block
7306546 at 235 gas each:
[`NukUMU5jW4R8r0dP2zM-piYKN6q__gHUN5seH2LwNR0`](https://explorer.chainweb-community.org/mainnet/tx/NukUMU5jW4R8r0dP2zM-piYKN6q__gHUN5seH2LwNR0)
and
[`FGX8DEmuC6e-4IyfcaEGFxqQ82PbtmgIcHApUTztwMw`](https://explorer.chainweb-community.org/mainnet/tx/FGX8DEmuC6e-4IyfcaEGFxqQ82PbtmgIcHApUTztwMw).
They are `k:f2be0b38ee4b878b5302aa269e2a9d73e767d8ee6244de2c642a17979948d5a5` and
`k:9afcbe3d0d837127ea30363d3b6e61129afbc1d4fd32e9c4d6551ff9822314cb`. They hold **no privilege
the contract recognises**: they pay gas to submit beacons and to settle boards, which is something
anyone may do. Their 5 KDA is gas money, not house money, and it is not in the pot. On
2026-10-11, after the proof rounds below, the first read 4.99982748 KDA (it sent every helper
transaction below) and the second read 5 (it had sent nothing yet).

**How the helpers are sized.** Each runs `crank/game-crank.mjs` with `CLAIM_GAS=125000` and
`CLAIMS_PER_TX=1`: one board per settlement transaction, asking for 125,000 × 1 + 2,000 = 127,000
gas, which covers the heaviest board the contract allows (see `crank/slots.env.example`). The
helpers run the tarball `slots-crank-bd66035348fe.tar.gz`,

```
95e8382f75dff3de1c9626757df17a9a4a0147347fd4e1af7c62b0fce9ed9c72  slots-crank-bd66035348fe.tar.gz
```

packed from our private repository at the commit the deployed module was tagged from; packing that
commit again on 2026-10-11 reproduced the same sha256. That tarball is not published. Its
`game-crank.mjs` is the program in `crank/` here with six lines different, in five places: a
comment and a log string that cite an internal design document, an error message that names the
private repository's path to the example settings file, a two-line comment that named a monitoring
service, and the key-file interlock, which there refuses a key under the private repository's
directory and here refuses one under any directory named `crank` or `slots-public`. Its
`slots.env.example`, `crank.env.example` and `game-crank.service` differ from the copies here in
comments only, its `provision-game-crank.sh` in comments and the wording of one progress message,
and its `pack-crank.sh` packs the private tree's path instead of
`crank/`. The tarball also carries the roulette table's own helper files, which this table does not
use.

## 4. Proving it works, with real money

Three rounds, played by test accounts of ours at the minimum stake, with every settlement sent by
the helper. Each round's fee was read from its `FEE-PAID` event, and equals the `fee-owed` the
round carried before it was dealt.

| date | what it did | request key | gas | block | confirmed by |
|---|---|---|---:|---:|---|
| 2026-10-11 | the helper's first liveness proof, before any round: it records drand round 21405529 as seen | [`5gYfTyn2trbtSSd2cx-gYGptD7CLhSMwYr97umhOr8g`](https://explorer.chainweb-community.org/mainnet/tx/5gYfTyn2trbtSSd2cx-gYGptD7CLhSMwYr97umhOr8g) | 1,744 | 7306551 | event `LIVENESS-PROVEN` 21405529 |
| 2026-10-11 | **proof round 1** — one spin of 0.01 KDA on machine 0 (classic), which opens round 1 and pins drand round 21405614 | [`O_SxScdVE0aqNW8QRF7nO4WoEriWBP01lp17xEWoMqk`](https://explorer.chainweb-community.org/mainnet/tx/O_SxScdVE0aqNW8QRF7nO4WoEriWBP01lp17xEWoMqk) | 764 | 7306555 | result `bet placed in round 1`; events `ROUND-OPENED` (round 1, beacon 21405614) and `BET-PLACED` |
| 2026-10-11 | round 1 resolved by the helper from drand round 21405614; the same transaction pays the round's fee, 0.000200195312 KDA, to `m:…SPT:SPT-funding` | [`DZMjPXa_ubS627BhmFVGlvpwvbs8Fge4ccG9ZXDlMew`](https://explorer.chainweb-community.org/mainnet/tx/DZMjPXa_ubS627BhmFVGlvpwvbs8Fge4ccG9ZXDlMew) | 2,223 | 7306560 | events `FEE-PAID` (round 1, 0.000200195312) and `ROUND-RESULT`; `(get-round 1)` → `"resolved"`, `fee-owed` 0 |
| 2026-10-11 | round 1's board settled by the helper: stops 21 42 31, 2 units, **paid 0.02 KDA** to the account that placed it | [`Hb14kcECFe0owhYEd8t4Ce4F6ItrMAZ4K4qugqYXpvA`](https://explorer.chainweb-community.org/mainnet/tx/Hb14kcECFe0owhYEd8t4Ce4F6ItrMAZ4K4qugqYXpvA) | 582 | 7306561 | result `paid 0.020000000000`; events `SPINS-SETTLED`, `CLAIMED`; `(get-round 1)` → `liability` 0 |
| 2026-10-11 | **proof round 2** — a fresh account, `k:6fc8d876…`, is sent 0.25 KDA | [`_WkSk5j-2wm-yU8lEEZxTJTARe4ZkLCrhNX85-4oPKk`](https://explorer.chainweb-community.org/mainnet/tx/_WkSk5j-2wm-yU8lEEZxTJTARe4ZkLCrhNX85-4oPKk) | 237 | 7306563 | `TRANSFER` 0.25 to it |
| 2026-10-11 | it places 20 spins of 0.01 KDA on machine 1 (easy), which opens round 2 and pins drand round 21405708 | [`57Z_WRhaHt5U-cnVYiMmKZDDQJFWE9rYSBy3MU3GZuo`](https://explorer.chainweb-community.org/mainnet/tx/57Z_WRhaHt5U-cnVYiMmKZDDQJFWE9rYSBy3MU3GZuo) | 804 | 7306565 | result `bet placed in round 2`; `ROUND-OPENED` (round 2, beacon 21405708) |
| 2026-10-11 | it is swept to **exactly 0 KDA** by an ordinary coin transfer whose gas another key paid, and signs nothing further | [`lcrhVGw_vEm8j2JuUORyusI8RcITRJDaqrcy863iL5U`](https://explorer.chainweb-community.org/mainnet/tx/lcrhVGw_vEm8j2JuUORyusI8RcITRJDaqrcy863iL5U) | 284 | 7306567 | `TRANSFER` of its remaining 0.04999196 KDA away |
| 2026-10-11 | round 2 resolved by the helper from drand round 21405708; fee 0.004003903527 KDA | [`gWShw5dCgLylV1tZ3S8R9gByItvYS4IiU4--CIUNQlY`](https://explorer.chainweb-community.org/mainnet/tx/gWShw5dCgLylV1tZ3S8R9gByItvYS4IiU4--CIUNQlY) | 2,222 | 7306570 | events `FEE-PAID` (round 2, 0.004003903527) and `ROUND-RESULT` |
| 2026-10-11 | round 2's board settled by the helper: 20 spins, 20 units, **paid 0.2 KDA** to an account that held 0 KDA and signed nothing | [`FNGZPME9164NokwnZrC0q_0iPAh8TZKNYr0IQ4xNMRA`](https://explorer.chainweb-community.org/mainnet/tx/FNGZPME9164NokwnZrC0q_0iPAh8TZKNYr0IQ4xNMRA) | 1,410 | 7306572 | result `paid 0.200000000000`; `(round-boards 2)` → `claimed` true, `payout` 0.2; `(coin.get-balance "k:6fc8d876faff8a14b0f16e8591d803f8a32fbd05e30b5f7223abe234b518db31")` = 0.2 (read back 2026-10-11) |
| 2026-10-11 | **proof round 3** — the heaviest board the contract allows: 77 spins of 0.01 KDA on machine 4 (free-spins), which opens round 3 and pins drand round 21405804 | [`RmNd7MbqiuInQXDhiGK8qFiWQkW1y3cqQ5256FlO8SA`](https://explorer.chainweb-community.org/mainnet/tx/RmNd7MbqiuInQXDhiGK8qFiWQkW1y3cqQ5256FlO8SA) | 804 | 7306575 | result `bet placed in round 3`; `BET-PLACED` (stake 0.77, reserve 77.013556324993) |
| 2026-10-11 | round 3 resolved by the helper from drand round 21405804; fee 0.013556324993 KDA | [`wNbGjyD0Hy86GcNHGFQ3ldg-r27hTRYmYrTrejO_mho`](https://explorer.chainweb-community.org/mainnet/tx/wNbGjyD0Hy86GcNHGFQ3ldg-r27hTRYmYrTrejO_mho) | 1,781 | 7306581 | events `FEE-PAID` (round 3, 0.013556324993) and `ROUND-RESULT` |
| 2026-10-11 | round 3's board settled by the helper in **one transaction** holding that claim alone, with a 127,000 gas limit: all 77 spins played, 52 units, **paid 0.52 KDA** | [`XCMgU1XP2R_zc7cGRprNxLEdmm9tD0qPhr_bmX3ApnE`](https://explorer.chainweb-community.org/mainnet/tx/XCMgU1XP2R_zc7cGRprNxLEdmm9tD0qPhr_bmX3ApnE) | 7,290 | 7306582 | result `paid 0.520000000000`; events `SPINS-SETTLED`, `CLAIMED`; `(get-round 3)` → `liability` 0 |

After the three rounds the pot reads **15,000.222239576168 KDA** and `reserved` 0 (read back
2026-10-11): 15,000, plus the 0.98 KDA staked, minus the 0.74 KDA paid to the three boards, minus
the 0.017760423832 KDA of fees that left for `m:…SPT:SPT-funding`. Every settlement above was sent
by the helper `k:f2be0b38…`; the test accounts signed only their own bets.

## 5. The dials at launch

No `set-params` has been sent. The dials are the launch values `initialize` wrote:

`(get-params)` → `reserve-fraction: 0.02`, `min-bet: 0.01`, `target-float: 30000`,
`bet-window: 30`, `drand-margin: 120`. Read back 2026-10-11. The contract's own constants, which
no dial moves: `MAX-SPINS` 77, and a board plays one machine.

Every future change to them will be a row here, with its transaction. A change reaches **future
rounds only**: a round that has already opened keeps the share, the minimum, the window and the
beacon it was given. The one figure read live is the target float, which moves the fee of later
boards in a round that is still open.

---

## Reading it yourself

```lisp
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots.get-params)
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots.pot-status)
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots.machines)
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots.get-round 1)
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots.round-boards 2)
(coin.get-balance "m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots:slots-pot")
(describe-keyset "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")
```

All read-only, all free, from any node on mainnet01 chain 2 — with `/local`, with Chainweaver, or
with `.github/scripts/fetch-onchain.py` as a worked example of building the request.
