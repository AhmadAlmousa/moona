# Moona Backend Audit

*Date: 2026-06-11 · Auditor: incoming full-stack engineer (taking over from the suspended backend dev) · Scope: everything under `backend/` (Dart Appwrite Function `moonaApi`, schema, provisioner, deploy tooling, tests) plus the **live** Appwrite Cloud project state, verified via the admin API.*

*Method: full read of all 4,440 lines of backend source, `bin/provision.dart`, `scripts/deploy_function.sh`, `DEPLOY_LOG.md`, and all three test files; `dart analyze` (clean) and `dart test` (29/29 pass) re-run locally; live verification of `moonaApi` deployments and raw `list_items` / `shares` rows in production. A prior repo-wide audit exists in `audit.md`; this document goes deeper on the backend and supersedes its backend sections where they differ — most importantly on the root cause of the live scratch bug.*

---

## 1. Verdict

The previous backend dev's work is **structurally sound and better than typical MVP code**: clean layering (`function_handler` → `operations` → `rules` → `appwrite_repository`), authorization consistently enforced on every list mutation, a documented wire contract that matches the client byte-for-byte, an idempotent provisioner, strict analyzer settings, and a real test suite. The coordination discipline in `back_to_frontend.md` / `DEPLOY_LOG.md` is genuinely good.

However, the audit found **one critical, currently-live data-corruption bug** that the test suite structurally could not catch, plus a security gap in phone-identity binding, and a deployment/observability process that allowed the critical bug to ship and stay invisible. The frontend's 2026-06-11 bug report (restore + Buy-Again auto-delete) is real, but its hypothesized root cause is wrong — see B1.

**Backend grade: B for design, D for data-layer correctness verification.** The single most important lesson for this codebase: the fake test repository does not behave like Appwrite, and nothing ever exercised the real database semantics before deploys.

---

## 2. Critical finding first: B1 — `''` written to datetime columns becomes "now" (live data corruption)

### What the code does
The schema declares `list_items.trashedAt`, `scratchedAt`, `scratchExpiresAt` (and `shares.respondedAt`, `revokedAt`) as **datetime** columns (`backend/lib/src/schema.dart:290-302,343-344`). But every write path that wants to "clear" them sends an **empty string**:

- `buildListItemDocument` — new items ship `trashedAt: ''`, `scratchedAt: ''`, `scratchExpiresAt: ''` (`rules.dart:262-267`)
- `trashPatch` — `scratchedAt: ''`, `scratchExpiresAt: ''` (`rules.dart:316-317`)
- `restoreTrashPatch` — `trashedAt: ''`, `scratchedAt: ''`, `scratchExpiresAt: ''` (`rules.dart:324-334`)
- `undoScratchPatch` — `scratchedAt: ''`, `scratchExpiresAt: ''` (`rules.dart:352-358`)
- `buildShareDocument` — `respondedAt: ''`, `revokedAt: ''` (`rules.dart:621-622`)

### What Appwrite actually does (verified in production, not theorized)
Appwrite TablesDB does **not** null a datetime column when given `''` — it stores the **current server time**. Two independent confirmations from live rows:

1. **All 4 active list items** have `trashedAt` equal to their `$createdAt` to the millisecond (e.g. row `6a21f7f1…`: `trashedAt: 2026-06-04T22:10:57.581Z` == `$createdAt`). `createRow` coerced the `''` to "now".
2. **Both trash rows written after the June-9 deploy** have `scratchedAt == scratchExpiresAt == $updatedAt` (e.g. row `6a29cc01…`: both `2026-06-10T20:48:03.373Z`, `$updatedAt 20:48:03.371Z`), values that are *impossible* from `scratchPatch` (which always sets expiry ≥ 3s after scratchedAt). `updateRow` coerced the two `''` values in `trashPatch` to "now". (`scratchedByUserId`, a string column, correctly stored `''` — the coercion is datetime-specific.)

### Consequence chain (this is the frontend's reported bug)
1. `createItem` births every new row with `scratchExpiresAt ≈ now` → `isScratchExpired` is immediately true.
2. The lazy sweep (`finalizeExpiredScratchesForOwner`, run on every `getBootstrapData` / `getActivity` / `suggestItems` / `getInsights`) trashes it on the next read.
3. `restoreTrashItem` and `undoScratchItem` re-set `scratchExpiresAt ≈ now` via the same coercion → restored/undone items are re-trashed by the next sweep.
4. Each bogus finalize appends a **false `scratched` list event**, which pollutes Buy-Again suggestions and Insights (phantom "purchases").

This exactly produces the two symptoms in `front_to_backend.md` (2026-06-11): restore-then-auto-delete and Buy-Again-add-then-auto-delete. The frontend's hypothesis ("backend forgets to clear the fields") is **incorrect** — the deployed `trashPatch` *does* write the fields; the writes themselves are the corruption. **Implementing the frontend's requested fix as written (set the fields with the current `''` idiom) would change nothing.** The fields must be written as JSON `null`.

Also note: production state currently matches repo HEAD in behavior. This is **not** repo↔deploy drift (the prior `audit.md` guessed it might be); the bug is in the source.

### Why the tests didn't catch it
`FakeRepo` (test/operations_test.dart) stores patch maps verbatim — `''` stays `''` and reads back as "no scratch". The tests even assert the broken idiom (`expect(undone['item']['scratchedByUserId'], '')`). The fake encodes the developer's *assumption* about Appwrite instead of Appwrite's *behavior*. See B5.

### Fix (see plan, Phase 0)
- Write `null` (not `''`) for every nullable **datetime** attribute in `buildListItemDocument`, `trashPatch`, `restoreTrashPatch`, `undoScratchPatch`, `buildShareDocument` (string columns may keep `''`).
- One-time data repair: null out `scratchedAt`/`scratchExpiresAt`/`scratchedByUserId` on all rows, null `trashedAt` on `status: active` rows, and null `respondedAt`/`revokedAt` on `pending` shares.
- Optionally purge `list_events` rows of type `scratched` created within ~2s of an `added` event for the same item since 2026-06-09 (the phantom purchases).
- Redeploy, then verify by reading raw rows (as done in this audit), not via the client.

---

## 3. Findings ranked

Criticality: how much damage it does today. Complexity: effort to resolve properly.

| # | Finding | Criticality | Complexity |
|---|---------|-------------|------------|
| B1 | `''` → datetime coercion corrupts rows; new/restored/undone items auto-trash; phantom purchase events (live now) | **Critical** | Low (code) + Medium (data repair + verify) |
| B2 | `ensureProfile` trusts payload `phone` — any user can re-bind their profile to any phone number (share/contact-lookup impersonation) | **High** | Low–Medium |
| B3 | No CI; hand-run deploys from local state; `backend/.env` (admin API key) **not gitignored** | **High** | Low |
| B4 | Pervasive silent `catch (_) {}` with zero logging; `mapError` leaks raw `error.toString()` to clients and labels unknown 500s `invalid_input` | **High** (observability) | Low |
| B5 | Test suite cannot detect data-layer semantics bugs (FakeRepo ≠ Appwrite); B1 proves it | **High** | Medium |
| B6 | `getBootstrapData` hot path: ~12 sequential awaits, duplicated queries, N+1 sequential `getProfile` lookups, 1000-event suggestions scan per call; `updateListItem` re-fetches owner shares on every single update | Medium | Medium |
| B7 | Global product catalog: every user-typed product name is readable by **all** users (bootstrap + realtime `products` channel); catalog grows unbounded; `searchProducts` is a full in-memory table scan | Medium | High (design) |
| B8 | Races/idempotency: duplicate-item check is read-then-write; `upsertShoppingPresence` get-then-create 409 unhandled; concurrent sweeps can double-append `scratched` events; re-trashing an already-trashed item appends duplicate events | Medium | Low–Medium |
| B9 | Missing status guards: `scratchItem` works on trashed rows; `restoreTrashItem` works on active rows; `trashItem` re-trashes trash | Medium | Trivial |
| B10 | Share edge cases: stale `activeReceivedOwnerId` blocks legit shares (`viewer_already_receiving` doesn't exclude the same owner in `respondShare`/`assertShareCanBeRequested`); `unlinkShare` on an already-revoked share still rewrites permissions + appends an event | Low–Med | Low |
| B11 | Deploy workaround: `dart-3.1` runtime (Dart SDK 3.1.5) forces the script to synthesize a dev-dep-free `pubspec.yaml`; runtime is several majors behind | Low–Med | Low |
| B12 | `ensureProfile` accepts `displayName: ''` and wipes the stored name (`'' ?? x` doesn't fall through); `updatePreferences` conversely silently ignores `''` | Low | Trivial |
| B13 | `adminDelete('users')` orphans the user's items, events, presence rows and storage files (only shares revoked + profile deleted) — incomplete erasure | Low–Med | Medium |
| B14 | `refreshOwnerPermissions` / `clearTrash` / `mergeProducts` do O(n) sequential row writes per call | Low | Medium |
| B15 | `dynamic repo` throughout `operations.dart` + `readDynamic` string-switch reflection — repo call typos only fail at runtime; `userDatabases` (JWT client) is constructed but never used (dead code) | Low–Med | Medium |
| B16 | `getActivity` `nextCursor` returns a spurious extra page when total % limit == 0 | Low | Trivial |
| B17 | Push bodies are English-only in an Arabic-first app | Low | Medium |

---

## 4. Detailed findings (B2–B17)

### B2 — Phone identity is payload-trusted (security)
`ensureProfile` (`appwrite_repository.dart:47-95`) writes `phone`/`phoneDigits` from the request payload on **every** login. The authenticated identity is the Appwrite account whose email alias is `phone-<digits>@moona.local`, but nothing checks the payload phone against that alias. Any signed-in user can call `{"action":"ensureProfile","phone":"<victim's number>"}` and their profile becomes the lookup result for the victim's number — `lookupContacts` will tell the victim's friends "this is your contact on Moona", and `requestShare(phone)` resolves to the attacker. (The `phoneDigits_unique` index only stops this when the victim already registered.)

OTP is deferred by owner decision, so *registration-time* phone squatting is a known/accepted product risk — but *re-binding an existing account to a different phone post-auth* is a pure backend hole. Fix: in `ensureProfile`, fetch the account (admin `users.get(actorId)`), derive digits from the alias email, and ignore/reject a payload phone that disagrees. ~20 lines.

### B3 — Deployment process and secret hygiene
- There is no CI: nothing runs `dart analyze`/`dart test` on push, and deploys are hand-run from whatever the local tree contains. The function has been deployed from uncommitted local state at least twice (deploys 2026-06-09 06:33/07:01 UTC vs. commit `f45f5fa` 2026-06-10 03:05 UTC). The repo got lucky this time (HEAD ≈ deployed); the process guarantees eventual drift.
- `backend/.env` is the documented home of `APPWRITE_API_KEY` (admin key; read by both `provision.dart` and `deploy_function.sh`) and **`.gitignore` does not cover it** (verified: `git check-ignore backend/.env` → not ignored). One absent-minded `git add -A` commits an admin key. Fix is one line, do it immediately.
- `DEPLOY_LOG.md` is good discipline — keep it, but make the deploy itself scripted-and-logged via CI rather than narrative.

### B4 — Silent failures and error mapping
- `appendListEvent`, `sendPushSafely`, `purchaseSuggestionsForOwner`, `profileLookup`, `productForEvent` all swallow exceptions with `catch (_) {}` and **no log line**. Best-effort semantics are the right call; doing it invisibly is not — a broken `list_events` table would silently kill activity/suggestions/insights with zero trace. The function context has `context.log`/`context.error`; thread it (or a logger callback) into these helpers.
- `mapError` (`function_handler.dart:96-126`): unknown exceptions return `error.toString()` to the client (internal details leak) with `code: invalid_input` and `status: 500` — semantically wrong on both axes. Add an `internal` error code, a generic client message, and keep the detail server-side in `context.error`. Non-401/404 `AppwriteException`s (e.g. 409s) also collapse to 500 `invalid_input`.

### B5 — Test fidelity
29/29 tests pass while production corrupts data; that is the definition of a fidelity gap. Three cheap layers, in order of value:
1. **Unit guard:** a test asserting that no patch/build helper ever emits `''` for a schema-declared datetime key (the schema specs are in code — iterate them).
2. **Fake semantics:** make `FakeRepo` (and ideally a shared fake used by the Flutter side too) coerce/reject writes the way Appwrite does — datetime `''` → throw in the fake, forcing call sites to use `null`.
3. **Smoke-against-real:** a tiny opt-in integration test (env-gated) that runs createItem→scratch→finalize→restore against a throwaway Appwrite project/table and asserts raw row state. This single test would have caught B1, and is the only layer that catches the *next* SDK/platform semantic surprise.

### B6 — `getBootstrapData` hot path
Every app launch runs: profile → viewer shares → sweep (which itself lists active items + owner shares, and per expired item: update + product fetch + shares re-fetch inside `updateListItem` + event append) → categories → units → **all products** → active items (again) → trash → participant shares → presence → sequential per-id `getProfile` loop → suggestions (up to 1000 events). All sequential. Concretely:
- `Future.wait` the independent reads (catalogs, items, trash, shares, presence).
- Batch `profileLookup` with one `Query.equal('$id', [ids])` listDocuments call instead of N `getRow`s.
- `updateListItem` (`appwrite_repository.dart:318-328`) should accept the caller's `ownerShares` instead of re-querying on every update — every operation already has them in hand.
- Reuse the sweep's `listActiveItems` result for the bootstrap response instead of re-querying.
- Cache or precompute suggestions (they only change when a `scratched` event lands) rather than scanning 1000 events per bootstrap.
Function timeout is 15s; today's data sizes are tiny, but this path degrades linearly with items+events+profiles and is the single most-called action.

### B7 — Global catalog privacy/scale (design decision to revisit)
`ensureProduct` promotes every user-typed item name into the global `products` table with `read(Role.users())`, and bootstrap returns the entire table to every user; the realtime `products` channel broadcasts every insert to all clients. Functionally fine for a seeded 50-product MVP; as real users type real things ("نظارة أحمد الطبية", medication names), this is a **privacy leak** and an unbounded payload. Options (in increasing effort): stop returning user-created products to other users (add `createdByUserId` + filter), per-user products with global seed catalog, or server-side `searchProducts` with `Query.search` + fulltext index instead of shipping the table. Decide before user count grows — migration cost compounds.

### B8 — Races and idempotency
- Duplicate-active-item enforcement is read-then-write (`assertNoDuplicateActiveItem` over a freshly listed page); two concurrent `createItem`s can both pass. No DB-level guard exists (a unique index on `ownerId+productId+status` is not expressible since trash duplicates are legal). Low frequency, acceptable short-term; an `ownerId_productId_active` synthetic-key column + unique index would close it properly.
- `upsertShoppingPresence` (`appwrite_repository.dart:422-458`): get-then-create; concurrent first heartbeats → `createRow` 409 which `isMissing` doesn't cover → surfaces as a 500. Catch 409 and retry as update (or just treat conflict as success).
- Two concurrent sweeps can both pass `finalizeScratchDocument`'s status check and double-append `scratched` events (double-counted purchases). Cheap mitigation: re-read the item right before the event append, or tolerate via B1's event cleanup; proper fix needs conditional updates.
- `trashItem` on an already-trashed item happily re-patches and appends a second event. Make it a no-op (`if status == trash return item`).

### B9 — Missing status guards (trivial, do with B1)
`scratchItem` should reject items with `status != 'active'` (today it scratches trash rows); `restoreTrashItem` should no-op or 409 on active rows; `trashItem` should no-op on trash rows (B8). Three one-line guards; they also shrink the race surface in B8.

### B10 — Share state edges
`assertShareCanBeRequested` and `respondShare` treat **any** non-empty `activeReceivedOwnerId` as "viewer already receiving" without excluding the requesting/sharing owner itself. A stale flag (e.g. set, then share row revoked through a path that didn't clear it, or a crash between `updateShare` and `setActiveReceivedOwner` in `unlinkShare` — they're two non-atomic writes) permanently blocks re-sharing to that viewer with `viewer_already_receiving`. Exclude `activeReceivedOwnerId == ownerId` in both checks, and consider lazily clearing the flag when no matching accepted share exists (the data for that check is already loaded). Separately, `unlinkShare` on an already-revoked share (patch == null) still runs `refreshOwnerPermissions` + appends a `share_revoked` event — wasted O(n) writes and a duplicate feed entry; early-return instead.

### B11 — Runtime pin and the pubspec-rewriting deploy script
`deploy_function.sh` exists solely because `dart-3.1` (SDK 3.1.5) can't resolve `test ^1.25.15`, so it stages a synthesized pubspec without dev_dependencies. The provisioner already supports `dart-3.8`+ (`runtimeFrom`). Bump `FunctionSpec.runtime` to a modern runtime, redeploy once, delete the workaround, and deploy the real `pubspec.yaml` (script even documents this exit path itself). Fold into the first CI-driven deploy.

### B12 — `ensureProfile` / `updatePreferences` empty-string asymmetry
`'displayName': input['displayName'] ?? existing?['displayName'] ?? …` — an explicit `''` (or whitespace) from the client overwrites the stored name, partially undoing the Q7 idempotency fix. Treat blank as absent (`normalizeText(...).isEmpty ? existing : input`). Mirror decision in `updatePreferences`, which currently *ignores* `''` — so a name can never be intentionally cleared; pick one semantic and document it in the contract file.

### B13 — User deletion completeness
`adminDelete('users')` revokes shares, deletes the auth user and profile — but leaves their `list_items` (active + trash), `list_events` (their actorId/owner history), `shopping_presence` row, and uploaded images in the bucket. For a phone-number-keyed consumer app this is a data-protection liability and also leaves rows whose permissions reference a deleted user id. Add a cleanup cascade (items, events, presence, files) — admin-only path, so complexity is bounded.

### B14 — Sequential bulk writes
`refreshOwnerPermissions` rewrites every list item one-by-one on each share accept/unlink (plus a realtime event per row, so accepting a share on a 200-item list = 200 sequential updates + 200 client refresh triggers); `clearTrash` and `mergeProducts` similarly loop sequential awaits. Bounded parallelism (`Future.wait` in chunks of ~10) is a drop-in ~5× win; long-term, consider whether viewer access could be table/permission-level rather than per-row rewrites.

### B15 — Type safety of the repo seam
Every operation takes `required dynamic repo` and the SDK objects are read through the `readDynamic` name-switch. A typo'd repo method or renamed SDK field compiles fine and fails only in production (and B4 means it fails *silently* in best-effort paths). Define an abstract `MoonaRepository` interface implemented by both `AppwriteRepository` and `FakeRepo` — mechanical refactor, big payoff with strict analyzer settings already enabled. Also: `userDatabases`/`appwriteJwtClient` are built per-request and never used (all access is admin-key with code-level authz — a legitimate design, but delete the dead JWT client or actually use it for defense-in-depth reads).

### B16 — `getActivity` cursor edge
`nextCursor = events.length < limit ? '' : documentId(events.last)` emits a cursor even when the page ended exactly at the last event; the client then fetches one guaranteed-empty page. Cosmetic; fix opportunistically (fetch `limit + 1`, return `limit`, cursor only if the extra row existed).

### B17 — Push localization
All push bodies are hardcoded English (`'$actorName added $productName.'`, `'… is shopping now.'`) in an app whose default language is Arabic. Recipient language is known (`profiles.language`). Push sends are per-recipient-set already; group recipients by language and localize the ~5 body templates. Low urgency while `MOONA_PUSH_ENABLED` is still off — do it before the gate flips.

---

## 5. Resolution plan

Ordered by (criticality ÷ effort). Each phase is independently shippable; Phase 0 is urgent and small.

### Phase 0 — Stop the corruption (today; ~half a day incl. verification)
1. **B1 code fix:** replace `''` with `null` for all nullable datetime attributes in `buildListItemDocument`, `trashPatch`, `restoreTrashPatch`, `undoScratchPatch`, `buildShareDocument`. Keep `''` for string columns (client parses both).
2. **B9 guards** (same files, three lines): `scratchItem`/`undoScratchItem` require `status == 'active'`; `restoreTrashItem` requires `status == 'trash'`; `trashItem` no-ops on trash.
3. **B5 layer 1:** unit test iterating `appwriteSchema` datetime attrs asserting no helper emits `''` for them; update `FakeRepo`/existing assertions to the `null` idiom.
4. **Deploy** via the existing script; **verify on raw rows** (create → scratch → undo → restore → finalize and read the rows back via admin API), not via the client.
5. **Data repair script** (one-off, `backend/bin/`): null `scratchedAt`/`scratchExpiresAt`/`scratchedByUserId` everywhere; null `trashedAt` on active rows; null `respondedAt`/`revokedAt` on pending shares; delete `scratched` events created ≤2s after the same item's `added` event since 2026-06-09 (phantom purchases).
6. Reply in `back_to_frontend.md`: correct the root-cause record (it was never "fields not cleared"; it was `''`→now coercion), note the client-side mitigations can stay as belt-and-braces, and give the new deployment id.

### Phase 1 — Make failure visible and the repo safe (this week; ~1 day)
1. **B3:** add `backend/.env` (and `**/.env`) to `.gitignore` *now*; rotate the admin key if there's any doubt it was ever staged. Add CI (GitHub Actions or equivalent): `dart analyze` + `dart test` for `backend/`, `flutter analyze` + `flutter test` for the app, on every push; deploy job runs the deploy script from CI on tagged commits only.
2. **B4:** pass `context` (or a logger) into the best-effort helpers; one `context.error(...)` per swallowed exception. Fix `mapError`: `internal` code + generic message for unknown errors, details only server-side.
3. **B12:** blank-as-absent for `displayName` in `ensureProfile`; document the chosen clear-semantics.
4. **B16:** cursor fix while in the area.

### Phase 2 — Security and state-machine hardening (next; ~1–2 days)
1. **B2:** bind profile phone to the authenticated account's alias email; reject mismatches with `invalid_input`.
2. **B10:** exclude same-owner in both `viewer_already_receiving` checks; lazy-clear stale `activeReceivedOwnerId`; early-return `unlinkShare` on already-revoked shares.
3. **B8:** handle 409 in `upsertShoppingPresence`; idempotent `trashItem`; re-check item state before appending finalize events.

### Phase 3 — Hot-path performance (before user growth; ~2 days)
1. **B6:** parallelize bootstrap reads; batch `profileLookup` into one query; pass `ownerShares` into `updateListItem`; reuse sweep results; bound/cache the suggestions scan.
2. **B11:** bump runtime to `dart-3.8`+, retire the pubspec-rewriting deploy bundle.
3. **B14:** chunked parallel writes in `refreshOwnerPermissions` / `clearTrash` / `mergeProducts`.

### Phase 4 — Design debts (scheduled, not urgent)
1. **B7:** decide the product-catalog privacy model and migrate (this gets harder every week it waits).
2. **B15:** typed `MoonaRepository` interface shared by live + fake; delete the unused JWT client or repurpose it.
3. **B13:** full cascade on user deletion.
4. **B5 layer 3:** env-gated integration smoke test against a disposable Appwrite project, run in CI nightly/pre-deploy.
5. **B17:** localized push bodies before `MOONA_PUSH_ENABLED` flips on.

---

## 6. Areas of improvement (beyond defects)

- **Observability:** there is no error telemetry at all — no Sentry/Crashlytics on the function, no structured logs, no alerting. Even `context.log` usage is absent outside the top-level handler. Minimum bar: log every swallowed exception (Phase 1) and a per-action duration/outcome line; that alone would have surfaced B1 within hours (a flood of `scratched` finalizes right after every bootstrap).
- **Contract as artifact:** `back_to_frontend.md` is excellent but hand-maintained. The `operations` map + payload validators could generate the action list and error-code table, removing drift risk between doc and dispatcher.
- **Schema migrations:** `provision.dart` is create-only-idempotent; it cannot alter or remove attributes/indexes, and there's no record of what the live schema *should* be vs. *is* (the June-9 provisioning added columns live with no drift check). Add a `--diff` mode that lists live-vs-spec discrepancies before writes.
- **Time injection:** `rules.dart` helpers accept `now` (good), but `operations.dart` and the repository call `DateTime.now()` directly, making expiry-window logic untestable end-to-end. Thread a clock through the operation context.
- **Backpressure/limits:** `lookupContacts` accepts 500 phones → up to 10 chained queries; `getInsights`/suggestions scan 1000 events per call with no per-user rate limit. Fine today; put limits in one place (a small `Limits` class) so they're visible and tunable.
- **Event retention:** `list_events` grows forever and trash is the only purchase history (`clearTrash` hard-deletes items but events survive — good, and worth stating in the contract doc as the durability guarantee the frontend once asked about).
- **Idempotency keys:** mutating actions accept no client request id; a retried `createItem` after a network timeout can double-create (duplicate guard helps only for same product). Cheap to add to the envelope later.
- **Keep doing:** the layering, the strict analyzer config, the deploy log narrative, the tolerant input parsing (`contactLookupPhones`, `intFrom`), the consistent `assertCanMutateOwnerList` on every item op (verified present on all eight item/scratch operations), and the permission propagation on share accept/unlink — all of this is solid work worth preserving through the fixes above.
