import 'dart:convert';

import '../models/models.dart';
import 'kv_store.dart';

/// Local, on-device cache of the last `lookupContacts` result so the share
/// picker can render "On Moona / Not on Moona" instantly instead of waiting on a
/// backend round-trip every time it opens. The fresh status is refreshed in the
/// background (on app start and whenever the picker opens), and the user can
/// force a refresh with the manual sync button.
///
/// Stored through the platform [KvStore] (a file on native, `localStorage` on
/// web), per-device and cleared on logout. Best-effort: any failure degrades to
/// "no cache" rather than throwing.
class ContactsLookupCache {
  const ContactsLookupCache();

  static const _key = 'contacts_lookup_cache.json';

  KvStore get _kv => createKvStore();

  /// Persists the latest lookup result. Swallows errors.
  Future<void> save(ContactLookupResult result) =>
      _kv.write(_key, jsonEncode(result.toJson()));

  /// Reads the cached lookup result, or null if absent/unreadable.
  Future<ContactLookupResult?> read() async {
    final stored = await _kv.read(_key);
    if (stored == null) return null;
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map
          ? ContactLookupResult.fromJson(decoded.cast<String, dynamic>())
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Removes the cache (on logout).
  Future<void> clear() => _kv.delete(_key);
}
