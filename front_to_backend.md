# Frontend → Backend Notes

This file carries contract changes, missing fields, blockers, and mockup-driven
API needs discovered during Flutter/Riverpod implementation. The backend dev
replies in `back_to_frontend.md`.

Last updated: 2026-06-11 (frontend — scratch restore + Buy Again bug traced to stale server fields; backend fix needed)

## Scratch fields not cleared on server — causes restore + Buy-Again bug (frontend, 2026-06-11)

Two user-visible bugs traced to the same root cause: `scratchedAt` /
`scratchExpiresAt` / `scratchedByUserId` are **not cleared on the server row**
when an item is finalized or restored.

### What the bugs look like
- **Restore from trash**: tapping Restore brought the item back as scratched
  (struck-through + Undo button) and it then auto-deleted after ~10s.
- **Buy Again re-add**: tapping a suggestion from the Buy Again dropdown added
  the item, but it appeared scratched immediately and then auto-deleted.

### Root cause
`finalizeScratch` on the server sets `status: "trash"` but leaves
`scratchedAt` / `scratchExpiresAt` / `scratchedByUserId` on the row. When the
item is later restored (or re-created from the same underlying row), the client
receives an active item with a past `scratchExpiresAt`. The backend's lazy
finalize sweep then picks it up, sees the expiry already passed, and moves it
back to trash — causing the "auto-delete" the user sees.

### Frontend mitigations shipped (2026-06-11)
1. **`isScratched` now checks future expiry**: `scratchExpiresAt?.isAfter(DateTime.now()) ?? false`. Items with a stale past `scratchExpiresAt` no longer render as scratched client-side.
2. **`restoreItem` clears scratch fields in the optimistic update**: the
   optimistic restored item explicitly has `scratchedAt/scratchExpiresAt/scratchedByUserId = null`, so it appears as a clean active item even before the server responds.
3. Same fix applied to `fake_moona_repository.restoreTrashItem`.

These mitigations suppress the visible bug on the client, but the **backend
still needs to clear the scratch fields on the actual row**:

### Backend asks (2 changes, same root cause)
1. **`finalizeScratch`** — after moving the item to `status: "trash"`, clear
   `scratchedAt`, `scratchExpiresAt`, and `scratchedByUserId` on the row
   (set them to null). Currently the row is trashed with the scratch fields
   still present.
2. **`restoreTrashItem`** — when restoring an item to `status: "active"`,
   clear the same three fields. Without this, the lazy-finalize sweep will
   immediately re-trash the just-restored item if the expiry is in the past.

No new action or schema change needed — just `null`-out those three fields in
both operations. Once done, the client-side mitigations become belt-and-braces
rather than the primary fix.

## Web/PWA push — wired on the frontend; needs ONE backend gate: a Web push provider (frontend, 2026-06-10)

Follow-up to the Android push pass. I extended push to the **installable PWA /
web** build in the same shape, so the existing send-on-event points light up for
web users too — **but it needs a small operational add on your side**, mirroring
the `moona_fcm` gate.

### What I added (frontend / web-only path)
- **Web FCM token registration.** On web I call `getToken(vapidKey: <FCM web push
  certificate>)` and register it as a push target exactly like Android:
  `account.createPushTarget(targetId: ID.unique(), identifier: <webFcmToken>,
  providerId: 'moona_fcm')`, with the same on-device target-id persistence and
  `updatePushTarget`/`deletePushTarget` lifecycle on token refresh / logout.
- **Service worker.** `web/firebase-messaging-sw.js` (FCM compat SW) handles
  background notifications + tap→focus/open. Foreground keeps the same in-app
  toast keyed off `data.type`.
- **VAPID key is config-gated.** `MoonaConfig.fcmVapidKey` (`--dart-define=
  FCM_VAPID_KEY=...`). **While it's empty, web push registration is skipped
  entirely** — nothing breaks, web just doesn't request a token. So shipping this
  ahead of the provider gate is safe.
- Firebase Web app + `firebase_options.dart` (web) are in place; these are public
  client identifiers, not secrets.

### The backend gate (this is the actual ask)
1. **Confirm whether `moona_fcm` (your existing FCM provider) covers Web Push too,
   or if Web needs a separate Appwrite Messaging provider.** Appwrite FCM
   providers generally fan out to web FCM tokens registered on the same provider,
   so I'm **assuming web push targets on `moona_fcm` work with your existing
   `messaging.createPush(users: [...])` sends with no new send code.** Please
   confirm — if web needs its own provider id, tell me here and I'll add the one
   constant (web path only).
2. **No new send logic expected.** Your `share_requested` / `share_accepted` /
   `item_added` / `item_edited` / `shopping_started` sends target *users*, so a
   web push target on that user is just another target Appwrite fans out to. If
   that's not how your provider is set up, flag it.
3. **`MOONA_PUSH_ENABLED` is the same single gate** — once it's on (still waiting
   on the Android device registration), web sends flow through it too.

### What I still owe (frontend, not blocking you)
- Paste the **FCM Web Push certificate (VAPID public key)** into the build
  (`Firebase → Project settings → Cloud Messaging → Web Push certificates →
  Generate key pair`). It's console-only / not API-exposed, so I'll grab it from
  the Firebase console and wire the `--dart-define`. Until then web push is a
  safe no-op.

**Net web-push ask: just confirm `moona_fcm` (or a web provider) covers web FCM
tokens; no new send code expected.** Everything else (token registration,
lifecycle, SW, foreground/tap routing) is done on the frontend and degrades to
nothing while the VAPID key is empty.

## Push (Phase 3, item 11) — BUILT on the frontend (Android). One gate left: yours (frontend, 2026-06-10)

## Push (Phase 3, item 11) — BUILT on the frontend (Android). One gate left: yours (frontend, 2026-06-10)

Your push setup note landed (Firebase `moona-71bf8`, config files dropped in,
`moona_fcm` FCM provider enabled, payload contract confirmed, owner green-lit
Android-only). So I did the frontend push pass in one focused go. **`flutter
analyze` (lib+test) clean, 78 tests pass (+7 in `test/push_test.dart`), and the
release APK builds with the Firebase deps in place.**

### What I added
- **Deps:** `firebase_core` + `firebase_messaging` (Android-only path). Firebase
  is initialised and the FCM push service is selected **only when
  `defaultTargetPlatform == android`** (in `main.dart`); web/desktop/tests keep a
  no-op push service, so nothing else is affected. `firebase_options.dart` is not
  needed — the Android `com.google.gms.google-services` Gradle plugin consumes
  your `android/app/google-services.json`.
- **Android wiring:** applied the `google-services` Gradle plugin (settings +
  app), added `POST_NOTIFICATIONS` to the manifest (requested at runtime after
  sign-in).
- **Registration / lifecycle:** after sign-in **and** session restore I call
  `account.createPushTarget(targetId: ID.unique(), identifier: <fcmToken>,
  providerId: 'moona_fcm')`. I **persist the target id on-device** so a token
  refresh `account.updatePushTarget`s the *same* target (no dupes), and **logout
  `account.deletePushTarget`s** it before the session is torn down. All
  best-effort — push never blocks auth.
- **Payload routing (matches your confirmed contract):** I read `data.type` ∈
  `{ share_requested, share_accepted, item_added, item_edited, shopping_started }`
  plus `ownerId` / `itemId` / `shareId` / `viewerId` / `actorId`. **Foreground:**
  a localized in-app toast keyed off `type` (Android suppresses the tray
  notification while foregrounded), falling back to the notification body.
  **Tap:** brings the app up and refreshes the visible list (a pending incoming
  share then auto-prompts via the existing bootstrap path); cold-start taps are
  handled via `getInitialMessage`. Title `Moona` + human-readable body are shown
  by the system tray when backgrounded, exactly as you described.

### The one remaining gate is yours
1. **Flip `MOONA_PUSH_ENABLED=true` on `moonaApi`** — but only **after** at least
   one device has registered a push target. To verify one exists: sign in on an
   Android device/build, grant the notification permission, then check that user
   in the Appwrite console (**Auth → the user → Targets**) — you should see a
   **push** target on provider **`moona_fcm`**. Once you see it, enable the gate
   and your already-wired send-on-event points light up.
2. **Confirm the provider id.** I hardcoded `MoonaConfig.fcmProviderId =
   'moona_fcm'` (from your note). If the provider id differs, tell me here and
   I'll change the one constant.

### Caveats I'm logging (no action needed unless they bite)
- **iOS/APNs stays parked** — I init Firebase + select the push impl on Android
  only, so the iOS build is untouched. When APNs creds are on `moona_apns`, the
  iOS pass is: enable the provider, add the iOS push entitlement +
  `UIBackgroundModes`, and drop the Android-only platform guard.
- **No `onBackgroundMessage` data handler.** You send notification+data messages,
  so the system tray displays them when backgrounded and tap-routing covers the
  rest. If you ever switch any event to **data-only** sends, flag it and I'll add
  a background isolate handler.

### Verify on-device (two devices on one shared list, once the gate is on)
Device A adds/edits an item, or starts shopping → device B gets the push (tray
when backgrounded, toast when foregrounded); tapping it opens B on the refreshed
list. Share request → target gets `share_requested`; accept → owner gets
`share_accepted`.

## Push (Phase 3, item 11) — backend requirements to unblock it (frontend, 2026-06-10)

Status sync first: **Phases A/B/C are now committed** (3 commits on
`feat/offline-signin-and-widget-fixes`; lib+test analyze clean, **71 tests pass**;
your backend pass committed alongside, 29 tests pass). One housekeeping heads-up:
I removed the obsolete `mockup/` prototype and gitignored the local `references/`
dir — no backend impact.

**Push back-out (so the build stays green):** a half-started push attempt had added
`firebase_core` + `firebase_messaging` to `pubspec.yaml` with **no** Firebase
project config. On Android that breaks `flutter build apk` (FCM needs the
`google-services` Gradle plugin + `google-services.json`), so I **reverted both
deps**. Push stays deferred until the setup below exists. When you confirm the
provider side is ready and the owner green-lights the FCM/APNs dependency, I'll
re-add the deps and do the frontend work in one focused pass (`account.createPushTarget`
registration + token lifecycle on login/logout + foreground/background handlers +
`moona://` tap deep-links). Your gated send-on-event points are already in place
(`6a27ba5da1f0974bb1a2`), so this is purely the operational + config gate.

**What's on your (backend) plate before push can light up:**
1. **Appwrite Messaging provider setup (operational, console).** Configure an FCM
   provider for Android and an APNs provider for iOS in the Appwrite console, and
   confirm the `moonaApi` function has the `messages.write` scope (you noted it
   already does). Flip the send gate on (`MOONA_PUSH_ENABLED=true`) only once a
   provider exists and at least one device has registered a push target — until
   then keep sends as no-ops.
2. **Firebase project + config files (owner/backend to provide).** A Firebase
   project is required because Appwrite's FCM provider needs the FCM server
   credentials, and the Android app needs `google-services.json`
   (and iOS needs `GoogleService-Info.plist` + an APNs key/cert uploaded to
   Appwrite/Firebase). I can't generate these — please drop them in (or hand me
   the Firebase project so I can fetch them). This is the actual blocker.
3. **Confirm the send targeting + payload shape you'll emit.** You said
   `messaging.createPush(users: [...])` targeting users directly (good — no topics).
   Please confirm the **data payload** keys you'll attach so I can wire deep-links:
   I'm planning to read a `type` (e.g. `share_requested` | `share_accepted` |
   `item_added` | `shopping_started`) plus an optional `ownerId` / `itemId`, and
   route taps via the existing `moona://` scheme. If you emit different keys, tell
   me here and I'll match them.

No code change requested from you right now — items 1–2 are operational/asset
setup, item 3 is a confirmation. Reply in `back_to_frontend.md` with the provider
status, the config files (or project access), and the push data-payload shape, and
I'll pick up the frontend push integration immediately.

## Phase C shipped (frontend) — Phase 3 reliability/realtime, built on your live contract

Picked up the next phase from `feature_plan.md`: **Phase 3**. Two of the three
are now built on the frontend against the contract you already deployed
(`6a27ba5da1f0974bb1a2`) — so **no new backend deploy is needed**, just on-device
verification. The third (push) is the one item still gated on your operational
setup; details at the bottom. `flutter analyze` (lib+test) clean, **71 tests
pass** (added `test/phase_c_test.dart`, +8).

### 1. Backend-owned scratch undo — replaces the client timer (your scratch contract)
The 10s scratch is now **server-owned**, not a client `Timer` + in-memory set.
- On tap I call **`scratchItem { itemId, windowSeconds: 10 }`** and render the
  countdown from the row's **`scratchExpiresAt`** (so a viewer who joins
  mid-scratch, or restarts the app, sees the correct remaining slice, not a
  fresh 10s). Undo calls **`undoScratchItem { itemId }`**; at expiry the client
  fires a best-effort **`finalizeScratch { itemId }`** (your lazy-on-read sweep is
  the safety net if it doesn't run).
- `ListItem` now parses `scratchedAt` / `scratchExpiresAt` / `scratchedByUserId`;
  `isScratched` is derived from `scratchExpiresAt`. I **dropped the client
  `scratched` Set** entirely — scratch state lives on the row, so it survives
  restarts and **propagates to all viewers via the existing `list_items`
  realtime channel** (a scratched-but-active row shows struck-through; the
  finalize arrives as a `status: trash` update and drops it from the active list).
- **Widget closed-app fix (the big one):** the background isolate now commits
  **`scratchItem` up front** on tap instead of a deferred `trashItem`. This
  **resolves the documented limitation** where a process killed inside the 10s
  window reverted the check-off — the scratch is durable server-side the instant
  it's tapped, and your lazy/`finalizeScratch` finalization trashes it regardless.
  Widget Undo now calls `undoScratchItem` server-side too.

### 2. Someone's-shopping-now (presence) — your `shopping_presence` table + action
- **Heartbeat:** Store Mode calls **`setShoppingPresence { active: true }`** on
  enter and re-sends every **30s** (well inside a 60s staleness window), and
  **`{ active: false }`** on exit.
- **Indicator:** a slim "X is shopping now" banner on the main screen **and** in
  Store Mode, shown when another participant on the visible owner list has a
  **fresh** heartbeat (client treats >60s as stale and re-evaluates on a 15s
  ticker). Names resolve via the bootstrap `profiles` map (falling back to a
  row's `actorDisplayName` if you include one).
- **Realtime:** I added `shopping_presence` to the subscribed channels
  (`tablesdb.moona.tables.shopping_presence.rows`) and **patch presence rows
  directly** from the realtime payload (upsert by `actorId`, drop on delete)
  rather than re-bootstrapping on every heartbeat. I read presence rows from
  bootstrap's **`shoppingPresence`** array and from realtime as
  `{ ownerId, actorId, actorDisplayName?, activeAt|updatedAt }`.

### Shape confirmations for you (all tolerant of omission)
- **`scratchItem` / `undoScratchItem` / `finalizeScratch`**: I don't read a
  response body — I update optimistically and reconcile from the `list_items`
  realtime row. So whatever you return is fine; I just need the **row update**
  to carry `scratchExpiresAt` (set on scratch, cleared on undo) and the eventual
  `status: trash` on finalize. Confirm scratch fields ride the normal
  `list_items` realtime row (I'm assuming they do).
- **`shopping_presence` realtime payload**: I parse `actorId`, `ownerId`, and a
  timestamp from `activeAt` → `updatedAt` → `$updatedAt` (first present wins).
  If the raw row has neither `activeAt` nor `updatedAt` set, freshness can't be
  computed — please make sure one of them is on the row.

**Net Phase C ask: nothing to deploy — just verify on-device** (two devices on
one shared list: scratch on A shows the countdown on B and finalizes to trash;
force-stop A then check off from its widget and confirm it stays trashed; both
see each other's "shopping now" banner in Store Mode).

### Push (Phase 3, item 11) — NOT built yet; blocked on your provider setup
I deliberately did **not** add `firebase_messaging`/APNs in this pass. It needs
a real Firebase project (`google-services.json`) + APNs cert that the Android/iOS
build requires — adding the dependency without those would break the build for
everyone. You also flagged sends stay no-ops until the **Messaging provider** is
configured and `MOONA_PUSH_ENABLED=true`. So push waits on: (a) you finishing
the provider/console setup, and (b) a decision from the app owner to take on the
FCM/APNs dependency. Once the provider exists, the frontend work is
`account.createPushTarget` registration + token lifecycle + tap deep-links
(reusing the `moona://` scheme) — I'll pick that up as a focused follow-up. Your
gated send-on-event points (`6a27ba5da1f0974bb1a2`) are ready for it.

## Phase B shipped (frontend) — built against your local Phase-2 contract

Picked up the next phase from `feature_plan.md`: **Phase 2 — event backbone +
history features**. All four are now built on the frontend against the contract
you implemented locally (per your 2026-06-09 feature-plan backend pass). It's
wired to **degrade to nothing** until your `provision.dart` + `moonaApi`
redeploy lands, so shipping the client ahead of the deploy is safe. `flutter
analyze` (lib+test) clean, **63 tests pass** (added `test/phase_b_test.dart`,
+11).

1. **Recent activity feed** — new pushed screen (`lib/features/activity/`),
   reached from a Settings row. Calls **`getActivity { limit, cursor }`**,
   paginates via `nextCursor` ("Load more"), resolves actor names from the
   page's `profiles` map (falling back to the bootstrap `profiles` lookup), and
   **live-refreshes** off a new `list_events` realtime subscription. I added
   `list_events` to the client's subscribed channels
   (`tablesdb.moona.tables.list_events.rows`) and a controller signal that
   refetches the open feed on any event. Unknown `type` values render as nothing
   (forward-compatible).
2. **Buy Again** — a horizontal "shelf" of one-tap re-add chips above the list
   (unfiltered view only). Renders from the compact **`suggestions.items`**
   embedded in `getBootstrapData` (so it shows offline/instantly), and
   `refreshSuggestions` pulls the full list from **`suggestItems { limit }`** on
   demand. Tap → existing `createItem` (prefilled unit/category/brand/seller),
   then the chip drops. Excludes products already on the active list client-side
   too, so it stays correct the instant something is added or arrives via
   realtime.
3. **Staple reminders** — pure client UI on Phase-2 data: a suggestion is shown
   as **"Due"** (tinted + badge, floated to the front) when your `dueScore >= 1`
   **or** (fallback) `now - lastPurchasedAt >= avgIntervalDays`. No extra
   backend beyond `suggestItems`.
4. **Insights** — new pushed screen (`lib/features/insights/`) from a Settings
   row. Calls **`getInsights { rangeDays }`** (fixed 90 for v1), rendering
   totals, a most-bought bar list, a by-category breakdown, and a day-of-week
   bar chart.

### Two small shape confirmations for you
- **`getInsights.byDayOfWeek`**: I render it as a length-7 array, **Sunday-first**
  (index 0 = Sunday … 6 = Saturday). The client tolerates a wrong length, but
  please emit Sunday-first so the day labels line up. `topProducts` entries I
  read as `{ productId, productName, productNameAr?, productNameEn?, count }`
  and `byCategory` as `{ categoryId, count }` — matching your documented shapes.
- **`suggestItems` / `suggestions.items`**: I read `{ productId, productName,
  productNameAr?, productNameEn?, unitId?, categoryId?, brand?, seller?,
  purchaseCount, lastPurchasedAt?, avgIntervalDays?, dueScore? }`. All optional
  fields tolerate omission.

**Net Phase B ask: just the provision + redeploy** so these light up live. When
that's deployed, drop the deployment id in `back_to_frontend.md` and I'll verify
on-device. Phase 3 (backend-owned scratch undo, presence, push) is **not** built
yet — that's the next phase after this deploy is verified.

## Phase A shipped (frontend) — one backend ask: attribution enrichment

Per the approved phased plan (`feature_plan.md`), Phase A is built on the
frontend. Three of the four are **frontend-only, no backend change**; the fourth
needs the small **Gate A** enrichment from you. `flutter analyze` (lib+test)
clean, **52 tests pass** (added `test/phase_a_test.dart`).

1. **Shop by seller** — *no backend change.* A secondary store-filter bar
   (`sellerFilter` on `AppState`, applied after the category filter; only shown
   when the current view spans 2+ stores). Reuses the existing `seller` field.
2. **Store Mode** — *no backend change.* New focused in-store screen
   (`lib/features/list/store_mode.dart`): category-grouped, big tap targets,
   progress bar, keep-awake (`wakelock_plus`), check-off reuses the existing
   scratch→trash flow.
3. **Bulk paste** — *no backend change for v1.* "Paste a list" in the add sheet
   splits lines and loops the existing `createItem` (dedupes input, skips
   duplicates, caps at 50). If/when you want it, the optional `createItemsBatch`
   from the plan would cut the N round-trips — **not requested yet.**
4. **Item attribution** — ⏳ **needs Gate A (the one backend ask).** The frontend
   already parses `createdByDisplayName` / `updatedByDisplayName` on list items
   and renders an "added by / last edited by" caption in the **edit sheet** on
   shared lists. It **degrades to nothing** until you enrich `getBootstrapData`
   active items with those names (via the existing `profileLookup`, exactly like
   `trashedByDisplayName`). Please keep the raw `createdByUserId`/
   `updatedByUserId` too — the client falls back through the `profiles` map.
   Once that deploy lands, attribution lights up with no further frontend change.

**Net Phase A ask: just the attribution name enrichment on bootstrap.** When
that's deployed, note the deployment id in `back_to_frontend.md` and I'll verify
live. Then we move to Phase B (`list_events` backbone + activity feed).

## Feature brainstorm — open for backend ideas + feasibility (frontend, 2026-06-09)

Not a change request yet. The user asked both of us to dump our best feature
ideas here first, then we'll discuss and pick together. Backend dev: please add
your own ideas below this section (and react to / cost any of mine). I've split
each by who carries the work so we can see the backend surface at a glance.

### The framing insight: Trash is an untapped purchase log
Every scratch-off lands in trash with `trashedAt` / `trashedByUserId` /
`trashReason`. That's a complete timestamped buying history we currently discard.
Three features fall out of it, all leaning on data you already store:

1. **"Buy Again" shelf** — a one-tap re-add row of most-bought / recently-bought
   items. *Backend:* a `getPurchaseHistory` action (frequency + recency
   aggregation over trash), **or** fold a small `frequentItems` list into
   `getBootstrapData`. *Frontend:* a chip/recents row + re-add.
2. **Staple reminders** — detect cadence (e.g. milk ~every 5 days) and surface
   "running low?" nudges. Same aggregation, plus a per-item interval estimate.
3. **Insights** — "bought X 6× this month," most-frequent items, busiest day.
   Cheap retention hook on the same data.

**Q for backend:** is trash retained indefinitely, or does `clearTrash` /
any TTL purge it? If trash is ephemeral, the history features need a separate
durable purchase-log write on trash (a heads-up worth deciding early).

### Shopping experience (highest daily-use payoff)
4. **Shopping / Store Mode** — focused full-screen run: group by `category`
   (already in schema), big tap targets, keep-screen-awake, progress ("4 of 11").
   *Frontend-only.*
5. **Shop-by-seller filter** — items already carry `seller`; a filter chip turns
   the list into a per-store run. *Frontend-only.*
6. **Estimated total / budget** — optional price per item, live sum.
   *Backend:* one nullable `price` field on list items. *Frontend:* input + sum.

### Faster input
7. **Voice add** — speak "milk, two loaves of bread, eggs" → parsed rows.
   *Frontend* (`speech_to_text`) + existing product matcher.
8. **Bulk paste** — paste a recipe/text list, split lines into items.
   *Frontend-only.*
9. **Barcode scan** — scan to add/identify a product. *Backend:* a `barcode`
   field on products + a lookup-by-barcode (could extend `searchProducts` or a
   new action). *Frontend:* `mobile_scanner` (camera already wired for images).

### Collaboration (we're a shared app — lean in)
10. **Assign item to a viewer** — "Noor grabs the milk." *Backend:* a nullable
    `assignedToUserId` on list items (+ enrich via the existing `profiles` map).
    *Frontend:* avatar on the card + assign action.
11. **"Someone's shopping now" presence** — a live indicator so two people don't
    double-buy. *Backend:* a small presence flag/doc (or reuse realtime).
    *Frontend:* banner + heartbeat.
12. **Push notifications** — invite received, item added to a shared list,
    "someone started shopping." Biggest *missing* primitive (no push today).
    *Backend:* Appwrite Messaging + storing FCM/APNs push targets per user;
    triggers on share + item events. *Frontend:* token registration + handlers.
    Bigger joint lift, but it's what makes sharing feel alive.

### Structure (heavier, later)
13. **Multiple named lists** (Groceries / Pharmacy / Hardware). Powerful but the
    heaviest change — touches schema, sharing, widget, and bootstrap. Flagging,
    not proposing for now.
14. **Saved templates** ("load my weekly staples") — can ride on the Buy-Again
    data once #1 exists.

**My top 3 to start (low backend cost, fast):** #1 Buy Again, #4 Shopping Mode,
#7 Voice add. The only backend ask among them is the history aggregation for #1.
Backend dev — add yours below and flag anything here that's cheaper/harder than I
assumed.

## Offline-first launch + widget display fix — no backend change (frontend)

Picked up four user-requested polish items. All frontend-only; **no backend
change requested** — flagging for awareness only.

1. **Offline-first sign-in.** The app now caches the last `getBootstrapData`
   response **locally on-device** (a JSON file in the app documents dir) and
   hydrates the home screen from it on launch while it re-validates the session
   and refreshes in the background (the Settings gear spins as the indicator).
   This reuses the existing `getBootstrapData` contract verbatim — same call,
   same shape; I just persist the raw response and re-parse it. The cache is
   cleared on logout and dropped if the restored session is rejected. No new
   endpoint, no payload change.
2. **Widget "+" → Add sheet** now feels instant because the app boots straight
   to the cached home screen, then opens the in-app add sheet (unchanged
   `moona://add` deep link).
3. **Widget item display fix** (the widget rendered empty on-device). Root cause
   confirmed via an on-screen diagnostic: data reached the widget store fine
   (`payload=true, items=2`) but the third-party launcher (Octopi) doesn't host
   the `RemoteViewsService`-backed `ListView`. Fix: dropped the
   service/`ListView` and now render rows directly as child `RemoteViews`
   (`LinearLayout` + `addView`) in `MoonaWidgetProvider`; per-row check-off +
   detail toggle use direct background `PendingIntent`s. Renders on every
   launcher (trade-off: no scroll, capped at 50 rows). Pure client/Android.
4. **Widget "open app" button** added left of "+" (`moona://open`). UI-only.
5. Settings: moved the share control under the user's account info. UI-only.

Confirmed working on-device. Nothing to action; replies optional.

## Home-screen widget — heads-up, no backend change requested (frontend)

Building an Android home-screen widget (iOS WidgetKit to follow). It is almost
entirely a frontend effort and reuses the existing contract — flagging one thing
for your awareness and a quick confirmation.

### What it does (no new endpoints)
- **Display** reuses data the app already has: the app writes a compact snapshot
  of the visible list to the widget's shared storage (`home_widget` plugin) on
  every list change; the native widget renders it. No background `getBootstrapData`,
  no new read endpoint.
- **Add from the widget** just launches the app to the existing in-app add sheet
  (`showItemForm`) via an app-internal `moona://add` deep link. No backend impact.
- **Check-off from the widget** reuses **`trashItem`** (`reason: "scratch_timer"`),
  exactly as the in-app 10s scratch already does.

### The one thing to confirm
When the user checks an item off **while the app is closed**, the tap runs in a
**headless background Dart isolate** (home_widget's WorkManager worker). There I
construct a fresh `AppwriteMoonaRepository`, call `restoreSession()`, then
`trashItem(id)`. This reuses the **persisted Appwrite session** (the SDK's cookie
jar under the app's documents dir — `path_provider` is auto-registered in the
background engine, so the same session loads). So a `moonaApi` execution will
arrive from a re-instantiated client on the **same session/user**, just not from
the main isolate.

Please confirm there's nothing server-side that would reject a function execution
on these grounds (e.g. session/JWT binding to a specific client instance, or
`trashItem` assuming prior `getBootstrapData` context in the same run). I expect
this is a no-op for you — `trashItem` is already documented as a standalone call
the frontend makes after the timer — but if you foresee an issue, the fallback is
to mint a short-lived JWT (`Account.createJWT`) while the app is foregrounded and
`setJWT` it in the isolate; that would need no backend change either, just a heads-up.

**Net: no backend change requested. Confirmation only.** Reply in
`back_to_frontend.md`.

### Limitations of the Android v1 (logged for later)
- **No animated countdown** in the widget (the OS throttles widget repaints) —
  a checked-off item shows strike-through + an Undo affordance for the window,
  then disappears. Not the smooth in-app countdown bar.
- **Widget follows the system light/dark theme** (`values-night`), not the
  in-app manual theme override. (The `dark` flag is in the payload for iOS/
  future use.)
- **Snapshot freshness**: the widget reflects this device's last app run + its
  own check-offs. Items added on **another device** appear only after this
  device's app is next opened (or a check-off triggers realtime while open).
- **Dropped the app-side "self-heal commit"** (kept auth non-blocking): if the
  process is killed *within* the 10s window before the background commit lands,
  that check-off **reverts** on next app open (the widget re-syncs to the
  authoritative list) instead of being committed. The common case (process alive
  ~10s while the user is on the home screen) commits fine.
- **Not yet verified on-device**: the closed-app check-off reusing the persisted
  Appwrite session in the background isolate (the session-reuse question above).

### Next steps (logged for later)
1. **On-device QA**: add the widget; verify the red-pinned compact list, tap →
   strike-through + Undo (undo within 10s restores; otherwise it's removed),
   "+" → in-app add sheet, detail toggle, AR/RTL + dark. **Crucially:** force-stop
   the app, check an item off **from the widget**, and confirm it trashes
   server-side (reopen / second device). If it only commits on reopen, wire the
   JWT fallback: `Account.createJWT` while foregrounded → `setJWT` in the isolate.
2. **iOS WidgetKit fast-follow** (separate PR): add a widget extension target +
   App Group `group.sa.almou.moona` + entitlements; `HomeWidget.setAppGroupId`;
   SwiftUI views reading the same payload; App Intents (iOS 16/17) for check-off
   + detail toggle; `widgetURL`/`Link("moona://add")` for add. Same session-reuse
   question applies on iOS.
3. (Optional) If bulletproof closed-app check-off is wanted, replace the in-isolate
   delayed commit with a WorkManager-scheduled commit so a killed process still
   finishes the trash.

## Fixed Android bottom sheets rendering under the navigation bar (frontend)

User reported modals showing up below the Android system navigation bar. Root
cause was frontend-only, no backend impact: our `showMoonaSheet` already passes
`useSafeArea: true`, but in Flutter that flag only guards **top/left/right**
(it's `SafeArea(bottom: false, ...)` internally) — the bottom is the caller's
responsibility. `_SheetScaffold` was padding the bottom by `viewInsets.bottom`
(keyboard) only, never the nav-bar inset, so with Flutter 3.41 + Android 15
edge-to-edge the sheet content slid under the nav bar. Fix: pad the bottom by
`math.max(viewInsets.bottom, viewPadding.bottom)` (they don't stack — an open
keyboard already covers the nav bar). `flutter analyze` clean, 35 tests pass.

## Root-caused the empty device contact list — it was never a device restriction (frontend)

Closing the loop on the long "empty contact picker" saga. The earlier theory
(a Samsung/One UI sideload restriction blocking our contacts read) was **wrong**.
A reference plugin (`references/ContactX`) read the full contact list on the same
device, which ruled the restriction theory out.

Real cause: **`flutter_contacts` adds `IN_VISIBLE_GROUP = 1` to its Android
query**, which drops every contact that isn't in a "visible group". Synced/SIM
contacts on Samsung/One UI are routinely flagged outside any visible group, so
the query returned an **empty cursor with no error** even with `READ_CONTACTS`
granted. `adb content query` and ContactX both see everything because they hit
`Contacts.CONTENT_URI` with no visible-group filter.

Fix (frontend-only, no backend impact): set
`FlutterContacts.config.includeNonVisibleOnAndroid = true` before
`getContacts(...)` in `loadDeviceContacts()`. `flutter analyze` is clean and all
35 tests pass.

Note on versions: we **stay pinned to `flutter_contacts` 1.x**. 1.x exposes the
`includeNonVisibleOnAndroid` flag; **2.x (incl. latest 2.2.1) removed it and
hardcodes the filter with no Dart opt-out**, so the empty-list bug is unfixable
from Dart on 2.x. Bumping to 2.x would require replacing the read path with a
native `Contacts.CONTENT_URI` query. Flagging so this pin isn't "upgraded" later
without that work. Nothing needed from the backend.

## Reviewed your 2026-06-05 contact-picker refactor + display-name edit (frontend)

Reviewed commit `cefc679` (your investigation + refactor). Everything looks
correct and the suite is still green — `flutter analyze` clean, **35 tests**
pass (the new `contact_picker_test.dart` you added is included).

### ✅ Picker helpers are correct and testable
`ContactPickerDeviceContact` / `ContactPickerRow` / `buildContactPickerRows` /
`contactLookupPhones` are all marked `@visibleForTesting` and cleanly separated
from widget code. The `_displayDigitsFor` fallback correctly keeps contacts with
any non-empty raw digits (e.g. short codes `123`) visible as "Not on Moona",
matching the requirement. Android `normalizedNumber` is tried first; local
normalization is the fallback; raw digits are the last resort — so no device
contact is silently dropped.

### ✅ Settings → Account edit wired up
`onTap: () => showDisplayNameDialog(context, ref)` and the edit icon are now on
the account row in `settings_sheet.dart`. `showDisplayNameDialog` is exported
publicly from `contact_picker.dart` and is reused from both the Settings entry
and the share flow's `_ensureDisplayName` gate — single source of truth.

### ✅ New strings picked up
`changeDisplayName`, `changeDisplayNameBody`, `yourName`, `yourNameHint`, and
`continueLabel` are all in `app_strings.dart` with AR + EN variants.

No further action needed from the frontend side on this note.

## Picked up your 2026-06-05 contact-picker bug follow-up (frontend)

Fixed all three native-integration issues you flagged. `flutter analyze` is clean
and all 30 tests pass.

### ✅ Removed the custom in-app permission dialog → request the OS directly
`showContactFlow` no longer shows our own "Allow access to contacts" dialog
first. It now calls `FlutterContacts.permissions.request(PermissionType.read)`
directly (the real 2.1.0 API — it's `permissions.request`, returning a
`PermissionStatus`, not a bool) and only loads `getAll(...)` on
`granted`/`limited`. On `denied`/`permanentlyDenied`/`restricted` the picker
opens in manual-entry mode with an **Open settings** action wired to
`FlutterContacts.permissions.openSettings()`. The method-channel call is wrapped
so web/desktop/tests (no contacts backend) degrade to manual entry instead of
throwing. Dropped the now-dead `contactsPermTitle/Body/allow/dontAllow` strings.

### ✅ Native permissions added
- Android: `<uses-permission android:name="android.permission.READ_CONTACTS"/>`
  in `android/app/src/main/AndroidManifest.xml` (release builds only merge the
  main manifest, so it had to live here).
- iOS: `NSContactsUsageDescription` in `ios/Runner/Info.plist` with a string
  noting names stay on-device.

### ✅ Device contacts are now the row source; lookup only enriches/splits
Rewrote the picker so rows are built from the **device contacts** first
(normalized + deduped by `phoneDigits`, all numbers per contact, not just the
first), then annotated from the `lookupContacts` response indexed by
`phoneDigits`. So an empty/failed lookup no longer collapses the picker — every
device contact still shows (under **Not on Moona** with Invite) and registered
hits float up to **On Moona**. Local saved names still win over the profile
`displayName`. I also defensively append any `registered` entry you return that
didn't line up with a device row (normalization drift) so it's never dropped.
Phones-only on the wire is unchanged.

## Picked up your 2026-06-05 contact-discovery + sharing-UX note (frontend)

Implemented all four asks from your 2026-06-05 handoff. `flutter analyze` is
clean and all 30 tests pass (added contact-lookup + display-name-gate tests).

### ✅ `lookupContacts` wired into the contact picker
The share picker now resolves device contacts against registered users via the
new `lookupContacts` action instead of blindly calling `requestShare`.
- **Phones only on the wire**: I send `{ phones: [...], limit: 250 }`. Local
  contact names never leave the device — I rejoin them client-side by
  `phoneDigits` (computed with the shared normalizer) so a registered user
  still shows under the name the owner saved them as, falling back to your
  `displayName`, then the number.
- **Sectioned UI**: results render as **On Moona** (registered, top) then
  **Not on Moona** (unregistered, with an "Invite" pill that routes through the
  existing `requestShare`→invite path). I rely on your registered-first
  ordering and also re-split client-side defensively.
- **`isSelf`** rows are shown disabled (can't tap), pre-empting `share_self`.
- Models: added `ContactLookupEntry` / `ContactLookupResult` (parses top-level
  `contacts` + `invalid`; tolerant of missing keys). Repo method
  `lookupContacts(List<String>)` on both live + fake repos; the live one returns
  empty + the picker degrades to manual entry on error.
- Reminder: this needs the `moonaApi` redeploy before it works live (you flagged
  it's not live yet). Until then the picker shows manual entry only.

### ✅ Display-name prompt before sharing
Before the contact flow opens (from **either** the header share button or the
Settings "Share with a contact" entry), if the profile name is empty **or is
just the phone digits** I prompt for a real name and persist it via
`updatePreferences(displayName:)`. So counterparties never see a raw user id.
Gate logic: `AppController.needsDisplayName` / `setDisplayName`.

### ✅ Header: theme icon → share-list entry
Removed the theme toggle from the main header (theme lives in Settings only now)
and put a **share** entry (person icon) in its place; it carries the
sharing-active badge and opens the contact flow. Settings gear stays.

### ✅ Visible sign-in indicator across the whole auth path
Session **restore** now flips `busy` on (disabling the login form + showing the
spinner with a "Signing in…" label) while it probes for a session and runs
`ensureProfile` + `getBootstrapData`, matching the existing sign-in path. So
there's a continuous indicator during session/account/profile/bootstrap work.


## Picked up your 2026-06-04 enrichment + token work (frontend)

Implemented the client side of everything in your two 2026-06-04 notes. All of
this is in code now; `flutter analyze` is clean and all 28 tests pass.

### ✅ Q8 mobile image auth — now wired to `createImageViewToken`
This was the only real outstanding client gap. I replaced the synchronous
`imageUrl(fileId)` with `imageViewUrl({itemId, fileId})` across the repository
interface. The live repo now calls `createImageViewToken` (action added to
`MoonaFunctions`), appends `&token=<encoded>` to the bucket view URL, and
**caches the token per `itemId|fileId`** until ~30s before `expire` so we don't
hit the function on every thumbnail rebuild. On a token error it falls back to
the bare view URL (web still authenticates via the session cookie). The list
thumbnail (`_ItemImage` in `item_card.dart`) now resolves the URL via a
`FutureBuilder` and shows the branded placeholder while loading / on 401.
- Using the default TTL (omitting `ttlSeconds`, so backend's 900s). Shout if
  you'd rather I pin a value.
- Reminder for you: this needs the redeploy with the `tokens.write` function
  scope before it works live — until then mobile image reads will 401 and show
  the placeholder (graceful, not a crash).

### ✅ Q3 / Q4 names — consuming your enriched shapes
No client change needed beyond what was already wired. Models parse both shapes:
`Share.counterpartyName/counterpartyPhone`, the bootstrap/sharing `profiles`
map (`BootstrapData.profileNames`), and `ListItem.trashedByDisplayName`. Sharing
UI, the incoming-share prompt, and Trash attribution now render real names once
your redeploy is live. One small note: `getSharingStatus` returns a top-level
`profiles` map next to `sharing`, but I only read the per-share
`counterparty*` fields there (bootstrap is where I read the `profiles` map), so
the duplicate `profiles` on `getSharingStatus` is currently unused by me — fine
to keep for symmetry, just FYI.

### ✅ Item-form UX (your investigation note)
Done: in the add/edit sheet, **Category now sits directly below the Important
toggle** and **defaults to `grocery`** for new items (falls back to the first
category if `grocery` is missing). Edits keep the item's existing category.

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

---

## Admin feature shipped (2026-06-12, full-stack, deployed)

In-app admin surface built + deployed end-to-end (frontend `lib/features/admin/*`
+ backend ops + live MCP provision/deploy). Contract + provisioning details are in
`back_to_frontend.md` → "Admin feature". Key points the frontend now relies on:
`profile.isAdmin` in bootstrap gates the Settings → Admin entry; `catalogs.brands`
/`catalogs.stores` feed the item-form brand/store autocomplete (free text still
allowed); new actions `adminResetUser` + `adminUpdate('users',…)` + brands/stores
admin kinds. moonaApi redeployed (`6a2c424784ad06540c58`).
