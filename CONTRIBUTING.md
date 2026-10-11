# Contributing

**Issues and questions are very welcome.** If you find something wrong in the tests, or in a claim
this repository makes, please open an issue — including "your README says X and the code does Y",
which is the most useful kind. **A flaw someone could exploit on mainnet is different:** report it
privately, as [SECURITY.md](SECURITY.md) describes, never in a public issue.

**Pull requests against the two contracts are not.** What runs on mainnet is
`pact/modules/slots.pact` and `pact/modules/drand.pact`, and changing either here would break
the one property this repository exists to let you check. Tell us what is wrong and we will fix it
through the process that produced the deployment. `drand` cannot be changed at all: it is sealed
on chain and can never be upgraded.

`deploy-bytes/` and `pact/tests/fixtures/` are **derived**, not authored. A pull request that
edits them by hand will fail CI, which re-derives both and compares.

Corrections to the documentation, a test you think is missing, or a case where our verification
recipe does not work on your machine — those are worth a pull request, and thank you.

Improvements to the helper under `crank/` are welcome too. It is a plain Node program, it holds
no privilege the contract recognises, and anyone may run one.

For anything you would rather not post in public, see [SECURITY.md](SECURITY.md).
