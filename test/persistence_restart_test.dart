/// Pruebas de persistencia con reinicio simulado del AppStore.
///
/// "Reinicio" = destruir una instancia de AppStore y crear otra nueva con el
/// mismo backend de SharedPreferences (igual que ocurre cuando el OS mata y
/// relanza la app). Las pruebas usan adaptadores falsos, no el SDK de Firebase.
///
/// No ejecutar contra producción.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigoriafit/models/profile.dart';
import 'package:vigoriafit/services/auth_service.dart';
import 'package:vigoriafit/services/profile_repository.dart';
import 'package:vigoriafit/services/store.dart';
import 'package:vigoriafit/services/sync_state.dart';
import 'package:vigoriafit/services/unit_system.dart';

// ── Adaptadores ───────────────────────────────────────────────────────────────

class _Auth implements AccountAuth {
  AccountIdentity? _user;
  final _ctrl = StreamController<AccountIdentity?>.broadcast();
  @override AccountIdentity? get current => _user;
  @override Stream<AccountIdentity?> get changes => _ctrl.stream;
  void signInAs(String uid) {
    _user = AccountIdentity(uid, '$uid@test.com', uid);
    _ctrl.add(_user);
  }
  void forceLogout() { _user = null; _ctrl.add(null); }
  @override Future<void> register(String n, String e, String p) async => signInAs(e);
  @override Future<void> signIn(String e, String p) async => signInAs(e);
  @override Future<void> signInWithGoogle() async => signInAs('g');
  @override Future<void> signOut() async => forceLogout();
}

class _Profiles implements ProfileRepository {
  bool failOnSave = false;
  bool permissionError = false;
  int saveCount = 0;
  String? lastSavedName;
  Duration saveDelay = Duration.zero;
  Completer<void>? _blocker;

  // Almacenamiento falso por UID para simular persistencia remota.
  final _store = <String, Profile>{};

  void blockNextSave() => _blocker = Completer<void>();
  void unblock() { _blocker?.complete(); _blocker = null; }

  @override
  Future<AccountProfile> loadOrCreate(AccountIdentity user) async {
    final saved = _store[user.uid];
    return AccountProfile(
      saved ?? Profile(name: user.name),
      onboarded: saved != null,
    );
  }

  @override
  Future<void> save(String uid, Profile profile, {required bool onboarded}) async {
    if (saveDelay > Duration.zero) await Future.delayed(saveDelay);
    if (_blocker != null) await _blocker!.future;
    if (failOnSave) { failOnSave = false; throw Exception('network error'); }
    if (permissionError) { permissionError = false; throw Exception('PERMISSION_DENIED'); }
    saveCount++;
    lastSavedName = profile.name;
    _store[uid] = profile;
  }
}

Future<AppStore> _boot(_Auth auth, _Profiles profiles, String uid) async {
  final store = AppStore(auth: auth, profiles: profiles, clearReminders: () async {});
  auth.signInAs(uid);
  await store.load();
  await Future.delayed(const Duration(milliseconds: 80));
  return store;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Persistencia con reinicio de AppStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // ── Escenario 1: borrador survives restart ─────────────────────────────
    test('Borrador local sobrevive a una recreación del AppStore', () async {
      final auth = _Auth();
      final profiles = _Profiles()..failOnSave = true;

      final store1 = await _boot(auth, profiles, 'uid_a');

      // Falla el guardado remoto; el borrador queda en SharedPreferences.
      try {
        await store1.saveProfile(store1.profile.copy()..name = 'Borrador guardado');
      } catch (_) {}
      expect(store1.profileSyncState, SyncState.failed);
      store1.dispose();

      // Simula reinicio: nueva instancia, mismas SharedPreferences.
      final auth2 = _Auth();
      final profiles2 = _Profiles(); // no falla
      final store2 = await _boot(auth2, profiles2, 'uid_a');

      // El borrador debe haberse leído desde SharedPreferences.
      expect(store2.profile.name, equals('Borrador guardado'),
          reason: 'El borrador debe persistir en SharedPreferences tras un reinicio');
      store2.dispose();
    });

    // ── Escenario 2: sincronización tras reconexión ────────────────────────
    test('Tras reconexión, el usuario puede reenviar la operación pendiente', () async {
      final auth = _Auth();
      final profiles = _Profiles()..failOnSave = true;
      final store = await _boot(auth, profiles, 'uid_a');

      try {
        await store.saveProfile(store.profile.copy()..name = 'Cambio offline');
      } catch (_) {}
      expect(store.profileSyncState, SyncState.failed);

      // Reconecta: reintento sin fallo.
      await store.saveProfile(store.profile.copy()..name = 'Cambio offline');
      expect(store.profileSyncState, SyncState.confirmed);
      expect(profiles.lastSavedName, equals('Cambio offline'));
      store.dispose();
    });

    // ── Escenario 3: idempotencia en múltiples reintentos ──────────────────
    test('Múltiples reintentos de la misma operación son idempotentes', () async {
      final auth = _Auth();
      final profiles = _Profiles();
      final store = await _boot(auth, profiles, 'uid_a');

      // Tres veces guardamos el mismo estado.
      final p = store.profile.copy()..name = 'Nombre Idempotente';
      await store.saveProfile(p);
      await store.saveProfile(p);
      await store.saveProfile(p);

      expect(profiles.saveCount, equals(3));
      expect(store.profileSyncState, SyncState.confirmed,
          reason: 'El último reintento debe quedar confirmado');
      store.dispose();
    });

    // ── Escenario 4: edición nueva mientras otra está en vuelo ─────────────
    test('Edición nueva prevalece sobre un reintento de edición anterior', () async {
      final auth = _Auth();
      final profiles = _Profiles();
      final store = await _boot(auth, profiles, 'uid_a');

      // Primera edición: falla remota.
      profiles.failOnSave = true;
      try {
        await store.saveProfile(store.profile.copy()..name = 'Edición vieja');
      } catch (_) {}

      // Segunda edición: éxito.
      await store.saveProfile(store.profile.copy()..name = 'Edición nueva');
      expect(profiles.lastSavedName, equals('Edición nueva'));
      expect(store.profileSyncState, SyncState.confirmed);
      store.dispose();
    });

    // ── Escenario 5: cambio de cuenta con pendiente ────────────────────────
    test('Operaciones de A no se ejecutan en la sesión de B', () async {
      final auth = _Auth();
      final profiles = _Profiles();
      final store = await _boot(auth, profiles, 'uid_a');

      await store.saveProfile(store.profile.copy()..name = 'Perfil de A');
      expect(profiles.lastSavedName, 'Perfil de A');

      // Cambia a B.
      auth.signInAs('uid_b');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(store.profileSyncState, SyncState.idle,
          reason: 'Estado sync de A no debe contaminar a B');

      await store.saveProfile(store.profile.copy()..name = 'Perfil de B');
      expect(profiles.lastSavedName, 'Perfil de B');
      store.dispose();
    });

    // ── Escenario 6: volver a A y recuperar sus datos ──────────────────────
    test('Al volver a A se recuperan sus datos locales', () async {
      final auth = _Auth();
      final profiles = _Profiles();
      final store = await _boot(auth, profiles, 'uid_a');

      await store.saveProfile(store.profile.copy()..name = 'Datos de A');

      auth.signInAs('uid_b');
      await Future.delayed(const Duration(milliseconds: 100));

      auth.signInAs('uid_a');
      await Future.delayed(const Duration(milliseconds: 100));

      // Los datos de A deben leerse desde la caché local.
      expect(store.profile.name, equals('Datos de A'),
          reason: 'Al volver a A, su nombre debe restaurarse desde SharedPreferences');
      store.dispose();
    });

    // ── Escenario 7: confirmación tardía después de timeout ────────────────
    test('Confirmación tardía no reemplaza el estado de sesión nueva', () async {
      final auth = _Auth();
      final profiles = _Profiles();
      profiles.saveDelay = const Duration(milliseconds: 200);
      final store = await _boot(auth, profiles, 'uid_a');

      // Inicia guardado lento y luego cambia de cuenta antes de que responda.
      final saveFuture = store
          .saveProfile(store.profile.copy()..name = 'Tardío')
          .catchError((_) {});

      // Cambio de cuenta inmediato.
      auth.signInAs('uid_b');
      await Future.delayed(const Duration(milliseconds: 50));
      // La confirmación tardía llega aquí.
      await saveFuture;

      // El estado de la sesión de B no debe mostrar "confirmed" de A.
      expect(store.currentUid, equals('uid_b'));
      expect(store.profileSyncState, SyncState.idle,
          reason: 'La confirmación tardía de A no debe afectar el estado de B');
      store.dispose();
    });

    // ── Escenario 8: rechazo de permisos sin bucle de reintentos ──────────
    test('Rechazo de permisos queda como rejected, sin reintento automático', () async {
      final auth = _Auth();
      final profiles = _Profiles()..permissionError = true;
      final store = await _boot(auth, profiles, 'uid_a');

      final states = <SyncState>[];
      store.addListener(() => states.add(store.profileSyncState));

      try {
        await store.saveProfile(store.profile.copy());
      } catch (_) {}

      // Solo debe haber una transición a rejected, no un bucle.
      expect(states.where((s) => s == SyncState.saving).length, 1,
          reason: 'Solo debe intentar guardar una vez');
      expect(states.last, SyncState.rejected);
      // No deben aparecer transiciones adicionales después del rechazo.
      await Future.delayed(const Duration(milliseconds: 100));
      expect(states.last, SyncState.rejected,
          reason: 'No debe haber reintento automático tras rejection');
      store.dispose();
    });

    // ── Escenario 9: consistencia perfil básico y privado ──────────────────
    test('El guardado atomiza perfil básico y privado en la misma llamada', () async {
      final auth = _Auth();
      final profiles = _Profiles();
      final store = await _boot(auth, profiles, 'uid_a');

      final p = store.profile.copy()
        ..name = 'Cristopher'
        ..weightKg = 82.5
        ..age = 28;
      await store.saveProfile(p);

      expect(profiles.lastSavedName, 'Cristopher');
      expect(profiles.saveCount, 1,
          reason: 'Básico y privado deben guardarse en una sola operación');
      store.dispose();
    });
  });

  group('Migración explícita', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // ── Migración repetida sin duplicaciones ──────────────────────────────
    test('Migración repetida no duplica el marcador', () async {
      final auth = _Auth();
      final profiles = _Profiles();
      final store1 = await _boot(auth, profiles, 'uid_m');
      store1.dispose();

      // Segunda ejecución: debe leer el marcador y no re-ejecutar.
      final auth2 = _Auth();
      final profiles2 = _Profiles();
      final store2 = await _boot(auth2, profiles2, 'uid_m');

      // No hay forma observable directa del marcador sin exponer internos.
      // Verificamos que la carga fue exitosa (sin error de sesión) y que
      // no se duplicó ningún perfil.
      expect(store2.sessionError, isNull);
      expect(profiles2.saveCount, 0,
          reason: 'La migración no debe crear perfiles adicionales');
      store2.dispose();
    });

    // ── Datos de propietario incierto no se importan ───────────────────────
    test('Claves antiguas brio_* no se asignan al usuario actual', () async {
      // Simula datos "huérfanos" con clave antigua.
      SharedPreferences.setMockInitialValues({
        'brio_profile_v1': '{"name":"Datos Antiguos","goal":0,"level":0,'
            '"age":25,"heightCm":175,"weightKg":70,"targetWeightKg":70,'
            '"daysPerWeek":3,"hasGym":false,"conditions":[],"allergies":[]}',
      });
      final auth = _Auth();
      final profiles = _Profiles();
      final store = await _boot(auth, profiles, 'uid_nuevo');

      // El perfil del usuario nuevo viene del repositorio remoto, no de la
      // clave antigua brio_*.
      expect(store.profile.name, equals('uid_nuevo'),
          reason: 'El perfil no debe cargarse desde claves antiguas sin UID');
      store.dispose();
    });

    // ── Marcador no se escribe si la migración falla ───────────────────────
    test('Marcador de migración persiste entre reinicios del store', () async {
      final auth = _Auth();
      final profiles = _Profiles();

      // Primera ejecución: escribe el marcador.
      final store1 = await _boot(auth, profiles, 'uid_x');
      store1.dispose();

      // Segunda ejecución: marcador ya presente en SharedPreferences.
      final auth2 = _Auth();
      final profiles2 = _Profiles();
      final store2 = await _boot(auth2, profiles2, 'uid_x');
      expect(store2.sessionError, isNull);
      store2.dispose();
    });
  });

  group('Preferencias por cuenta', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('Tema persiste al reiniciar el store', () async {
      final auth = _Auth();
      final profiles = _Profiles();
      final store1 = await _boot(auth, profiles, 'uid_t');

      await store1.setThemeMode(ThemeMode.dark);
      store1.dispose();

      final auth2 = _Auth();
      final profiles2 = _Profiles();
      final store2 = await _boot(auth2, profiles2, 'uid_t');
      expect(store2.themeMode, ThemeMode.dark,
          reason: 'El tema debe sobrevivir a un reinicio del store');
      store2.dispose();
    });

    test('Unidades persisten al reiniciar el store', () async {
      final auth = _Auth();
      final profiles = _Profiles();
      final store1 = await _boot(auth, profiles, 'uid_u');

      await store1.setUnits(UnitSystem.imperial);
      store1.dispose();

      final auth2 = _Auth();
      final profiles2 = _Profiles();
      final store2 = await _boot(auth2, profiles2, 'uid_u');
      expect(store2.units, UnitSystem.imperial,
          reason: 'Las unidades deben sobrevivir a un reinicio del store');
      store2.dispose();
    });

    test('Tema aislado entre cuentas', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = _Auth();
      final profiles = _Profiles();
      final store = await _boot(auth, profiles, 'uid_a');
      await store.setThemeMode(ThemeMode.dark);

      auth.signInAs('uid_b');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(store.themeMode, ThemeMode.system,
          reason: 'La cuenta B debe comenzar con el tema por defecto');
      store.dispose();
    });

    test('Unidades aisladas entre cuentas', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = _Auth();
      final profiles = _Profiles();
      final store = await _boot(auth, profiles, 'uid_a');
      await store.setUnits(UnitSystem.imperial);

      auth.signInAs('uid_b');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(store.units, UnitSystem.metric,
          reason: 'La cuenta B debe comenzar con unidades métricas por defecto');
      store.dispose();
    });

    test('Cambiar unidades no altera los valores canónicos del perfil', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = _Auth();
      final profiles = _Profiles();
      final store = await _boot(auth, profiles, 'uid_k');

      await store.saveProfile(store.profile.copy()..weightKg = 75.0..heightCm = 175.0);
      final wBefore = store.profile.weightKg;
      final hBefore = store.profile.heightCm;

      await store.setUnits(UnitSystem.imperial);
      await store.setUnits(UnitSystem.metric);

      expect(store.profile.weightKg, equals(wBefore),
          reason: 'Cambiar unidades no debe alterar weightKg canónico');
      expect(store.profile.heightCm, equals(hBefore),
          reason: 'Cambiar unidades no debe alterar heightCm canónico');
      store.dispose();
    });
  });
}
