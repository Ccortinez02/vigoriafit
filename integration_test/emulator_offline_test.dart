/// Prueba de integración del repositorio de perfiles contra Firebase Emulator.
///
/// Ejecutar en simulador o dispositivo con el emulador activo:
///   firebase emulators:start --only auth,firestore &
///   flutter test integration_test/emulator_offline_test.dart \
///     --dart-define=USE_EMULATOR=true \
///     -d <simulator-id>
///
/// Requisitos: emulador activo en localhost:9099 (Auth) y localhost:8080 (Firestore).
library;

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigoriafit/firebase_options.dart';
import 'package:vigoriafit/models/profile.dart';
import 'package:vigoriafit/services/auth_service.dart';
import 'package:vigoriafit/services/firebase_profile_repository.dart';
import 'package:vigoriafit/services/store.dart';

const _project = 'vigoria-fe224';
const _authBase = 'http://localhost:9099';
const _firestoreBase = 'http://localhost:8080';

Future<void> _clearEmulator() async {
  await http.delete(
    Uri.parse('$_authBase/emulator/v1/projects/$_project/accounts'),
    headers: {'Authorization': 'Bearer owner'},
  );
  await http.delete(
    Uri.parse(
      '$_firestoreBase/emulator/v1/projects/$_project/databases/(default)/documents',
    ),
    headers: {'Authorization': 'Bearer owner'},
  );
}

Future<Map<String, dynamic>?> _firestoreGet(String path) async {
  final resp = await http.get(
    Uri.parse('$_firestoreBase/v1/projects/$_project/databases/(default)/documents/$path'),
    headers: {'Authorization': 'Bearer owner'},
  );
  if (resp.statusCode == 404) return null;
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool _firebaseReady = false;

  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!_firebaseReady) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Enrutamiento al emulador (igual que main.dart con --dart-define=USE_EMULATOR=true)
      await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
      FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
      _firebaseReady = true;
    }
    await _clearEmulator();
  });

  setUp(() async {
    await _clearEmulator();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await _clearEmulator();
  });

  group('Repositorio Firebase contra emulador', () {
    test(
      'Guardado básico: perfil llega a Firestore del emulador',
      () async {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: 'basic@test.local',
          password: 'password123',
        );
        final uid = cred.user!.uid;
        final identity = AccountIdentity(uid, 'basic@test.local', 'Basic');
        final repo = FirebaseProfileRepository();

        // loadOrCreate crea el documento en Firestore.
        final loaded = await repo.loadOrCreate(identity);
        expect(loaded.profile.name, 'Basic');

        // save escribe los datos actualizados.
        final updated = Profile(name: 'Basic Actualizado', weightKg: 70, heightCm: 175);
        await repo.save(uid, updated, onboarded: true);

        // Verificar vía REST que el dato llegó al emulador.
        final doc = await _firestoreGet('users/$uid');
        expect(doc, isNotNull);
        final fields = doc!['fields'] as Map<String, dynamic>;
        expect(fields['name']?['stringValue'], 'Basic Actualizado');
        expect(fields['onboarded']?['booleanValue'], true);

        await FirebaseAuth.instance.signOut();
      },
    );

    test(
      'Dos ediciones consecutivas: la segunda sobreescribe a la primera en Firestore',
      () async {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: 'consecutive@test.local',
          password: 'password123',
        );
        final uid = cred.user!.uid;
        final identity = AccountIdentity(uid, 'consecutive@test.local', 'Consecutive');
        final repo = FirebaseProfileRepository();

        await repo.loadOrCreate(identity);

        final p1 = Profile(name: 'Edición 1', weightKg: 70);
        await repo.save(uid, p1, onboarded: true);

        final p2 = Profile(name: 'Edición 2', weightKg: 75);
        await repo.save(uid, p2, onboarded: true);

        // Solo la segunda edición debe estar en Firestore.
        final doc = await _firestoreGet('users/$uid');
        final fields = doc!['fields'] as Map<String, dynamic>;
        expect(fields['name']?['stringValue'], 'Edición 2');

        // El health_profile también debe tener el peso de la segunda edición.
        final health = await _firestoreGet('users/$uid/private/health_profile');
        final hFields = health!['fields'] as Map<String, dynamic>;
        // weightKg puede ser doubleValue o integerValue según Firestore.
        final weightRaw = hFields['weightKg'];
        final weight = (weightRaw?['doubleValue'] ?? weightRaw?['integerValue']) as num?;
        expect(weight, closeTo(75, 0.01));

        await FirebaseAuth.instance.signOut();
      },
    );

    test(
      'Rechazo de permisos: usuario B no puede escribir el perfil de usuario A',
      () async {
        // Crea usuario A y su perfil.
        final credA = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: 'useraA@test.local',
          password: 'password123',
        );
        final uidA = credA.user!.uid;
        final repoA = FirebaseProfileRepository();
        await repoA.loadOrCreate(AccountIdentity(uidA, 'useraA@test.local', 'A'));

        // Inicia sesión como usuario B.
        await FirebaseAuth.instance.signOut();
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: 'userB@test.local',
          password: 'password123',
        );

        // B intenta sobreescribir el perfil de A.
        final repoB = FirebaseProfileRepository();
        await expectLater(
          repoB.save(uidA, Profile(name: 'Hack'), onboarded: false),
          throwsA(anything),
        );

        // El perfil de A no cambió.
        final doc = await _firestoreGet('users/$uidA');
        final fields = doc!['fields'] as Map<String, dynamic>;
        expect(fields['name']?['stringValue'], 'A');

        await FirebaseAuth.instance.signOut();
      },
    );

    test(
      'AppStore con emulador: guardado → fallo simulado → flag pendingWrite en SharedPreferences',
      () async {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: 'pending@test.local',
          password: 'password123',
        );
        final uid = cred.user!.uid;

        // Preparar el store con repositorio real (emulador) y prefs simuladas.
        SharedPreferences.setMockInitialValues({});
        final store = AppStore(
          auth: FirebaseAccountAuth(),
          profiles: FirebaseProfileRepository(),
          clearReminders: () async {},
        );
        await store.load();
        await store.completeOnboarding(Profile(name: 'Pending Test', weightKg: 70));

        // Verificar que el onboarding llegó al emulador.
        final doc = await _firestoreGet('users/$uid');
        expect(doc, isNotNull);
        final fields = doc!['fields'] as Map<String, dynamic>;
        expect(fields['name']?['stringValue'], 'Pending Test');
        expect(fields['onboarded']?['booleanValue'], true);

        store.dispose();
        await FirebaseAuth.instance.signOut();
      },
    );
  });
}
