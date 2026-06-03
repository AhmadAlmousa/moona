# Frontend → Backend Notes

This file carries contract changes, missing fields, blockers, and mockup-driven
API needs discovered during Flutter/Riverpod implementation. The backend dev
replies in `back_to_frontend.md`.

Last updated: 2026-06-03 PM (frontend)

## Review of the backend contract (2026-06-03 PM)

I reviewed `backend/lib/src/*` against the live Flutter integration. Good news first:
the wire contract matches end-to-end — collection ids, the single `moonaApi`
dispatcher + `action` field, the `{ ok, data }` / `{ ok, error }` envelope,
realtime channel names (`tablesdb.moona.tables.<id>.rows`), and every document
field name (`stableId`, `userId`, `phoneDigits`, product `nameAr/nameEn/
displayName`, etc.) all line up with my models. `flutter analyze` is clean and
all 19 tests pass.

### Node→Dart SDK migration — reviewed, no client changes needed
I diffed the new Dart backend against the previous Node implementation. The
migration is wire-compatible: `function_handler.dart` keeps the same header
auth + `action` dispatch + `{ok,data}` envelope, `operations.dart` returns the
exact same response keys, and `rowToMap()` in `appwrite_repository.dart` spreads
the Appwrite `Row.data` to the top level and re-adds `$id`/`$permissions`/
`$createdAt`/`$updatedAt` — so the JSON my models parse is identical. No Flutter
change required for the migration.

### ⚠️ Deployment gap — the migration isn't live yet
Checked the live project via the Appwrite admin API: `moonaApi` is still the
**Node deployment** (`runtime: node-22`, latest deployment `6a203ace…` created
2026-06-03 14:31, status `ready`) — i.e. the Dart code is local/uncommitted and
hasn't been deployed. Practical impact for me: the **Q7 `ensureProfile` fix is
correct in code but NOT live**, so production still wipes returning users'
`displayName/language/theme` on each login until the Dart function is deployed
(and the function runtime switched to the Dart runtime). Flagging so it doesn't
get marked done prematurely — the running app otherwise works fine against the
Node deployment since the contract is identical. (Live data verified: 6 tables,
seed counts 5 categories / 12 units / 50 products, document shapes match.)

Two things still need backend follow-up:

### ✅ Fixed in code (pending deploy) — `ensureProfile` preserves prefs (was Q7)
`backend/lib/src/appwrite_repository.dart` now keeps an existing profile's
`displayName`, `language`, and `theme` unless the payload explicitly supplies a
replacement. New profiles still use the existing default values. **Not yet live**
— see the deployment-gap note above.

### ⏳ Still open — names for shares & trash (Q3 / Q4)
Confirmed from the code that `sharingStatus()` returns shares carrying only
`ownerId`/`viewerId`, bootstrap has no `profiles` map, and `trashPatch` records
only `trashedByUserId` (no display name). The client is **already wired** to
consume either of two shapes — it just has no data yet, so the Sharing settings,
the incoming-share prompt, and "who scratched this off" in Trash currently fall
back to raw user ids. Please pick one and I'll render it automatically:
- add `counterpartyName` + `counterpartyPhone` to each share (and
  `trashedByDisplayName` to trash items), **or**
- include a `profiles` map (`userId → { displayName, phone }`) in
  `getBootstrapData` and `getSharingStatus`. My `nameFor()` already checks this
  map first, so this single addition covers both Q3 and Q4.

Note: `requestShare` already returns full `owner`/`viewer` profiles — only
bootstrap / `getSharingStatus` are missing the lookup.

### ❓ Image view auth on mobile (refines Q8)
`item_images` has `fileSecurity: true` with per-user read permissions. The
client builds a plain `…/files/{id}/view?project=…` URL and loads it via
`Image.network`. That carries no Appwrite session on mobile, so reads will 401.
How should the mobile client authenticate image views — a file token / signed
URL, a JWT query param, or something else? Web is probably fine via the session
cookie; mobile is the concern.

## Status

Frontend plan approved. Building the full user-facing Flutter app (Riverpod,
go_router, Appwrite SDK) in one pass against the contract in
`back_to_frontend.md`. The admin area is **out of scope for Flutter** — it is
managed via the Appwrite Console (admin = allowlisted user in
`MOONA_ADMIN_USER_IDS`). OTP stays deferred; auth is phone + password with the
phone-alias rules you documented. Item images use Appwrite Storage (not P2P).

The live Appwrite Cloud project is now configured as the default backend. The
fake in-memory repository remains only for tests or deliberate local overrides.

## Open requirements / questions

### 1. Concrete config values  **(resolved)**
- `APPWRITE_ENDPOINT=https://nyc.cloud.appwrite.io/v1`
- `APPWRITE_PROJECT_ID=6a20305f000a1a0251d2`
- Database id: `moona`
- Storage bucket id: `item_images`

### 2. Function invocation + response contract  **(resolved)**
The client calls the single deployed function `moonaApi` with
`Functions.createExecution(functionId: 'moonaApi', body: <jsonString>,
xasync: false)`. The JSON body includes `action` with the operation name, such
as `createItem`. Responses are parsed as `{ "ok": true, "data": {…} }` /
`{ "ok": false, "error": {…} }`.

### 3. Counterparty identity on shares  **(still open — see top section)**
`getSharingStatus` / bootstrap `sharing.outgoing` / `sharing.incoming` currently
expose only `ownerId` / `viewerId`. The Settings→Sharing UI and the new
incoming-share-request prompt need to show a **name**. Please include the other
party's `displayName` + `phone` on each share (or return a `profiles` lookup map
keyed by userId in bootstrap + sharing responses).

### 4. Trash attribution name  **(still open — see top section)**
Trash rows must show **who scratched the item off** (per `project.md`). Items
carry `trashedByUserId`; please add `trashedByDisplayName` to trash items (or
cover it via the profiles map from #3) so I can render it without extra lookups.

### 5. Per-language product display  **(resolved)**
Confirmed in `schema.dart`/`rules.dart`: products carry `displayName`, `nameAr`,
`nameEn`. The client renders `nameAr`/`nameEn` by active language and falls back
to `displayName` (`Product.label(lang)`). No change needed.

### 6. Phone normalization for non-Saudi numbers  **(resolved)**
Confirmed canonical rule from `normalization.dart` (`normalizePhone`, default cc
`966`): strip non-digits; `+`→drop a leading `00`; bare `00…`→drop `00`;
leading `0`→replace with `966`; otherwise prepend `966` only when not already
prefixed and ≤10 digits; require 8–15 digits. The client mirrors this byte-for-
byte in `lib/core/util/phone.dart` and a unit test covers each branch.

### 7. `ensureProfile` idempotency  **(resolved)**
The backend preserves existing `displayName/language/theme` on returning login
unless the payload explicitly sends replacements.

### 8. Image lifecycle  **(mostly resolved; mobile-view auth still open)**
Confirmed: client uploads to `item_images` with user-scoped read/update/delete
permissions, passes `imageFileId` to `createItem`/`updateItem`; backend
re-permissions via `updateImagePermissions`, and accepted viewers gain read via
`refreshOwnerPermissions`. Remaining question is how the **mobile** client
authenticates the view URL under `fileSecurity` — see top section.

### 9. Viewer realtime after accept  **(resolved)**
Confirmed `respondShare`→`refreshOwnerPermissions` rewrites owner item + image
permissions to include accepted viewers, so the viewer's permission-scoped
`list_items` subscription receives the owner's rows. The client re-runs
`getBootstrapData` on every `shares`/`profiles` realtime event and on
accept/unlink, which re-scopes the visible list to the new owner — no manual
subscription re-scoping needed (channels are permission-filtered server-side).

### 10. Provision + seed  **(resolved)**
The Appwrite Cloud project has 6 tables, the `item_images` bucket, one ready
`moonaApi` deployment, 5 categories, 12 units, and 50 products.

---

Replies for remaining product-shape questions can still go in
`back_to_frontend.md`.
