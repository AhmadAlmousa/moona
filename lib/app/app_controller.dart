import 'dart:async';
import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/util/phone.dart';
import '../data/models/models.dart';
import '../data/repositories/moona_repository.dart';
import '../features/push/push_notifications.dart';
import 'app_state.dart';
import 'providers.dart';

/// Orchestrates session, list, sharing, preferences, scratch-to-delete timers,
/// and realtime reconciliation. UI widgets read [AppState] and call these
/// methods; optimistic updates keep the list responsive.
class AppController extends Notifier<AppState> {
  /// Best-effort client-side finalize timers (one per in-progress scratch this
  /// device initiated). The authoritative scratch state lives on the item
  /// server-side, so a missed finalize self-heals via the backend's lazy sweep.
  final Map<String, Timer> _finalizeTimers = {};
  StreamSubscription<RealtimeChange>? _realtimeSub;
  bool _disposed = false;

  MoonaRepository get _repo => ref.read(repositoryProvider);
  PushNotifications get _push => ref.read(pushProvider);
  void _toast(String message) => ref.read(toastProvider.notifier).show(message);

  @override
  AppState build() {
    ref.onDispose(() {
      _disposed = true;
      _cancelEverything();
    });
    final locale = PlatformDispatcher.instance.locale;
    final deviceDark =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    Future<void>.microtask(_restoreSession);
    return AppState(
      screen: AppScreen.login,
      lang: locale.languageCode == 'ar' ? 'ar' : 'en',
      dark: deviceDark,
    );
  }

  // ── auth ──────────────────────────────────────────────────────────────
  Future<void> _restoreSession() async {
    if (state.screen != AppScreen.login || state.busy) return;
    // Offline-first: if a previous sign-in cached the list, show the home screen
    // immediately (with the sign-in indicator spinning via [busy]) while we
    // re-validate the session and refresh in the background. Otherwise fall back
    // to the login screen with its spinner as before.
    final cached = await _repo.cachedBootstrap();
    if (_disposed) return;
    if (cached != null && state.screen == AppScreen.login) {
      _applyBootstrap(cached, busy: true);
    } else {
      state = state.copyWith(busy: true);
    }
    try {
      final restored = await _repo.restoreSession();
      if (_disposed) return;
      if (restored) {
        await _loadBootstrap();
        if (!_disposed) {
          _subscribeRealtime();
          unawaited(_push.registerForSession());
        }
        return;
      }
      // The persisted session is gone. If we optimistically showed the cached
      // home screen, drop back to login and clear the now-stale cache.
      if (state.screen == AppScreen.main) {
        await _repo.clearCache();
        if (_disposed) return;
        state = AppState(
          screen: AppScreen.login,
          lang: state.lang,
          dark: state.dark,
        );
        return;
      }
    } catch (e, stack) {
      debugPrint('Moona session restore failed: $e\n$stack');
    }
    if (!_disposed) state = state.copyWith(busy: false);
  }

  Future<void> signIn(String phone, String password) async {
    state = state.copyWith(busy: true, loginError: null);
    try {
      normalizePhone(phone); // client-side validation, mirrors backend.
      await _repo.signIn(phone: phone, password: password);
      await _loadBootstrap();
      _subscribeRealtime();
      unawaited(_push.registerForSession());
    } on InvalidPhoneException {
      state = state.copyWith(busy: false, loginError: state.t.enterPhone);
    } on MoonaException catch (e) {
      if (e.code == MoonaException.unknown) {
        debugPrint('Moona signIn failed: ${e.message}');
      }
      state = state.copyWith(
        busy: false,
        loginError: switch (e.code) {
          MoonaException.wrongPassword => state.t.wrongPass,
          MoonaException.networkError => state.t.networkError,
          _ => state.t.genericError,
        },
      );
    } catch (e, stack) {
      debugPrint('Moona signIn failed: $e\n$stack');
      state = state.copyWith(busy: false, loginError: state.t.genericError);
    }
  }

  Future<void> logout() async {
    _cancelEverything();
    // Delete the push target before tearing down the session (the account API
    // call needs to be authenticated). Best-effort — never blocks logout.
    await _push.unregister();
    await _repo.clearCache();
    await _repo.signOut();
    state = AppState(
      screen: AppScreen.login,
      lang: state.lang,
      dark: state.dark,
    );
  }

  Future<void> _loadBootstrap() async {
    final data = await _repo.bootstrap();
    _applyBootstrap(data, busy: false);
  }

  /// Writes a [BootstrapData] into [state] and switches to the main screen.
  /// Keep [busy] true when hydrating from the local cache so the home screen
  /// shows the sign-in indicator (spinning gear) until the live refresh lands.
  void _applyBootstrap(BootstrapData data, {required bool busy}) {
    state = state.copyWith(
      screen: AppScreen.main,
      busy: busy,
      loginError: null,
      profile: data.profile,
      lang: data.profile.language,
      dark: data.profile.isDark,
      ownerId: data.visibleList.ownerId,
      isShared: data.visibleList.isShared,
      items: data.visibleList.items,
      trash: data.visibleList.trash,
      categories: data.categories,
      units: data.units,
      products: data.products,
      sharing: data.sharing,
      profileNames: data.profileNames,
      suggestions: data.suggestions,
      presence: data.shoppingPresence,
      filter: 'all',
      sellerFilter: 'all',
    );
  }

  Future<void> refresh() async {
    if (state.screen != AppScreen.main) return;
    await _loadBootstrap();
  }

  // ── preferences ────────────────────────────────────────────────────────
  void toggleLang() {
    final next = state.lang == 'ar' ? 'en' : 'ar';
    state = state.copyWith(
      lang: next,
      profile: state.profile?.copyWith(language: next),
    );
    _persistPrefs(language: next);
  }

  void toggleTheme() {
    final next = !state.dark;
    state = state.copyWith(
      dark: next,
      profile: state.profile?.copyWith(theme: next ? 'dark' : 'light'),
    );
    _persistPrefs(theme: next ? 'dark' : 'light');
  }

  Future<void> _persistPrefs({String? language, String? theme}) async {
    try {
      await _repo.updatePreferences(language: language, theme: theme);
    } catch (_) {
      // Preference persistence is best-effort; the UI already reflects it.
    }
  }

  void setFilter(String filter) => state = state.copyWith(filter: filter);

  void setSellerFilter(String seller) =>
      state = state.copyWith(sellerFilter: seller);

  void setSort(SortKey key) => state = state.copyWith(sortKey: key);

  void toggleGrouped() => state = state.copyWith(grouped: !state.grouped);

  // ── items ────────────────────────────────────────────────────────────
  /// Adds an item. Returns true on success so the form can close (a duplicate
  /// or error keeps the form open with the user's input).
  Future<bool> addItem(ItemFormData form) async {
    try {
      final item = await _repo.addItem(form);
      state = state.copyWith(items: _upsertActiveItem(state.items, item));
      _toast(state.t.itemAdded);
      return true;
    } on MoonaException catch (e) {
      _toast(_messageFor(e));
      return false;
    } catch (_) {
      _toast(state.t.genericError);
      return false;
    }
  }

  /// Adds many items from pasted lines (one product name per entry). Skips
  /// duplicates and per-line errors silently — a bad line shouldn't abort the
  /// batch — and shows a single summary toast. Returns how many were added.
  Future<int> addItemsBulk(List<String> names) async {
    final categoryId = _defaultCategoryId();
    var added = 0;
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      try {
        final item = await _repo.addItem(
          ItemFormData(productName: name, categoryId: categoryId),
        );
        state = state.copyWith(items: _upsertActiveItem(state.items, item));
        added++;
      } on MoonaException {
        // Duplicate / invalid line — skip it rather than failing the whole paste.
      } catch (_) {
        // Network or unexpected — skip this line.
      }
    }
    _toast(added > 0 ? state.t.itemsAdded(added) : state.t.nothingAdded);
    return added;
  }

  /// Default category for new items — `grocery` when present, else the first.
  String? _defaultCategoryId() {
    for (final category in state.categories) {
      if (category.id == 'grocery') return category.id;
    }
    return state.categories.isEmpty ? null : state.categories.first.id;
  }

  // ── buy again / suggestions ──────────────────────────────────────────────
  /// One-tap re-add of a Buy-Again suggestion. Reuses [addItem] (so duplicates
  /// and errors toast the same way) and drops the suggestion on success.
  Future<bool> addSuggestion(PurchaseSuggestion suggestion) async {
    final ok = await addItem(
      ItemFormData(
        productName: suggestion.productName,
        unitId: suggestion.unitId,
        categoryId: suggestion.categoryId ?? _defaultCategoryId(),
        brand: suggestion.brand,
        seller: suggestion.seller,
      ),
    );
    if (ok) {
      state = state.copyWith(
        suggestions: state.suggestions
            .where((s) => s.productId != suggestion.productId)
            .toList(),
      );
    }
    return ok;
  }

  /// Refreshes the Buy-Again list on demand (best-effort; leaves the cached
  /// bootstrap suggestions in place on failure).
  Future<void> refreshSuggestions() async {
    try {
      final suggestions = await _repo.suggestItems();
      state = state.copyWith(suggestions: suggestions);
    } catch (_) {
      // Non-fatal — keep whatever bootstrap embedded.
    }
  }

  // ── activity feed + insights ─────────────────────────────────────────────
  /// Loads a page of the activity feed, or null on error (screen shows a
  /// retry/empty state). Pass the previous page's `nextCursor` to page back.
  Future<ActivityFeedPage?> loadActivity({String? cursor}) async {
    try {
      return await _repo.getActivity(cursor: cursor);
    } catch (_) {
      return null;
    }
  }

  /// Loads aggregated insights for [rangeDays], or null on error.
  Future<Insights?> loadInsights({int rangeDays = 90}) async {
    try {
      return await _repo.getInsights(rangeDays: rangeDays);
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateItem(String itemId, ItemFormData form) async {
    try {
      final updated = await _repo.updateItem(itemId, form);
      state = state.copyWith(
        items: [
          for (final i in state.items)
            if (i.id == itemId) updated else i,
        ],
      );
      _toast(state.t.itemUpdated);
      return true;
    } on MoonaException catch (e) {
      _toast(_messageFor(e));
      return false;
    } catch (_) {
      _toast(state.t.genericError);
      return false;
    }
  }

  /// Delete from the edit flow — moves straight to trash.
  Future<void> deleteItem(String itemId) async {
    final item = _activeById(itemId);
    if (item == null) return;
    _applyTrash(item);
    _toast(state.t.removed);
    try {
      await _repo.trashItem(itemId, reason: 'deleted');
    } catch (_) {
      await refresh();
    }
  }

  // ── scratch-to-delete (backend-owned) ───────────────────────────────────
  /// A tap scratches the item (struck-through with a [MoonaConfig.scratchWindow]
  /// countdown to undo), then finalizes it to trash. The scratch state lives on
  /// the item server-side (`scratchExpiresAt`), so it survives restarts,
  /// propagates to other viewers via realtime, and the widget commits it even if
  /// the app process is killed. We still keep a client finalize timer for prompt
  /// trashing; the backend's lazy sweep is the safety net if it doesn't fire.
  void toggleScratch(String itemId) {
    final item = _activeById(itemId);
    if (item == null) return;
    if (item.isScratched) {
      _undoScratch(itemId);
    } else {
      _beginScratch(item);
    }
  }

  void _beginScratch(ListItem item) {
    final now = DateTime.now();
    _replaceActiveItem(
      item.id,
      (i) => i.copyWith(
        scratchedAt: now,
        scratchExpiresAt: now.add(MoonaConfig.scratchWindow),
        scratchedByUserId: state.profile?.id,
      ),
    );
    _finalizeTimers[item.id]?.cancel();
    _finalizeTimers[item.id] = Timer(
      MoonaConfig.scratchWindow,
      () => _finalizeScratch(item.id),
    );
    unawaited(
      _repo
          .scratchItem(
            item.id,
            windowSeconds: MoonaConfig.scratchWindow.inSeconds,
          )
          .catchError((Object _) {
            // Roll the optimistic scratch back on failure.
            _finalizeTimers.remove(item.id)?.cancel();
            _clearScratch(item.id);
          }),
    );
  }

  void _undoScratch(String itemId) {
    _finalizeTimers.remove(itemId)?.cancel();
    _clearScratch(itemId);
    unawaited(_repo.undoScratchItem(itemId).catchError((Object _) => refresh()));
  }

  Future<void> _finalizeScratch(String itemId) async {
    _finalizeTimers.remove(itemId);
    final item = _activeById(itemId);
    if (item == null) return;
    _applyTrash(item);
    _toast(state.t.removed);
    try {
      await _repo.finalizeScratch(itemId);
    } catch (_) {
      await refresh();
    }
  }

  /// Clears the optimistic scratch fields on a still-active item.
  void _clearScratch(String itemId) => _replaceActiveItem(
    itemId,
    (i) => i.copyWith(
      scratchedAt: null,
      scratchExpiresAt: null,
      scratchedByUserId: null,
    ),
  );

  void _replaceActiveItem(String itemId, ListItem Function(ListItem) update) {
    state = state.copyWith(
      items: [
        for (final i in state.items)
          if (i.id == itemId) update(i) else i,
      ],
    );
  }

  ListItem? _activeById(String id) {
    for (final i in state.items) {
      if (i.id == id) return i;
    }
    return null;
  }

  void _applyTrash(ListItem item) {
    final trashed = ListItem(
      id: item.id,
      ownerId: item.ownerId,
      productId: item.productId,
      count: item.count,
      unitId: item.unitId,
      brand: item.brand,
      seller: item.seller,
      categoryId: item.categoryId,
      imageFileId: item.imageFileId,
      important: item.important,
      note: item.note,
      status: ItemStatus.trash,
      trashedAt: DateTime.now(),
      trashedByUserId: state.profile?.id,
      trashedByDisplayName: state.profile?.displayName,
      trashReason: 'scratch_timer',
    );
    state = state.copyWith(
      items: state.items.where((i) => i.id != item.id).toList(),
      trash: [trashed, ...state.trash],
    );
  }

  // ── trash ────────────────────────────────────────────────────────────
  Future<void> restoreItem(String itemId) async {
    ListItem? item;
    for (final i in state.trash) {
      if (i.id == itemId) item = i;
    }
    if (item == null) return;
    state = state.copyWith(
      trash: state.trash.where((i) => i.id != itemId).toList(),
      items: [
        ...state.items,
        item.copyWith(
          status: ItemStatus.active,
          scratchedAt: null,
          scratchExpiresAt: null,
          scratchedByUserId: null,
        ),
      ],
    );
    _toast(state.t.restore);
    try {
      await _repo.restoreTrashItem(itemId);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> clearTrash() async {
    state = state.copyWith(trash: const []);
    try {
      await _repo.clearTrash();
    } catch (_) {
      await refresh();
    }
  }

  // ── sharing ────────────────────────────────────────────────────────────
  /// Resolves which of [phones] are registered Moona users. Phone numbers only —
  /// device contact names stay on the device. Degrades to an empty result on
  /// error so the picker can still offer manual entry.
  Future<ContactLookupResult> lookupContacts(List<String> phones) async {
    try {
      return await _repo.lookupContacts(phones);
    } catch (_) {
      return const ContactLookupResult();
    }
  }

  /// Whether the profile still lacks a real display name (empty, or just the
  /// phone number) — used to gate sharing so counterparties never see a raw id.
  bool get needsDisplayName {
    final profile = state.profile;
    if (profile == null) return false;
    final name = profile.displayName.trim();
    if (name.isEmpty) return true;
    final nameDigits = name.replaceAll(RegExp(r'\D'), '');
    final phoneDigits = profile.phone.replaceAll(RegExp(r'\D'), '');
    return nameDigits.isNotEmpty && nameDigits == phoneDigits;
  }

  /// Persists a chosen display name (optimistic; best-effort persistence) so
  /// shared lists show a real name instead of a raw user id.
  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    final profile = state.profile;
    if (trimmed.isEmpty || profile == null) return;
    state = state.copyWith(profile: profile.copyWith(displayName: trimmed));
    try {
      await _repo.updatePreferences(displayName: trimmed);
    } catch (_) {
      // Best-effort; the UI already reflects the new name.
    }
  }

  Future<void> requestShare(String phone) async {
    try {
      final result = await _repo.requestShare(phone);
      if (!result.targetExists) {
        _toast(state.t.invited);
        return;
      }
      _toast(state.t.shareRequested);
      await _refreshSharing();
    } on MoonaException catch (e) {
      _toast(_messageFor(e));
    } catch (_) {
      _toast(state.t.genericError);
    }
  }

  Future<void> respondShare(String shareId, {required bool accepted}) async {
    try {
      await _repo.respondShare(shareId, accepted: accepted);
      _toast(accepted ? state.t.shareAccepted : state.t.shareDeclined);
      await _loadBootstrap();
    } on MoonaException catch (e) {
      _toast(_messageFor(e));
    } catch (_) {
      _toast(state.t.genericError);
    }
  }

  Future<void> unlink() async {
    final outgoing = state.sharing.acceptedOutgoing;
    try {
      if (state.isShared) {
        await _repo.unlinkShare(ownerId: state.ownerId);
      } else if (outgoing != null) {
        await _repo.unlinkShare(shareId: outgoing.id);
      } else {
        return;
      }
      _toast(state.t.unlinked);
      await _loadBootstrap();
    } on MoonaException catch (e) {
      _toast(_messageFor(e));
    } catch (_) {
      _toast(state.t.genericError);
    }
  }

  Future<void> _refreshSharing() async {
    try {
      final sharing = await _repo.getSharingStatus();
      state = state.copyWith(sharing: sharing);
    } catch (_) {
      // Non-fatal.
    }
  }

  // ── presence ─────────────────────────────────────────────────────────────
  /// Sets/clears this device's "shopping now" presence (heartbeated by Store
  /// Mode). Best-effort: presence is a nicety, never blocks the UI.
  Future<void> setShoppingPresence(bool active) async {
    try {
      await _repo.setShoppingPresence(active: active);
    } catch (_) {
      // Best-effort.
    }
  }

  // ── push notifications ───────────────────────────────────────────────────
  /// Handles a notification tap. The two-screen app has nowhere deeper to route,
  /// so when signed in we refresh the visible list (picking up a newly added or
  /// shared item); a pending incoming share auto-prompts via the existing
  /// bootstrap path. No-op while still on login (cold-start bootstrap covers it).
  void handlePushTap(Map<String, dynamic> data) {
    if (state.screen == AppScreen.main) unawaited(refresh());
  }

  /// Surfaces a foreground push as a toast (Android suppresses the system tray
  /// notification while the app is foregrounded). Prefers a localized message
  /// keyed off the backend `type`, falling back to the notification body.
  void showPushToast(Map<String, dynamic> data) {
    final message = pushToastMessage(data);
    if (message != null && message.isNotEmpty) _toast(message);
  }

  /// Maps a push payload to a localized foreground toast. Returns null when the
  /// type is unknown and no usable body is present (so nothing is shown).
  String? pushToastMessage(Map<String, dynamic> data) {
    final t = state.t;
    switch (data['type']) {
      case 'share_requested':
        return t.pushShareRequested;
      case 'share_accepted':
        return t.pushShareAccepted;
      case 'item_added':
        return t.pushItemAdded;
      case 'item_edited':
        return t.pushItemEdited;
      case 'shopping_started':
        return t.pushShoppingStarted;
    }
    final body = data['_body'];
    return body is String && body.isNotEmpty ? body : null;
  }

  // ── realtime ────────────────────────────────────────────────────────────
  void _subscribeRealtime() {
    _realtimeSub?.cancel();
    _realtimeSub = _repo.realtimeChanges().listen(_onRealtime);
  }

  void _onRealtime(RealtimeChange change) {
    switch (change.collection) {
      case MoonaCollections.listItems:
        _reconcileListItem(change);
      case MoonaCollections.shares:
      case MoonaCollections.profiles:
        _loadBootstrap();
      case MoonaCollections.categories:
      case MoonaCollections.units:
      case MoonaCollections.products:
        refresh();
      case MoonaCollections.listEvents:
        // Signal an open activity feed to refetch; the list itself reconciles
        // via the `list_items` channel, so nothing else to do here.
        state = state.copyWith(activityRevision: state.activityRevision + 1);
      case MoonaCollections.shoppingPresence:
        _reconcilePresence(change);
    }
  }

  /// Patches the live presence list from a `shopping_presence` realtime row
  /// instead of re-bootstrapping on every ~30s heartbeat.
  void _reconcilePresence(RealtimeChange change) {
    final ShoppingPresence row;
    try {
      row = ShoppingPresence.fromJson(change.payload);
    } catch (_) {
      return;
    }
    if (row.actorId.isEmpty) return;
    if (row.ownerId.isNotEmpty && row.ownerId != state.ownerId) return;
    final others = state.presence.where((p) => p.actorId != row.actorId).toList();
    if (change.type != RealtimeChangeType.delete) others.add(row);
    state = state.copyWith(presence: others);
  }

  void _reconcileListItem(RealtimeChange change) {
    final ListItem item;
    try {
      item = ListItem.fromJson(change.payload);
    } catch (_) {
      refresh();
      return;
    }
    if (item.ownerId != state.ownerId) return;
    final active = state.items.where((i) => i.id != item.id).toList();
    final trash = state.trash.where((i) => i.id != item.id).toList();
    if (change.type == RealtimeChangeType.delete) {
      state = state.copyWith(items: active, trash: trash);
      return;
    }
    if (item.status == ItemStatus.active) {
      active.add(item);
    } else {
      trash.insert(0, item);
    }
    state = state.copyWith(items: active, trash: trash);
  }

  // ── helpers ────────────────────────────────────────────────────────────
  List<ListItem> _upsertActiveItem(List<ListItem> items, ListItem item) => [
    for (final existing in items)
      if (existing.id != item.id) existing,
    item,
  ];

  String _messageFor(MoonaException e) => switch (e.code) {
    MoonaException.duplicateItem => state.t.duplicate,
    MoonaException.shareSelf => state.t.shareSelf,
    MoonaException.shareTargetMissing => state.t.userNotFound,
    MoonaException.viewerAlreadyReceiving => state.t.alreadyReceiving,
    MoonaException.invalidImage => state.t.genericError,
    _ => state.t.genericError,
  };

  void _cancelEverything() {
    for (final timer in _finalizeTimers.values) {
      timer.cancel();
    }
    _finalizeTimers.clear();
    _realtimeSub?.cancel();
    _realtimeSub = null;
  }
}
