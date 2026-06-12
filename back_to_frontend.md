# Moona Backend To Frontend Contract

Last updated: 2026-06-10

> **Backend/dev push gate recheck (2026-06-10):**
> Picked up the latest frontend note after the Android push integration landed.
> I rechecked the live Appwrite project before touching the send gate.
>
> Current Appwrite state:
> - `moona_fcm` is still present, enabled, and configured as the Android FCM
>   push provider for Firebase project `moona-71bf8`.
> - `moona_apns` still exists as a disabled APNs shell; iOS remains parked.
> - `moonaApi` function variables still do **not** include
>   `MOONA_PUSH_ENABLED`.
> - Dedicated target checks for all 5 current users still show **0 push
>   targets**. Each user currently has only the default email target; none has
>   a `providerType: "push"` target on `moona_fcm`.
>
> I did **not** create/set `MOONA_PUSH_ENABLED=true` yet. The agreed backend
> gate is still waiting on at least one Android device registration from the
> frontend path:
> `account.createPushTarget(targetId: ID.unique(), identifier: <fcmToken>,
> providerId: "moona_fcm")`.
>
> Please run/sign in on the current Android build, grant notification
> permission, then verify the signed-in user in Appwrite Auth -> Targets shows
> a push target for `moona_fcm`. Once that target exists, I can flip
> `MOONA_PUSH_ENABLED=true` on `moonaApi` without a code redeploy.

> **Backend/dev push gate check (2026-06-10):**
> I picked up the remaining Android push gate from the latest
> `front_to_backend.md` note.
>
> Current Appwrite state:
> - `moona_fcm` is still enabled as the Android FCM push provider.
> - `moonaApi` function variables still do **not** include
>   `MOONA_PUSH_ENABLED`, so backend send points remain disabled.
> - I checked all current Appwrite users through the dedicated target endpoint:
>   there are **0 push targets** registered. The existing targets are email-only.
>
> I did **not** flip `MOONA_PUSH_ENABLED=true` yet because the agreed gate is
> "only after at least one Android device has registered a push target." Please
> run the current Android build, sign in, grant notification permission, and let
> the frontend call `account.createPushTarget(... providerId: 'moona_fcm')`.
> Once one push target exists, the backend can create/set
> `MOONA_PUSH_ENABLED=true` on `moonaApi` and the already-wired event sends
> should start flowing. Provider id remains confirmed as `moona_fcm`.

> **Backend/dev push setup note (2026-06-10):**
> Picked up the Phase 3 push blocker from `front_to_backend.md` and did the
> backend-side setup after owner confirmation to use the existing Firebase
> project.
>
> Current verified state:
> - Firebase tooling is available (`firebase-tools` `15.19.1`) and Firebase MCP
>   is authenticated as `progware@gmail.com`.
> - Active Firebase project is now `moona-71bf8` (`displayName: moona`).
> - Created Firebase Android app `Moona Android`:
>   `1:57956565699:android:e176f4a07b7e06067dd876`,
>   package `sa.almou.moona`.
> - Created Firebase iOS app `Moona iOS`:
>   `1:57956565699:ios:f34f6f253b8febf27dd876`,
>   bundle `sa.almou.moona`.
> - Added Firebase client config files:
>   `android/app/google-services.json` and
>   `ios/Runner/GoogleService-Info.plist`.
> - Added `GoogleService-Info.plist` to the iOS Runner Xcode project resources
>   so it is copied into the app bundle.
> - Appwrite Messaging providers:
>   `moona_fcm` (`provider: fcm`) is now configured with the Firebase service
>   account for `moona-71bf8` and enabled; `moona_apns` (`provider: apns`) exists
>   as a disabled shell with no Apple credentials attached yet. Owner direction:
>   skip iOS/APNs for now and continue Android-only push.
> - `moonaApi` is still live on deployment `6a27ba5da1f0974bb1a2` and still has
>   the `messages.write` scope.
> - `MOONA_PUSH_ENABLED` is not present in the function variables, so the current
>   send points remain hard no-ops even if frontend code registers push targets.
>
> Confirmed push data payload contract from the deployed backend code:
> - `share_requested` -> target: requested viewer;
>   data: `{ type, ownerId, shareId }`.
> - `share_accepted` -> target: owner;
>   data: `{ type, ownerId, viewerId, shareId }`.
> - `item_added` / `item_edited` -> target: all other accepted participants on
>   the visible owner list;
>   data: `{ type, ownerId, actorId, itemId, productId }`.
> - `shopping_started` -> target: all other accepted participants on the visible
>   owner list;
>   data: `{ type, ownerId, actorId }`.
>
> All push messages use title `Moona`. Bodies are human-readable summaries and
> should not be used for routing; route from `data.type` plus `ownerId` /
> `itemId` / `shareId` as applicable.
>
> Remaining Android push gate before backend sends are enabled:
> 1. Frontend can now add the Firebase/Appwrite push dependencies and register
>    Android push targets against the existing payload contract.
> 2. Only after at least one frontend push target is registered, create/set
>    `MOONA_PUSH_ENABLED=true` on `moonaApi`.
> 3. iOS/APNs remains parked; do not block the Android push pass on it.

> **Backend/dev deploy note (2026-06-09, Phase B correction + push send points live):**
> Picked up the Phase B frontend handoff. I found and fixed two
> `getInsights` response mismatches before frontend verification:
> `byDayOfWeek` is now Sunday-first (`0 = Sunday ... 6 = Saturday`), and
> `topProducts[]` now emits `count` instead of `purchaseCount`.
>
> I also wired the planned gated push send-on-event points in the function:
> share requested -> target viewer, share accepted -> owner, item added/edited
> on a shared list -> the other list participants, and fresh shopping-presence
> start -> the other list participants. Sends remain best-effort and go through
> the existing `MOONA_PUSH_ENABLED=true` repository gate, so they are no-ops
> until provider setup and frontend push-target registration are ready.
> Repeated presence heartbeats do not re-notify; stale rows reset `activeAt`
> when treated as a fresh shopping start.
>
> Live deployment:
> - `moonaApi` active deployment: `6a27ba5da1f0974bb1a2`
> - Created: `2026-06-09T07:01:49.782+00:00`
> - Runtime/entrypoint: `dart-3.1` / `lib/main.dart`
> - Function is `live: true`; scopes still include `messages.write`.
>
> Smoke verification: no-auth execution of
> `{"action":"getInsights","rangeDays":90}` hit deployment
> `6a27ba5da1f0974bb1a2` and returned `401 unauthorized`, confirming the live
> dispatcher is serving the new build. Verification before deploy: backend
> analyzer clean; backend tests pass (`29` tests). No schema/provisioning change
> was needed.

> **Backend/dev deploy note (2026-06-09, feature-plan backend live):**
> Gate A and the broader feature-plan backend pass are now provisioned and live
> in Appwrite Cloud.
>
> Live deployment:
> - `moonaApi` active deployment: `6a27b3b63f2951eb1502`
> - Created: `2026-06-09T06:33:26.374+00:00`
> - Runtime/entrypoint: `dart-3.1` / `lib/main.dart`
> - Function is `live: true`; scopes include `messages.write`.
>
> Live schema verified:
> - Project now has 8 TablesDB tables, including `list_events` and
>   `shopping_presence`.
> - `list_items` has `scratchedAt`, `scratchExpiresAt`, `scratchedByUserId`.
> - `owner_scratch` index is available.
>
> Smoke verification: no-auth execution of
> `{"action":"getActivity","limit":1}` hit deployment
> `6a27b3b63f2951eb1502` and returned `401 unauthorized`, which confirms the
> live Dart dispatcher recognizes the new action. Phase A item attribution
> enrichment should now be visible after the frontend refreshes bootstrap data.
>
> Backend tooling note: `backend/bin/provision.dart` now tolerates Appwrite
> Cloud's plan-limit `additional_resource_not_allowed` response for already
> existing database/bucket resources after confirming the configured resource
> exists. `backend/scripts/deploy_function.sh` now preserves the `messages.write`
> scope when used for future CLI deploys.

> **Backend/dev sync note (2026-06-09, Phase A frontend review):**
> Reviewed the frontend Phase A handoff and current Flutter changes. No new
> backend contract is needed for Shop by seller, Store Mode, or Bulk paste v1;
> they correctly reuse existing item fields and existing `createItem` /
> scratch-to-trash behavior. The optional `createItemsBatch` can stay parked.
>
> The one requested backend gate, item attribution enrichment, is already
> implemented locally in the feature-plan backend pass below:
> `getBootstrapData` enriches active and trash item rows with
> `createdByDisplayName` / `updatedByDisplayName` while preserving raw
> `createdByUserId` / `updatedByUserId`. The frontend parser/edit-sheet display
> should light up after live schema/function deployment. No extra backend code
> change is needed from this Phase A review.
>
> Verification on the current frontend tree: `analyze_files` clean for
> `lib/` + `test/`; Flutter tests pass (`52` tests). Live backend provisioning
> and redeploy are now complete; see the deploy note above.

> **Backend/dev implementation note (2026-06-09, feature-plan backend pass):**
> Implemented the local backend contract for the selected feature plan. This is
> code-complete, tested locally, and now deployed/provisioned live. See the
> deploy note above for the active deployment id and live verification.
>
> New schema:
> - `list_items`: `scratchedAt`, `scratchExpiresAt`, `scratchedByUserId`.
> - New `list_events` table, row-security read for the owner + accepted viewers.
>   Event `type` values: `added`, `edited`, `scratched`, `deleted`, `restored`,
>   `cleared`, `share_accepted`, `share_revoked`.
> - New `shopping_presence` table keyed by actor id, row-security read for the
>   visible owner list participants.
> - Function provisioning now includes `messages.write` for future push sends.
>
> New/extended actions:
> - `getBootstrapData` now lazily finalizes expired scratches, enriches active
>   and trash items with `createdByDisplayName` / `updatedByDisplayName`, returns
>   `shoppingPresence`, and returns compact suggestions at
>   `suggestions.items`.
> - `getActivity { limit, cursor } -> { events, nextCursor, profiles }`.
> - `suggestItems { limit } -> { suggestions }`.
> - `getInsights { rangeDays } -> { insights }`.
> - `scratchItem { itemId, windowSeconds? }`, `undoScratchItem { itemId }`,
>   `finalizeScratch { itemId, force? }`.
> - `setShoppingPresence { active }`.
>
> Existing mutations now append best-effort events: `createItem` -> `added`,
> `updateItem` -> `edited`, `trashItem(reason: "scratch_timer")` -> `scratched`,
> other `trashItem` calls -> `deleted`, `restoreTrashItem` -> `restored`,
> `clearTrash` -> one `cleared` event with `clearedCount`, share accept/revoke
> -> share events. Event append failures intentionally do not roll back the user
> mutation.
>
> Backend-owned scratch behavior: scratched items keep `status: "active"` until
> finalized. `scratchItem` sets the scratch fields and realtime updates the
> existing `list_items` row; `undoScratchItem` clears the fields before expiry;
> `finalizeScratch` / lazy reads move the item to trash with
> `trashReason: "scratch_timer"` and write the purchase/history event.
>
> Push note: repository support is gated by `MOONA_PUSH_ENABLED=true` and uses
> Appwrite Messaging direct `users` targeting. The function has the scope in
> provisioning, but provider setup and frontend push-target registration are
> still required before sends should be enabled.
>
> Verified locally: `dart analyze` clean for `backend/`; backend Dart tests pass
> (`26` tests).

> **Backend/dev feature exploration note (2026-06-09, historical):**
> Logged backend-side product ideas for frontend review. This note is the
> brainstorming source; the implementation note above supersedes it for items
> that have now been built locally.
>
> 1. **Item attribution.** `list_items` already stores `createdByUserId` and
> `updatedByUserId`; bootstrap could enrich active/trash items with
> `createdByDisplayName` and `updatedByDisplayName` from the existing profiles
> lookup. Low backend risk, no schema change, and useful in shared lists so the
> UI can show who added or last changed an item.
> 2. **Invite unregistered contacts.** Today `requestShare` requires an existing
> profile. Add phone-based pending invites so a non-Moona contact can receive an
> SMS/link, sign up later, and automatically claim the invite by normalized
> `phoneDigits`. Likely needs a new `share_invites` table or extra share fields,
> plus `createInvite` / `claimInvites` behavior during `ensureProfile`.
> 3. **Recurring/suggested items.** Add a `suggestItems` action that looks at
> recently trashed or repeatedly added products for the visible owner and returns
> compact product suggestions. Frontend could show a small "usual items" row
> above the add button. This uses existing list history first; a later version
> could add per-product counters.
> 4. **Sharing roles.** Add a `role` field to shares, starting with `editor`
> and `viewer`, with an optional `checker` role if we want users who can scratch
> items but not edit details. Backend would split read/mutate authorization by
> role instead of treating every accepted viewer as an editor. Frontend would
> expose the role in Sharing settings.
> 5. **Backend-owned scratch undo.** Replace the client-owned 10-second delete
> window with backend state: `scratchItem`, `undoScratchItem`, and finalization
> after the deadline. This is larger, but it makes widget/background check-off
> reliable even if the app process is killed before the delayed `trashItem`
> call runs.
> 6. **Recent activity feed.** Add a small `list_events` table for item added,
> edited, scratched, restored, cleared, and share accepted/revoked events. It
> gives shared-list users a clear "what changed" view without crowding item
> cards. This pairs well with item attribution but is a bigger schema addition.
> 7. **Multiple lists/households.** Long-term expansion: add `lists` and
> `memberships` so a user can have Groceries, Pharmacy, Trip, etc. This is the
> highest product ceiling and the highest migration cost because the current
> model assumes one owned list plus one received list.
>
> Backend recommendation: start with **item attribution** and **unregistered
> contact invites**. They fit the existing Appwrite Function model, improve
> current shared-list workflows, and give the frontend meaningful UI work
> without forcing a full list/membership redesign.

> **Backend/dev sync note (2026-06-08, frontend widget fix acknowledged):**
> Resynced with `front_to_backend.md`. Confirmed the widget empty-list issue is
> closed on the frontend side: data was reaching shared widget storage, and the
> failing path was launcher support for the `RemoteViewsService`-backed
> `ListView`. The direct `LinearLayout`/`addView` native rendering fix does not
> need any backend contract or endpoint change. No backend action remains for
> widget display.
>
> The separate contact-match normalization fix below is still a backend/code
> action. It has been implemented and tested locally, but live `lookupContacts`
> will keep the old behavior until `moonaApi` is redeployed.

> **Backend/dev sync note (2026-06-08, widget empty list + contact match miss):**
> The Android home-screen widget empty list is not something the backend can
> directly fix if the in-app list is populated: the widget renders only the
> compact snapshot Flutter writes from `AppState.items` into `home_widget`
> storage. `getBootstrapData` already returns active items and the widget does
> not call the backend for display. If the widget still shows empty while the
> app list has items, debug the snapshot/native adapter path (`pushWidgetSnapshot`
> -> `moona_widget_payload` -> `MoonaWidgetService.onDataSetChanged`).
>
> I did find and fix a backend-relevant contact-discovery miss. Phone
> normalization now canonicalizes Saudi numbers saved with a national trunk zero
> after the country code (`+966 05...`, `0096605...`, `96605...`) to the same
> `9665...` digits used by auth/profile rows, and maps Arabic/Persian digit
> glyphs before validation. `lookupContacts` also queries both canonical and
> legacy `9660...` digit variants, then maps returned profile rows back to the
> canonical `phoneDigits`. The Flutter-side mirrored normalizer was updated too
> so registered lookup hits attach to the existing device-contact row instead of
> falling back to a duplicate entry. This is a code change and needs the backend
> function redeployed before it affects live `lookupContacts`.

> **Backend/dev sync note (2026-06-08, home-screen widget check-off):**
> Confirmed: no backend change is needed for the Android widget check-off path.
> `trashItem` is a standalone action. The function handler derives `actorId`
> and the user JWT from the Appwrite execution headers on every invocation, and
> `trashItem` then loads the item, checks that the actor is the owner or an
> accepted viewer for that owner list, and applies `trashPatch(actorId,
> reason)`. It does not depend on a previous `getBootstrapData` call, a warmed
> repository, realtime state, or any main-isolate/client-instance identity.
>
> So a headless isolate that creates a fresh `AppwriteMoonaRepository`, restores
> the persisted Appwrite session, and calls `trashItem(id, reason:
> "scratch_timer")` should be accepted exactly like the in-app delayed commit.
> If on-device QA shows `unauthorized` from the closed-app widget path, that
> means Appwrite did not attach the user execution headers from that restored
> mobile session in the background engine; the frontend fallback you proposed
> is correct: mint `Account.createJWT` while foregrounded and use `setJWT` in
> the isolate before `Functions.createExecution`. No server code/schema change
> would be needed for that fallback either.

> **Backend/dev sync note (2026-06-05):**
> I checked `front_to_backend.md` after the frontend review of the contact
> picker refactor and Settings display-name edit. No new backend action is
> requested. The older Q3/Q4/Q8 "open" and "pending deploy" markers in the
> frontend notes are historical; they are superseded by the live Dart deployment
> `6a22265af33282ae69f2`, which includes `lookupContacts`,
> `createImageViewToken`, counterparty/profile enrichment, trash display-name
> enrichment, and the `tokens.write` scope. I am leaving
> `front_to_backend.md` unchanged because it is the frontend-owned handoff file.

> **Backend/dev note (2026-06-05, contact picker investigation + display-name edit):**
> I investigated the still-empty device contact picker. The Appwrite
> `lookupContacts` action is not the blocker; the client was still waiting for
> lookup completion before showing the local device rows, and strict local
> normalization could drop phone contacts before they were rendered. I changed
> the picker to build local device rows immediately, keep contacts with any
> phone digits visible as "Not on Moona", then enrich/split rows after
> `lookupContacts` returns. The lookup payload is now deduped and capped to the
> backend limit, and Android `normalizedNumber` is used when available. I also
> added a Settings -> Account edit action so users can change `displayName`
> after first entry; it reuses `updatePreferences(displayName:)`. Verified with
> `dart analyze` and the Flutter test suite, including focused contact-picker
> row tests.

> **Backend/dev note (2026-06-05, contact picker bug follow-up):**
> I redeployed `moonaApi`; active deployment is now
> `6a22265af33282ae69f2` (runtime `dart-3.1`, status `ready`, scopes now include
> `tokens.write`). The live dispatcher now includes `lookupContacts` -- smoke
> test with no user auth returns `unauthorized` instead of "Unknown Moona
> function", which proves the action is live. Remaining contact-picker bugs are
> frontend-native integration issues: remove the custom in-app contacts
> permission dialog and request the OS permission directly via
> `FlutterContacts.permissions.request(PermissionType.read)` before
> `getAll(...)`; add Android `READ_CONTACTS` and iOS
> `NSContactsUsageDescription`; and render the local device contacts as a
> fallback even if `lookupContacts` returns empty/errors, so a backend/network
> miss does not collapse the picker to an empty list. The lookup response should
> enrich/split the rows, not be the only source of rows.

> **Backend/dev note (2026-06-05, contact discovery + sharing UX handoff):**
> I added a new backend action, `lookupContacts`, for the contact selector. It
> normalizes phone numbers with the same rules as auth/share, deduplicates by
> `phoneDigits`, checks existing profiles in a batched query, and returns
> registered contacts first plus separate `registered` / `unregistered` lists.
> This is now live via deployment `6a22265af33282ae69f2` and needs no schema
> change. Frontend owner: please wire the contact picker to send phone
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

> **Backend dev note (2026-06-04, local changes now deployed):**
> I picked up the remaining Q3/Q4/Q8 items after reviewing the frontend dev's
> deploy handoff. Backend code now enriches bootstrap/sharing responses with a
> `profiles` lookup plus `counterpartyName`/`counterpartyPhone`, adds
> `trashedByDisplayName` to returned trash rows, and adds
> `createImageViewToken` for mobile-safe private image views. This is now live
> via deployment `6a22265af33282ae69f2`, including the added `tokens.write`
> function scope.

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
  - `list_events`
  - `shopping_presence`
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
  - `getActivity`
  - `suggestItems`
  - `getInsights`
  - `scratchItem`
  - `undoScratchItem`
  - `finalizeScratch`
  - `setShoppingPresence`
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
catalogs, sharing status, shopping presence, compact suggestions, and a
`profiles` lookup for display names.

Response additions:

```json
{
  "profiles": {
    "user-id": {
      "userId": "user-id",
      "displayName": "Noor",
      "phone": "+966501112233",
      "phoneDigits": "966501112233"
    }
  },
  "shoppingPresence": [],
  "suggestions": { "items": [] }
}
```

Returned share rows also include `counterpartyId`, `counterpartyName`, and
`counterpartyPhone`. Returned active/trash item rows include
`createdByDisplayName` and `updatedByDisplayName` when the profile is available.
Returned trash rows also include `trashedByDisplayName`.

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

`getActivity`

```json
{ "limit": 50, "cursor": "" }
```

Returns paginated list events for the visible owner list. `limit` is clamped to
1-100. `cursor` is optional and should be the previous page's `nextCursor`.

```json
{
  "events": [
    {
      "$id": "event-id",
      "ownerId": "owner-id",
      "actorId": "viewer-id",
      "actorDisplayName": "Noor",
      "type": "scratched",
      "itemId": "list-item-id",
      "productId": "product-id",
      "productName": "Milk",
      "productNameAr": "حليب",
      "productNameEn": "Milk",
      "count": 1,
      "unitId": "bottle",
      "categoryId": "grocery",
      "brand": "",
      "seller": "",
      "important": false,
      "clearedCount": 0,
      "createdAt": "2026-06-09T12:00:00.000Z"
    }
  ],
  "nextCursor": "",
  "profiles": {}
}
```

`suggestItems`

```json
{ "limit": 20 }
```

Returns purchase suggestions aggregated from finalized `scratched` events over a
bounded recent history scan, excluding products already active on the visible
list.

```json
{
  "suggestions": [
    {
      "productId": "product-id",
      "productName": "Milk",
      "productNameAr": "حليب",
      "productNameEn": "Milk",
      "unitId": "bottle",
      "categoryId": "grocery",
      "brand": "",
      "seller": "",
      "purchaseCount": 4,
      "lastPurchasedAt": "2026-06-09T12:00:00.000Z",
      "avgIntervalDays": 7,
      "dueScore": 1.8
    }
  ]
}
```

`getInsights`

```json
{ "rangeDays": 90 }
```

`rangeDays` is clamped to 7-365. Returns lazy aggregates over finalized
`scratched` events for the visible owner list.

```json
{
  "insights": {
    "rangeDays": 90,
    "totalChecked": 12,
    "distinctProducts": 8,
    "topProducts": [],
    "byCategory": [],
    "byDayOfWeek": [0, 2, 1, 4, 3, 1, 1],
    "byWeek": []
  }
}
```

`scratchItem`

```json
{ "itemId": "list-item-id", "windowSeconds": 10 }
```

Sets `scratchedAt`, `scratchExpiresAt`, and `scratchedByUserId` while keeping
`status: "active"`. `windowSeconds` is optional and clamped to 3-120.

`undoScratchItem`

```json
{ "itemId": "list-item-id" }
```

Clears scratch fields if the scratch has not expired. If it has expired, the
backend finalizes it instead.

`finalizeScratch`

```json
{ "itemId": "list-item-id", "force": false }
```

Moves an expired scratched item to trash with `trashReason: "scratch_timer"` and
appends a `scratched` list event. `force` is optional and should normally be
omitted.

`setShoppingPresence`

```json
{ "active": true }
```

When active, upserts the caller's row in `shopping_presence` for their visible
owner list and returns the enriched row. `{ "active": false }` clears it.

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
- `tablesdb.moona.tables.list_events.rows`
- `tablesdb.moona.tables.shopping_presence.rows`

Expected handling:

- `list_items`: refresh or patch active/trash visible list.
- `shares`: refresh sharing status and visible owner.
- `profiles`: refresh preferences and `activeReceivedOwnerId`.
- `categories`, `units`, `products`: refresh catalogs/autocomplete data.
- `list_events`: refresh or prepend activity feed rows.
- `shopping_presence`: refresh shopping-now indicators.

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
- The Appwrite Cloud MVP project is provisioned with 8 tables, the
  `item_images` bucket, the `moonaApi` function, 5 categories, 12 units, and 50
  products. A local API key is only needed if rerunning the provisioner from a
  shell.

## Admin feature (2026-06-12)

- **Schema deltas (provisioned live):** `profiles.isAdmin` boolean (optional);
  two new collections `brands` + `stores` (rowSecurity off, `read("users")`;
  columns `stableId/name/normalizedName/active/createdAt/updatedAt`; unique index
  on `normalizedName`, fulltext on `name`). Both added to the realtime channel set.
- **Bootstrap additions:** `profile.isAdmin` (bool); `catalogs.brands` +
  `catalogs.stores` (active terms, each `{$id,name,active}`).
- **Admin actions** (gated by `MOONA_ADMIN_USER_IDS` env var OR `profiles.isAdmin`):
  `adminList/adminCreate/adminUpdate/adminDelete` over kinds
  `users|categories|units|products|brands|stores`; `adminResetUser {id}` (wipes a
  user's items/events/shares/presence + images, keeps the account);
  `adminUpdate('users', id, {isAdmin?,displayName?})` for promote/demote/rename;
  `adminDelete('users', id)` now does the full data cascade before deleting the
  account. Catalog deletes are soft (`active=false`); brand/store free text on
  items is unchanged (autocomplete only suggests).
- **Deployed:** moonaApi deployment `6a2c424784ad06540c58` (rollback
  `6a2c01cfb8e6620125c0`). First admin seeded = userId `6a20d796f1dd431e0eff`.
