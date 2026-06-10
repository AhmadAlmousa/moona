import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
/// logout can delete it. Stored in the app documents directory next to the
/// session cookie jar — per-device, private, and cleared on logout.
///
/// All operations are best-effort: any failure degrades to "no stored target"
/// rather than throwing, so push registration never blocks auth.
class PushTargetStore {
  const PushTargetStore();

  static const _fileName = 'push_target.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> save(StoredPushTarget target) async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({'targetId': target.targetId, 'token': target.token}),
        flush: true,
      );
    } catch (e) {
      debugPrint('Moona push target save failed: $e');
    }
  }

  Future<StoredPushTarget?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final targetId = decoded['targetId']?.toString() ?? '';
      final token = decoded['token']?.toString() ?? '';
      if (targetId.isEmpty) return null;
      return StoredPushTarget(targetId: targetId, token: token);
    } catch (e) {
      debugPrint('Moona push target read failed: $e');
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Moona push target clear failed: $e');
    }
  }
}
