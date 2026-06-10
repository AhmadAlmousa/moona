/// Platform-agnostic string key/value persistence.
///
/// Backed by a file in the app documents directory on native (`kv_store_io.dart`)
/// and by `window.localStorage` on web (`kv_store_web.dart`). The concrete impl
/// is selected at compile time by the conditional import in `kv_store.dart`, so
/// callers (offline bootstrap cache, push-target record) work on every platform
/// — including the PWA — without `dart:io`/`path_provider` throwing on web.
///
/// All operations are best-effort: failures degrade to "no value" rather than
/// throwing, so persistence never blocks auth or rendering.
library;

abstract class KvStore {
  /// The stored string for [key], or null if absent/unreadable.
  Future<String?> read(String key);

  /// Persists [value] under [key]. Swallows errors.
  Future<void> write(String key, String value);

  /// Removes [key] if present. Swallows errors.
  Future<void> delete(String key);
}
