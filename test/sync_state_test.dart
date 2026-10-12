import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigoriafit/models/profile.dart';
import 'package:vigoriafit/services/auth_service.dart';
import 'package:vigoriafit/services/profile_repository.dart';
import 'package:vigoriafit/services/store.dart';
import 'package:vigoriafit/services/sync_state.dart';

// ── Adaptadores falsos ────────────────────────────────────────────────────────

class _FakeAuth implements AccountAuth {
  AccountIdentity? _user;
  final _ctrl = StreamController<AccountIdentity?>.broadcast();

  @override
  AccountIdentity? get current => _user;
  @override
  Stream<AccountIdentity?> get changes => _ctrl.stream;

  void signInAs(String uid) {
    _user = AccountIdentity(uid, '$uid@test.com', 'User $uid');
    _ctrl.add(_user);
  }

  void logout() {
    _user = null;
    _ctrl.add(null);
  }

  @override
  Future<void> register(String name, String email, String password) async =>
      signInAs(email);
  @override
  Future<void> signIn(String email, String password) async =>
      signInAs(email);
  @override
  Future<void> signInWithGoogle() async => signInAs('google_user');
  @override
  Future<void> signOut() async => logout();
}

class _FakeProfiles implements ProfileRepository {
  bool failNext = false;
  bool permissionDeniedNext = false;
  int saveCount = 0;
  Profile? lastSaved;

  @override
  Future<AccountProfile> loadOrCreate(AccountIdentity user) async {
    return AccountProfile(Profile(name: user.name), onboarded: false);
  }

  @override
  Future<void> save(String uid, Profile profile, {required bool onboarded}) async {
    if (failNext) {
      failNext = false;
      throw Exception('network error');
    }
    if (permissionDeniedNext) {
      permissionDeniedNext = false;
      throw Exception('PERMISSION_DENIED');
    }
    saveCount++;
    lastSaved = profile;
  }
}

Future<AppStore> _makeStore(_FakeAuth auth, _FakeProfiles profiles) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore(
    auth: auth,
    profiles: profiles,
    clearReminders: () async {},
  );
  auth.signInAs('uid_a');
  await store.load();
  await Future.delayed(const Duration(milliseconds: 100));
  return store;
}

// ── Pruebas ───────────────────────────────────────────────────────────────────

void main() {
  group('SyncState — ciclo de vida del guardado', () {
    late _FakeAuth auth;
    late _FakeProfiles profiles;
    late AppStore store;

    setUp(() async {
      auth = _FakeAuth();
      profiles = _FakeProfiles();
      store = await _makeStore(auth, profiles);
    });

    tearDown(() => store.dispose());

    test('Estado inicial es idle', () {
      expect(store.profileSyncState, SyncState.idle);
    });

    test('Guardado exitoso: saving → confirmed', () async {
      final states = <SyncState>[];
      store.addListener(() => states.add(store.profileSyncState));

      await store.saveProfile(store.profile.copy());

      expect(states, containsAllInOrder([SyncState.saving, SyncState.confirmed]));
    });

    test('Error de red: saving → failed', () async {
      profiles.failNext = true;
      final states = <SyncState>[];
      store.addListener(() => states.add(store.profileSyncState));

      try {
        await store.saveProfile(store.profile.copy());
      } catch (_) {}

      expect(states, containsAllInOrder([SyncState.saving, SyncState.failed]));
    });

    test('Error de permisos: saving → rejected', () async {
      profiles.permissionDeniedNext = true;
      final states = <SyncState>[];
      store.addListener(() => states.add(store.profileSyncState));

      try {
        await store.saveProfile(store.profile.copy());
      } catch (_) {}

      expect(
        states,
        containsAllInOrder([SyncState.saving, SyncState.rejected]),
      );
    });

    test('Reintento exitoso no duplica el registro', () async {
      profiles.failNext = true;
      try {
        await store.saveProfile(store.profile.copy());
      } catch (_) {}

      final countBefore = profiles.saveCount;
      await store.saveProfile(store.profile.copy());

      expect(profiles.saveCount, equals(countBefore + 1),
          reason: 'Un reintento debe producir exactamente una operación nueva');
    });

    test('Cambio de cuenta limpia el estado sync', () async {
      await store.saveProfile(store.profile.copy());
      expect(store.profileSyncState, SyncState.confirmed);

      auth.signInAs('uid_b');
      await Future.delayed(const Duration(milliseconds: 200));

      expect(store.profileSyncState, SyncState.idle,
          reason: 'El estado sync debe resetearse al cambiar de cuenta');
    });

    test('Borrador local conservado tras error de red', () async {
      profiles.failNext = true;
      final states = <SyncState>[];
      store.addListener(() => states.add(store.profileSyncState));

      try {
        await store.saveProfile(store.profile.copy()..name = 'Borrador');
      } catch (_) {}

      expect(store.profileSyncState, SyncState.failed);
    });
  });

  group('SyncState — aislamiento entre cuentas', () {
    late _FakeAuth auth;
    late _FakeProfiles profiles;
    late AppStore store;

    setUp(() async {
      auth = _FakeAuth();
      profiles = _FakeProfiles();
      store = await _makeStore(auth, profiles);
    });

    tearDown(() => store.dispose());

    test('Operaciones de A y B se registran por separado', () async {
      final profileA = store.profile.copy()..name = 'Usuario A';
      await store.saveProfile(profileA);
      expect(profiles.lastSaved?.name, equals('Usuario A'));

      auth.signInAs('uid_b');
      await Future.delayed(const Duration(milliseconds: 200));

      final profileB = store.profile.copy()..name = 'Usuario B';
      await store.saveProfile(profileB);

      expect(profiles.lastSaved?.name, equals('Usuario B'));
      expect(profiles.saveCount, equals(2));
    });
  });

  group('SyncState — idempotencia (relacionado con #249)', () {
    test('Reintento no crea duplicado en el repositorio', () async {
      final auth = _FakeAuth();
      final profiles = _FakeProfiles();
      SharedPreferences.setMockInitialValues({});
      final store = await _makeStore(auth, profiles);

      profiles.failNext = true;
      try {
        await store.saveProfile(store.profile.copy());
      } catch (_) {}

      expect(profiles.saveCount, 0, reason: 'El primer intento fallido no debe contar');

      await store.saveProfile(store.profile.copy());
      expect(profiles.saveCount, 1, reason: 'El reintento debe producir exactamente una escritura');

      store.dispose();
    });
  });
}
