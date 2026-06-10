/// Push-notification integration boundary (Android FCM, Phase 3 item 11).
///
/// The default [NoopPushNotifications] keeps web, desktop, and the test suite
/// free of any Firebase plugin call. The Android app overrides `pushProvider`
/// with the Firebase-backed implementation in `main` (see lib/main.dart), behind
/// a `defaultTargetPlatform == android` guard — this file deliberately imports
/// no Firebase package so it stays safe to pull into the provider graph and
/// tests (`flutter test` reports `TargetPlatform.android`, so platform alone
/// cannot gate the impl).
library;

/// A push routing payload: the backend's `data` map, plus optional `_title` /
/// `_body` lifted from the notification block for a foreground toast fallback.
typedef PushHandler = void Function(Map<String, dynamic> data);

abstract class PushNotifications {
  /// Wires the foreground + tap listeners once at startup. [onForeground] fires
  /// for messages received while the app is foregrounded; [onTap] fires when a
  /// notification is tapped (including the cold-start launch message).
  Future<void> init({PushHandler? onForeground, PushHandler? onTap});

  /// Requests notification permission, resolves the device token, and registers
  /// it as an Appwrite push target for the signed-in user. Best-effort — never
  /// throws — and called after sign-in / session restore.
  Future<void> registerForSession();

  /// Deletes this device's push target. Called on logout, before the session is
  /// torn down (so the account API call is still authenticated).
  Future<void> unregister();
}

/// No-op push integration for platforms without FCM wired (web/desktop) and for
/// tests. Every method completes successfully without touching any plugin.
class NoopPushNotifications implements PushNotifications {
  const NoopPushNotifications();

  @override
  Future<void> init({PushHandler? onForeground, PushHandler? onTap}) async {}

  @override
  Future<void> registerForSession() async {}

  @override
  Future<void> unregister() async {}
}
