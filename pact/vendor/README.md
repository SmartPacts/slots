# Vendored snapshots — copies, never hand-edited

The contract compiles against Kadena's `coin` contract and the two fungible interfaces. This
folder holds copies of them so the REPL suite can run with no network at all.

**Editing a copy here changes nothing on chain and silently forks the tests from the real code.**

| File | Snapshot of | Source | Taken |
|---|---|---|---|
| `fixtures/coin.pact` | Kadena `coin` v6 test fixture | our private test tree (not public) | 2026-09-07 |
| `fixtures/fungible-v2.pact` | Kadena `fungible-v2` interface | our private test tree (not public) | 2026-09-07 |
| `fixtures/fungible-xchain-v1.pact` | Kadena `fungible-xchain-v1` interface | our private test tree (not public) | 2026-09-07 |

These come from a repository that is not public, so check them by the sha256 below. The `coin`
fixture is **not** the `coin` mainnet runs — which is exactly why a locally computed module hash
for `slots` never equals the one on chain ([VERIFY.md](../../VERIFY.md) §3).

```
e99c51f0781b1d0c43882c42189efd745791d10060679abf32706e0bfae3f437  fixtures/coin.pact
8006386f7e9279737ab848e3dd90b7b3e0cf73ce49fde570892fc702eb04e850  fixtures/fungible-v2.pact
f47bf73860d19ea4851be57b081fdfd7a411419c3c2e6cacd0eaac950e24fa25  fixtures/fungible-xchain-v1.pact
```

The beacon verifier is **not** vendored. `drand` is one of this repository's own two modules and
lives in `pact/modules/` next to `slots`, which pins it by hash.
