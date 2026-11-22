import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/screens/home_screen.dart';
import 'package:masra/screens/profile_screen.dart';
import 'package:masra/widgets/home_avatar.dart';

// The avatar at the top right of Home, with a fake photo reader: the photo,
// the letter when there is none or it cannot be read, and reading it again
// after Profile. Plain pages stand in for Profile and Explore, so no Firebase
// app is needed. The Home tests push the real Profile page, which cannot be
// built without Firebase, so they only check that it was opened and when
// Home tries to read the photo again.

/// Two real 1x1 PNG pictures in different colours. They must decode, or the
/// avatar would fall back to the letter and the tests would be unreliable.
final _pngA = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, //
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xE0, 0x9E, 0xB8, 0x0C, //
  0x00, 0x01, 0xED, 0x01, 0x43, 0x0A, 0x0B, 0x2E, 0x8C, 0x00, 0x00, 0x00, //
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);
final _pngB = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, //
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xB4, 0xD5, 0x05, //
  0x00, 0x04, 0x88, 0x01, 0xEC, 0x87, 0x60, 0x8B, 0x16, 0x00, 0x00, 0x00, //
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

/// Stands in for the saved photo. Each read can return a photo, no photo,
/// an error, or wait until the test answers it ([hold]).
class _FakePhotos {
  Uint8List? photo;
  Object? error;
  bool hold = false;
  int reads = 0;
  final List<Completer<Uint8List?>> held = [];

  Future<Uint8List?> read() {
    reads++;
    if (hold) {
      final answer = Completer<Uint8List?>();
      held.add(answer);
      return answer.future;
    }
    if (error != null) return Future.error(error!);
    return Future.value(photo);
  }
}

/// Records every page pushed, so a test can see which page a tap opened.
class _PushRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

/// A stand-in for Profile or Explore. Its tab button replaces it with the
/// other page, as the bottom tabs of both pages do.
class _TabPage extends StatelessWidget {
  final String name;
  final String other;

  const _TabPage(this.name, this.other);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text(name),
          TextButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => _TabPage(other, name)),
            ),
            child: Text('Go to $other'),
          ),
        ],
      ),
    );
  }
}

/// The avatar on a plain page. Tapping it opens a stand-in Profile page, and
/// the phone's back button returns, as on Home.
Widget _launcher(_FakePhotos photos, {String initial = 'S'}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: HomeAvatar(
            initial: initial,
            loadPhoto: photos.read,
            onOpenProfile: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _TabPage('Profile page', 'Explore page'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final _image = find.descendant(
  of: find.byType(HomeAvatar),
  matching: find.byType(Image),
);
final _letter = find.descendant(
  of: find.byType(HomeAvatar),
  matching: find.text('S'),
);

/// The bytes of the photo the avatar shows, or null when it shows none. The
/// photo is decoded at a smaller size, so the bytes sit inside a ResizeImage.
Uint8List? _shownBytes(WidgetTester tester) {
  if (_image.evaluate().isEmpty) return null;
  final resized = tester.widget<Image>(_image).image as ResizeImage;
  return (resized.imageProvider as MemoryImage).bytes;
}

/// Lets the reads finish and the 200 ms fade and page changes end. Home's
/// background animation repeats forever, so pumpAndSettle is never used.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// The phone's back button.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

void main() {
  testWidgets('shows the photo when the user has one', (tester) async {
    final photos = _FakePhotos()..photo = _pngA;
    await tester.pumpWidget(_launcher(photos));
    await _settle(tester);

    expect(_shownBytes(tester), same(_pngA));
    expect(_letter, findsNothing);
    expect(tester.getSize(find.byType(HomeAvatar)), const Size(46, 46));
    // The gradient shows as a 2 px frame around the photo.
    expect(tester.getSize(_image), const Size(42, 42));
    // Decoded at twice the box width, not at the saved size. Only the width
    // is set, so the photo keeps its shape.
    final resized = tester.widget<Image>(_image).image as ResizeImage;
    expect(resized.width, (42 * tester.view.devicePixelRatio * 2).round());
    expect(resized.height, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the first letter when the user has no photo', (
    tester,
  ) async {
    final photos = _FakePhotos();
    await tester.pumpWidget(_launcher(photos));
    await _settle(tester);

    expect(_letter, findsOneWidget);
    expect(_image, findsNothing);
  });

  testWidgets('shows the first letter when the photo cannot be read', (
    tester,
  ) async {
    final photos = _FakePhotos()..error = Exception('offline');
    await tester.pumpWidget(_launcher(photos));
    await _settle(tester);

    expect(_letter, findsOneWidget);
    expect(_image, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows the letter while the photo loads, then fades it in without moving',
    (tester) async {
      final photos = _FakePhotos()..hold = true;
      await tester.pumpWidget(_launcher(photos));
      await tester.pump();

      expect(_letter, findsOneWidget);
      expect(_image, findsNothing);
      final avatarBefore = tester.getRect(find.byType(HomeAvatar));
      final letterBefore = tester.getRect(_letter);

      photos.held.single.complete(_pngA);
      // The fade starts on the next frame; this is part way through it.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_letter, findsOneWidget);
      expect(_image, findsOneWidget);
      expect(tester.getRect(_letter), letterBefore);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(_letter, findsNothing);
      expect(_shownBytes(tester), same(_pngA));
      expect(tester.getRect(find.byType(HomeAvatar)), avatarBefore);
    },
  );

  testWidgets('reads the photo again after coming back from Profile: added', (
    tester,
  ) async {
    final photos = _FakePhotos();
    await tester.pumpWidget(_launcher(photos));
    await _settle(tester);
    expect(_letter, findsOneWidget);

    await tester.tap(find.byType(HomeAvatar));
    await _settle(tester);
    expect(find.text('Profile page'), findsOneWidget);
    // Nothing is read while Profile is open.
    expect(photos.reads, 1);

    photos.photo = _pngA;
    await _back(tester);
    expect(_shownBytes(tester), same(_pngA));
    expect(photos.reads, 2);
  });

  testWidgets(
    'reads the photo again after coming back from Profile: changed, with no letter in between',
    (tester) async {
      final photos = _FakePhotos()..photo = _pngA;
      await tester.pumpWidget(_launcher(photos));
      await _settle(tester);
      expect(_shownBytes(tester), same(_pngA));

      await tester.tap(find.byType(HomeAvatar));
      await _settle(tester);
      photos.hold = true;
      await _back(tester);
      // The old photo stays while the new one is read.
      expect(_shownBytes(tester), same(_pngA));
      expect(_letter, findsNothing);

      photos.held.single.complete(_pngB);
      await _settle(tester);
      expect(_shownBytes(tester), same(_pngB));
    },
  );

  testWidgets('reads the photo again after coming back from Profile: removed', (
    tester,
  ) async {
    final photos = _FakePhotos()..photo = _pngA;
    await tester.pumpWidget(_launcher(photos));
    await _settle(tester);
    expect(_shownBytes(tester), same(_pngA));

    await tester.tap(find.byType(HomeAvatar));
    await _settle(tester);
    photos.photo = null;
    await _back(tester);

    expect(_letter, findsOneWidget);
    expect(_image, findsNothing);
  });

  testWidgets('a failed read after Profile keeps the photo already shown', (
    tester,
  ) async {
    final photos = _FakePhotos()..photo = _pngA;
    await tester.pumpWidget(_launcher(photos));
    await _settle(tester);

    await tester.tap(find.byType(HomeAvatar));
    await _settle(tester);
    photos.error = Exception('offline');
    await _back(tester);

    expect(_shownBytes(tester), same(_pngA));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an older read that finishes late never replaces a newer one', (
    tester,
  ) async {
    final photos = _FakePhotos()..hold = true;
    await tester.pumpWidget(_launcher(photos));
    await tester.pump();

    await tester.tap(find.byType(HomeAvatar));
    await _settle(tester);
    await _back(tester);
    expect(photos.held.length, 2);

    photos.held[1].complete(_pngB);
    await _settle(tester);
    photos.held[0].complete(_pngA);
    await _settle(tester);
    expect(_shownBytes(tester), same(_pngB));
  });

  testWidgets(
    'an older read that finishes late is ignored even when the newer one failed',
    (tester) async {
      // The first read is slow, the photo is removed on Profile, and the
      // read after Profile fails offline: the old photo must not appear.
      final photos = _FakePhotos()..hold = true;
      await tester.pumpWidget(_launcher(photos));
      await tester.pump();

      await tester.tap(find.byType(HomeAvatar));
      await _settle(tester);
      await _back(tester);
      expect(photos.held.length, 2);

      photos.held[1].completeError(Exception('offline'));
      photos.held[0].complete(_pngA);
      await _settle(tester);
      expect(_letter, findsOneWidget);
      expect(_image, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reads the photo again when Profile was left through its tabs', (
    tester,
  ) async {
    final photos = _FakePhotos();
    await tester.pumpWidget(_launcher(photos));
    await _settle(tester);
    expect(_letter, findsOneWidget);

    // Profile, then its Explore tab, then Explore's Profile tab. Each tab
    // replaces the page before it, and Home stays underneath.
    await tester.tap(find.byType(HomeAvatar));
    await _settle(tester);
    await tester.tap(find.text('Go to Explore page'));
    await _settle(tester);
    await tester.tap(find.text('Go to Profile page'));
    await _settle(tester);
    expect(find.text('Profile page'), findsOneWidget);
    // Nothing is read while Home is underneath.
    expect(photos.reads, 1);

    // The photo is added on the second Profile page, then Back returns to
    // Home.
    photos.photo = _pngA;
    await _back(tester);
    expect(_shownBytes(tester), same(_pngA));
    expect(photos.reads, 2);
  });

  testWidgets('keeps the picture shown when the same photo is read again', (
    tester,
  ) async {
    final photos = _FakePhotos()..photo = _pngA;
    await tester.pumpWidget(_launcher(photos));
    await _settle(tester);
    expect(_shownBytes(tester), same(_pngA));

    await tester.tap(find.byType(HomeAvatar));
    await _settle(tester);
    // Each read gives new bytes, here with the same picture in them.
    photos.photo = Uint8List.fromList(_pngA);
    await _back(tester);

    expect(photos.reads, 2);
    // The bytes already shown are kept, so the picture is not decoded again.
    expect(_shownBytes(tester), same(_pngA));
  });

  testWidgets('does not read the photo again when it is rebuilt', (
    tester,
  ) async {
    final photos = _FakePhotos();
    await tester.pumpWidget(_launcher(photos));
    await _settle(tester);
    expect(photos.reads, 1);

    // Home rebuilds often (name, journey, recommendations); a new letter
    // still shows, but the photo is not read again.
    await tester.pumpWidget(_launcher(photos, initial: 'T'));
    await _settle(tester);
    await tester.pumpWidget(_launcher(photos, initial: 'T'));
    await _settle(tester);

    expect(photos.reads, 1);
    expect(
      find.descendant(of: find.byType(HomeAvatar), matching: find.text('T')),
      findsOneWidget,
    );
  });

  testWidgets('is one button called Open profile, with or without a photo', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    final withPhoto = _FakePhotos()..photo = _pngA;
    await tester.pumpWidget(_launcher(withPhoto));
    await _settle(tester);
    expect(
      tester.getSemantics(find.byType(HomeAvatar)),
      isSemantics(label: 'Open profile', isButton: true, hasTapAction: true),
    );
    // The label is exactly this, so the letter is not read out.
    expect(tester.getSemantics(find.byType(HomeAvatar)).label, 'Open profile');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    final noPhoto = _FakePhotos();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(_launcher(noPhoto));
    await _settle(tester);
    expect(_letter, findsOneWidget);
    expect(
      tester.getSemantics(find.byType(HomeAvatar)),
      isSemantics(label: 'Open profile', isButton: true, hasTapAction: true),
    );
    expect(tester.getSemantics(find.byType(HomeAvatar)).label, 'Open profile');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    handle.dispose();
  });

  group('on Home', () {
    testWidgets(
      'Home shows the avatar with the letter when the photo cannot be read',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        // Lets the entrance animation run.
        await tester.pump(const Duration(milliseconds: 1200));

        expect(find.byType(HomeAvatar), findsOneWidget);
        expect(tester.getSize(find.byType(HomeAvatar)), const Size(46, 46));
        // Without Firebase the name and the photo cannot be read.
        expect(
          find.descendant(
            of: find.byType(HomeAvatar),
            matching: find.text('U'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(HomeAvatar),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
        expect(find.bySemanticsLabel('Open profile'), findsOneWidget);
        expect(tester.takeException(), isNull);

        handle.dispose();
      },
    );

    testWidgets('tapping the avatar on Home opens Profile', (tester) async {
      final recorder = _PushRecorder();
      await tester.pumpWidget(
        MaterialApp(navigatorObservers: [recorder], home: const HomeScreen()),
      );
      await tester.pump(const Duration(milliseconds: 1200));
      expect(recorder.pushed.length, 1);

      await tester.tap(find.byType(HomeAvatar));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // The real Profile page cannot be built without Firebase.
      expect(tester.takeException().toString(), contains('no-app'));

      expect(recorder.pushed.length, 2);
      final route = recorder.pushed.last as MaterialPageRoute<dynamic>;
      expect(
        route.builder(tester.element(find.byType(Navigator))),
        isA<ProfileScreen>(),
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(HomeAvatar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home reads the photo again only after Profile closes', (
      tester,
    ) async {
      // Without Firebase every photo read fails and logs one line, so
      // counting those lines shows when Home read the photo.
      final logs = <String>[];
      final realDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      int photoReads() =>
          logs.where((line) => line.startsWith('HOME PHOTO LOAD ERROR')).length;

      try {
        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pump(const Duration(milliseconds: 1200));
        expect(photoReads(), 1);

        await tester.tap(find.byType(HomeAvatar));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        // The real Profile page cannot be built without Firebase.
        expect(tester.takeException().toString(), contains('no-app'));

        // Nothing is read while Profile is open.
        await tester.pump(const Duration(seconds: 2));
        expect(photoReads(), 1);
        expect(tester.takeException(), isNull);

        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(photoReads(), 2);
        expect(tester.takeException(), isNull);
      } finally {
        debugPrint = realDebugPrint;
      }
    });
  });
}
