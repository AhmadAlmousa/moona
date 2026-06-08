import 'dart:async';
import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/util/phone.dart';
import '../data/models/models.dart';
import '../data/repositories/moona_repository.dart';
import 'app_state.dart';
import 'providers.dart';

/// Orchestrates session, list, sharing, preferences, scratch-to-delete timers,
/// and realtime reconciliation. UI widgets read [AppState] and call these
/// methods; optimistic updates keep the list responsive.
class AppController extends Notifier<AppState> {
  final Map<String, Timer> _scratchTimers = {};
  StreamSubscription<RealtimeChange>? _realtimeSub;
  bool _disposed = false;

  MoonaRepository get _repo => ref.read(repositoryProvider);
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
        if (!_disposed) _subscribeRealtime();
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
      filter: 'all',
      scratched: const {},
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

  // ── scratch-to-delete ──────────────────────────────────────────────────
  void toggleScratch(String itemId) {
    if (state.scratched.contains(itemId)) {
      _cancelScratch(itemId);
      return;
    }
    state = state.copyWith(scratched: {...state.scratched, itemId});
    _scratchTimers[itemId] = Timer(MoonaConfig.scratchWindow, () {
      _commitScratch(itemId);
    });
  }

  void _cancelScratch(String itemId) {
    _scratchTimers.remove(itemId)?.cancel();
    state = state.copyWith(scratched: {...state.scratched}..remove(itemId));
  }

  Future<void> _commitScratch(String itemId) async {
    _scratchTimers.remove(itemId);
    final item = _activeById(itemId);
    state = state.copyWith(scratched: {...state.scratched}..remove(itemId));
    if (item == null) return;
    _applyTrash(item);
    _toast(state.t.removed);
    try {
      await _repo.trashItem(itemId, reason: 'scratch_timer');
    } catch (_) {
      await refresh();
    }
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
        item.copyWith(status: ItemStatus.active),
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
    }
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
    for (final timer in _scratchTimers.values) {
      timer.cancel();
    }
    _scratchTimers.clear();
    _realtimeSub?.cancel();
    _realtimeSub = null;
  }
}
