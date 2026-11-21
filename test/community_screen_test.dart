import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/features/community/community_screen.dart';

// The Community screen opens on top of the tab the user came from, and both
// the back arrow and the phone's back button return to that tab. A plain
// page stands in for the tab, so no Firebase app is needed.

/// A page with an "Open" button that pushes Community, as Home, Explore and
/// Profile do.
Widget _launcher() {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommunityScreen()),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openCommunity(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(find.byType(CommunityScreen), findsOneWidget);
  expect(find.text('Open'), findsNothing);
}

void _expectBackOnTab(WidgetTester tester) {
  expect(find.byType(CommunityScreen), findsNothing);
  expect(find.text('Open'), findsOneWidget);
  // The tab is the only screen left, so nothing was stacked twice.
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  expect(navigator.canPop(), isFalse);
}

void main() {
  testWidgets('the back arrow returns to the tab underneath', (tester) async {
    await tester.pumpWidget(_launcher());
    await _openCommunity(tester);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    _expectBackOnTab(tester);
  });

  testWidgets('the phone back button returns to the tab underneath', (
    tester,
  ) async {
    await tester.pumpWidget(_launcher());
    await _openCommunity(tester);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    _expectBackOnTab(tester);
  });

  testWidgets('the back arrow is big enough to tap and has a label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_launcher());
    await _openCommunity(tester);

    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
}
