import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../data/repositories/appwrite_moona_repository.dart';
import '../data/repositories/fake_moona_repository.dart';
import '../data/repositories/moona_repository.dart';
import '../features/push/push_notifications.dart';
import 'app_controller.dart';
import 'app_state.dart';

/// The active backend. The checked-in defaults point to Appwrite Cloud; the fake
/// remains available only when Appwrite config is deliberately blanked out.
final repositoryProvider = Provider<MoonaRepository>((ref) {
  final repo = MoonaConfig.hasLiveBackend
      ? AppwriteMoonaRepository()
      : FakeMoonaRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

/// Push-notification integration. Defaults to a no-op so web, desktop, and the
/// test suite stay Firebase-free; `main` overrides this with the Firebase-backed
/// implementation on Android (see lib/main.dart).
final pushProvider = Provider<PushNotifications>(
  (ref) => const NoopPushNotifications(),
);

/// A lightweight toast message with a unique key so identical strings still
/// re-trigger the toast UI.
@immutable
class ToastEvent {
  const ToastEvent(this.message, this.key);
  final String message;
  final int key;
}

class ToastController extends Notifier<ToastEvent?> {
  @override
  ToastEvent? build() => null;

  void show(String message) {
    state = ToastEvent(message, DateTime.now().microsecondsSinceEpoch);
  }
}

final toastProvider = NotifierProvider<ToastController, ToastEvent?>(
  ToastController.new,
);
