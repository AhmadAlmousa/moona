import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Local, on-device cache of the last successful `getBootstrapData` response so
/// the app can render the home screen instantly on launch while it re-validates
/// the session and refreshes in the background (offline-first sign-in).
///
/// Stores the raw response JSON (re-parsed via `BootstrapData.fromJson`) in the
/// app documents directory — the same private location as the Appwrite session
/// cookie jar, so it's per-device and cleared on logout. All operations are
/// best-effort: any failure degrades to "no cache" rather than throwing.
class BootstrapCache {
  const BootstrapCache();

  static const _fileName = 'bootstrap_cache.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Persists the raw bootstrap response map. Swallows I/O errors.
  Future<void> save(Map<String, dynamic> raw) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(raw), flush: true);
    } catch (e) {
      debugPrint('Moona bootstrap cache save failed: $e');
    }
  }

  /// Reads the cached raw bootstrap map, or null if absent/unreadable.
  Future<Map<String, dynamic>?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (e) {
      debugPrint('Moona bootstrap cache read failed: $e');
      return null;
    }
  }

  /// Removes the cache (on logout, or when a restored session is rejected).
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Moona bootstrap cache clear failed: $e');
    }
  }
}
