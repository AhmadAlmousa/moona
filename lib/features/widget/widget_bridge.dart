/// Home-screen widget bridge (Android first; iOS shares the same payload later).
///
/// Three actors read/write a small shared store (`HomeWidgetPreferences` on
/// Android): the Flutter app (writes the snapshot), the native RemoteViews
/// widget (renders it), and a background Dart isolate (handles taps while the
/// app is closed). All three agree on the keys + URI scheme defined here.
///
/// The check-off mirrors [AppController]'s backend-owned scratch: a tap commits
/// `scratchItem` server-side *immediately* (so a killed process can no longer
/// revert the check-off — the backend owns the window + finalization), then
/// marks the item struck-through with an Undo affordance. Because each tap runs
/// as a *separate* background invocation, the cancellation source of truth is
/// the shared store (a `scratchedAt` stamp), not an in-memory timer. Undo calls
/// `undoScratchItem`; after the window the snapshot row is dropped and a
/// best-effort `finalizeScratch` runs (the backend's lazy sweep is the safety
/// net if this isolate dies first).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../app/app_state.dart';
import '../../core/config.dart';
import '../../core/util/format.dart';
import '../../data/models/models.dart';
import '../../data/repositories/appwrite_moona_repository.dart';
import '../../data/repositories/moona_repository.dart';

/// Shared keys, the Android provider name, and the interactivity URI scheme.
class MoonaWidget {
  const MoonaWidget._();

  /// JSON snapshot of the visible list the native widget renders.
  static const String payloadKey = 'moona_widget_payload';

  /// Compact/detailed toggle, kept independent of the item snapshot so the
  /// user's choice survives list refreshes pushed by the app.
  static const String detailKey = 'moona_widget_detail';

  /// Fully-qualified AppWidgetProvider class to refresh (matches the Kotlin).
  static const String androidProvider = 'sa.almou.moona.MoonaWidgetProvider';

  // Interactivity URIs — `host` is the action, e.g. `moona://scratch?id=…`.
  static const String scheme = 'moona';
  // Hosts must be lowercase — Uri.host lowercases the authority.
  static const String hostScratch = 'scratch';
  static const String hostUndo = 'undo';
  static const String hostToggleDetail = 'toggledetail';
  static const String hostAdd = 'add';
}

/// Builds the JSON-serialisable snapshot the native widget renders. Pure (no
/// plugin I/O) so it can be unit-tested. Shows the whole active list with
/// important items pinned to the top — deliberately independent of the app's
/// transient category filter / sort so the widget is always the full list.
@visibleForTesting
Map<String, dynamic> buildWidgetPayload(AppState s) {
  final t = s.t;
  final items = [...s.items]..sort((a, b) {
    final byImportant = (b.important ? 1 : 0) - (a.important ? 1 : 0);
    if (byImportant != 0) return byImportant;
    return s
        .productName(a.productId)
        .toLowerCase()
        .compareTo(s.productName(b.productId).toLowerCase());
  });
  return {
    'lang': s.lang,
    'rtl': s.lang == 'ar',
    'dark': s.dark,
    'title': s.isShared && s.ownerName.isNotEmpty ? s.ownerName : t.myList,
    'strings': {
      'empty': t.emptyTitle,
      'undo': t.undo,
      'add': t.addItem,
      'details': t.moreDetails,
    },
    'items': [
      for (final item in items)
        {
          'id': item.id,
          'name': s.productName(item.productId),
          'important': item.important,
          'brand': item.brand,
          'store': item.seller,
          'count': _countLabel(s, item),
          'scratched': item.isScratched,
        },
    ],
  };
}

String _countLabel(AppState s, ListItem item) {
  final unit = s.unitById(item.unitId)?.label(s.lang);
  final n = formatCount(item.count);
  return (unit == null || unit.isEmpty) ? n : '$n $unit';
}

/// Last snapshot written, to skip redundant native refreshes when an unrelated
/// part of [AppState] changes (the push listener fires on every state change).
String? _lastPushedJson;

/// Writes the latest snapshot to shared storage and refreshes the widget.
/// Best-effort: no-op on web and swallows the platform error where the plugin
/// isn't available (tests/desktop), so callers can fire it unconditionally.
///
/// Pass [force] to write + refresh even when the snapshot is unchanged (e.g. on
/// app resume) so the native widget always re-renders the current list.
Future<void> pushWidgetSnapshot(AppState s, {bool force = false}) async {
  if (kIsWeb) return;
  final json = jsonEncode(buildWidgetPayload(s));
  if (!force && json == _lastPushedJson) return;
  _lastPushedJson = json;
  try {
    await HomeWidget.saveWidgetData<String>(MoonaWidget.payloadKey, json);
    await _refreshWidget();
  } catch (e) {
    _lastPushedJson = null; // Allow a retry on the next change.
    debugPrint('Moona widget push failed: $e');
  }
}

/// Background isolate entry point for widget taps (registered in `main`). Must
/// stay top-level + `vm:entry-point` so its handle survives AOT.
@pragma('vm:entry-point')
Future<void> moonaWidgetInteraction(Uri? uri) async {
  if (uri == null) return;
  try {
    switch (uri.host) {
      case MoonaWidget.hostToggleDetail:
        final current =
            await HomeWidget.getWidgetData<bool>(
              MoonaWidget.detailKey,
              defaultValue: false,
            ) ??
            false;
        await HomeWidget.saveWidgetData<bool>(MoonaWidget.detailKey, !current);
        await _refreshWidget();
      case MoonaWidget.hostScratch:
        final id = uri.queryParameters['id'];
        if (id != null && id.isNotEmpty) await _scratch(id);
      case MoonaWidget.hostUndo:
        final id = uri.queryParameters['id'];
        if (id != null && id.isNotEmpty) await _undo(id);
    }
  } catch (e) {
    debugPrint('Moona widget interaction failed ($uri): $e');
  }
}

/// Commits the scratch server-side immediately, marks [id] struck-through, then
/// after the window drops it from the snapshot (best-effort finalize) unless an
/// Undo (or another change) cancelled it in the meantime.
Future<void> _scratch(String id) async {
  final payload = await _readPayload();
  final item = _findItem(payload, id);
  if (item == null || item['scratched'] == true) return;

  // Commit the scratch up front so the check-off is durable even if this
  // isolate is killed before the window elapses (the backend owns finalization).
  final committed = await _runRepo(
    (repo) =>
        repo.scratchItem(id, windowSeconds: MoonaConfig.scratchWindow.inSeconds),
  );
  if (!committed) return; // No session / error — leave the row untouched.

  final stamp = DateTime.now().millisecondsSinceEpoch;
  item['scratched'] = true;
  item['scratchedAt'] = stamp;
  await _writePayload(payload);
  await _refreshWidget();

  await Future<void>.delayed(MoonaConfig.scratchWindow);

  // Re-read: only finalize if still scratched with the same stamp (i.e. not
  // undone, re-scratched, or already gone).
  final after = await _readPayload();
  final current = _findItem(after, id);
  if (current == null ||
      current['scratched'] != true ||
      current['scratchedAt'] != stamp) {
    return;
  }
  // Best-effort: prompt the trash + drop from the snapshot. If this isolate dies
  // first the backend still finalizes lazily and the next app open re-syncs.
  await _runRepo((repo) => repo.finalizeScratch(id));
  final items = _items(after)..removeWhere((e) => e['id'] == id);
  after['items'] = items;
  await _writePayload(after);
  await _refreshWidget();
}

/// Cancels a pending scratch for [id] (the Undo tap on a struck-through row).
/// The scratch was committed server-side on tap, so this must clear it there too.
Future<void> _undo(String id) async {
  final payload = await _readPayload();
  final item = _findItem(payload, id);
  if (item == null) return;
  item['scratched'] = false;
  item.remove('scratchedAt');
  await _writePayload(payload);
  await _refreshWidget();
  await _runRepo((repo) => repo.undoScratchItem(id));
}

/// Runs [action] against a fresh repo that reuses the persisted Appwrite session
/// (path_provider is auto-registered in the background engine, so the cookie jar
/// loads). Returns false on no-session / error so callers can defer. Overridable
/// in tests via [debugWidgetRepoRunner] so the background path stays network-free.
typedef WidgetRepoAction = Future<void> Function(MoonaRepository repo);

Future<bool> _runRepo(WidgetRepoAction action) =>
    (debugWidgetRepoRunner ?? _liveRepoRunner)(action);

/// Test seam: when set, [_runRepo] uses this instead of a live Appwrite repo.
@visibleForTesting
Future<bool> Function(WidgetRepoAction action)? debugWidgetRepoRunner;

Future<bool> _liveRepoRunner(WidgetRepoAction action) async {
  if (!MoonaConfig.hasLiveBackend) return false;
  final repo = AppwriteMoonaRepository();
  try {
    if (!await repo.restoreSession()) return false;
    await action(repo);
    return true;
  } catch (e) {
    debugPrint('Moona widget repo action failed: $e');
    return false;
  } finally {
    repo.dispose();
  }
}

Future<void> _refreshWidget() =>
    HomeWidget.updateWidget(qualifiedAndroidName: MoonaWidget.androidProvider);

Future<Map<String, dynamic>> _readPayload() async {
  final raw = await HomeWidget.getWidgetData<String>(MoonaWidget.payloadKey);
  if (raw == null || raw.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

Future<void> _writePayload(Map<String, dynamic> payload) =>
    HomeWidget.saveWidgetData<String>(
      MoonaWidget.payloadKey,
      jsonEncode(payload),
    );

List<Map<String, dynamic>> _items(Map<String, dynamic> payload) {
  final raw = payload['items'];
  if (raw is! List) return <Map<String, dynamic>>[];
  return [
    for (final e in raw)
      if (e is Map) e.cast<String, dynamic>(),
  ];
}

Map<String, dynamic>? _findItem(Map<String, dynamic> payload, String id) {
  for (final e in _items(payload)) {
    if (e['id'] == id) return e;
  }
  return null;
}
