import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'kv_store.dart';

/// The Appwrite push target this device last registered: its `targetId` and the
/// FCM `token` it was registered with.
@immutable
class StoredPushTarget {
  const StoredPushTarget({required this.targetId, required this.token});

  final String targetId;
  final String token;
}

/// Local, on-device record of this device's Appwrite push target so a token
/// refresh updates the *existing* target (instead of piling up duplicates) and
/// logout can delete it. Persisted through the platform [KvStore]: a file next to
/// the session cookie jar on native, and `localStorage` on web — so web push
/// (PWA) also reuses one target per browser rather than creating a new one on
/// every sign-in.
///
/// All operations are best-effort: any failure degrades to "no stored target"
/// rather than throwing, so push registration never blocks auth.
class PushTargetStore {
  const PushTargetStore();

  static const _key = 'push_target.json';

  KvStore get _kv => createKvStore();

  Future<void> save(StoredPushTarget target) => _kv.write(
    _key,
    jsonEncode({'targetId': target.targetId, 'token': target.token}),
  );

  Future<StoredPushTarget?> read() async {
    final stored = await _kv.read(_key);
    if (stored == null) return null;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return null;
      final targetId = decoded['targetId']?.toString() ?? '';
      final token = decoded['token']?.toString() ?? '';
      if (targetId.isEmpty) return null;
      return StoredPushTarget(targetId: targetId, token: token);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _kv.delete(_key);
}
