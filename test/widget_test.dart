// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:focus_spark/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Two-stage splash loading and home screen transition smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FocusSparkApp());

    // Stage 1: Verify Company Logo Splash Screen is displayed
    expect(find.byType(FocusSparkApp), findsOneWidget);

    // Fast-forward past Stage 1 (2.5 seconds) to enter Stage 2 (Game Splash Screen)
    await tester.pump(const Duration(milliseconds: 2800));

    // Stage 2: Verify Game Title Splash Screen is displayed (displaying ONLY game name & tagline)
    expect(find.text('BRAIN REBOOT'), findsOneWidget);
    expect(find.text('CLEAR BRAIN FOG & ELEVATE FOCUS'), findsOneWidget);

    // Fast-forward past Stage 2 (3.0 seconds) to enter Home Screen
    await tester.pump(const Duration(milliseconds: 3300));

    // Main Interface: Verify action button and level map button are displayed on Home Screen
    expect(find.text('NEW SESSION'), findsOneWidget);
    expect(find.text('TAP FOR LEVEL MAP'), findsOneWidget);
  });
}
