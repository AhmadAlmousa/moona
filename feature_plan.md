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

---
---

# UI/UX expert pass — next-wave feature proposals (2026-06-11)

> **Context:** the 11 features above are shipped. This section is a fresh UX
> review proposing the *next* wave, based on patterns proven in comparable apps
> (Bring!, AnyList, OurGroceries, Listonic, Google Keep / WhatsApp-adjacent
> sharing flows), filtered against what is already built or parked, and grounded
> in Moona's actual architecture (offline-first bootstrap cache, `list_events`
> backbone, `searchProducts` matcher, bulk-paste pipeline, `moona://` scheme,
> Store Mode, push). Same conventions as above: every item states an explicit
> **Backend role**.
>
> **Lens used:** Moona's core loop is *capture at home → coordinate with one
> other person → execute in the store*. The proposals below each remove friction
> from exactly one of those three moments. Parked items (multiple lists, budget,
> barcode, assign-to-viewer, roles, invite-unregistered) stay parked, though A1
> deliberately softens the invite-unregistered gap.

## Tier A — high impact, small effort (mostly frontend-only)

### A1. Share/export list as text (WhatsApp-ready) + paste-back import
- **Why:** in the target market the fallback coordination tool *is* WhatsApp.
  Letting a user send the visible list as clean text ("• حليب ×2 …") to someone
  **without a Moona account** keeps Moona the source of truth instead of being
  abandoned for a chat message. The same format round-trips through the existing
  bulk-paste pipeline, so the recipient's reply ("add eggs and bread") pastes
  straight back in. This is the cheapest possible answer to the parked
  *invite-unregistered* item — and every exported message is organic marketing.
- **Frontend:** "Share as text" in the header/settings menu → compose localized
  plain text (group by category, include count+unit) → `share_plus` system sheet.
  Bulk-paste already tolerates the bullet format (strip `•`, `-`, counts).
- **Backend role: NONE.**
- **Effort:** S.

### A2. Smart quantity parsing in the add field
- **Why:** Bring!/Listonic users type `2 kg rice` / `٢ كيلو رز` and the app
  splits it. Moona's add sheet currently needs separate taps for count and unit
  — the highest-frequency flow in the app pays that cost on every item. Parsing
  leading/trailing quantity+unit tokens (AR + EN, Arabic-Indic numerals already
  normalized in `phone.dart`-style helpers) cuts adds to one field, one confirm.
- **Frontend:** pure parser in front of the existing `item_form.dart` state
  (unit names matched against the loaded `units` catalog, both locales);
  pre-fills count/unit chips, user can still correct. Unit-tested like
  `phone_test.dart`.
- **Backend role: NONE.**
- **Effort:** S–M.

### A3. Recent-items quick chips inside the add sheet
- **Why:** Buy Again (above) lives on the *home* screen for re-stocking intent;
  this is the same data surfaced at the *moment of typing*. OurGroceries shows
  your last/frequent items as one-tap chips before you type a letter — most
  sessions end without using the keyboard at all.
- **Frontend:** reuse the bootstrap-embedded `suggestions` + most recent
  `scratched` names; render 8 chips above the text field in `item_form.dart`;
  tap = prefill + confirm.
- **Backend role: NONE** (data already in bootstrap).
- **Effort:** S.

### A4. Global undo snackbar (beyond scratch)
- **Why:** scratch has a beautiful 10s undo; *every other* destructive action
  (edit-sheet delete, **clear trash**, bulk add) is final. Inconsistent safety
  teaches users to hesitate. A "Trash cleared — UNDO" snackbar is the standard
  Material contract users already expect.
- **Frontend:** delete/bulk paths are already optimistic — hold the repo call
  (or its inverse) behind the snackbar window, mirroring `_finalizeTimers`.
- **Backend role: NONE** for delete-undo (defer the `trashItem` call);
  **SMALL** if clear-trash undo is wanted server-truthfully (either delay the
  `clearTrash` call client-side — recommended, zero backend — or add a soft
  `restoreTrash` window later).
- **Effort:** S (deferred-call variant).

### A5. Check-off feel: haptics + completion moment
- **Why:** the scratch gesture is Moona's signature interaction; right now it is
  visually correct but physically silent. A light haptic on scratch, a heavier
  one on finalize, and a one-shot celebration when Store Mode hits 100%
  ("Done — 14 items ✓") is cheap delight that makes the core loop *feel*
  finished. Every successful list app over-invests exactly here.
- **Frontend:** `HapticFeedback.*` in `item_card.dart` / Store Mode; completion
  state derived from the existing progress bar value.
- **Backend role: NONE.** **Effort:** S.

### A6. "Follow system" theme option
- **Why:** the toggle is binary light/dark; the platform default everywhere else
  is tri-state. Users who auto-switch at sunset currently fight Moona twice a day.
- **Frontend + backend (tiny):** `theme` enum gains `system`
  (`profiles.theme` enum + `validTheme` in `operations.dart`); client maps it to
  `ThemeMode.system`. Older clients unaffected if backend keeps accepting
  light/dark.
- **Backend role: SMALL** (enum value + validation). **Effort:** S.

### A7. In-list search/filter field
- **Why:** with Buy Again + bulk paste shipping, real lists grow past one
  screen; finding "did we already add tahini?" by scrolling is the #1 silent
  friction in long lists. A pull-down search field (Keep-style) that filters the
  visible list — and offers "add ‹query›" when nothing matches — turns a miss
  into an add.
- **Frontend:** AppState filter string + the existing list-filter pipeline; the
  no-match CTA reuses `addItem`.
- **Backend role: NONE.** **Effort:** S.

## Tier B — high impact, moderate effort

### B1. Voice add (AR/EN dictation → bulk pipeline)
- **Why:** hands-busy capture (cooking, driving) is the moment lists leak to
  memory. Bring! and Alexa-class assistants own this; Moona can get 90% with
  on-device dictation: one button, speak "حليب وبيض وخبز", split on connectors
  ("و", "and", commas) → existing `addItemsBulk`. Arabic-first dictation is a
  differentiator most Western list apps do badly.
- **Frontend:** `speech_to_text` plugin (on-device, no server), mic button in
  the add sheet, results piped through the A2 parser then `addItemsBulk`;
  graceful degrade where the locale model is missing (hide the mic).
- **Backend role: NONE.** **Effort:** M.

### B2. List templates ("My baskets")
- **Why:** AnyList/Bring! recurring-list templates are their stickiest feature.
  Households re-buy the same ~20 staples weekly and event baskets seasonally
  ("Ramadan", "school week", "trip"). One tap → template's items are added
  (duplicates skipped — `addItemsBulk` semantics already do this). Distinct from
  Buy Again: templates are *intentional curation*, suggestions are *inference*.
- **Frontend:** "Save current list as template" + a templates row/sheet;
  apply = bulk add.
- **Backend role: SMALL-MEDIUM.** New `list_templates` table (ownerId, name,
  items JSON snapshot[name/count/unit/category], timestamps; read/write owner +
  accepted viewers) + `saveTemplate` / `listTemplates` / `deleteTemplate`
  actions, or — zero-schema MVP — store templates **client-side in the KvStore**
  first and promote to backend when sharing templates matters. Recommend the
  client-side MVP.
- **Effort:** M (client-side MVP: S–M).

### B3. "Not available here" — postpone in Store Mode
- **Why:** the real-store failure case: item's out of stock. Today the choices
  are scratch it (lies to history — looks *purchased*, poisoning Buy Again
  cadence) or leave it (list never completes, progress bar stuck). A long-press
  "not available" parks the item visually (dimmed, bottom section), keeps it
  active, completes the trip progress without it, and clears the flag on next
  app open. Protects the integrity of the Phase-2 purchase signal — strongly
  recommended **before** Buy Again data accumulates.
- **Frontend:** transient client-side flag (KvStore, per trip) — no server state
  needed for v1 since it's a *this-trip* concept; Store Mode sections + progress
  math respect it.
- **Backend role: NONE (v1).** If the shared partner should see it live, later
  promote to an item field + realtime (SMALL).
- **Effort:** S–M.

### B4. Learned store order (aisle-order sorting per seller)
- **Why:** OurGroceries' killer in-store feature: the app learns the order you
  check things off in a given store and sorts the next trip's list that way —
  milk ends up at the bottom because dairy is your last aisle. Store Mode +
  `seller` + the `scratched` event stream (with `categoryId` and `seller`)
  already capture everything needed.
- **Frontend:** per-seller category-order vector learned from finalized-scratch
  order (client-side from `getActivity`/local trip log, stored in KvStore);
  Store Mode sorts groups by it when a seller filter is active; falls back to
  the default category order.
- **Backend role: NONE** (events already carry seller+category;
  client aggregates). **Effort:** M.

### B5. Notification preferences + quiet hours
- **Why:** P11b ("item added/edited") is the highest-volume push class; without
  per-class mute, the first over-notified user disables notifications at the OS
  level and *all* pushes (including share requests) die. Standard fatigue
  control: per-type toggles (shares / list changes / shopping-now) + optional
  quiet hours, defaulting list-change pushes ON only for shared lists.
- **Frontend:** toggles in the settings sheet → stored on the profile.
- **Backend role: SMALL-MEDIUM.** `profiles.pushPrefs` (string/JSON or discrete
  booleans) + `sendPushSafely` filters recipients by their prefs before
  `createPush` (`operations.dart:1118-1139` is the single choke point — good
  design dividend).
- **Effort:** M.

### B6. Android/PWA share-target ("Share to Moona")
- **Why:** lists arrive as text from outside (WhatsApp message from spouse, a
  recipe site's ingredients). Registering Moona as a system **share target**
  (Android intent filter + PWA `share_target` manifest entry) means
  select text → Share → Moona → bulk-paste preview sheet → done. Pairs with A1
  to complete the WhatsApp round-trip; reuses the deferred-intent pattern the
  widget's `moona://add` already established in `main.dart`.
- **Frontend:** Android `ACTION_SEND` intent filter + PWA manifest
  `share_target`; route received text into the bulk-paste confirm sheet.
- **Backend role: NONE.** **Effort:** M.

### B7. Post-trip summary
- **Why:** closes the loop after Store Mode: "Trip done — 14 items, 32 min, 3
  not available" with a one-tap "send summary" (A1 text share) to the partner
  who didn't shop. Gives presence/push a natural *end* event ("Noor finished
  shopping") and makes Insights feel alive instead of buried in Settings.
- **Frontend:** trip = Store-Mode session; aggregate locally from scratches
  during the session; summary sheet on exit.
- **Backend role: NONE** for v1 (optional later: `shopping_finished` push via
  the existing presence action when `active:false` with a summary payload —
  SMALL). **Effort:** M.

## Tier C — heavier / strategic (flag now, schedule deliberately)

### C1. Offline mutation queue (capture never fails)
- **Why:** the bootstrap cache made *reading* offline-first; *writing* still
  requires connectivity — yet the two highest-stakes moments are connectivity
  holes (supermarket interiors, kitchens at the edge of Wi-Fi). Queue
  `createItem`/`scratchItem`/`undoScratch` locally (KvStore), apply optimistic
  UI immediately (already the pattern), replay on reconnect; surface a subtle
  "syncing N changes" pill. Duplicate-on-replay is already handled server-side
  (`duplicate_item` 409 → drop). This is the single biggest *reliability* UX
  gap left; also the riskiest (conflict semantics on shared lists), hence Tier C.
- **Backend role: NONE** (existing idempotent-ish actions suffice for v1;
  scratch replay after expiry already self-heals via the lazy sweep).
- **Effort:** L–XL. Do **after** the audit's M1 correctness fixes land.

### C2. Near-duplicate guard at add time ("Did you mean…?")
- **Why:** "طماطم/بندورة", "tomato/tomatoes" create parallel histories that
  quietly degrade Buy Again, Insights, and autocomplete. The backend already
  computes similarity (`suggestProductMerges`, `rules.dart:733`); surfacing the
  same check at add time — "You usually call this *Tomatoes* — use that?" —
  prevents the mess instead of admin-merging it later.
- **Frontend:** on add-confirm, run the similarity check against the loaded
  product names (the Levenshtein helper is small — mirror it client-side);
  one-tap accept swaps the name.
- **Backend role: NONE** (client-side against the bootstrap catalog) or
  **SMALL** (a `checkProductName` action reusing `similarityScore`).
- **Effort:** M.

### C3. Unpark iOS: APNs push + iOS home-screen widget
- **Why:** every sharing pair is two devices; in this market the second device
  is very often an iPhone. A shared list where one side gets pushes/widget and
  the other doesn't *feels* broken to the iOS partner. The widget bridge was
  explicitly designed payload-compatible ("iOS shares the same payload later" —
  `widget_bridge.dart:1`), and push is one provider config away
  (`moona_apns` shell already exists per `back_to_frontend.md`).
- **Backend role: OPERATIONAL** (APNs cert on the existing provider).
  Frontend: WidgetKit extension consuming the existing JSON payload + APNs
  permission flow.
- **Effort:** L (needs Apple credentials + a Mac in the loop).

## Recommended order & how it composes
1. **A1 + A7 + A5** (one small sprint: share-as-text, search, haptics) — pure
   frontend, immediately user-visible.
2. **A2 → A3 → B1** in that order: the quantity parser (A2) is the foundation
   the chips (A3) and voice (B1) both feed through — one pipeline, three
   entry points.
3. **B3 before Buy-Again data matures** — protects purchase-signal integrity.
4. **B5 lands with/before push P11b rollout** — fatigue control before volume.
5. **A4, A6, B6, B2, B7, B4** as filler items between heavier audit work.
6. **C1 after audit Milestone 1**, C2 anytime, C3 when Apple credentials exist.

**Explicitly not proposed** (considered and rejected for now): meal-planning /
recipe management (scope creep into a different app), price tracking (parked as
*budget*), gamified streaks (wrong tone for a household utility), AI list
generation (cost + trust; the deterministic suggestions already cover the
value), in-app chat (WhatsApp owns it — A1/B6 integrate instead of competing).
