import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/profile_screen.dart';
import 'package:frontend/components/self_bias_identification/services/profile_photo_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/profile_avatar.dart';

// A 1x1 transparent PNG, a real image that Image.memory can decode.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  late Directory dir;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('profile_photo_test');
    ProfilePhotoService.directoryProvider = () async => dir;
    ProfilePhotoService.picker = (source) async => _png;
    ProfilePhotoService.photo.value = null;
    AppState.userId = 'stu1';
  });

  tearDown(() {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // A file may still be closing; the OS cleans the temp folder anyway.
    }
  });

  group('ProfilePhotoService', () {
    test('a chosen photo is saved and shown', () async {
      expect(await ProfilePhotoService.choose(ImageSource.gallery), isTrue);
      expect(ProfilePhotoService.photo.value, _png);
      expect(dir.listSync().length, 1);
    });

    test('it comes back after the app restarts and after a logout', () async {
      await ProfilePhotoService.choose(ImageSource.gallery);
      // A logout clears preferences and the in-memory value, not the file.
      SharedPreferences.setMockInitialValues({});
      ProfilePhotoService.photo.value = null;
      await ProfilePhotoService.load();
      expect(ProfilePhotoService.photo.value, _png);
    });

    test('each student keeps their own photo', () async {
      await ProfilePhotoService.choose(ImageSource.gallery);
      AppState.userId = 'someone_else';
      await ProfilePhotoService.load();
      expect(ProfilePhotoService.photo.value, isNull);
      AppState.userId = 'stu1';
      await ProfilePhotoService.load();
      expect(ProfilePhotoService.photo.value, _png);
    });

    test('cancelling the picker changes nothing', () async {
      ProfilePhotoService.picker = (source) async => null;
      expect(await ProfilePhotoService.choose(ImageSource.camera), isFalse);
      expect(ProfilePhotoService.photo.value, isNull);
      expect(dir.listSync(), isEmpty);
    });

    test('an empty or oversized picture is refused and not saved', () async {
      ProfilePhotoService.picker = (source) async => Uint8List(0);
      await expectLater(
        ProfilePhotoService.choose(ImageSource.gallery),
        throwsFormatException,
      );
      ProfilePhotoService.picker =
          (source) async => Uint8List(ProfilePhotoService.maxBytes + 1);
      await expectLater(
        ProfilePhotoService.choose(ImageSource.gallery),
        throwsFormatException,
      );
      expect(dir.listSync(), isEmpty);
    });

    test('remove deletes the file and clears the photo', () async {
      await ProfilePhotoService.choose(ImageSource.gallery);
      await ProfilePhotoService.remove();
      expect(ProfilePhotoService.photo.value, isNull);
      expect(dir.listSync(), isEmpty);
      await ProfilePhotoService.remove(); // nothing left: no error
    });

    test('an odd user id cannot escape the folder', () async {
      AppState.userId = '../../evil/id';
      await ProfilePhotoService.choose(ImageSource.gallery);
      final names = dir.listSync().map((f) => f.uri.pathSegments.last).toList();
      expect(names.single, startsWith('profile_photo_'));
      expect(names.single.contains('/'), isFalse);
    });
  });

  group('ProfileAvatar', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Center(child: ProfileAvatar()))),
        );

    testWidgets('shows the first letter when there is no photo', (tester) async {
      AppState.userId = 'dinuka';
      await pump(tester);
      expect(find.text('D'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('shows the photo when there is one, and updates live',
        (tester) async {
      await pump(tester);
      expect(find.byType(Image), findsNothing);
      ProfilePhotoService.photo.value = _png;
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('S'), findsNothing);
      ProfilePhotoService.photo.value = null;
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });
  });

  group('Profile page', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('has the photo, the stats and the existing sections',
        (tester) async {
      await open(tester);
      expect(find.byKey(const Key('change-photo')), findsOneWidget);
      expect(find.text('Entries'), findsOneWidget);
      expect(find.text('Avg PAS'), findsOneWidget);
      expect(find.text('Scans'), findsOneWidget);
      expect(find.text('HISTORY'), findsOneWidget);
      expect(find.text('RESEARCH & PRIVACY'), findsOneWidget);
      expect(find.text('Delete my data'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('tapping the photo offers gallery, and remove only with a photo',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('change-photo')));
      await tester.pumpAndSettle();
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Remove photo'), findsNothing);
      expect(find.textContaining('never sent to the server'), findsOneWidget);
    });

    testWidgets('choosing from the gallery asks the picker for the gallery',
        (tester) async {
      ImageSource? asked;
      ProfilePhotoService.picker = (source) async {
        asked = source;
        return null; // cancelled, so nothing is written during the test
      };
      await open(tester);
      await tester.tap(find.byKey(const Key('change-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();
      expect(asked, ImageSource.gallery);
    });
  });
}
