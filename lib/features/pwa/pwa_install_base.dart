/// Result of triggering the PWA install dialog.
library;

enum PwaInstallOutcome {
  /// The user accepted and the app was installed.
  accepted,

  /// The user dismissed the dialog.
  dismissed,

  /// No install prompt was available (not installable, already installed, or a
  /// browser without `beforeinstallprompt` such as iOS Safari).
  unavailable,
}
