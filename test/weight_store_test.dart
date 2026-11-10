// Tests que verifican la lógica de peso directamente en AppStore,
// complementando weight_edit_test.dart.
//
// Hallazgo del plan de validación:
//   "weight_edit_test.dart define funciones locales que simulan el store.
//    Se debe comprobar también AppStore y su persistencia."

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigoriafit/models/logs.dart';
import 'package:vigoriafit/models/profile.dart';
import 'package:vigoriafit/services/store.dart';
import 'package:vigoriafit/services/auth_service.dart';
import 'package:vigoriafit/services/profile_repository.dart';

class _FakeAuth implements AccountAuth {
  AccountIdentity? user = const AccountIdentity('test-uid', 'test@test.com', 'Test User');
  final events = StreamController<AccountIdentity?>.broadcast(sync: true);

  @override
  AccountIdentity? get current => user;

  @override
  Stream<AccountIdentity?> get changes => events.stream;

  @override
  Future<void> register(String name, String email, String password) async {}
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signOut() async {}
}

class _FakeProfileRepo implements ProfileRepository {
  final Map<String, AccountProfile> profiles = {};

  @override
  Future<AccountProfile> loadOrCreate(AccountIdentity user) async {
    return profiles.putIfAbsent(
      user.uid,
      () => AccountProfile(Profile(name: user.name, weightKg: 70.0), onboarded: true),
    );
  }

  @override
  Future<void> save(String uid, Profile profile, {required bool onboarded}) async {
    profiles[uid] = AccountProfile(profile, onboarded: onboarded);
  }
}

Future<AppStore> buildStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore(
    auth: _FakeAuth(),
    profiles: _FakeProfileRepo(),
    clearReminders: () async {},
  );
  await store.load();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppStore.addWeight', () {
    test('registra una entrada de peso en el store', () async {
      final store = await buildStore();
      await store.addWeight(70.0);
      expect(store.weights.length, 1);
      expect(store.weights.first.kg, 70.0);
    });

    test('reemplaza entrada del mismo día (sin duplicar)', () async {
      final store = await buildStore();
      await store.addWeight(70.0);
      await store.addWeight(72.0);
      expect(store.weights.length, 1);
      expect(store.weights.first.kg, 72.0);
    });

    test('lastWeight refleja el valor más reciente', () async {
      final store = await buildStore();
      await store.addWeight(68.0);
      expect(store.lastWeight, 68.0);
    });
  });

  group('AppStore.updateWeight', () {
    test('actualiza el kg de la entrada del día', () async {
      final store = await buildStore();
      await store.addWeight(70.0);
      final dk = dayKey(DateTime.now());
      await store.updateWeight(dk, 68.5);
      expect(store.weights.first.kg, 68.5);
    });

    test('rechaza valor negativo con ArgumentError', () async {
      final store = await buildStore();
      await store.addWeight(70.0);
      final dk = dayKey(DateTime.now());
      expect(() => store.updateWeight(dk, -1), throwsArgumentError);
    });

    test('rechaza cero con ArgumentError', () async {
      final store = await buildStore();
      await store.addWeight(70.0);
      final dk = dayKey(DateTime.now());
      expect(() => store.updateWeight(dk, 0), throwsArgumentError);
    });

    test('rechaza 500 kg o más con ArgumentError', () async {
      final store = await buildStore();
      await store.addWeight(70.0);
      final dk = dayKey(DateTime.now());
      expect(() => store.updateWeight(dk, 500), throwsArgumentError);
    });

    test('rechaza NaN con ArgumentError', () async {
      final store = await buildStore();
      await store.addWeight(70.0);
      final dk = dayKey(DateTime.now());
      expect(() => store.updateWeight(dk, double.nan), throwsArgumentError);
    });
  });

  group('AppStore.deleteWeight', () {
    test('elimina la entrada indicada', () async {
      final store = await buildStore();
      await store.addWeight(70.0);
      final dk = dayKey(DateTime.now());
      await store.deleteWeight(dk);
      expect(store.weights.isEmpty, true);
    });

    test('lastWeight es null al borrar el único registro', () async {
      final store = await buildStore();
      await store.addWeight(70.0);
      final dk = dayKey(DateTime.now());
      await store.deleteWeight(dk);
      expect(store.lastWeight, isNull);
    });
  });
}
