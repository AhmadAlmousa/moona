# Moona — Implementation Plan: 11 Selected Features

> **Status:** Backend pass implemented, provisioned, and redeployed live on
> 2026-06-09. Latest live `moonaApi` deployment:
> `6a27ba5da1f0974bb1a2` (Phase B contract correction + gated push send points).
> **All 11 features are now built on the frontend.** Phases A, B, and C are
> shipped. Phase 3: **backend-owned scratch undo** + **presence** are built
> against the live contract (verify on-device); **push (item 11) is now built
> too — Android-only** (FCM token → Appwrite push target via
> `account.createPushTarget`/`updatePushTarget`/`deletePushTarget`, provider
> `moona_fcm`; foreground toast + tap routing on the confirmed `data.type`
> contract). `flutter analyze` clean, 78 tests pass, release APK builds. **The
> only remaining step is operational and backend-owned:** flip
> `MOONA_PUSH_ENABLED=true` once a device has registered a push target (see
> `front_to_backend.md`). iOS/APNs remains parked.
> Originally frontend-authored for backend-dev review.
> Every feature below states an explicit **Backend role** so the backend surface
> is unambiguous.

> **Backend review (2026-06-09):** Overall direction approved with a few
> backend constraints noted below. I would keep the first implementation narrow:
> Phase 1 + the `list_events` backbone, then layer suggestions/insights once the
> event write path is proven. The plan's biggest correction is presence: the
> current `profiles` rows are only readable by their owning user, so profile
> realtime cannot reliably broadcast "shopping now" to other participants unless
> we change profile permissions. I would rather use a dedicated presence table.

## Context
Both devs brainstormed and the combined backlog was ranked by complexity (prior
plan). The user picked **11 features to build** and **parked 6** for later. This
plan turns the 11 into an implementation strategy, grouped into 3 phases, with the
backend contract (new tables / fields / actions / messaging) called out per feature
and consolidated at the end.

**Selected (this plan):** Buy Again · Staple reminders · Insights · Store Mode ·
Shop by seller · Bulk paste · Push notifications · Someone's-shopping-now (presence)
· Item attribution · Backend-owned scratch undo · Recent activity feed.

**Parked (out of scope here):** Multiple named lists · Estimated budget · Barcode
scan · Assign-to-viewer · Sharing roles · Invite-unregistered.

## Architecture grounding (what already exists)
- **Frontend** (`lib/`): central `AppController`/`AppState`
  (`lib/app/app_controller.dart`), repo abstraction
  (`lib/data/repositories/moona_repository.dart` + `appwrite_…` live +
  `fake_…` in-memory), models (`lib/data/models/models.dart`), home list +
  sorting/grouping/category-filter (`lib/features/list/main_screen.dart`), item
  card + scratch/undo (`lib/features/list/item_card.dart`), add/edit sheet +
  product autocomplete (`lib/features/list/item_form.dart`), AR/EN strings
  (`lib/core/l10n/app_strings.dart`), widget bridge + `moona://` deep links +
  background isolate (`lib/features/widget/widget_bridge.dart`), settings
  (`lib/features/sharing/settings_sheet.dart`), offline bootstrap cache
  (`lib/data/cache/bootstrap_cache.dart`).
- **Backend** (`backend/lib/src/`): single `moonaApi` function dispatching on
  `action` (`function_handler.dart` + `operations.dart`), repo/data layer
  (`appwrite_repository.dart`), declarative schema (`schema.dart`), permissions
  (`listItemPermissions`, `sharePermissions`, `profileLookup`).
- **Confirmed facts that shape this plan:**
  - `list_items` **already has** `createdByUserId`, `updatedByUserId`,
    `trashedByUserId`, `trashedAt`, `trashReason` — but **no** `price`,
    `assignedToUserId`, scratch-state fields.
  - `seller` is already on every item (Shop-by-seller is frontend-only).
  - **`clearTrash` HARD-deletes** trashed rows; there is no retention log → history
    features need a durable log (see the backbone decision below).
  - Sorting already supports group-by-category (Store Mode reuses it).
  - Realtime is permission-scoped per table; adding a table adds a channel.
  - **Standing requirement:** every new repo method must also be implemented in
    `fake_moona_repository.dart` so the test suite + web build stay green.

---

## ⭐ Cross-cutting backbone decision (please weigh in first)
Five of the eleven features need durable, queryable item-history that survives
`clearTrash`: **Activity feed, Buy Again, Staple reminders, Insights**, and the
purchase signal produced by **Backend-owned scratch undo**.

**Recommendation:** one **append-only `list_events` table** serves all of them.
- Activity feed = recent events for the visible owner list.
- Buy Again / staples / insights = aggregations over `type = scratched` (+ `added`).
- It makes the `clearTrash` hard-delete irrelevant (events persist independently).

**Alternative** (backend's call): a separate focused `purchase_history` table for
the aggregations, leaving `list_events` purely for the feed. Slightly more schema
but cleaner separation of concerns. **Either works for the frontend** — flagging so
the backend dev picks the model they'd rather own. The rest of this plan assumes
the single `list_events` table.

> **Backend decision:** use a single `list_events` table for the MVP. If
> suggestions or insights get slow later, add a materialized `purchase_stats`
> table maintained from events; do not start with both `list_events` and
> `purchase_history`. For now, bound aggregations by `rangeDays` and/or a max
> event count so the function stays inside the 15s timeout.

Proposed `list_events` shape (append-only, written by the function only):
```
ownerId (req), actorId (req),
type (enum: added | edited | scratched | deleted | restored | cleared
            | share_accepted | share_revoked),
itemId?, productId?, productName?, count?, unitId?, categoryId?,
brand?, seller?, important?, createdAt (req)
indexes: (ownerId, createdAt desc), (ownerId, type, createdAt)
permissions: read = owner + accepted viewers; write = function only
realtime: tablesdb.moona.tables.list_events.rows
```

> **Backend note:** include snapshot product labels (`productName`,
> `productNameAr`, `productNameEn` if available) because product catalog rows can
> later be merged/renamed. `deleted` is separate from `scratched`: explicit
> edit-sheet deletes are not a purchase signal, while finalized scratches are.

---

## Phase 1 — Quick wins (frontend-led, little/no backend)

### 1. Shop by seller
- **Backend role: NONE.** `seller` already on items.
- **Frontend:** add a seller filter/group alongside the existing category filter
  (`_CategoryBar` pattern in `main_screen.dart`); add `seller` to the sort/group
  keys. Pure UI + AppState filter field. New AR/EN strings.

### 2. Store Mode
- **Backend role: NONE** (consumes existing items; later reads presence from
  Phase 3, but ships without it).
- **Frontend:** new route/screen — mandatory group-by-category (sort already
  supports it), large tap targets, `wakelock_plus` to keep screen awake, a
  progress bar (checked ÷ total). Entry point: a button on the main screen.
  No model changes.

### 3. Bulk paste
- **Backend role: OPTIONAL.** MVP loops the existing `createItem`. Optional
  optimization: a `createItemsBatch { items: [...] }` action to cut N round-trips
  and dedupe server-side. Flagging as a backend "nice-to-have," not required.
- **Frontend:** a "paste list" affordance in the add sheet → split lines → resolve
  each via the existing `searchProducts` matcher → create. Reuses `item_form.dart`.

### 4. Item attribution
- **Backend role: SMALL (enrichment only, no schema change).** `createdByUserId` /
  `updatedByUserId` already exist; enrich `getBootstrapData` active items with
  `createdByDisplayName` / `updatedByDisplayName` via the existing `profileLookup`
  (exactly like `trashedByDisplayName` today).
- **Frontend:** parse the two new name fields on `ListItem`; show "added by …" /
  "edited by …" on the card footer or edit sheet — only rendered in shared lists.
  Cached for free (part of bootstrap).

> **Backend comment:** agree. This is the best first backend change because it is
> enrichment-only. I will also include the raw ids already present so older
> clients remain compatible and newer clients can fall back through `profiles`.

---

## Phase 2 — Event backbone + history features
*Lands the `list_events` table first; the rest build on it.*

### 5. Recent activity feed
- **Backend role: NEW TABLE + WRITES + READ ACTION.**
  - Create `list_events` (shape above).
  - Write an event inside `createItem`, `updateItem`, `trashItem`,
    `restoreTrashItem`, `clearTrash`, `respondShare(accept)`, `unlinkShare`.
  - New action **`getActivity { limit, cursor } → { events[], nextCursor }`**
    (paginated, scoped to the visible owner).
  - Add the `list_events` realtime channel.
- **Frontend:** new screen (reached from Settings or a header entry) rendering
  events with actor name + relative time; live-updates via the new realtime
  channel; repo method `getActivity` (+ fake impl). New AR/EN strings.

> **Backend comment:** `clearTrash` should emit one `cleared` event with a
> `clearedCount` field, not one event per deleted trash row. The event write
> should happen after the mutation succeeds; for multi-step operations, failure
> to append the event should be logged but should not roll back the user action.

### 6. Buy Again
- **Backend role: NEW READ ACTION (aggregation over `list_events`).**
  - **`suggestItems { limit } → { suggestions: [{ productId, productName, unitId,
    categoryId, brand, seller, purchaseCount, lastPurchasedAt, avgIntervalDays,
    dueScore }] }`** — top products by frequency+recency for the visible owner,
    **excluding products already on the active list**.
  - Recommend **also embedding a compact top-N in `getBootstrapData`** so the
    Buy-Again row renders on cached/offline launch; `suggestItems` serves the
    full/refreshed list on demand.
- **Frontend:** a horizontal chip row above the list; tap → prefilled `createItem`.
  New `PurchaseSuggestion` model + AppState field.

> **Backend comment:** agree, with a bounded first version: aggregate finalized
> `scratched` events from the last 180-365 days and cap scanned rows. If the list
> becomes large, this is the first place to introduce `purchase_stats`.

### 7. Staple reminders
- **Backend role: NONE beyond #6** — `avgIntervalDays` + `lastPurchasedAt` +
  `dueScore` come from the same `suggestItems` payload.
- **Frontend:** compute "due" client-side (days-since-last vs cadence); surface
  due staples as a badged subsection of the Buy-Again row ("you usually buy milk by
  now"). Pure UI on Phase-2 data.

### 8. Insights
- **Backend role: NEW READ ACTION (lazy aggregation).**
  - **`getInsights { rangeDays } → { totalChecked, distinctProducts,
    topProducts[], byCategory[], byDayOfWeek[7], byWeek[] }`**, aggregated over
    `list_events` for the visible owner. Lazy — only called when the screen opens.
- **Frontend:** new Insights screen (from Settings) rendering simple stats/charts;
  repo method `getInsights` (+ fake impl). New AR/EN strings.

> **Backend comment:** make `rangeDays` explicit and clamp it, for example
> 7-365 days. Returning arrays keyed by stable ids (`categoryId`, `productId`)
> plus snapshot display labels will keep the charts resilient to catalog changes.

---

## Phase 3 — Reliability + realtime/messaging (heavier joint backend)

### 9. Backend-owned scratch undo
*The principled fix for the widget's "process killed before the 10s commit reverts"
limitation already logged in `front_to_backend.md`.*
- **Backend role: NEW FIELDS + NEW ACTIONS + FINALIZATION.**
  - Add to `list_items`: `scratchedAt?`, `scratchExpiresAt?`, `scratchedByUserId?`
    (keep `status='active'` until finalize → `'trash'`, to avoid churning every
    existing status filter; **enum alternative** — add a `scratched` status — is
    the backend's call to weigh).
  - **`scratchItem { itemId, windowSeconds? }`** → set scratch fields,
    `scratchExpiresAt = now + window` (default 10s); realtime propagates so all
    viewers see a consistent strike-through/countdown.
  - **`undoScratchItem { itemId }`** → clear scratch fields if not yet finalized.
  - **Finalize:** lazy sweep on `getBootstrapData` (move expired scratches to trash
    via the existing `trashPatch` **and write the `scratched` `list_events` row** —
    this is where Phase 2's purchase signal originates) + a best-effort client
    `finalizeScratch { itemId }` after the window. **Optional** cron sweep for
    timeliness (backend decides if worth the extra function).
  - `trashItem` stays for explicit deletes (`reason: user_delete`); the *scratch*
    path moves to `scratchItem`.
- **Frontend:** replace the local `Timer` + `scratched` Set in `item_card.dart` /
  `app_controller.dart` with server-driven scratch state (countdown derived from
  `scratchExpiresAt`); **the widget background isolate calls `scratchItem` instead
  of the deferred `trashItem`**, so a killed process no longer reverts the check-off.

> **Backend decision:** use additive scratch fields and keep `status='active'`
> until finalize. A new `scratched` status would touch every active/trash query,
> duplicate check, widget payload, and older client assumption. `scratchItem`,
> `undoScratchItem`, and `finalizeScratch` should be idempotent. Any accepted
> list participant can undo before expiry; after expiry, finalize wins.
>
> **Finalize decision:** lazy-on-read plus a best-effort client
> `finalizeScratch` is enough for v1. Add a scheduled sweep only after we see a
> real timeliness problem. Lazy sweep should run before `getBootstrapData`,
> `suggestItems`, `getActivity`, and list mutations so stale scratches do not
> distort counts.

### 10. Someone's-shopping-now (presence)
- **Backend role: SMALL TABLE + 1 ACTION.**
  - Preferred backend shape: add `shopping_presence` rows keyed by actor/user
    (`ownerId`, `actorId`, `activeAt`, `updatedAt`) with read permissions for
    the owner + accepted viewers of `ownerId`. Do **not** put this on `profiles`
    unless we are willing to broaden profile row permissions; current profile
    documents are user-private.
  - **`setShoppingPresence { active }`** → upsert/delete the caller's presence row
    for the visible owner. Subscribe to
    `tablesdb.moona.tables.shopping_presence.rows`.
- **Frontend:** heartbeat (~30s) while in Store Mode; render "Noor is shopping now"
  when another member of the visible owner list has a fresh heartbeat
  (treat > 60s as stale, client-side). Clear on exit/background. Pairs with push.

### 11. Push notifications
- **Backend role: LARGE (Appwrite Messaging + provider setup + send-on-event).**
  - **Operational (backend-owned):** configure a Messaging provider in the Appwrite
    console (FCM server key for Android, APNs cert for iOS); grant the function a
    `messaging.write` scope.
  - **Send logic:** after the relevant mutation, call `messaging.createPush`
    targeting recipient users directly. Appwrite can fan out to that user's push
    targets; per-user topics are unnecessary for private app events and add
    subscription lifecycle work. Events, phased:
    - **P11a:** share requested → notify target viewer; share accepted → notify owner.
    - **P11b:** item added/edited on a *shared* list → notify the other members.
    - **P11c:** "someone started shopping" (from `setShoppingPresence`) → notify
      members; (optional) staple-due / daily digest via a scheduled function.
- **Frontend:** integrate `firebase_messaging` (Android) / APNs (iOS); obtain the
  device token; register it as an Appwrite push target
  (`account.createPushTarget`); handle foreground/background notifications and
  deep-link taps (reuse the `moona://` scheme). Token lifecycle on login/logout.

> **Backend comment:** confirmed from Appwrite docs that server-side
> `messaging.createPush` supports `users`, `targets`, and `topics`. Use `users`
> for Moona's private notifications. Frontend still owns push permission,
> token refresh, `account.createPushTarget` / update / cleanup, and Android
> `POST_NOTIFICATIONS`.

---

## Backend surface — consolidated (for the backend dev to scan)
| Feature | Backend role | New action(s) | Schema change | Realtime / Messaging |
|---------|-------------|---------------|---------------|----------------------|
| Shop by seller | **None** | — | — | — |
| Store Mode | **None** | — | — | — |
| Bulk paste | **Optional** | `createItemsBatch`? | — | — |
| Item attribution | **Enrich only** | — (extend `getBootstrapData`) | none (fields exist) | — |
| Activity feed | **New table + writes** | `getActivity` | `list_events` table | + `list_events` channel |
| Buy Again | **New read** | `suggestItems` (+ bootstrap embed) | (reads `list_events`) | — |
| Staple reminders | **None beyond Buy Again** | — | — | — |
| Insights | **New read** | `getInsights` | (reads `list_events`) | — |
| Scratch undo | **Fields + actions + finalize** | `scratchItem`, `undoScratchItem`, `finalizeScratch` | `list_items`: `scratchedAt`, `scratchExpiresAt`, `scratchedByUserId` | (existing `list_items` channel; optional cron) |
| Presence | **Table + 1 action** | `setShoppingPresence` | `shopping_presence` table | + `shopping_presence` channel |
| Push | **Large** | send-on-event in existing handlers | push targets (Appwrite-managed) | Appwrite Messaging + provider + `messaging.write` scope |

**New tables:** `list_events`, `shopping_presence`.
**New fields:** `list_items` ×3 (scratch).
**New actions:** `getActivity`, `suggestItems`, `getInsights`, `scratchItem`,
`undoScratchItem`, `finalizeScratch`, `setShoppingPresence` (+ optional
`createItemsBatch`).
**Bootstrap additions:** `createdByDisplayName`/`updatedByDisplayName` on items;
compact `suggestions` block.
**Ops:** Messaging provider + `messaging.write` scope; (optional) scratch-finalize cron.

## Open questions for the backend dev
1. **Backbone:** single `list_events` for feed + history aggregations, or a
   separate `purchase_history`? (Frontend is fine either way.)
   - **Backend answer:** single `list_events` for v1; add materialized
     `purchase_stats` later only if needed.
2. **Scratch state model:** additive fields with `status='active'` until finalize
   (recommended, low churn) vs a new `scratched` status enum value?
   - **Backend answer:** additive fields, keep `status='active'` until finalize.
3. **Finalize mechanism:** lazy-on-read + best-effort client call enough, or do you
   want a scheduled cron sweep for timeliness?
   - **Backend answer:** lazy-on-read + best-effort `finalizeScratch` for v1.
     Cron is optional later.
4. **Suggestions delivery:** OK to embed a compact top-N in `getBootstrapData`
   (for offline-first Buy-Again) in addition to the `suggestItems` action?
   - **Backend answer:** yes, compact top-N only, generated after scratch
     finalization and kept bounded.
5. **Push targeting:** target users directly via `messaging.createPush`, or
   per-user topics? Any preference on where push-target registration lives?
   - **Backend answer:** target users directly via `messaging.createPush(users:
     [...])`. Push-target registration lives in the frontend Appwrite Account
     flow; backend only sends.

## Sequencing rationale
- **Phase 1** ships value immediately with near-zero backend risk and warms up the
  frontend patterns (filters, new screen, repo method, attribution display).
- **Phase 2** lands the `list_events` backbone once, then Activity feed + Buy Again
  + Staples + Insights all fall out of it — and it dissolves the `clearTrash`
  retention problem.
- **Phase 3** takes the two heaviest/most-coupled items last: scratch-undo (touches
  the most-used path + the widget, and emits Phase 2's purchase event), then
  presence + push (realtime/messaging, with push rolled out P11a→P11c).

## Verification (per phase, once built)
- After each repo-method addition: implement it in `fake_moona_repository.dart`,
  keep `flutter analyze` clean and the test suite green; add focused unit tests
  (filter logic, suggestion/insights parsing, scratch-state reconciliation).
- **Phase 1:** on-device — seller filter narrows the list; Store Mode keeps the
  screen awake + progress advances on scratch; bulk paste creates N items; shared
  list shows "added by".
- **Phase 2:** scratch an item, `clearTrash`, confirm it still appears in Activity
  feed + Buy Again (proves durability); Insights screen matches event counts.
- **Phase 3:** force-stop the app, check an item off **from the widget**, confirm it
  finalizes server-side (the scratch-undo reliability goal); two devices on one
  shared list show presence + receive pushes on share/add/shopping events.
