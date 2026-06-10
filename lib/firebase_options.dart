/// Firebase options for the **web** target only.
///
/// Android initialises Firebase from `android/app/google-services.json` via the
/// `com.google.gms.google-services` Gradle plugin, so it needs no options here.
/// Web has no such file — `Firebase.initializeApp` must be given explicit
/// options — so `main.dart` passes [DefaultFirebaseOptions.web] under `kIsWeb`.
///
/// Values come from the Firebase web app `Moona Web`
/// (`1:57956565699:web:...`) in project `moona-71bf8`. These are client config
/// identifiers, not secrets (the same values ship in any web Firebase app).
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyALifOCIv0rR3ECDDxkIW14RI4V0v2WYNc',
    appId: '1:57956565699:web:b72aa0f6c576e2497dd876',
    messagingSenderId: '57956565699',
    projectId: 'moona-71bf8',
    authDomain: 'moona-71bf8.firebaseapp.com',
    storageBucket: 'moona-71bf8.firebasestorage.app',
    measurementId: 'G-VKQ0Z6EVE9',
  );
}
