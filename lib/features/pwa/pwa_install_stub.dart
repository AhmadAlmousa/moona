/// Non-web stub: native platforms are never "installable as a PWA".
library;

import 'pwa_install_base.dart';

export 'pwa_install_base.dart';

bool pwaCanInstall() => false;

Future<PwaInstallOutcome> pwaPromptInstall() async =>
    PwaInstallOutcome.unavailable;
