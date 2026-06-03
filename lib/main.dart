import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_state.dart';
import 'app/providers.dart';
import 'core/theme/moona_colors.dart';
import 'core/theme/moona_theme.dart';
import 'data/models/models.dart';
import 'features/auth/login_screen.dart';
import 'features/list/main_screen.dart';
import 'features/sharing/incoming_share.dart';

void main() {
  runApp(const ProviderScope(child: MoonaApp()));
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

class _RootState extends ConsumerState<_Root> {
  final Set<String> _promptedShares = {};

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

    final screen = ref.watch(appControllerProvider.select((s) => s.screen));
    return switch (screen) {
      AppScreen.login => const LoginScreen(),
      AppScreen.main => const MainScreen(),
    };
  }
}
