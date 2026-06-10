/// Web [KvStore] backing: `window.localStorage`, namespaced with a `moona.`
/// prefix. Keeps the offline bootstrap cache and the Appwrite push-target record
/// working in the PWA — where `path_provider`/`dart:io` are unavailable — so push
/// targets aren't recreated (duplicated) on every sign-in and the home screen can
/// still hydrate from cache on launch.
library;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'kv_store_base.dart';

export 'kv_store_base.dart';

/// Factory resolved by the conditional import in `kv_store.dart`.
KvStore createKvStore() => const _LocalStorageKvStore();

class _LocalStorageKvStore implements KvStore {
  const _LocalStorageKvStore();

  static const _prefix = 'moona.';

  @override
  Future<String?> read(String key) async {
    try {
      return web.window.localStorage.getItem('$_prefix$key');
    } catch (e) {
      debugPrint('Moona kv read failed ($key): $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      web.window.localStorage.setItem('$_prefix$key', value);
    } catch (e) {
      debugPrint('Moona kv write failed ($key): $e');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      web.window.localStorage.removeItem('$_prefix$key');
    } catch (e) {
      debugPrint('Moona kv delete failed ($key): $e');
    }
  }
}
