/// Web impl: bridges to the `beforeinstallprompt` event stashed by the script in
/// `web/index.html` (`window.moonaPwaCanInstall` / `window.moonaPwaPromptInstall`).
library;

import 'dart:js_interop';

import 'pwa_install_base.dart';

export 'pwa_install_base.dart';

@JS('moonaPwaCanInstall')
external JSBoolean _canInstall();

@JS('moonaPwaPromptInstall')
external JSPromise<JSString> _promptInstall();

/// Whether the browser can show the native install dialog right now.
bool pwaCanInstall() {
  try {
    return _canInstall().toDart;
  } catch (_) {
    return false;
  }
}

/// Triggers the native install dialog and resolves to the user's choice.
Future<PwaInstallOutcome> pwaPromptInstall() async {
  try {
    final outcome = (await _promptInstall().toDart).toDart;
    return switch (outcome) {
      'accepted' => PwaInstallOutcome.accepted,
      'unavailable' => PwaInstallOutcome.unavailable,
      _ => PwaInstallOutcome.dismissed,
    };
  } catch (_) {
    return PwaInstallOutcome.unavailable;
  }
}
