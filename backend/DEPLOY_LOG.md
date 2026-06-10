# Moona Backend — Deploy Log

## 2026-06-09 — Phase B correction + gated push send points

Redeployed `moonaApi` with the Phase B contract correction and push send-on-event
points.

Code changes in this deployment:
- `getInsights.byDayOfWeek` is Sunday-first (`0 = Sunday ... 6 = Saturday`).
- `getInsights.topProducts[]` now emits `count` instead of `purchaseCount`.
- Gated best-effort push sends are wired for share requested, share accepted,
  item added/edited on shared lists, and fresh shopping-presence starts.
- Presence heartbeats do not re-notify; stale presence rows reset `activeAt`
  when treated as a fresh shopping start.

Validation before deploy:
- Backend analyzer: no errors.
- Backend tests: 29/29 passed.

Deployment result:
- Active deployment: `6a27ba5da1f0974bb1a2`
- Created: `2026-06-09T07:01:49.782+00:00`
- Runtime: `dart-3.1`
- Entrypoint: `lib/main.dart`
- Status: `ready`, function `live: true`
- Build size: ~2.79 MB
- Function scopes still include `messages.write`.

Smoke verification:
- A no-auth execution with body
  `{"action":"getInsights","rangeDays":90}` completed against deployment
  `6a27ba5da1f0974bb1a2` and returned the expected
  `{"ok":false,"error":{"code":"unauthorized",...}}`.
- That verifies the live dispatcher is serving the new build.

## 2026-06-09 — Feature-plan backend provisioning/redeploy

Provisioned and redeployed the backend pass for `feature_plan.md`: item
attribution enrichment, event backbone/history actions, backend-owned scratch
state, shopping presence, and push-ready function scope.

Validation before live writes:
- Backend analyzer: no errors.
- Backend tests: 26/26 passed.

Provisioning:
- Ran `dart run bin/provision.dart` against the Appwrite Cloud project.
- Added `list_items.scratchedAt`, `list_items.scratchExpiresAt`, and
  `list_items.scratchedByUserId`.
- Created `list_events` and `shopping_presence`.
- Verified `list_items.owner_scratch` is available.
- Verified the project now has 8 TablesDB tables.

Deployment result:
- Active deployment: `6a27b3b63f2951eb1502`
- Created: `2026-06-09T06:33:26.374+00:00`
- Runtime: `dart-3.1`
- Entrypoint: `lib/main.dart`
- Status: `ready`, function `live: true`
- Build size: ~2.79 MB
- Function scopes include `messages.write`.

Smoke verification:
- A no-auth execution with body
  `{"action":"getActivity","limit":1}` completed against deployment
  `6a27b3b63f2951eb1502` and returned the expected
  `{"ok":false,"error":{"code":"unauthorized",...}}`.
- That verifies the live dispatcher recognizes a new feature-plan action.

Tooling fixes made during deploy:
- `bin/provision.dart` now tolerates Appwrite Cloud returning
  `additional_resource_not_allowed` for the already-existing database or storage
  bucket after fetching and confirming the configured resource exists.
- `scripts/deploy_function.sh` now keeps `messages.write` in the function scope
  list so future CLI deploys do not strip the push-ready scope.

## 2026-06-05 — Contact discovery / token-scope redeploy

Redeployed `moonaApi` with the current Dart backend code so the
`lookupContacts` action is live for the contact selector. I used the same
runtime-only trimmed bundle approach documented below because Appwrite Cloud's
`dart-3.1` runtime still resolves with Dart SDK 3.1.5.

Validation before deploy:
- `dart analyze` via the Dart MCP: no errors.
- Backend tests: 19/19 passed, including the `lookupContacts` operation tests.

Deployment result:
- Active deployment: `6a22265af33282ae69f2`
- Created: `2026-06-05T01:28:59.111+00:00`
- Runtime: `dart-3.1`
- Entrypoint: `lib/main.dart`
- Status: `ready`
- Build size: ~2.76 MB
- Function scopes now include `tokens.write` in addition to the existing
  database/table/user/storage scopes.

Smoke verification:
- A no-auth execution with body
  `{"action":"lookupContacts","phones":["0501112233"]}` completed against
  deployment `6a22265af33282ae69f2` and returned the expected
  `{"ok":false,"error":{"code":"unauthorized",...}}`.
- This proves the live dispatcher recognizes `lookupContacts`; the previous
  symptom would have been `Unknown Moona function: lookupContacts`.

## 2026-06-03 — Node→Dart function deploy (done by the frontend dev, acting backend dev)

**Context / authorization.** The Node→Dart SDK migration existed only in the repo
(`backend/lib/src/*.dart`); the live Appwrite function `moonaApi` was still running
the **old Node deployment** (`runtime: node-22`, deployment `6a203acee49baf82abbb`).
The repo owner asked me (the Flutter/frontend dev) to act as backend dev *for this
one task* and push the Dart migration live in your absence. Source code in
`backend/lib/**` and `lib/src/**` was **not modified** — this was a deploy-only
operation, with one deploy-bundle tweak documented below. Done via the configured
Appwrite admin API (the project's MCP key), not the CLI (CLI isn't installed here).

### Result (verified)
`moonaApi` now runs the **Dart** code:
- `runtime: dart-3.1`, `live: true`
- active `deploymentId: 6a2054560278461c89c5` (status `ready`, build ~2.7 MB)
- Smoke test (unknown action, no auth) returned, from the Dart handler:
  `{"ok":false,"error":{"code":"invalid_input","message":"Unknown Moona function: __healthcheck__."}}`
  with header `x-powered-by: Dart with package:shelf` → confirms the Dart runtime
  is serving and the `{ok,error}` envelope is intact. No data was read or written
  (the dispatcher rejects unknown actions before any repository call).

### Steps performed
1. Validated the Dart backend locally: `dart pub get`, `dart analyze` (clean),
   `dart test` (15/15 pass).
2. `functions.update(moonaApi)` — changed `runtime: node-22 → dart-3.1`,
   `entrypoint: functions/moona/main.js → lib/main.dart`,
   `commands: "npm install" → "dart pub get"`. All other config passed through
   unchanged (`execute: [users]`, the 9 scopes, `timeout: 15`, env vars). This
   matches `FunctionSpec` in `lib/src/schema.dart`. (Side effect: function went
   `live: false` until a matching Dart deployment was built — expected.)
3. `functions.createDeployment(moonaApi, code=<bundle>, activate=true)`.
4. Polled the build to `ready`; it auto-activated. Verified with a function
   execution (see above).

### ⚠️ Build gotcha you need to know about (and decide on)
The first deployment **failed to build** on `dart-3.1`. Root cause from the build
log:

```
The current Dart SDK version is 3.1.5.
Because moona_backend depends on test >=1.25.6 which requires SDK >=3.2.0 <4.0.0,
version solving failed.
```

The `dart-3.1` runtime ships **Dart SDK 3.1.5**, but `dev_dependencies: test ^1.25.15`
in `pubspec.yaml` needs SDK ≥ 3.2.0, so `dart pub get` fails during the build.
(`dart_appwrite ^25.0.0` itself is fine on 3.1.5 — pub only flagged `test`.)

**What I did to get it live without touching your source:** I deployed a
**trimmed bundle** that drops the dev-only deps — same `lib/` + `bin/` +
`analysis_options.yaml`, but a `pubspec.yaml` with **no `dev_dependencies`** and
**no `pubspec.lock`/`test/`**. The function doesn't need `test` at runtime, so
this builds clean on 3.1.5 and is behaviourally identical. Your in-repo
`pubspec.yaml` is unchanged, so local `dart test` still works.

**This is a temporary shim — please pick a permanent fix:**
- **(A) Bump the runtime** to `dart-3.5`/`dart-3.8`+ in `lib/src/schema.dart`
  (`runtimeFrom` already maps these) and redeploy. Then the *real* `pubspec.yaml`
  (with `test`) builds as-is. Cleanest — but confirm the runtime is enabled on
  Cloud first (I couldn't list runtimes; the MCP key lacks the `public` scope).
- **(B) Keep `dart-3.1`** and make the deploy reproducibly strip dev deps — see
  `scripts/deploy_function.sh` (added) and/or an `.appwriteignore`. Note: a plain
  `appwrite push` of the full repo on `dart-3.1` **will fail again** the same way,
  so don't deploy the raw folder without the trim.

### Deployment ID trail
| Deployment | Runtime | Status | Notes |
|---|---|---|---|
| `6a203acee49baf82abbb` | node-22 | ready (inactive) | original Node build — kept for rollback |
| `6a20538f85e4bdac58d5` | dart-3.1 | **failed** | first Dart attempt; failed on `test` SDK constraint |
| `6a2054560278461c89c5` | dart-3.1 | **ready (ACTIVE)** | trimmed bundle; currently serving |

### Rollback (if the Dart deploy misbehaves)
The Node deployment is still present and can be restored:
1. `functions.update(moonaApi, runtime=node-22, entrypoint="functions/moona/main.js", commands="npm install", …)`
2. `functions.updateFunctionDeployment(moonaApi, deploymentId="6a203acee49baf82abbb")`
The function returns to the exact pre-deploy state. (The Node source files were
deleted in the migration commit; restore from git history if a Node rebuild is
ever needed.)

### Impact on the app
The `ensureProfile` idempotency fix (preserves `displayName/language/theme` on
returning login) that lived only in the Dart code is now **live**. The wire
contract is unchanged, so the Flutter client needed no changes.
