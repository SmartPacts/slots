# The helper — anyone can run one

`game-crank.mjs` is a small Node program that keeps rounds moving. One process serves one game,
named by `CRANK_MOD`; for this table that is `n_48867b242317a0216a67f8c7ca26696b5878e0e3.slots`.
It holds **no privilege the contract recognises**. Every call it makes is one anybody may make:

| call | what it does | who may send it |
|---|---|---|
| `resolve` | submits a round's drand beacon; the contract verifies the BN254 signature itself and fixes the round's seed from it | anyone |
| `prove-liveness` | records that a newer beacon exists, which is what stops a pending round drifting toward its 90-day refund | anyone |
| `claim` | settles a board — plays every one of its spins and pays what it won **to the account that placed it**, whoever sends the transaction. A board that won nothing is settled the same way, which releases what the pot reserved for it | anyone |

It signs `coin.GAS` and nothing else. **A stolen crank key buys its holder the ability to pay
somebody else's gas.** It cannot choose a reel, cannot touch the pot, and cannot be paid by the
contract: the fee goes to the treasury account inside `resolve`, so there is nothing to redirect.

The house runs two of these because the house is the party with the standing reason to, not
because it is the only party who may. **If every one of ours is down, nothing is lost and nothing
expires**: a player can settle their own board, anyone at all can settle it for them, drand
values never expire, and the first pass after a restart settles every board still outstanding.
Payment is delayed, never forfeited.

That is also the whole mechanism behind "you need no KDA to be paid": the promise is kept by a
**process**, not by the module. Stating it the other way round would be dishonest.

## Why more than one is worth running

The module cannot tell "the beacon is unobtainable" from "nobody fetched it" — a beacon that is
never fetched is indistinguishable on chain from one that does not exist. So a round can reach its
refund after 90 days of total silence, and because the refund is round-level it would also strip a
passive winner back to their stake. **One `prove-liveness` call carrying any newer beacon protects
every pending round at once.** The duty is one call per ninety days, not one per round.

Two instances collide harmlessly: the loser of the race is refused with "a later beacon is already
on record", or finds the round already settled, which is the module saying the record is already
current. To keep that loser from paying for a send that cannot land, set `CRANK_FOLLOWER_MS` on
one of a pair (below): it then waits that long after a round becomes actionable before it even
dry-runs, and by then the other's send has landed.

## Slots needs its claim sizing

A slots claim plays every spin of the board — up to 77 — so its gas depends on the machine and the
spins, and the heaviest board allowed (free-spins, every spin playing all 24 free spins) was
bounded at 108,425 gas on a node. The program budgets a batch at `CLAIM_GAS` × its members +
2,000, and a batch that runs out of gas is retried every pass, so **`game-crank.mjs` refuses to
start slots with `CLAIM_GAS` below 125,000**, and refuses any `CLAIM_GAS` × `CLAIMS_PER_TX` +
2,000 above the 150,000 a transaction may use. [`slots.env.example`](slots.env.example) carries
the setting the house runs: `CLAIM_GAS=125000`, `CLAIMS_PER_TX=1`. Only the gas used is billed, so
the cost of that headroom is more transactions per round, not more KDA. Proof round 3 in
[`../deployments/mainnet01-chain-2.md`](../deployments/mainnet01-chain-2.md) is a 77-spin
free-spins board settled this way, in one transaction.

## Running one

You need Node (the provisioner installs v24.21.0; that is the version it is run on) and a clone of
this repository. Everything below runs from inside `crank/`.

```bash
cd crank
npm ci                                             # installs the pinned dependencies from package-lock.json
node crank-keygen.mjs "$HOME/slots/crank-key.json"
```

`crank-keygen.mjs` takes one argument, the path of the key file to write. It creates the directory
if needed, writes the file with mode 0600, prints the public key and the `k:` account, and refuses
to overwrite a file that already exists. Keep that file outside the checkout, and send its account a
little KDA on the chain the crank will use: every call it makes costs gas.

The program reads **environment variables and nothing else**. `crank.env.example` and
`slots.env.example` are written for systemd, which reads `/etc/<game>/crank.env` through the
unit's `EnvironmentFile=`; the program itself never opens that file. By hand, put the settings on
the command line, replacing the three values in angle brackets with your own (see the devnet
paragraph below):

```bash
GAME=slots \
CLAIM_GAS=125000 CLAIMS_PER_TX=1 \
CRANK_BOT_KEY="$HOME/slots/crank-key.json" \
CRANK_HOST=<your node's URL> \
CRANK_NETWORK=<its network id> \
CRANK_MOD=<the module you deployed> \
node game-crank.mjs --once
```

`--once` makes one full pass and then exits. It is **not** a dry run: it sends every transaction
that pass calls for — a resolve, the boards' settlements, a liveness proof. Without `--once` it
repeats the pass every `POLL_MS` until stopped.

| setting | default in the code | what it is |
|---|---|---|
| `GAME` | none, required | the game's short name; it labels the log, and for `slots` it turns on the claim-sizing floor |
| `CRANK_MOD` | none, required | the module it drives. There is deliberately no default, so a process can never fall back to another game's table |
| `CRANK_BOT_KEY` | none, required | path to the key file `crank-keygen.mjs` wrote |
| `CRANK_HOST` | `http://localhost:8095` | the node it reads from and sends to |
| `CRANK_NETWORK` | `recap-development` | the network id; `mainnet01` turns on the interlocks below |
| `CRANK_CHAIN` | `2` | the chain the module lives on |
| `CRANK_MAINNET` | unset | must be `armed` when the network is `mainnet01` |
| `CRANK_MIN_BALANCE` | `1` | KDA the bot's own account must hold for the heartbeat to be sent (below it, the heartbeat is withheld and the log says why) |
| `CRANK_FOLLOWER_MS` | `0` (the leader) | how long a follower waits after a round becomes actionable before it acts; set `90000` on exactly one machine of a pair |
| `HEARTBEAT_URL` | empty (off) | a URL it requests after every pass that read the chain |
| `POLL_MS` | `15000` | milliseconds between passes |
| `LIVENESS_MS` | `21600000` (6 h) | how old the on-chain liveness record may get before it is refreshed |
| `CLAIMS_PER_PASS` | `400` | the most claims one pass sends |
| `CLAIMS_PER_TX` | `40` | claims per transaction; anything above 120 is capped at 120. Slots runs `1` |
| `CLAIM_GAS` | `2000` | gas allowed per claim in a batch. Slots refuses to start below `125000` |
| `DRAND_RELAYS` | `https://api.drand.sh,https://api2.drand.sh,https://api3.drand.sh,https://drand.cloudflare.com` | comma-separated drand relays |

A number that does not parse, or is not positive, falls back to its default.

**To try it on a devnet you need your own deployment.** A devnet does not have the table, and it
cannot host the principal namespace the mainnet modules live in. Deploy `pact/modules/drand.pact`
and `pact/modules/slots.pact` there yourself under a namespace your devnet allows. Both files
name the mainnet namespace, `slots` names its governance keyset, and `slots` pins `drand` by its
full name and hash, so your copy must replace those with your own namespace, your own keyset and
the hash your `drand` reports. Then set `CRANK_MOD` to the name you deployed (for example
`free.slots`), `CRANK_HOST` and `CRANK_NETWORK` to your devnet's, and fund the key's account there.

**Mainnet is interlocked on purpose.** With `CRANK_NETWORK=mainnet01` the program refuses to
start unless `CRANK_MAINNET=armed` is set, refuses a localhost node, refuses a key file inside
this checkout or under any directory named `crank` or `slots-public`, and refuses to start when it
reads the key's account balance and that balance is not positive — all before it sends anything.
A balance it cannot read (a node outage) does not stop it: it starts, keeps retrying the node, and
withholds the heartbeat until the balance reads.

For a machine you want to leave running, `provision-game-crank.sh` installs it on a fresh
Ubuntu 24.04 host as a systemd service: `bash provision-game-crank.sh slots <tarball> <sha256>`.
`game-crank.service` is the unit template it renders — sandboxed, with the mainnet settings
already in it and the key and your own settings kept in `/etc/slots`, outside the directory an
update replaces. On a fresh host it creates `/etc/slots/crank.env` from `slots.env.example`, so
the claim sizing is in place from the start. `pack-crank.sh slots <output-directory>` builds the
tarball the provisioner installs, from committed bytes only, reproducibly.

**Your key is yours.** Nothing here ever asks for a seed phrase, and the provisioner never
regenerates a key — that would orphan whatever the old account holds.

## What it does not do

- It does not decide anything. The reels come from a drand signature; the contract checks it.
- It does not hold player money. Winnings go from the pot to the board's own account.
- It is not required. The contract is complete without it; this only spares players the trouble.
