import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moona/app/providers.dart';
import 'package:moona/data/repositories/fake_moona_repository.dart';
import 'package:moona/main.dart';
import 'package:moona/shared/widgets/buttons.dart';

void main() {
  Widget app() => ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(FakeMoonaRepository())],
    child: const MoonaApp(),
  );

  testWidgets('app boots into the login screen', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(MoonaButton), findsWidgets);
    expect(
      find.image(const AssetImage('assets/icon/moona_icon_foreground.png')),
      findsOneWidget,
    );
  });

  testWidgets('signing in shows the shopping list', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '966501112233');
    await tester.enterText(find.byType(TextField).last, 'pw');

    await tester.tap(find.byType(MoonaButton).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Noor's seeded list contains Tomatoes / طماطم (Arabic UI after sign-in).
    expect(find.text('طماطم'), findsOneWidget);
  });
}
