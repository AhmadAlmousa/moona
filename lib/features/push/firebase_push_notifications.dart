/// Firebase Cloud Messaging implementation of [PushNotifications] (Android).
///
/// Imported only by `main.dart`, which overrides `pushProvider` with this impl
/// on Android after `Firebase.initializeApp()`. Token lifecycle: register on
/// sign-in, update on refresh, delete on logout — all via the repository's
/// Appwrite push-target methods (which reuse the signed-in session). Foreground
/// messages and notification taps are surfaced through the [PushHandler]s.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config.dart';
import '../../data/repositories/moona_repository.dart';
import 'push_notifications.dart';

class FirebasePushNotifications implements PushNotifications {
  FirebasePushNotifications(this._ref);

  final Ref _ref;
  bool _wired = false;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  PushHandler? _onForeground;
  PushHandler? _onTap;

  MoonaRepository get _repo => _ref.read(repositoryProvider);

  @override
  Future<void> init({PushHandler? onForeground, PushHandler? onTap}) async {
    _onForeground = onForeground;
    _onTap = onTap;
    if (_wired) return;
    _wired = true;
    _ref.onDispose(() {
      _tokenSub?.cancel();
      _foregroundSub?.cancel();
      _openedSub?.cancel();
    });

    _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
      final data = _payload(message);
      if (data.isNotEmpty) _onForeground?.call(data);
    });
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final data = _payload(message);
      if (data.isNotEmpty) _onTap?.call(data);
    });
    // A token rotation must update the existing push target so this device keeps
    // receiving (the repo reuses the persisted target id).
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_repo.registerPushTarget(token));
    });

    // Cold start: the app may have been launched by tapping a notification.
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        final data = _payload(initial);
        if (data.isNotEmpty) _onTap?.call(data);
      }
    } catch (e) {
      debugPrint('Moona push getInitialMessage failed: $e');
    }
  }

  @override
  Future<void> registerForSession() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // Web/PWA requires the FCM Web Push (VAPID) public key for getToken; native
      // doesn't. With no key configured, skip rather than fail (push stays off).
      final String? token;
      if (kIsWeb) {
        if (MoonaConfig.fcmVapidKey.isEmpty) {
          debugPrint('Moona push: web VAPID key not set; skipping registration');
          return;
        }
        token = await messaging.getToken(vapidKey: MoonaConfig.fcmVapidKey);
      } else {
        token = await messaging.getToken();
      }
      if (token == null || token.isEmpty) return;
      await _repo.registerPushTarget(token);
    } catch (e) {
      debugPrint('Moona push registerForSession failed: $e');
    }
  }

  @override
  Future<void> unregister() async {
    try {
      await _repo.removePushTarget();
    } catch (e) {
      debugPrint('Moona push unregister failed: $e');
    }
  }

  /// Flattens a message into the routing map: backend `data` keys plus the
  /// notification title/body under `_title` / `_body` for a foreground fallback.
  Map<String, dynamic> _payload(RemoteMessage message) {
    final data = <String, dynamic>{...message.data};
    final notification = message.notification;
    if (notification != null) {
      if (notification.title != null) data['_title'] = notification.title;
      if (notification.body != null) data['_body'] = notification.body;
    }
    return data;
  }
}
