# Moona Backend To Frontend Contract

Last updated: 2026-06-05

> **Backend/dev note (2026-06-05, contact discovery + sharing UX handoff):**
> I added a new backend action, `lookupContacts`, for the contact selector. It
> normalizes phone numbers with the same rules as auth/share, deduplicates by
> `phoneDigits`, checks existing profiles in a batched query, and returns
> registered contacts first plus separate `registered` / `unregistered` lists.
> This is **not live yet** until `moonaApi` is redeployed, but it needs no
> schema change. Frontend owner: please wire the contact picker to send phone
> numbers only (no local contact names), map results back by `phoneDigits`,
> split the UI into Registered and Not registered sections, and place registered
> users at the top. Also pick up these user-requested UI changes: keep a visible
> sign-in loading indicator during session/account/profile/bootstrap work,
> replace the main header theme icon with the share-list entry (theme stays in
> Settings), and prompt the user for a real display name before/while sharing if
> their profile name is empty/default so other devices never fall back to a raw
> user id.

> **Backend/dev note (2026-06-04, font + emoji regression):**
> I resynced with `front_to_backend.md` and fixed the remaining style regression
> from the font swap. `buildMoonaTheme` now applies the local Cairo/Nunito
> families through the app-wide `textTheme` again, matching the old
> `google_fonts` theme path more closely while keeping bundled fonts. Flutter
> Web CanvasKit fallback fonts now resolve from self-hosted
> `web/font-fallbacks/` (Roboto + all Noto Color Emoji shards), so category
> emoji no longer depend on `fonts.gstatic.com`. Verified against a fake web
> build under `server.py` COEP headers: category emoji render, fallback requests
> are same-origin, and there were no font load failures.

> **Backend/dev investigation note (2026-06-04, mobile login + duplicate add):**
> I found that the app never restored an existing Appwrite client session on
> startup, so mobile reruns always landed on the login screen even when the SDK
> still had a valid session. I also broadened auth error mapping so Appwrite
> account-conflict variants surface as "Incorrect password" instead of the
> generic error, and added a double-submit guard for the add/edit sheet. Frontend
> owner: please review the item form UX change requested by the user — category
> is now intended to sit directly below the Important toggle and default to
> `grocery` for new items.

> **Backend dev note (2026-06-04, local changes pending deploy):**
> I picked up the remaining Q3/Q4/Q8 items after reviewing the frontend dev's
> deploy handoff. Backend code now enriches bootstrap/sharing responses with a
> `profiles` lookup plus `counterpartyName`/`counterpartyPhone`, adds
> `trashedByDisplayName` to returned trash rows, and adds
> `createImageViewToken` for mobile-safe private image views. This is **not live
> yet** until `moonaApi` is redeployed with the updated Dart bundle and the added
> `tokens.write` function scope.

> **Deploy note (2026-06-03, pushed by the frontend dev acting as backend dev):**
> `moonaApi` is now running the **Dart** build (`runtime: dart-3.1`, active
> deployment `6a2054560278461c89c5`, verified healthy). The Node→Dart migration
> is live, so the `ensureProfile` idempotency fix (preserves
> `displayName/language/theme` on returning login) is now in production. Wire
> contract is unchanged — no client change needed. Full account + a build caveat
> for the backend dev in `backend/DEPLOY_LOG.md`.

## Appwrite IDs

- Endpoint: `https://nyc.cloud.appwrite.io/v1`.
- Project ID: `6a20305f000a1a0251d2`.
- Database ID: `moona`.
- Collections:
  - `profiles`
  - `categories`
  - `units`
  - `products`
  - `list_items`
  - `shares`
- Storage bucket: `item_images`.
- Deployed Function ID: `moonaApi`.
- Registered platforms:
  - Android application ID `sa.almou.moona`
  - iOS bundle ID `sa.almou.moona`
  - Web hostnames `localhost`, `127.0.0.1`, `dev.almou.sa`
- Operation action values sent in the function payload:
  - `ensureProfile`
  - `updatePreferences`
  - `getBootstrapData`
  - `searchProducts`
  - `lookupContacts`
  - `createItem`
  - `updateItem`
  - `trashItem`
  - `restoreTrashItem`
  - `clearTrash`
  - `requestShare`
  - `respondShare`
  - `unlinkShare`
  - `getSharingStatus`
  - `createImageViewToken`
  - `adminList`
  - `adminCreate`
  - `adminUpdate`
  - `adminDelete`
  - `adminMergeSuggestions`
  - `adminMergeProducts`

The Flutter app calls `Functions.createExecution` for `moonaApi` with
`xasync: false`. The request body must include `"action": "<operation>"`.

The function returns:

```json
{ "ok": true, "data": {} }
```

or:

```json
{
  "ok": false,
  "error": { "code": "duplicate_item", "message": "...", "details": {} }
}
```

## Phone Auth Rules

MVP uses Appwrite email/password auth with a deterministic phone alias. The
frontend should normalize phone input before Appwrite auth:

- Strip non-digits.
- `+966501112233` -> digits `966501112233`.
- `00966501112233` -> digits `966501112233`.
- Saudi local `0501112233` -> digits `966501112233`.
- Alias email: `phone-<digits>@moona.local`.
- Example: `phone-966501112233@moona.local`.

Flow:

1. Try `Account.createEmailPasswordSession(aliasEmail, password)`.
2. If the user is missing, call `Account.create(userId, aliasEmail, password)`.
3. Log in with email/password.
4. Call `ensureProfile` with the original phone and optional display prefs.

OTP is intentionally deferred for MVP.

## Function Payloads

`ensureProfile`

```json
{
  "phone": "0501112233",
  "displayName": "Noor",
  "language": "ar",
  "theme": "light"
}
```

Returns `{ "profile": { ... } }`.

`updatePreferences`

```json
{ "language": "en", "theme": "dark", "displayName": "Noor" }
```

`getBootstrapData`

```json
{}
```

Returns profile, visible list owner/shared state, active items, trash items,
catalogs, sharing status, and a `profiles` lookup for display names.

Response additions pending deploy:

```json
{
  "profiles": {
    "user-id": {
      "userId": "user-id",
      "displayName": "Noor",
      "phone": "+966501112233",
      "phoneDigits": "966501112233"
    }
  }
}
```

Returned share rows also include `counterpartyId`, `counterpartyName`, and
`counterpartyPhone`. Returned trash rows include `trashedByDisplayName` when the
profile is available.

`searchProducts`

```json
{ "query": "mi", "limit": 20 }
```

Returns `{ "suggestions": [product] }`. Queries shorter than 2 normalized
characters return an empty list.

`lookupContacts`

```json
{
  "phones": ["0501112233", "+966507654321"],
  "limit": 250
}
```

Alternative accepted shape for frontend convenience:

```json
{
  "contacts": [
    { "phones": [{ "number": "0501112233" }, { "number": "+966507654321" }] }
  ]
}
```

Returns normalized contact registration status. `contacts` is ordered with
registered users first. `registered` and `unregistered` are also split for
sectioned UI. Invalid phone values are reported in `invalid` and do not fail the
whole request.

```json
{
  "contacts": [
    {
      "phone": "+966507654321",
      "phoneDigits": "966507654321",
      "registered": true,
      "userId": "viewer-id",
      "displayName": "Noor",
      "isSelf": false
    },
    {
      "phone": "+966550000000",
      "phoneDigits": "966550000000",
      "registered": false
    }
  ],
  "registered": [],
  "unregistered": [],
  "invalid": []
}
```

Send only phone numbers to this action. Keep local contact names on-device and
join by `phoneDigits`. `isSelf` lets the picker disable sharing with the current
user before `requestShare` returns `share_self`.

`createItem`

```json
{
  "productName": "Milk",
  "count": 1,
  "unitId": "bottle",
  "brand": "Almarai",
  "seller": "Carrefour",
  "categoryId": "grocery",
  "imageFileId": "file-id",
  "important": false,
  "note": ""
}
```

Creates on the caller's active visible owner list. If the caller receives an
accepted shared list, the item is created on the owner's list.

`updateItem`

```json
{
  "itemId": "list-item-id",
  "productName": "Milk",
  "count": 2,
  "unitId": "bottle",
  "brand": "",
  "seller": "",
  "categoryId": "grocery",
  "imageFileId": "file-id",
  "important": true,
  "note": "low fat"
}
```

`trashItem`

```json
{ "itemId": "list-item-id", "reason": "scratch_timer" }
```

Frontend owns the 10-second scratch timer and calls this after the timer
expires. The backend records `trashedAt`, `trashedByUserId`, and `trashReason`.

`restoreTrashItem`

```json
{ "itemId": "list-item-id" }
```

`clearTrash`

```json
{}
```

`requestShare`

```json
{ "phone": "0507654321" }
```

Creates or reopens a pending share. The target user must already exist.

`respondShare`

```json
{ "shareId": "share-id", "accepted": true }
```

Only the target viewer can respond. Accepting sets
`profiles.activeReceivedOwnerId` for the viewer.

`unlinkShare`

```json
{ "shareId": "share-id" }
```

Alternatively owner can send `{ "viewerId": "user-id" }`, and viewer can send
`{ "ownerId": "user-id" }`.

`getSharingStatus`

```json
{}
```

Pending deploy, returns:

```json
{
  "sharing": {
    "activeReceivedOwnerId": "",
    "outgoing": [
      {
        "$id": "share-id",
        "ownerId": "owner-id",
        "viewerId": "viewer-id",
        "status": "accepted",
        "counterpartyId": "viewer-id",
        "counterpartyName": "Noor",
        "counterpartyPhone": "+966501112233"
      }
    ],
    "incoming": []
  },
  "profiles": {
    "viewer-id": {
      "userId": "viewer-id",
      "displayName": "Noor",
      "phone": "+966501112233",
      "phoneDigits": "966501112233"
    }
  }
}
```

`createImageViewToken`

```json
{ "itemId": "list-item-id", "fileId": "file-id", "ttlSeconds": 900 }
```

`ttlSeconds` is optional and clamped to 60-3600 seconds. The backend verifies
that the item owns the image file and that the caller is the list owner or an
accepted viewer before issuing a token.

Returns:

```json
{
  "bucketId": "item_images",
  "fileId": "file-id",
  "tokenId": "token-id",
  "token": "jwt-file-token",
  "expire": "2026-06-04T12:00:00.000Z",
  "ttlSeconds": 900
}
```

Use the token with Appwrite Storage `getFileView` / `getFilePreview`, or append
it to the existing URL as `&token=<encoded token>`.

Admin functions require the authenticated Appwrite user ID to be listed in
`MOONA_ADMIN_USER_IDS`.

`adminList`

```json
{ "kind": "categories" }
```

Kinds: `categories`, `units`, `products`, `users`.

`adminCreate`

```json
{ "kind": "units", "data": { "id": "kg", "nameAr": "كيلو", "nameEn": "Kilogram" } }
```

`adminUpdate`

```json
{ "kind": "products", "id": "p1", "data": { "displayName": "Bread" } }
```

`adminDelete`

```json
{ "kind": "categories", "id": "grocery" }
```

Catalog deletes mark records inactive. User delete removes the Appwrite user
and profile after revoking related shares.

`adminMergeSuggestions`

```json
{ "limit": 25 }
```

`adminMergeProducts`

```json
{ "sourceProductId": "p2", "targetProductId": "p1" }
```

Moves list items from source to target, then marks the source product inactive.

## Realtime Channels

Subscribe only after auth. Use normal Appwrite permission-scoped channels:

- `tablesdb.moona.tables.profiles.rows`
- `tablesdb.moona.tables.categories.rows`
- `tablesdb.moona.tables.units.rows`
- `tablesdb.moona.tables.products.rows`
- `tablesdb.moona.tables.list_items.rows`
- `tablesdb.moona.tables.shares.rows`

Expected handling:

- `list_items`: refresh or patch active/trash visible list.
- `shares`: refresh sharing status and visible owner.
- `profiles`: refresh preferences and `activeReceivedOwnerId`.
- `categories`, `units`, `products`: refresh catalogs/autocomplete data.

Document and file permissions are updated to owner plus accepted viewers when a
share is accepted/unlinked or when an item image is saved.

## Error Codes

- `unauthorized`
- `duplicate_item`
- `product_missing`
- `share_self`
- `share_target_missing`
- `share_pending`
- `viewer_already_receiving`
- `invalid_image`
- `admin_only`
- `invalid_input`
- `not_found`

## Current Assumptions

- One owner can have multiple accepted viewers.
- Each viewer can accept one active owner list for MVP.
- Product names are reused case-insensitively.
- Important items are returned before normal items.
- Universal products are not deleted when list items are trashed or deleted.
- Item images live in Appwrite Storage for MVP, despite the older product note
  mentioning peer-to-peer image storage.
- The Appwrite Cloud MVP project is provisioned with 6 tables, the
  `item_images` bucket, the `moonaApi` function, 5 categories, 12 units, and 50
  products. A local API key is only needed if rerunning the provisioner from a
  shell.
