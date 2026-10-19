import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/profile_screen.dart';
import 'package:frontend/components/self_bias_identification/services/profile_name_service.dart';
import 'package:frontend/components/self_bias_identification/services/profile_photo_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/profile_avatar.dart';
import 'package:frontend/components/temporal_causal_patterns/services/local_storage.dart';

/// Stands in for Firestore, and records what was written.
class _Remote {
  final saved = <String, String>{};
  Object? failWith;
  String stored = '';

  void install() {
    ProfileNameService.remoteSave = (uid, name) async {
      if (failWith != null) throw failWith!;
      saved[uid] = name;
    };
    ProfileNameService.remoteLoad = (uid) async => stored;
  }
}

void main() {
  late _Remote remote;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.userId = 'uid123';
    ProfileNameService.name.value = '';
    ProfilePhotoService.photo.value = null;
    remote = _Remote()..install();
  });

  group('ProfileNameService', () {
    test('with no name yet it shows the account id', () {
      expect(ProfileNameService.displayName, 'uid123');
    });

    test('saving writes Firestore and the phone, and updates the app', () async {
      await ProfileNameService.save('  Malindu   Perera ');
      expect(remote.saved, {'uid123': 'Malindu Perera'});
      expect(await LocalStorage.getName(), 'Malindu Perera');
      expect(ProfileNameService.name.value, 'Malindu Perera');
      expect(ProfileNameService.displayName, 'Malindu Perera');
    });

    test('if Firestore cannot be reached nothing changes anywhere', () async {
      await ProfileNameService.save('Old Name');
      remote.failWith = Exception('offline');
      await expectLater(ProfileNameService.save('New Name'), throwsException);
      expect(await LocalStorage.getName(), 'Old Name');
      expect(ProfileNameService.name.value, 'Old Name');
      expect(remote.saved['uid123'], 'Old Name');
    });

    test('a name that is too short, too long or odd is refused', () async {
      for (final bad in ['', ' ', 'A', 'x' * 41, 'Bob<script>', 'a\u0007b']) {
        expect(ProfileNameService.validate(bad), isNotNull, reason: bad);
        await expectLater(ProfileNameService.save(bad), throwsFormatException);
      }
      expect(remote.saved, isEmpty);
      expect(await LocalStorage.getName(), '');
    });

    test('ordinary names are accepted, including other scripts', () {
      for (final ok in ['Al', "Mary-Jane O'Neil", 'මලින්දු', 'x' * 40]) {
        expect(ProfileNameService.validate(ok), isNull, reason: ok);
      }
    });

    test('load reads the saved name from the phone', () async {
      await LocalStorage.saveName('Saved Name');
      await ProfileNameService.load();
      expect(ProfileNameService.name.value, 'Saved Name');
    });

    test('load falls back to Firestore when the phone has none', () async {
      remote.stored = 'From Firestore';
      await ProfileNameService.load();
      expect(ProfileNameService.name.value, 'From Firestore');
      expect(await LocalStorage.getName(), 'From Firestore');
    });

    test('load survives Firestore being unreachable', () async {
      ProfileNameService.remoteLoad = (uid) async => throw Exception('offline');
      await ProfileNameService.load();
      expect(ProfileNameService.name.value, '');
      expect(ProfileNameService.displayName, 'uid123');
    });
  });

  testWidgets('the avatar initial follows the name', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: ProfileAvatar()))),
    );
    expect(find.text('U'), findsOneWidget);
    ProfileNameService.name.value = 'Malindu';
    await tester.pump();
    expect(find.text('M'), findsOneWidget);
  });

  group('Profile page', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('editing the name saves it and shows it', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('edit-name')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('name-field')), 'Malindu');
      await tester.tap(find.byKey(const Key('save-name')));
      await tester.pumpAndSettle();
      expect(remote.saved['uid123'], 'Malindu');
      expect(find.text('Malindu'), findsWidgets);
      expect(find.text('Your name'), findsNothing); // dialog closed
    });

    testWidgets('a too-short name shows a message and stays open',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('edit-name')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('name-field')), 'A');
      await tester.tap(find.byKey(const Key('save-name')));
      await tester.pumpAndSettle();
      expect(find.text('Enter at least 2 characters.'), findsOneWidget);
      expect(remote.saved, isEmpty);
    });

    testWidgets('a failed save keeps the dialog open with a message',
        (tester) async {
      remote.failWith = Exception('offline');
      await open(tester);
      await tester.tap(find.byKey(const Key('edit-name')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('name-field')), 'Malindu');
      await tester.tap(find.byKey(const Key('save-name')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save'), findsOneWidget);
      expect(ProfileNameService.name.value, '');
    });
  });
}
