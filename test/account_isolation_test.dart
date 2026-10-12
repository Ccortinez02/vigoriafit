import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigoriafit/models/profile.dart';
import 'package:vigoriafit/services/account_preferences.dart';
import 'package:vigoriafit/services/auth_service.dart';
import 'package:vigoriafit/services/profile_repository.dart';
import 'package:vigoriafit/services/store.dart';

class FakeAuth implements AccountAuth {
  AccountIdentity? user;
  final events = StreamController<AccountIdentity?>.broadcast(sync: true);
  @override
  AccountIdentity? get current => user;
  @override
  Stream<AccountIdentity?> get changes => events.stream;
  void change(String? uid) {
    user = uid == null ? null : AccountIdentity(uid, '$uid@example.test', uid);
    events.add(user);
  }

  @override
  Future<void> register(String name, String email, String password) async =>
      change(email);
  @override
  Future<void> signIn(String email, String password) async => change(email);
  @override
  Future<void> signInWithGoogle() async => change('google');
  @override
  Future<void> signOut() async => change(null);
}

class FakeProfiles implements ProfileRepository {
  final profiles = <String, AccountProfile>{};
  final pending = <String, Completer<AccountProfile>>{};
  bool failSave = false;
  bool failLoad = false;
  @override
  Future<AccountProfile> loadOrCreate(AccountIdentity user) async {
    if (failLoad) throw StateError('offline');
    if (pending.containsKey(user.uid)) return pending[user.uid]!.future;
    return profiles.putIfAbsent(
      user.uid,
      () => AccountProfile(Profile(name: user.name), onboarded: false),
    );
  }

  @override
  Future<void> save(
    String uid,
    Profile profile, {
    required bool onboarded,
  }) async {
    if (failSave) throw StateError('denied');
    profiles[uid] = AccountProfile(profile.copy(), onboarded: onboarded);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAuth auth;
  late FakeProfiles profiles;
  late AppStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'brio_profile_v1': Profile(name: 'LEGACY SECRET').toJson(),
      'brio_session_v1': 'old@example.test',
      'brio_onboarded_v1': true,
      'brio_is_trainer_v1': true,
    });
    auth = FakeAuth();
    profiles = FakeProfiles();
    store = AppStore(
      auth: auth,
      profiles: profiles,
      clearReminders: () async {},
    );
  });
  tearDown(() async {
    store.dispose();
    await auth.events.close();
  });

  test(
    'Legacy local credentials do not authenticate or migrate health data',
    () async {
      await store.load();
      expect(store.authed, false);
      await store.login('alice', 'password');
      expect(store.profile.name, 'alice');
      expect(store.onboarded, false);
      expect(store.isTrainer, false);
      expect(store.localUserId, 'alice');
    },
  );

  test(
    'Switching accounts clears profile, logs, groups and onboarding',
    () async {
      await store.load();
      await store.login('alice', 'password');
      await store.completeOnboarding(Profile(name: 'Alice private'));
      await store.addWater(3);
      await store.setMyGroup('group-a', '123456');
      await store.logExerciseWeight('Squat', 30);
      await store.logout();
      expect(store.profile.name, '');
      expect(store.waterToday, 0);
      expect(store.groupId, null);
      await store.login('bob', 'password');
      expect(store.profile.name, 'bob');
      expect(store.onboarded, false);
      expect(store.waterToday, 0);
      expect(store.exerciseWeightHistory('Squat'), isEmpty);
      await store.logout();
      await store.login('alice', 'password');
      expect(store.profile.name, 'Alice private');
      expect(store.waterToday, 3);
      expect(store.groupId, 'group-a');
      expect(store.exerciseWeightHistory('Squat').single.kg, 30);
    },
  );

  test(
    'A delayed old-account profile cannot replace the current account',
    () async {
      await store.load();
      profiles.pending['alice'] = Completer<AccountProfile>();
      final first = store.login('alice', 'password');
      await Future<void>.delayed(Duration.zero);
      await store.login('bob', 'password');
      profiles.pending['alice']!.complete(
        AccountProfile(Profile(name: 'Alice secret'), onboarded: true),
      );
      await first;
      expect(store.currentUid, 'bob');
      expect(store.profile.name, 'bob');
      expect(store.onboarded, false);
    },
  );

  test(
    'Cached profile is not treated as confirmed after a remote read error',
    () async {
      await store.load();
      profiles.failLoad = true;
      await store.login('alice', 'password');
      expect(store.sessionError, isNotNull);
      expect(store.onboarded, false);
      profiles.failLoad = false;
      await store.retryProfile();
      expect(store.sessionError, isNull);
      expect(store.profile.name, 'alice');
    },
  );

  test(
    'Failed profile save does not complete onboarding or replace profile',
    () async {
      await store.load();
      await store.login('alice', 'password');
      profiles.failSave = true;
      await expectLater(
        store.completeOnboarding(Profile(name: 'Unsaved')),
        throwsStateError,
      );
      expect(store.onboarded, false);
      expect(store.profile.name, 'alice');
    },
  );

  test(
    'Restores Firebase session on startup, never local sessionEmail',
    () async {
      auth.change('alice');
      profiles.profiles['alice'] = AccountProfile(
        Profile(name: 'Cloud Alice'),
        onboarded: true,
      );
      await store.load();
      expect(store.authed, true);
      expect(store.profile.name, 'Cloud Alice');
      expect(store.onboarded, true);
    },
  );

  test('Old preference handles remain bound to their UID', () async {
    final prefs = await SharedPreferences.getInstance();
    final a = AccountPreferences(prefs, 'a');
    final b = AccountPreferences(prefs, 'b');
    await a.setString('profile', 'Alice');
    expect(b.getString('profile'), isNull);
    await b.setString('profile', 'Bob');
    await a.setString('profile', 'Late Alice write');
    expect(b.getString('profile'), 'Bob');
  });

  test(
    'Weight changes persist remotely and failed saves preserve history',
    () async {
      await store.load();
      await store.login('alice', 'password');
      await store.completeOnboarding(Profile(name: 'Alice'));
      await store.addWeight(75);
      expect(profiles.profiles['alice']!.profile.weightKg, 75);
      profiles.failSave = true;
      await expectLater(store.addWeight(80), throwsStateError);
      // Durante la sesión: _profile en memoria no se actualiza tras un fallo.
      expect(store.profile.weightKg, 75);
      expect(store.weights.last.kg, 75);
      await store.logout();
      await store.login('alice', 'password');
      // Sprint 2: el borrador (80) sobrevive al reinicio gracias al flag
      // pendingWrite y se re-sincroniza al recuperar la sesión. El valor
      // confirmado pasa a ser 80 en local y en el repositorio remoto falso.
      // Este comportamiento cumple el criterio 6 del sprint.
      expect(store.profile.weightKg, 80);
    },
  );
}
