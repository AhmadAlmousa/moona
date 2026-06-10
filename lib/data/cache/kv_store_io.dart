/// Native [KvStore] backing: a file per key in the app documents directory (the
/// same private location as the Appwrite session cookie jar — per-device and
/// cleared on logout). Used on Android/iOS/desktop; web uses `kv_store_web.dart`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'kv_store_base.dart';

export 'kv_store_base.dart';

/// Factory resolved by the conditional import in `kv_store.dart`.
KvStore createKvStore() => const _FileKvStore();

class _FileKvStore implements KvStore {
  const _FileKvStore();

  Future<File> _file(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$key');
  }

  @override
  Future<String?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      debugPrint('Moona kv read failed ($key): $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      final file = await _file(key);
      await file.writeAsString(value, flush: true);
    } catch (e) {
      debugPrint('Moona kv write failed ($key): $e');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Moona kv delete failed ($key): $e');
    }
  }
}
