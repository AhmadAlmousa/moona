import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'app/app_state.dart';
import 'app/providers.dart';
import 'core/theme/moona_colors.dart';
import 'core/theme/moona_theme.dart';
import 'data/models/models.dart';
import 'features/auth/login_screen.dart';
import 'features/list/item_form.dart';
import 'features/list/main_screen.dart';
import 'features/push/firebase_push_notifications.dart';
import 'features/sharing/incoming_share.dart';
import 'features/widget/widget_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Background isolate entry for taps on the home-screen widget.
  HomeWidget.registerInteractivityCallback(moonaWidgetInteraction);

  // Push is Android-only for now (iOS/APNs parked). Initialise Firebase and
  // swap in the FCM-backed push service only there; everything else (web,
  // desktop, tests) keeps the default no-op provider.
  var firebaseReady = false;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
    } catch (e) {
      // A Firebase init hiccup must not block app start; push just stays off.
      debugPrint('Moona Firebase init failed: $e');
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        if (firebaseReady)
          pushProvider.overrideWith((ref) => FirebasePushNotifications(ref)),
      ],
      child: const MoonaApp(),
    ),
  );
}

class MoonaApp extends ConsumerWidget {
  const MoonaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appControllerProvider.select((s) => s.lang));
    final dark = ref.watch(appControllerProvider.select((s) => s.dark));
    final arabic = lang == 'ar';

    return MaterialApp(
      title: 'Moona',
      debugShowCheckedModeBanner: false,
      theme: buildMoonaTheme(brightness: Brightness.light, arabic: arabic),
      darkTheme: buildMoonaTheme(brightness: Brightness.dark, arabic: arabic),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerStatefulWidget {
  const _Root();

  @override
  ConsumerState<_Root> createState() => _RootState();
}

class _RootState extends ConsumerState<_Root> with WidgetsBindingObserver {
  final Set<String> _promptedShares = {};

  /// Live widget-tap subscription, plus a deferred "open the add sheet" request
  /// from a `moona://add` widget launch that arrives before we reach the main
  /// screen (cold start still on login/bootstrap).
  StreamSubscription<Uri?>? _widgetClicks;
  bool _pendingWidgetAdd = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      HomeWidget.initiallyLaunchedFromHomeWidget()
          .then(_onWidgetUri)
          .catchError((_) {});
      _widgetClicks = HomeWidget.widgetClicked.listen(
        _onWidgetUri,
        onError: (_) {},
      );
      // Wire push handlers (no-op unless the FCM provider was installed in main).
      // Foreground messages become toasts; taps refresh the visible list.
      final controller = ref.read(appControllerProvider.notifier);
      unawaited(
        ref
            .read(pushProvider)
            .init(
              onForeground: controller.showPushToast,
              onTap: controller.handlePushTap,
            )
            .catchError((Object _) {}),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClicks?.cancel();
    super.dispose();
  }

  /// Re-push the snapshot whenever the app returns to the foreground so the
  /// home-screen widget reflects the current list (and re-renders) even if the
  /// list itself didn't change while away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final s = ref.read(appControllerProvider);
      if (s.screen == AppScreen.main) pushWidgetSnapshot(s, force: true);
    }
  }

  /// A widget launch URI — only `moona://add` is handled here (check-off/undo
  /// run in the background isolate, not via app launch).
  void _onWidgetUri(Uri? uri) {
    if (uri == null || uri.host != MoonaWidget.hostAdd) return;
    _pendingWidgetAdd = true;
    _maybeOpenWidgetAdd();
  }

  /// Opens the in-app add sheet once we're signed in and on the main screen.
  void _maybeOpenWidgetAdd() {
    if (!_pendingWidgetAdd || !mounted) return;
    if (ref.read(appControllerProvider).screen != AppScreen.main) return;
    _pendingWidgetAdd = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showItemForm(context, ref);
    });
  }

  void _showToast(String message) {
    final c = context.c;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.surface,
            fontWeight: FontWeight.w800,
            fontSize: 14.5,
          ),
        ),
        backgroundColor: c.onSurface,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        duration: const Duration(milliseconds: 2300),
      ),
    );
  }

  void _maybePromptShare(List<Share> pending) {
    if (pending.isEmpty) return;
    final share = pending.first;
    if (_promptedShares.contains(share.id)) return;
    _promptedShares.add(share.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showIncomingShareDialog(context, ref, share);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(toastProvider, (_, next) {
      if (next != null) _showToast(next.message);
    });
    ref.listen(
      appControllerProvider.select(
        (s) =>
            s.screen == AppScreen.main ? s.sharing.pendingIncoming : <Share>[],
      ),
      (_, next) => _maybePromptShare(next),
    );
    // Mirror the signed-in list into the home-screen widget on every change,
    // and flush any pending widget-launched "add" once we reach the main screen.
    ref.listen(appControllerProvider, (_, next) {
      if (next.screen == AppScreen.main) pushWidgetSnapshot(next);
      _maybeOpenWidgetAdd();
    });

    final AppScreen screen = ref.watch(appControllerProvider.select((s) => s.screen));
    return switch (screen) {
      AppScreen.login => const LoginScreen(),
      AppScreen.main => const MainScreen(),
    };
  }
}
