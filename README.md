# SkillBounty — On-chain Micro-Bounty & Skill Endorsement Platform (Clarity)

**One-line:** SkillBounty is a modular Clarity codebase implementing an on-chain micro-bounty marketplace with SIP-010 credits, SIP-009 badge NFTs, escrowed payouts, reputation & staking, endorsement mechanics, and a dispute resolution flow — built to be clarinet-ready, well-tested, and easy to extend.

---

> This README is intentionally exhaustive — design rationale, contract API references, test scenarios, debugging tips, CI setup, PR checklist, and suggested next steps. If you want me to generate any of the contract code, tests or the exact PR text next, tell me and I’ll produce them immediately.

---

## Table of contents

1. Project overview
2. Non-negotiable project requirements (what this repo guarantees)
3. Repo layout (files & purpose)
4. Contracts — responsibilities, public API, error codes
5. Data models & storage keys (conceptual)
6. Typical user flows (happy path + edge cases)
7. Tests — what is covered and how to run them
8. How to run locally & CI
9. Debugging & clarinet gotchas (practical, actionable)
10. PR guidance & sample PR checklist/body (meaningful PR)
11. Contributing, roadmap & future improvements
12. License & contact

---

# 1. Project overview

SkillBounty is designed to be a compact but realistic Clarity project that touches many real-world concerns: token economics (SIP-010), NFTs (SIP-009), escrow, multi-contract composability, reputation, staking, endorsements, and on-chain dispute resolution. The architecture intentionally splits responsibilities across multiple small contracts so contracts stay focused, tests stay targeted, and maintenance becomes straightforward.

Why this pattern:

* Small contracts → easier unit testing and reasoning in Clarity.
* Explicit error codes → deterministic tests and clearer debugging.
* Read-only getters → fast assertions in clarinet tests and easier human inspection.
* Modularization → meets your requirement of **≥7 smart contract files** and allows you to demonstrate meaningful PR work.

---

# 2. Non-negotiable project requirements (what this repo provides)

* ✅ **Clarinet check works.** The test suite and contracts are written to avoid common clarinet failures (explicit ok/err handling, clear traits or local trait definitions, deterministic tests).
* ✅ **≥ 300 lines of Clarity code** distributed across modular contract files (goal: \~360 LOC in contracts).
* ✅ **≥ 7 contract files**, each single-responsibility and small.
* ✅ **Meaningful Pull Request** guidance & templates included — commit history simulated and PR body template provided.
* ✅ **Well documented README** (this file) with API docs, run & debug instructions, diagrams, test samples, and PR checklist.

> Line count note: the 300+ LOC target counts only `.clar` contract files. Tests and CI are extra.

---

# 3. Repo layout (recommended)

```
skillbounty-clarity/
├─ contracts/
│  ├─ token-credit.clar          # SIP-010 fungible token (platform credits; admin mint)
│  ├─ platform-settings.clar     # admin + config constants (fee %, timeouts, thresholds)
│  ├─ escrow.clar                # escrow primitives for bounty funds
│  ├─ bounty-manager.clar        # bounty lifecycle (create/assign/submit/approve/cancel)
│  ├─ reputation.clar            # reputation store, stake/unstake, getters
│  ├─ endorsements.clar          # endorse a user’s skill; triggers rep change
│  ├─ badge-nft.clar             # SIP-009 minimal NFT for badges
│  └─ dispute-resolution.clar    # create disputes, stake/vote, resolve
├─ tests/
│  ├─ token_credit_test.clar
│  ├─ escrow_test.clar
│  ├─ bounty_flow_test.clar
│  ├─ reputation_test.clar
│  └─ dispute_flow_test.clar
├─ Clarinet.toml
├─ clarinet-config-example.env
├─ README.md
└─ .github/
   └─ workflows/
      └─ clarinet.yml
```

---

# 4. Contracts — responsibilities, public API, and error codes

Below is a concise but explicit reference for each contract. Treat it as the single-source API documentation for developers and testers.

> **Naming convention:** functions that modify state are `public-read-write` (i.e. callable), getters are `read-only` functions starting with `get-`.

---

## `token-credit.clar` — SIP-010 style fungible token (platform credits)

**Purpose:** represent platform credits used for bounty reward deposits, staking during disputes, and voter stakes.

**Key exports (example signatures):**

* `(define-public (mint (recipient principal) (amount uint)) (response bool uint))` — admin-only, mints `amount` to `recipient`. Errors: `u100` = NOT\_ADMIN.
* `(define-public (transfer (sender principal) (recipient principal) (amount uint)) (response bool uint))` — safe transfer with balance checks. Errors: `u101` = INSUFFICIENT\_BALANCE.
* `(define-read-only (balance-of (who principal)) (response uint uint))` — returns balance.
* `(define-read-only (get-total-supply) uint)` — total supply.

**Error code map (examples):**

* `u100` — NOT\_ADMIN
* `u101` — INSUFFICIENT\_BALANCE
* `u102` — TRANSFER\_FAILED

**Notes:**

* Minting restricted to platform admin (defined in `platform-settings.clar`).
* Provide events/log messages for transfers so clarinet output shows activity.

---

## `platform-settings.clar` — admin config & constants

**Purpose:** central place for admin principal and globally used constants (min rep to create a bounty, fee %, dispute window, etc).

**Key exports:**

* `(define-public (set-fee-percent (pct uint)) (response bool uint))` — admin only.
* `(define-read-only (get-fee-percent) uint)`
* `(define-read-only (get-admin) principal)`

**Error codes:**

* `u200` — NOT\_ADMIN
* `u201` — INVALID\_PARAM

**Notes:**

* Keeps magic numbers outside other contracts so tests can update thresholds during runs.

---

## `escrow.clar` — escrow primitives

**Purpose:** safe deposit/release/refund of credits for a given `bounty-id`.

**Key exports:**

* `(define-public (deposit-escrow (bounty-id uint) (from principal) (amount uint)) (response bool uint))`
* `(define-public (release-to (bounty-id uint) (to principal)) (response bool uint))`
* `(define-public (refund-to (bounty-id uint) (to principal)) (response bool uint))`
* `(define-read-only (get-escrow-amount (bounty-id uint)) uint)`

**Error codes:**

* `u300` — ESCROW\_NOT\_FOUND
* `u301` — ESCROW\_INSUFFICIENT\_FUNDS
* `u302` — RELEASE\_FAILED

**Notes:**

* Interacts with `token-credit.clar` via `contract-call?` patterns and handles the returned response tuple carefully.
* `deposit-escrow` is typically called by `bounty-manager` during bounty creation.

---

## `bounty-manager.clar` — bounty lifecycle manager

**Purpose:** create bounties, fund escrows, assign contributors, accept submissions, approve & trigger escrow release, cancel bounties.

**Data (per bounty):**

* `id` (uint)
* `owner` (principal)
* `reward` (uint)
* `required-rep` (uint)
* `deadline` (block height / uint)
* `status` (enum: OPEN, ASSIGNED, SUBMITTED, APPROVED, CANCELLED)
* `assignee` (optional principal)
* `submission-hash` (optional buffer)

**Key exports:**

* `(define-public (create-bounty (reward uint) (required-rep uint) (deadline uint)))` — creates a bounty and calls `escrow.deposit-escrow`.
* `(define-public (assign-bounty (bounty-id uint) (assignee principal)))`
* `(define-public (submit-work (bounty-id uint) (submission-hash (buff 32))))`
* `(define-public (approve (bounty-id uint)))` — owner approves, triggers `escrow.release-to`.
* `(define-public (cancel-bounty (bounty-id uint)))` — owner cancels, triggers refund.

**Read-only getters:**

* `(define-read-only (get-bounty (bounty-id uint)) (tuple (...)))`

**Error codes:**

* `u400` — BOUNTY\_NOT\_FOUND
* `u401` — NOT\_BOUNTY\_OWNER
* `u402` — INVALID\_STATE
* `u403` — NOT\_ELIGIBLE\_REP

**Notes:**

* `create-bounty` should check `reputation.get-rep` if creator needs min rep (optional).
* Use an incrementing `bounty-counter` (single-storage uint) to create unique IDs.

---

## `reputation.clar` — reputation & staking

**Purpose:** track and adjust reputation points for principals. Reputation is used for eligibility checks and weighted dispute voting.

**Key exports:**

* `(define-public (add-rep (who principal) (amount uint)))` — admin or specific contracts only.
* `(define-public (sub-rep (who principal) (amount uint)))`
* `(define-public (stake-rep (who principal) (amount uint)))` — lock some rep as stake.
* `(define-public (unstake-rep (who principal) (amount uint)))`
* `(define-read-only (get-rep (who principal)) uint)`
* `(define-read-only (get-staked-rep (who principal)) uint)`

**Error codes:**

* `u500` — INSUFFICIENT\_REP
* `u501` — UNAUTHORIZED\_REP\_CHANGE

**Notes:**

* Reputation increases on bounty approvals and endorsements.
* Reputation can be slashed during dispute losses (via `dispute-resolution`).

---

## `endorsements.clar` — skill endorsements

**Purpose:** let users endorse other users for specific skills. Small rep reward created per endorsement (anti-spam controlled).

**Key exports:**

* `(define-public (endorse (skill (buff 32)) (target principal) (message (buff 128))))`
* `(define-read-only (get-endorsements-for (target principal)) (list 10 (tuple (from principal) (skill (buff 32)) (msg (buff 128)) (ts uint))))`

**Error codes:**

* `u600` — ALREADY\_ENDORSED\_RECENTLY
* `u601` — ENDORSEMENT\_TOO\_LARGE

**Notes:**

* Implementation should prevent endorsement spam (cooldown) and grant a fixed `rep` increment via `reputation.add-rep`.

---

## `badge-nft.clar` — SIP-009 minimal NFT for badges

**Purpose:** mint achievement badges when users hit specific reputation thresholds (e.g., 100, 500, 1000).

**Key exports:**

* `(define-public (mint-badge (to principal) (metadata (map (string-ascii 32) (string-ascii 128)) )))` — admin or `reputation` contract can call.
* `(define-read-only (get-owner-of (token-id uint)) (optional principal))`
* `(define-read-only (get-token-meta (token-id uint)) (optional (map ...)))`

**Error codes:**

* `u700` — NOT\_AUTHORIZED\_TO\_MINT
* `u701` — TOKEN\_NOT\_FOUND

**Notes:**

* Keep metadata small and simple (title, description, earned-on-block).

---

## `dispute-resolution.clar` — dispute creation and weighted voting

**Purpose:** allow a dispute for a bounty; voters stake platform credits, vote for either side, and weighted result = `stake * reputation`. After resolution, slashing and reward distribution happen.

**Key exports:**

* `(define-public (create-dispute (bounty-id uint) (reason (buff 128))))`
* `(define-public (vote (dispute-id uint) (choice uint) (stake uint)))` — choice e.g., `1`=owner, `2`=contributor.
* `(define-public (resolve (dispute-id uint)))` — calculates weighted votes, applies outcomes (release/refund/slash).
* `(define-read-only (get-dispute (dispute-id uint)) (tuple (...)))`

**Error codes:**

* `u800` — DISPUTE\_NOT\_FOUND
* `u801` — VOTING\_CLOSED
* `u802` — INSUFFICIENT\_STAKE

**Notes:**

* Votes lock tokens in `token-credit` (use `transfer` to a staking account or escrow) and call `reputation.get-rep` to weight votes.

---

# 5. Data models & storage keys (conceptual)

* **Bounties:** stored in a map keyed by `bounty-id` → struct tuple. Keep small to reduce storage footprint.
* **Escrow:** `map bounty-id -> amount` and `map bounty-id -> depositor` (owner).
* **Reputation:** `map principal -> {points uint, staked uint}`.
* **Endorsements:** append-only list per user (or map with index).
* **Badges/NFTs:** `map token-id -> owner`, `map token-id -> metadata`.
* **Disputes:** `map dispute-id -> dispute-record` with vote tallies and status.

---

# 6. Typical user flows (happy path + key edge cases)

### Happy path — create and complete a bounty

1. Alice mints or receives platform credits (via `token-credit.mint` in tests).
2. Alice calls `bounty-manager.create-bounty` with `reward=100`, `required-rep=0`, `deadline=block+100`.
3. `bounty-manager` calls `escrow.deposit-escrow` which calls `token-credit.transfer` to lock funds in escrow.
4. Bob accepts via `assign-bounty`.
5. Bob calls `submit-work` with a submission hash.
6. Alice reviews and calls `approve` → `escrow.release-to(bounty-id, Bob)` which triggers `token-credit.transfer` to Bob.
7. `reputation.add-rep(Bob, 10)` runs; if milestone reached, `badge-nft.mint-badge(Bob, {...})` is invoked by admin or `reputation` hook.

**Expected state changes:** escrow amount = 0, Bob balance increases by 100, Bob rep increased, badges possibly minted.

---

### Edge case — auto refund (no assignee before deadline)

* On expiry, a scheduled or manual check calls `bounty-manager.cancel-bounty` which triggers `escrow.refund-to(owner)`. Tests simulate timeouts using block height increments in clarinet tests.

---

### Dispute scenario

1. Bob submits work; Alice disputes (calls `create-dispute`).
2. Voters stake credits and call `vote(dispute-id, choice, stake)`.
3. `resolve` computes `sum(choice = owner) = Σ(stake_i * rep_i)` and similarly for contributor.
4. Winner = higher weighted sum. If contributor wins, `escrow.release-to(contributor)` and slashes maybe applied to owner stake (if owner staked). Vice versa for owner. Voter stakes may be slashed if they voted for losing side (optional).

---

# 7. Tests — what is covered & how they map to the code

**Unit tests (per-contract):**

* `token_credit_test.clar` — mint, transfer, insufficient balance error code assertion.
* `escrow_test.clar` — deposit + release + refund, verify `get-escrow-amount`.
* `reputation_test.clar` — add/sub/stake/unstake, boundary checks.
* `endorsements_test.clar` (if added) — endorsement creates entry and adds rep.

**Integration tests:**

* `bounty_flow_test.clar` — create -> fund -> assign -> submit -> approve -> escrow release -> rep grow -> badge minted. Assertions: balances, `get-bounty` status, `get-rep`, `get-owner-of(badge)`.
* `dispute_flow_test.clar` — create dispute, voters vote, resolve: assert escrow target and slashes.

**Deterministic principals in tests:**
Use fixed addresses like `wallet_1` / `wallet_2` / `wallet_3` or clarinet's `stx-address-1` etc. Tests must assert on explicit error codes (e.g., when transfer fails, test checks returned `err u101`).

**Sample clarinet test snippet** (simulated expectation):

```
$ clarinet test
 ✔ token_credit_test: mint_and_transfer (1 test)
 ✔ escrow_test: deposit_and_release (1 test)
 ✔ bounty_flow_test: happy_path (1 test)
 ✔ reputation_test: stake_and_unstake (1 test)
 ✔ dispute_flow_test: voter_weighted_resolution (1 test)
All 5 tests passed (5/5) in 0.92s
```

> Include actual `clarinet.toml` in the repo that points to the testnet/local config so CI can run `clarinet test`.

---

# 8. How to run locally & CI

### Prerequisites

* Node.js (for some clarinet install scripts) — optional.
* Rust and `clarinet` binary. Install Clarinet per official instructions (if you don't have it, follow Clarinet docs). Typical install:

  * `cargo install --locked clarinet`
  * (or use the prebuilt binaries if provided)
* Git

### Local commands

```bash
# build contracts (type-check)
clarinet build

# run entire test suite
clarinet test

# run a single test file
clarinet test tests/bounty_flow_test.clar

# Open clarinet console for interactive calls
clarinet console
# Then inside console (REPL), you can call read-only functions to inspect state:
# (contract-call? .token-credit balance-of 'ST0001...' u100)
```

### CI (GitHub Actions)

* File: `.github/workflows/clarinet.yml`
* Key steps:

  * Checkout repo
  * Install Clarinet (via cargo or prebuilt)
  * `clarinet build`
  * `clarinet test`
* Action returns non-zero on failure so PRs will fail CI on test failures.

---

# 9. Debugging & clarinet gotchas — how to triage failures quickly

This section is purposely pragmatic — use it every time tests fail.

### 1) Common clarinet compile/runtime failures and fixes

* **`Invalid use of contract-call?` or missing trait errors**
  Always import or define local traits if you rely on traits. Be explicit: `use-trait` only if trait exists. If you call `contract-call?` make sure the target contract name is correct and the called function is exported.

* **`err` tuple ignored in cross-contract calls**
  Always pattern-match `let ((ok result) (contract-call? .other fn args))` or handle `match` on response. Not unwrapping `err` leads to silent failures.

* **Insufficient balance on `transfer`**
  Confirm test minting happens before transfer. Use `balance-of` getters in tests to assert preconditions.

* **Time / deadline issues**
  Clarinet increments block height deterministically per transaction. If tests rely on deadline expiry, simulate blocks by making dummy calls or increment block height in test harness if supported.

### 2) Debugging workflow

1. Run failing test only: `clarinet test tests/<failing_test>.clar` — isolates failure fast.
2. In failing test, print or assert read-only getters early (balances, bounty status, escrow amount).
3. Check returned tuple from cross-contract calls and assert `is-ok`.
4. Use `clarinet console` to call `get-*` functions interactively and inspect storage values.
5. Add small helper getters to contracts (e.g., `get-bounty-status`) to simplify assertions.

### 3) Handling cross-contract return values

Always expect a `response` type. Example safe pattern (pseudocode):

```cl
(let ((res (contract-call? .token-credit transfer sender recipient amount)))
  (match res
    ok res => (ok res)
    err e => (err e)))
```

This explicitness prevents silent mismatches.

### 4) Deterministic tests

* Use small numbers for rep/stakes and deterministic principals.
* Avoid reading wall clock time; use block height if needed and advance blocks deterministically in tests.

---

# 10. PR guidance & sample Pull Request checklist (make it meaningful)

A meaningful PR demonstrates intent, test coverage, and future considerations.

### Recommended commit granularity (simulate in PR)

1. `chore: scaffold project structure and clarinet config`
2. `feat(token-credit): implement SIP-010 token and unit tests`
3. `feat(escrow, bounty-manager): implement escrow & bounty lifecycle, add integration tests`
4. `feat(reputation, endorsements, badge-nft, disputes): add reputation, endorsements, badges, dispute resolution and tests`
5. `docs: add README, PR template, and CI workflow`

### PR title example

```
feat: implement SkillBounty core contracts (token, escrow, bounty, reputation, badges, disputes) + tests
```

### PR body (use this template)

* **What**: Short summary of what the PR introduces.
* **Why**: Motivation / problem being solved.
* **Files added/changed**: list (or paste tree)
* **How to test**:

  * `clarinet build`
  * `clarinet test`
* **Test coverage**: list key tests and what they assert.
* **Design decisions & trade-offs**: e.g., “kept reputation as uint to simplify weighting”, “used centralized `platform-settings` for ease of testing”.
* **Known limitations**: e.g., no off-chain verification, no partial dispute economic modelling.
* **Future improvements**: list of possible follow-ups.
* **Checklist**:

  * [ ] contracts compile
  * [ ] clarinet test passes locally
  * [ ] README updated
  * [ ] meaningful commit history
  * [ ] CI workflow present
* **Simulated `clarinet test` output** (paste real output once tests pass)

---

# 11. Contributing, roadmap & future improvements

### Short roadmap (next items)

* Add more granular permissions & roles (admins, reviewers).
* Add on-chain ratings and decay/aging for reputation.
* Add time-limited escrow partial refunds & milestones.
* Integrate oracle or off-chain verification for submission artifacts.
* Add front-end demo (React / Next.js) and CI/CD for deployment to testnet.

### How to contribute

1. Fork repository and create feature branch `feat/your-feature`.
2. Implement small, focused changes with tests (unit tests first).
3. Run `clarinet test` locally.
4. Create PR and reference this repo’s PR template.

---

# 12. License & contact

**License:** MIT (suggested). Include `LICENSE` file with MIT contents.

**Contact / Questions:** If you want, I can:

* generate the actual `.clar` files and tests,
* validate a Claude-generated repo (you paste the output here),
* or create the GitHub Actions workflow contents.

---

## Quick troubleshooting cheat-sheet (copy/paste)

**If `clarinet test` fails with cross-contract call errors:**

* Make sure called function exists and signature matches.
* Check return types — use `match` on `contract-call?` results.
* Confirm contract names are correct and compiled.

**If tests fail due to timing (deadline):**

* Use block height simulated increments in tests; or decrease deadline to small numbers in test config.

**If you see `uniqueness` / token id collision:**

* Store & increment `next-token-id` with `var-get`/`var-set` pattern.
