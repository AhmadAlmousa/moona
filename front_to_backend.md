# Frontend → Backend Notes

This file carries contract changes, missing fields, blockers, and mockup-driven
API needs discovered during Flutter/Riverpod implementation. The backend dev
replies in `back_to_frontend.md`.

Last updated: 2026-06-03 (frontend)

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

### 3. Counterparty identity on shares
`getSharingStatus` / bootstrap `sharing.outgoing` / `sharing.incoming` currently
expose only `ownerId` / `viewerId`. The Settings→Sharing UI and the new
incoming-share-request prompt need to show a **name**. Please include the other
party's `displayName` + `phone` on each share (or return a `profiles` lookup map
keyed by userId in bootstrap + sharing responses).

### 4. Trash attribution name
Trash rows must show **who scratched the item off** (per `project.md`). Items
carry `trashedByUserId`; please add `trashedByDisplayName` to trash items (or
cover it via the profiles map from #3) so I can render it without extra lookups.

### 5. Per-language product display
For `searchProducts` suggestions and bootstrap `catalogs.products`, confirm each
product returns `displayName`, `nameAr`, `nameEn`. The client will render
`nameAr`/`nameEn` by active language and fall back to `displayName`. Tell me if
you'd rather the client always render `displayName`.

### 6. Phone normalization for non-Saudi numbers
Your examples are Saudi-only (`05…` → `9665…`). Since `phoneDigits` is unique
and must match on both sides, confirm the canonical rule for **international**
numbers: should the client require a country code, default to KSA when no `+`/
`00` is present, or reject ambiguous input? I'll mirror exactly whatever
`normalizePhone` does so client and server agree.

### 7. `ensureProfile` idempotency
Confirm calling `ensureProfile` on **every** login does not overwrite an
existing `displayName` / `language` / `theme` (device defaults should apply only
on first creation). Ongoing changes will go through `updatePreferences`.

### 8. Image lifecycle
Confirm the client uploads directly to `item_images` with the user session, what
permissions to set on upload, then passes `imageFileId` to `createItem` /
`updateItem`. Confirm how to build the view URL (`getFileView` vs
`getFilePreview`) and that accepted viewers gain read access after
`updateImagePermissions`.

### 9. Viewer realtime after accept
Confirm that once a viewer accepts (`respondShare`), they receive `list_items`
realtime events for the **owner's** documents (permissions propagated by
`refreshOwnerPermissions`), and tell me whether the client must refetch /
re-scope subscriptions on accept and on unlink.

### 10. Provision + seed  **(resolved)**
The Appwrite Cloud project has 6 tables, the `item_images` bucket, one ready
`moonaApi` deployment, 5 categories, 12 units, and 50 products.

---

Replies for remaining product-shape questions can still go in
`back_to_frontend.md`.
