/// Entry point for the platform-specific [KvStore].
///
/// The conditional import picks the file backing on native and the
/// `localStorage` backing on web; both re-export [KvStore] and provide
/// `createKvStore()`. Import this file (never the `_io`/`_web` variants directly).
library;

export 'kv_store_io.dart' if (dart.library.js_interop) 'kv_store_web.dart';
