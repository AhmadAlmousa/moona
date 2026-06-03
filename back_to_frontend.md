# Moona Backend To Frontend Contract

Last updated: 2026-06-03

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
  - `createItem`
  - `updateItem`
  - `trashItem`
  - `restoreTrashItem`
  - `clearTrash`
  - `requestShare`
  - `respondShare`
  - `unlinkShare`
  - `getSharingStatus`
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
catalogs, and sharing status.

`searchProducts`

```json
{ "query": "mi", "limit": 20 }
```

Returns `{ "suggestions": [product] }`. Queries shorter than 2 normalized
characters return an empty list.

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
