# Reporting a security issue

**Open a GitHub security advisory on this repository** — Security → Report a vulnerability. It is
private until we publish it, it reaches us immediately, and it needs no account of ours to be
working. That is the route we can promise today, so it is the one we publish.

**No GitHub account?** Write to **contact@smartpacts.io** saying only that you have a security
report — not the details — and we will set up a private channel with you from there. That address
is the only mailbox we have; anything else you may have seen does not exist.

There is **no bug bounty**. We would rather say that plainly than imply one.

## What we commit to

- An acknowledgement within **72 hours**, from a person.
- An assessment, with our reasoning, within **10 days** — including when we conclude it is not a
  problem, and why.
- Credit where you want it, and none where you do not.

## What is at stake

The contract is **live on Kadena mainnet01, chain 2**, and holds real KDA: the house's pot, the
stake of any round still taking boards, and the winnings of boards nobody has settled yet.

It is **not frozen**. Its governance is a 2-of-3 keyset, and until it is frozen those keys can
upgrade the module and, as module admin, move the pot and rewrite any stored record directly — in
one transaction, with no new code and no change to the module hash. That means a problem found
today can be fixed, and it also means you should judge the operators and not only the code.
Freezing removes that power permanently and has not happened.

The beacon verifier, `drand`, **is** sealed: its governance is `(enforce false)`, so nobody can
upgrade it, and `slots` pins it by hash. A flaw in it cannot be patched — it would have to be
replaced by deploying a new slots contract against a new verifier.

Please do not test against mainnet. Everything here runs locally —
`cd pact/tests && ./run-tests.sh` — and the suite already carries fixtures for the failure paths,
including a frozen copy of the module, a retuned copy for the upgrade case, and three inverted
controls: one for the verifier pin, one for the round opener that must not exist as a separate
export, and one for the load-time check that only the governance keys can install the module.

## Scope

In scope: the two contracts in `pact/modules/`, the helper in `crank/`, the claims this repository
makes about any of them, and the recipe in [VERIFY.md](VERIFY.md). **If you can make that recipe
report a pass on code the chain is not running, tell us urgently** — that is the claim everything
else rests on.

Out of scope: the Kadena node software, the `coin` contract and the fungible interfaces (the
copies under `pact/vendor/fixtures/` are Kadena's) — please report those upstream. The drand beacon
itself belongs to the League of Entropy; what is ours is the verifier that checks it.
