import 'dart:convert';

import 'kv_store.dart';

/// Local, on-device cache of the last successful `getBootstrapData` response so
/// the app can render the home screen instantly on launch while it re-validates
/// the session and refreshes in the background (offline-first sign-in).
///
/// Stores the raw response JSON (re-parsed via `BootstrapData.fromJson`) through
/// the platform [KvStore]: a file in the app documents directory on native, and
/// `localStorage` on web — so offline-first works in the PWA too. Per-device and
/// cleared on logout. All operations are best-effort: any failure degrades to
/// "no cache" rather than throwing.
class BootstrapCache {
  const BootstrapCache();

  static const _key = 'bootstrap_cache.json';

  KvStore get _kv => createKvStore();

  /// Persists the raw bootstrap response map. Swallows errors.
  Future<void> save(Map<String, dynamic> raw) =>
      _kv.write(_key, jsonEncode(raw));

  /// Reads the cached raw bootstrap map, or null if absent/unreadable.
  Future<Map<String, dynamic>?> read() async {
    final stored = await _kv.read(_key);
    if (stored == null) return null;
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Removes the cache (on logout, or when a restored session is rejected).
  Future<void> clear() => _kv.delete(_key);
}
