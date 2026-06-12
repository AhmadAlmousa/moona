# Moona — Repository Audit & Improvement Plan

*Audit date: 2026-06-11 · Branch: `feat/offline-signin-and-widget-fixes` (clean) · Auditor: principal-level review, analysis only (no code modified)*

---

## 1. Executive Summary

**Overall health grade: B−.** Moona is a well-engineered MVP: clean layering on both the Flutter client and the Appwrite Dart Function backend, 78 + 29 passing tests, `flutter analyze` clean, accurate docs, and unusually good rationale comments. What drags the grade down is everything *around* the code: there is **no CI of any kind**, the backend is deployed by a hand-run script that rewrites its own `pubspec.yaml` (and the repo currently disagrees with what is live in production), and there is **zero crash/error telemetry**. One known correctness bug is live right now (restored items auto-re-trash themselves), and the security trust anchor of the whole sharing feature — phone-number ownership — is unverified by design.

**Top 3 risks**
1. **Unverified phone identity** — anyone can register *any* phone number and receive lists/shares intended for that number's real owner (deferred OTP).
2. **Repo ↔ production drift** — manual deploys, no CI, and a live bug whose fix may already exist in the repo but demonstrably isn't behaving in production.
3. **Silent failure in production** — pervasive (mostly deliberate) error swallowing with no telemetry means breakage is invisible until a user complains.

**Top 3 opportunities**
1. A minimal CI pipeline (analyze + both test suites + scripted deploy) — small effort, removes the largest class of risk.
2. Parallelizing/batching `getBootstrapData` — the single hottest path; currently ~10 sequential awaits plus an N+1 profile lookup on every app start.
3. Scoping the product catalog and realtime channels — fixes a privacy leak and a thundering-herd refresh pattern before user count grows.

---

## 2. Repo Map

**Purpose.** Bilingual (Arabic-RTL / English-LTR) shared shopping-list app for households. Phone+password auth (OTP deferred), one active list per owner, one accepted viewer per share, scratch-to-delete with a 10 s undo window, trash, activity feed, insights, "Buy Again" suggestions, presence ("X is shopping now"), Android home-screen widget, Android+Web push, installable PWA. Apparent maturity: **late-stage MVP heading to production** (live Appwrite Cloud project, real users mentioned in coordination docs).

**Stack.** Flutter 3.41 / Dart 3.11, Riverpod 3, Appwrite Cloud (TablesDB, Storage, Functions, Realtime, Messaging), Firebase Cloud Messaging (Android + web push), single Dart Appwrite Function (`moonaApi`) as the entire backend API.

**Architecture sketch.**

```
Flutter app (lib/)
  features/* (screens)  →  AppController (lib/app/app_controller.dart)
                              │ optimistic updates + realtime reconciliation
                              ▼
                          MoonaRepository (interface, lib/data/repositories/moona_repository.dart)
                            ├─ AppwriteMoonaRepository (live; createExecution → moonaApi)
                            └─ FakeMoonaRepository (offline demo + tests)
Appwrite Cloud
  moonaApi function (backend/lib/)
    function_handler.dart (auth headers, error envelope)
      → operations.dart (28 ops, dispatch by `action`)
        → rules.dart (pure domain logic; unit-tested)
        → appwrite_repository.dart (TablesDB/Storage/Messaging adapters, permissions)
  TablesDB: profiles, categories, units, products, list_items, shares,
            list_events, shopping_presence  (+ item_images bucket)
```

**Key directories**

| Path | What it is |
|---|---|
| `lib/app/` | `AppController` + `AppState` + Riverpod providers — all client orchestration |
| `lib/data/` | Models (manual JSON), repositories (live/fake), offline caches (KvStore: file on native, localStorage on web) |
| `lib/features/` | Screens: list, item form, sharing, trash, activity, insights, auth, push, PWA install, home-widget bridge |
| `lib/core/` | Config (Appwrite IDs), theme, l10n (hand-rolled `AppStrings`), phone util |
| `backend/lib/src/` | Function handler, operations, pure rules, Appwrite repository, schema spec, provisioning seed data |
| `backend/bin/provision.dart` | Idempotent provisioning of DB/tables/indexes/bucket/function |
| `backend/scripts/deploy_function.sh` | Manual deploy that strips dev-deps to fit the pinned `dart-3.1` runtime |
| `front_to_backend.md` / `back_to_frontend.md` | Dual-agent API contract + coordination log (52 KB / 36 KB) |
| `test/`, `backend/test/` | 78 frontend tests + 29 backend tests, all passing |

**Surprises found during mapping**
- There is **no `.github/`** — no CI, despite a disciplined test culture.
- The backend function runtime is pinned to **`dart-3.1`** (`backend/lib/src/schema.dart:448`) while the repo targets Dart 3.11; the deploy script generates a throwaway `pubspec.yaml` at deploy time to make this work.
- The coordination docs reveal a **live production bug** (scratch fields not cleared) whose fix *appears* to already exist in repo code — strong evidence of repo/production drift (see C1).
- `front_to_backend.md`/`back_to_frontend.md` are an unusually effective two-agent contract mechanism — worth preserving.

---

## 3. Audit Report

Severity legend: **Critical / High / Medium / Low**. Each finding is labeled **[fact]** (verifiable in the file cited) or **[judgment]** (my assessment).

### 3.1 Security

**S1 · HIGH — Phone identity is unverified; sharing trusts it anyway.**
- **[fact]** First sign-in with any phone number auto-creates the account; the alias email is derived purely from the digits (`lib/data/repositories/appwrite_moona_repository.dart:468-491`, `lib/core/util/phone.dart:56`, `README.md:7`). No OTP, no possession proof.
- **[fact]** `ensureProfile` stores whatever phone the client sends on the profile row (`backend/lib/src/operations.dart:14-29`, `backend/lib/src/appwrite_repository.dart:47-95`). The `phoneDigits_unique` index (`backend/lib/src/schema.dart:150-153`) prevents two profiles claiming the same number, but **first-come wins**.
- **Why it matters:** Sharing (`requestShare`, `lookupContacts`) resolves people *by phone number*. An attacker can pre-register a victim's number and silently receive lists, push notifications, and contact-lookup hits meant for that person. For a household app handling real phone numbers in Saudi Arabia this is the core trust problem, and it is the documented deferred item ("OTP deferred") — but it should be treated as a launch blocker for any public release, not a nice-to-have.

**S2 · MEDIUM — `lookupContacts` is an unthrottled phone→identity oracle.**
- **[fact]** Any authenticated user can submit up to 500 numbers per call and gets back, for each registered number: `userId`, `displayName`, normalized phone (`backend/lib/src/operations.dart:145-205`, result shape at `operations.dart:1401-1426`). There is no per-user rate limit in the function; only Appwrite's platform limits apply.
- **Why it matters:** Combined with S1's auto-signup, this lets anyone enumerate the user base and harvest display names for arbitrary phone lists (classic WhatsApp-style scraping). Mitigation is cheap: cap calls per user per hour, and consider returning only a boolean `registered` until a share is accepted.

**S3 · MEDIUM — `imageFileId` ownership is never checked; permissions are then granted on it.**
- **[fact]** `createItem`/`updateItem` accept any `imageFileId`; `validateImageFile` checks only extension and size (`backend/lib/src/appwrite_repository.dart:487-511`), then `updateImagePermissions` grants the list's participants read/update/**delete** on that file (`backend/lib/src/operations.dart:224-232`, `appwrite_repository.dart:472-485`, `filePermissions` at `749-766`).
- **Why it matters:** A user who learns another user's file ID can attach it to their own item and gain (and grant others) full access to that file. File IDs are `ID.unique()` so guessing is impractical — **[judgment]** real-world risk is low, but the check (file creator == actor, e.g. via the file's existing permissions) is one conditional.

**S4 · MEDIUM — User-typed product names become a global, all-users-readable catalog.**
- **[fact]** `createItem` calls `ensureProduct(payload['productName'])`, which creates a `products` row readable by every authenticated user (`backend/lib/src/operations.dart:218`, `appwrite_repository.dart:199-215`, `catalogDocumentPermissions()` at `705`). These rows then feed every user's autocomplete (`searchProducts` lists the whole catalog, `operations.dart:135`).
- **Why it matters:** Private strings ("Ahmad's medication", a brand + person name) typed by one household leak into every other user's autocomplete, forever, and the catalog grows unboundedly (also a perf issue, see P2). `project.md` describes a *universal* catalog as intentional, but user-generated entries going global is almost certainly not the intent.

**S5 · LOW — Unknown backend errors leak `toString()` to the client with a misleading code.**
- **[fact]** `mapError` returns `error.toString()` as the message with `code: invalid_input`, `status: 500` for any non-Moona, non-Appwrite exception (`backend/lib/src/function_handler.dart:120-125`).
- **Why it matters:** internal details (types, file paths in stack-bearing messages) reach clients, and a 500 labeled `invalid_input` makes client-side error handling lie.

**S6 · LOW — Firebase client config lives in git history.**
- **[fact]** `google-services.json` / `GoogleService-Info.plist` were committed in `4afd8ca` and untracked in `bf13965`; `lib/firebase_options.dart` is still tracked. These are client-side identifiers, not secrets (Firebase's own docs), and `.gitignore:35-38` documents the reasoning. No action strictly required; history rewrite is not worth it.

**What's healthy [fact]:** function execution is restricted to `role:users` (`backend/lib/src/schema.dart:452`), so `x-appwrite-user-id` comes from the platform, not the caller; admin operations are default-deny via an env allowlist (`backend/lib/src/operations.dart:1456-1464`); authorization checks (`assertCanMutateOwnerList`, `respondSharePatch` viewer check, `createImageViewToken` read check) are consistently present and unit-tested; row-level permissions are set per participant on every document write.

### 3.2 Correctness

**C1 · HIGH — Live bug: scratch fields survive finalize/restore, so restored items auto-delete.**
- **[fact]** `front_to_backend.md` (dated 2026-06-11, the most recent entry) reports the live function leaves `scratchedAt`/`scratchExpiresAt`/`scratchedByUserId` on rows after `finalizeScratch` and `restoreTrashItem`, causing restored and re-added items to be re-trashed by the lazy sweep. The frontend shipped client-side mitigations (`lib/data/models/models.dart:232` now requires a *future* expiry).
- **[fact]** The repo's backend code *does* clear these fields — but writes **empty strings** to datetime columns (`backend/lib/src/rules.dart:308-322` `trashPatch`, `324-334` `restoreTrashPatch`, `352-358` `undoScratchPatch`), while the columns are `datetime` type (`backend/lib/src/schema.dart:295-302`). The frontend's ask explicitly says "set them to **null**".
- **[judgment]** Either the deployed function predates `f45f5fa`, or Appwrite silently drops/rejects `''` for datetime columns on update. Both explanations are bad: the first means deployment drift, the second means the "clearing" code has never worked. **This is the single most urgent code fix** — it is user-visible data loss (items silently vanish back into trash).

**C2 · HIGH — No CI/CD; deploys are manual and structurally drift-prone.**
- **[fact]** No CI config exists anywhere in the repo. The deploy path is `backend/scripts/deploy_function.sh`, which builds a temp bundle with a *regenerated* `pubspec.yaml` (no lockfile) against the pinned `dart-3.1` runtime (`schema.dart:448`); `DEPLOY_LOG.md` documents a failed deployment and a hand-rolled rollback procedure.
- **Why it matters:** Nothing verifies that what is live matches the repo (C1 is the live demonstration), tests gate nothing, and a fresh `dart pub get` at deploy time can resolve different dependency versions than anyone has tested.

**C3 · MEDIUM — Read-then-write races on product creation and duplicate-item checks.**
- **[fact]** `ensureProduct` does find-then-create (`backend/lib/src/appwrite_repository.dart:199-215`); two concurrent `createItem` calls with the same new name race — the loser hits the `normalized_unique` index (`schema.dart:252-255`) and the raw 409 propagates to the user as a generic error rather than being retried as a lookup. Same pattern for `assertNoDuplicateActiveItem` (`operations.dart:220-221`): two devices adding the same product simultaneously can both pass the check.
- **Why it matters:** Low frequency, but the failure mode is a confusing user-facing error in the happy "both spouses add milk" path this app is *for*. Catch-409-and-refetch makes it self-healing.

**C4 · MEDIUM — Realtime subscription has no error handling or reconnect.**
- **[fact]** `_repo.realtimeChanges().listen(_onRealtime)` with no `onError`/`onDone` and no resubscribe logic (`lib/app/app_controller.dart:638-641`).
- **Why it matters:** A dropped websocket (mobile networks, server restart) silently kills live sync for the rest of the session; the user sees a stale list with no indication. The dual-agent docs sell "near realtime" as a core feature.

**C5 · LOW — `clearTrash` deletes serially with no partial-failure story.**
- **[fact]** One-by-one deletes; an exception mid-loop leaves some trash deleted, no event written, error surfaced as generic (`backend/lib/src/operations.dart:392-418`).

### 3.3 Performance

**P1 · MEDIUM — `getBootstrapData` is fully sequential and does N+1 profile lookups.**
- **[fact]** ~10 independent awaited reads run one after another (`backend/lib/src/operations.dart:58-108`), and `profileLookup` issues one `getDocument` per distinct user id in a serial loop (`operations.dart:1295-1313`). Additionally `finalizeExpiredScratchesForOwner` re-lists all active items + shares at the top of *every* read operation (`operations.dart:1001-1017`, called from bootstrap, activity, suggestions, insights).
- **Why it matters:** This is the cold-start critical path of every app launch (and the README already apologizes for slow first sign-in). `Future.wait` on the independent reads and a single `Query.equal('userId', [ids])` batch would cut wall time substantially with no contract change.

**P2 · MEDIUM — The whole product catalog is shipped on every bootstrap and search.**
- **[fact]** `listProducts()` pages through the *entire* table (`appwrite_repository.dart:176-180` via `listAllDocuments` at `768-789`) for every bootstrap (`operations.dart:64`) and every `searchProducts` call (`operations.dart:135`), then filters in memory.
- **Why it matters:** Combined with S4 (every user's typo becomes a row), payload size, function memory, and search latency grow with total app usage forever. Fine at 5 users; a real problem at 5,000.

**P3 · MEDIUM — Catalog realtime events trigger a full re-bootstrap on every client.**
- **[fact]** Clients subscribe to all eight tables including `products` (`lib/data/repositories/appwrite_moona_repository.dart:382-388`; products are readable by all users), and any `products`/`categories`/`units` event calls `refresh()` → full `getBootstrapData` (`lib/app/app_controller.dart:650-653`). `shares`/`profiles` events likewise trigger un-debounced `_loadBootstrap()` (`app_controller.dart:647-649`).
- **Why it matters:** Every time *any* user anywhere creates a new product name, **every online client re-bootstraps simultaneously** — a self-inflicted thundering herd that multiplies P1×P2.

**P4 · LOW — `refreshOwnerPermissions` rewrites every item document on share accept/unlink (`backend/lib/src/appwrite_repository.dart:390-414`).** Unavoidable with row-level permissions; fine at list scale (≤ a few hundred items), just keep it in mind before "multiple lists".

**P5 · LOW — `list_events` grows without retention; insights/suggestions cap reads at 1000 (`operations.dart:708-715, 1210-1218`) so reads are bounded, but storage is not.**

### 3.4 Architecture & code quality

**A1 · MEDIUM — Backend operations take `repo` as `dynamic`; there is no repository interface.**
- **[fact]** `typedef Operation = Future<JsonMap> Function({required dynamic repo, ...})` (`backend/lib/src/operations.dart:8-12`); every repo call in 1,488 lines is dynamically dispatched. Tests pass a hand-rolled fake through the same `dynamic` seam.
- **Why it matters:** A typo'd or re-signed repo method compiles fine and fails only at runtime in production; the fake can silently drift from `AppwriteRepository`. The backend's own `analysis_options.yaml` enables `strict-casts`/`strict-inference` — this `dynamic` seam defeats it where it matters most. Extracting the abstract interface `AppwriteRepository` already conforms to is mostly mechanical.

**A2 · LOW — Phone normalization is duplicated client/server, deliberately.**
- **[fact]** `lib/core/util/phone.dart:27-58` mirrors `backend/lib/src/normalization.dart:5-42` (and says so at `phone.dart:21-23`); both sides have tests. **[judgment]** Acceptable trade-off for two pubspecs; the auth-critical invariant (same digits → same alias email) deserves a shared fixture file of input→expected pairs consumed by both test suites so drift fails a test rather than locking a user out.

**A3 · LOW — Large files are large but cohesive.** `main_screen.dart` (1,039 lines) is ~15 small private widgets; `models.dart` (949) is manual JSON with tests; `app_controller.dart` (726) is one coherent orchestrator. **[judgment]** No god-object problem; do not refactor for line count alone.

**A4 · LOW — Error swallowing is pervasive but disciplined.** 20 `catch (_)` in `app_controller.dart` alone, 7 in `operations.dart` — nearly all are commented best-effort paths (push, events, prefs) with optimistic-UI rollback or `refresh()` fallback. The genuine problem is not the swallowing, it's that nothing records the swallowed errors anywhere (see D2).

### 3.5 Testing

**T1 · MEDIUM — Zero integration tests against real Appwrite.** All 29 backend tests exercise operations against an in-memory fake (`backend/test/operations_test.dart`); schema, provisioning, permissions, and Appwrite type semantics are untested. **[judgment]** C1 (datetime `''` vs `null`) is precisely the bug class this gap produces, and it shipped. One smoke test against a staging project (sign-in → create → scratch → finalize → restore → assert fields null) would have caught it.

**T2 · LOW — No coverage measurement, and UI flows (sharing sheets, trash sheet, store mode) have thin widget-test coverage.** What exists is good: tests assert behavior, not execution (e.g. `test/app_controller_test.dart` walks scratch→finalize→undo with fake clocks).

### 3.6 Dependencies

**Healthy.** Direct deps are current within constraints (`flutter pub outdated`: appwrite 25.0→25.1 and riverpod patch available; `flutter_contacts` pinned to 1.x with a documented, verified reason — `pubspec.yaml:43-53`; `permission_handler` 11.x held back by it). Lockfiles committed for both packages. **The one real issue is the backend deploy, which bypasses its own lockfile (C2).** No license-risk packages. One sentence verdict: keep, bump patches, nothing structural.

### 3.7 DevEx & operations

**D1 · HIGH — No CI (same evidence as C2; listed here because it is also the biggest DevEx gap).** `flutter analyze`, `flutter test`, `dart test` all pass today — they are simply never enforced.

**D2 · MEDIUM — No observability anywhere.** No Crashlytics/Sentry on the client (errors go to `debugPrint`, e.g. `app_controller.dart:85,113`); backend logging is a single `context.error(...)` line (`function_handler.dart:53`); push delivery failures are swallowed by design (`operations.dart:1118-1139`). With this much intentional best-effort error handling, telemetry is the *only* way to know production is sick.

**D3 · LOW — Lint strictness is inconsistent:** backend enables `strict-casts`/`strict-inference`/`strict-raw-types` (`backend/analysis_options.yaml`); the app uses stock `flutter_lints` (`analysis_options.yaml`).

**D4 · LOW — Coordination/status docs are excellent but unbounded:** `front_to_backend.md` (52 KB) and `back_to_frontend.md` (36 KB) mix *current contract* with *historical log*; resolved items should be archived so the contract stays readable.

### 3.8 Documentation

**Strong overall — one sentence each:** README is accurate and tested (run modes, origin allow-list, test checklist all verified against code/config); `backend/README.md`, `DEPLOY_LOG.md` (with rollback steps), and inline rationale comments (e.g. the `flutter_contacts` pin) are exemplary. Gaps: no single "current known issues" list (C1 lives only inside a 52 KB log), and the admin operations (`adminList`/`adminCreate`/…) exist with no documented invocation path or UI.

### 3.9 Strengths (what to preserve)

1. **Clean, testable layering** — pure `rules.dart` separated from I/O; client `MoonaRepository` interface with a live + fake implementation that powers both an offline demo mode and the entire test suite.
2. **Optimistic UI done right** — every mutation applies locally first with rollback-or-refresh on failure, plus realtime reconciliation (`app_controller.dart` throughout).
3. **Offline-first bootstrap cache** with graceful schema-drift handling (`bootstrap_cache.dart`, `appwrite_moona_repository.dart:96-106`).
4. **Consistent server-side authorization** with unit tests for the rules (S7 evidence above).
5. **Idempotent provisioning** (`backend/bin/provision.dart`) — schema as code, conflict-tolerant.
6. **Documented decisions** — dependency pins, workarounds, and platform gotchas are written down where the next reader needs them.
7. **All checks green today**: `flutter analyze` clean, 78 + 29 tests passing, release APK documented as building.

---

## 4. Improvement Strategy

### Theme 1 — Put a floor under production (CI + deploy integrity)
*Explains: C1, C2, D1, T1.*
**Target state:** every push runs `flutter analyze` + `flutter test` + `dart test`; the backend deploys via one script invoked from CI that stamps the git SHA into a function env var; a smoke test against a staging Appwrite project runs before activation.
**Principle:** the repo must be the single source of truth for what is running. Today it provably is not.
**Done when:** CI is red-blocking; a `version` action (or env var) on `moonaApi` returns the deployed SHA and it matches `main`.

### Theme 2 — Fix what is lying to users (correctness of the scratch/restore lifecycle)
*Explains: C1, C3, C4.*
**Target state:** scratch fields are cleared with `null` (verified against real Appwrite), restored items stay restored; 409 races self-heal; realtime reconnects with backoff and falls back to refresh-on-resume.
**Principle:** for a list app, "the item I restored stays restored" is the contract; everything else is decoration.
**Done when:** the integration smoke test asserts the full scratch→finalize→restore field lifecycle on a live project, and the frontend's client-side mitigations are demoted to belt-and-braces (as `front_to_backend.md` already frames it).

### Theme 3 — Make phone-as-identity defensible before strangers can find each other
*Explains: S1, S2, S4.*
**Target state (MVP-calibrated):** rate-limit `lookupContacts` per user; return display names only for already-connected users; decide OTP (Appwrite phone sessions or an SMS provider) as an explicit go/no-go before public launch; stop publishing user-typed product names globally (per-owner products that only seed the global catalog via the existing admin merge flow).
**Principle:** the cost of S1 is bounded only while the user base is people who know each other. The mitigation ladder (rate limit → reduced disclosure → OTP) lets you ship value now without closing the door.
**Done when:** an abuse scenario write-up exists, the cheap mitigations are live, and OTP has an owner decision recorded.

### Theme 4 — Make the hot path scale like the product hopes to
*Explains: P1, P2, P3.*
**Target state:** bootstrap parallelized + batched (one query for N profiles); product search server-side-indexed instead of full-table in-memory; clients no longer resubscribe/re-bootstrap on global catalog events.
**Principle:** fix the O(total-users) couplings (global products, global realtime) before they're load-bearing; the O(list-size) ones are fine.
**Done when:** bootstrap makes ≤ 4 backend round-trip "waves" and a product created by user A causes zero network traffic for unrelated user B.

### Explicitly NOT recommending (effort vs. payoff at this maturity)
- **No microservice/function split** — the single dispatcher is the right shape for the free plan and this team size.
- **No refactor of large UI files** (`main_screen.dart`, `item_form.dart`) — they are cohesive; splitting is churn without payoff.
- **No l10n framework migration** — hand-rolled `AppStrings` is fine at 361 lines for 2 locales.
- **No git-history rewrite** for the Firebase client config (S6) — the keys are not secrets.
- **No de-duplication of phone normalization into a shared package** — a shared test-fixture file gives 90 % of the safety for 10 % of the build complexity.
- **iOS/APNs stays parked** — matches the documented plan; revisit with Apple credentials.

---

## 5. Task Plan

### Milestone 0 — Safety net (do first; everything else stands on it)

| # | Task | Files/areas | Acceptance criteria | Effort | Risk | Depends on |
|---|---|---|---|---|---|---|
| 0.1 | **Add CI: analyze + both test suites** on push/PR (GitHub Actions or equivalent) | new `.github/workflows/ci.yml` | CI fails on analyzer warnings or any test failure in `/` and `/backend`; branch protection on `main` | S | None | — |
| 0.2 | **Stamp + expose the deployed backend version** | `backend/scripts/deploy_function.sh`, `function_handler.dart` (new `version` action or env var) | Calling `version` returns the git SHA; doc note in `backend/README.md` | S | Low | — |
| 0.3 | **Integration smoke test vs. a staging Appwrite project** (sign-in, create item, scratch, finalize, restore, assert scratch fields are null, share round-trip) | new `backend/test/integration/`, staging project creds in CI secrets | Test runs in CI (manual trigger ok initially); fails on the current C1 behavior | M | Low | 0.1 |
| 0.4 | **Wire crash/error reporting**: Crashlytics (or Sentry) on the client; route the swallowed-error sites' `debugPrint`s through a single `reportError()` helper | `lib/main.dart`, new `lib/core/report.dart`, touch ~10 catch sites | An induced exception appears in the dashboard from a release build; backend errors include action name in `context.error` | M | Low | — |

### Milestone 1 — Critical fixes (security + correctness)

| # | Task | Files/areas | Acceptance criteria | Effort | Risk | Depends on |
|---|---|---|---|---|---|---|
| 1.1 | **Fix scratch-field clearing end-to-end and redeploy** (see sketch §5.1) | `backend/lib/src/rules.dart` (null instead of `''` for datetime fields), schema verification, deploy | Integration test 0.3 passes against the *deployed* function; `front_to_backend.md` item closed | S–M | Medium (touches every trash/restore path — covered by existing unit tests + new smoke test) | 0.3 strongly recommended |
| 1.2 | **Rate-limit + reduce disclosure in `lookupContacts`** | `backend/lib/src/operations.dart:145-205` | Per-user calls/hour capped (simple counter row or Appwrite rate limits); `displayName` omitted unless a share already links the two users | M | Low | — |
| 1.3 | **Verify `imageFileId` ownership in create/updateItem** | `backend/lib/src/appwrite_repository.dart:487-511`, `operations.dart:224-232` | Attaching a file the actor lacks permission on returns `invalid_image`; unit test added | S | Low | — |
| 1.4 | **Stop leaking `toString()` for unknown errors** | `backend/lib/src/function_handler.dart:120-125` | Unknown errors → `code: internal_error`, generic message, full detail only in `context.error` | S | None | — |
| 1.5 | **Realtime resilience**: `onError`/`onDone` + exponential-backoff resubscribe + refresh on app resume | `lib/app/app_controller.dart:638-641`, `lib/main.dart` lifecycle hook | Killing the websocket in dev tools recovers live sync without restart | S | Low | — |
| 1.6 | **Self-heal product/duplicate races** | `backend/lib/src/appwrite_repository.dart:199-215`, `operations.dart:220-221` | Concurrent same-name `createItem` calls: one succeeds, the other gets `duplicate_item` (not a 500); test with fake injecting 409 | S | Low | — |
| 1.7 | **Decision task: phone verification (OTP)** — write the go/no-go with cost (SMS provider vs Appwrite phone sessions) and the migration path for existing alias accounts | docs; owner decision | A dated decision recorded; if "go", spawns its own XL implementation epic | S (decision) / XL (impl) | — | — |

### Milestone 2 — High-leverage improvements

| # | Task | Files/areas | Acceptance criteria | Effort | Risk | Depends on |
|---|---|---|---|---|---|---|
| 2.1 | **Parallelize + batch `getBootstrapData`** (see sketch §5.2) | `backend/lib/src/operations.dart:52-127, 1295-1313`, add `listProfilesByIds` to repo | Independent reads run via `Future.wait`; profiles fetched with one `Query.equal('userId', ids)` per 100; measured cold latency reduction noted in PR | M | Medium (pure refactor of read path; envelope unchanged; covered by operations tests) | 0.1 |
| 2.2 | **Type the backend repo seam**: extract an abstract `MoonaBackendRepository`, make operations take it instead of `dynamic`, fake implements it | `backend/lib/src/operations.dart:8-12` + all ops, `appwrite_repository.dart`, `backend/test/` | `dart analyze` catches a deliberately misspelled repo call; no `dynamic repo` remains | M | Low (compile-time mechanical) | — |
| 2.3 | **Scope the product catalog**: user-created products get `ownerId` + owner-only read; global catalog remains seed + admin-promoted entries; search queries server-side (`Query.contains`/fulltext index on `normalizedName`) instead of full-table | `backend/lib/src/schema.dart` (products table), `appwrite_repository.dart:176-215`, `operations.dart:129-143`, provisioning migration | New private names invisible to other users; search no longer calls `listAllDocuments`; bootstrap ships seed catalog + own products only | L | **High** (data migration + autocomplete behavior change — needs the 0.3 smoke test and a migration script for existing rows) | 0.3, 2.2 |
| 2.4 | **Realtime hygiene**: drop the `products`/`categories`/`units` channels from the client subscription (catalog changes are picked up on next bootstrap), debounce `_loadBootstrap` from `shares`/`profiles` events | `lib/data/repositories/appwrite_moona_repository.dart:382-388`, `lib/app/app_controller.dart:643-661` | A product created by another user triggers no traffic on unrelated clients; 5 rapid share events cause one bootstrap | S | Low | — |
| 2.5 | **Run deploys from CI** using 0.2's script; bump runtime to `dart-3.11` per `DEPLOY_LOG.md` option (A) so the real `pubspec.yaml`+lockfile deploy as-is | `backend/lib/src/schema.dart:448`, `deploy_function.sh` (simplify), CI workflow | `main` merge → staging deploy + smoke test → manual promote; deploy bundle uses the committed lockfile | M | Medium (runtime bump needs one verification deploy; rollback path already documented) | 0.1–0.3 |

### Milestone 3 — Quality & polish

| # | Task | Files/areas | Acceptance criteria | Effort | Risk |
|---|---|---|---|---|---|
| 3.1 | Adopt backend's strict analyzer modes in the app (fix fallout) | `analysis_options.yaml` | CI green with `strict-casts`/`strict-inference` | M | Low |
| 3.2 | Shared phone-normalization fixture consumed by both test suites | `test/phone_test.dart`, `backend/test/normalization_test.dart`, new JSON fixture | Editing one normalizer without the other fails a test | S | None |
| 3.3 | Coverage reporting in CI (`flutter test --coverage`, `dart test --coverage`) with a recorded baseline; target ≥ 80 % on `lib/app/` + `backend/lib/src/` (already close) | CI | Coverage visible per PR | S | None |
| 3.4 | Archive resolved items out of `front_to_backend.md`/`back_to_frontend.md`; add a top-level `KNOWN_ISSUES.md` | docs | Contract docs ≤ ~15 KB each; C1-class issues tracked in one place | S | None |
| 3.5 | `list_events` retention decision + sweep (e.g. keep 18 months) | `backend/lib/src/operations.dart` (or scheduled function) | Documented retention; events older than cutoff pruned | M | Low |
| 3.6 | Add widget tests for sharing accept/decline flow and trash sheet | `test/` | Flows covered with behavior assertions | M | None |

### Quick wins (high impact, S effort — can be done immediately, in order)
1. **1.4** — stop leaking `toString()` (`function_handler.dart:120-125`).
2. **1.5** — realtime `onError` + resubscribe (`app_controller.dart:638-641`).
3. **2.4** — unsubscribe catalog channels / debounce bootstrap.
4. **0.1** — CI workflow (everything is already green; this is mostly YAML).
5. **0.2** — SHA-stamped deploys.
6. **3.2** — shared phone fixture.
7. Patch bumps: `appwrite` 25.0→25.1, `flutter_riverpod` 3.3.1→3.3.2.

### 5.1 Implementation sketch — Task 1.1 (scratch-field clearing, the live bug)
1. **Reproduce against real Appwrite first** (don't trust the fake): on staging, scratch an item, let it finalize, `getRow` it — confirm whether `scratchExpiresAt` still holds a value. This distinguishes *deployment drift* from *`''`-rejected-for-datetime*.
2. Change `trashPatch`, `restoreTrashPatch`, `undoScratchPatch` (`backend/lib/src/rules.dart:308-358`) — and `buildListItemDocument`'s initial fields (`rules.dart:262-267`) — to use `null` for the three datetime/scratch columns instead of `''`. Keep `''` for plain string columns (`trashedByUserId` etc.) or null them too for consistency; verify `hasScratch`/`isScratchExpired` (`rules.dart:360-374`) treat null correctly (they already do — `(item['x'] ?? '')`).
3. **Gotcha:** the existing fake-repo tests assert `''` values in patches (`backend/test/operations_test.dart`) — update assertions to null. Second gotcha: Appwrite may *reject* explicit `null` for **required** columns — the three scratch columns are `required: false` (`schema.dart:295-302`), so null is legal.
4. Redeploy via the script, then run the §0.3 smoke test against the live function: scratch → finalize → restore → assert all three fields null and the item stays active past the old expiry.
5. Close the item in `front_to_backend.md` and leave the client-side mitigations in place (cheap defense in depth).

### 5.2 Implementation sketch — Task 2.1 (bootstrap parallelization)
1. In `getBootstrapData` (`operations.dart:52-127`): wave 1 = `Future.wait([getProfile, listSharesForViewer])` (needed to compute `ownerId`); wave 2 = `Future.wait([listCategories, listUnits, listProducts, listActiveItems, listTrashItems, listSharesForParticipant, listShoppingPresence])`; wave 3 = batched profile lookup + suggestions.
2. Replace `profileLookup`'s per-id loop (`operations.dart:1295-1313`) with a repo method `listProfilesByIds(Set<String>)` using `Query.equal('userId', ids)` chunked at 100 (pattern already exists in `listProfilesByPhoneDigits`, `appwrite_repository.dart:133-159`). Keep the per-id fallback for the fake until it grows the method.
3. Move `finalizeExpiredScratchesForOwner` to *after* `listActiveItems` returns and reuse that result (it currently re-lists items itself, `operations.dart:1001-1017`) — if any item was finalized, re-list once; otherwise use the in-hand data.
4. **Gotcha:** Appwrite Cloud free plan may throttle concurrent requests per key — cap concurrency (e.g. waves as above rather than one giant `Future.wait`). Verify response-envelope byte-equality on a fixture before/after (existing operations tests already pin the shape).

### 5.3 Implementation sketch — Task 0.1 (CI)
1. `ci.yml` with two jobs: **app** (`subosito/flutter-action`, `flutter pub get`, `flutter analyze --fatal-infos`, `flutter test`) and **backend** (`dart-lang/setup-dart`, `dart pub get`, `dart analyze --fatal-infos`, `dart test`) — paths-filtered so backend-only changes skip the Flutter job if desired.
2. Pin the Flutter version to what the README states (3.41+) to avoid surprise SDK bumps.
3. **Gotcha:** the app job needs no Firebase config (push provider defaults to no-op in tests — `lib/app/providers.dart:27-31` — and `firebase_options.dart` is tracked), so tests run as-is; do **not** add `google-services.json` to CI.
4. Branch-protect `main` on both jobs. Add a `flutter build web --release` step later if web deploys become regular.

---

## 6. Open Questions (need a human decision)

1. **OTP / phone verification (gates Task 1.7):** Is public launch planned, or does Moona stay invite-by-word-of-mouth for households? Public launch makes S1 a blocker and needs an SMS budget; private use can defer it behind the cheap S2 mitigations.
2. **Is the global, user-extendable product catalog intentional product design?** `project.md` describes a curated "universal product" catalog, but today any typo by any user goes global (S4/P2). Task 2.3 assumes the answer is "user entries should be private until promoted" — please confirm before that migration.
3. **What happened with C1 in production?** Was deployment `6a27ba5da1f0974bb1a2` built from `f45f5fa` or earlier? Knowing whether this was drift or the `''`-datetime issue changes how much to trust the current deploy pipeline (and step 1 of sketch §5.1 answers it empirically if no one remembers).
4. **Scale expectations / performance target:** what user count should bootstrap latency be engineered for? (Determines whether 2.3 is M2 or can slide to M3.)
5. **`list_events` retention (Task 3.5):** is indefinite purchase history a product feature (insights over years) or can it be pruned at 12–18 months?
6. **Admin tooling:** `adminList/Create/Update/Delete/Merge` exist server-side with an env allowlist but no client. Is an admin UI planned (per `project.md`'s "admin area" goal), or should these stay curl-only and be documented as such?
7. **Hosting/domain plan for web:** `dev.almou.sa` is in the Appwrite origin allow-list — is production web hosting decided (affects whether `server.py` needs replacing with real hosting + headers)?

---

### Review-depth note
Deep review: the full backend (`backend/lib/src`, provisioning, deploy script), client core (`main.dart`, `app_controller.dart`, providers, repositories, caches, widget bridge, push), schema, tests (executed: 78 + 29 pass; `flutter analyze` clean), docs, git history, and dependency state. **Lighter review:** individual UI screens (`item_form.dart`, `insights_screen.dart`, `store_mode.dart`, `contact_picker.dart`, shared widgets — structure skimmed, logic not line-audited), Android/iOS native folders, `web/` assets, and the `fake_moona_repository.dart` internals. Findings in those areas would most likely be cosmetic; the system's risk concentrates where this audit went deep.
