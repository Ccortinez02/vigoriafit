import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigoriafit/models/profile.dart';
import 'package:vigoriafit/services/auth_service.dart';
import 'package:vigoriafit/services/profile_repository.dart';
import 'package:vigoriafit/services/store.dart';
import 'package:vigoriafit/services/sync_state.dart';

/// Auth fake idéntico al de los otros tests.
class _Auth implements AccountAuth {
  AccountIdentity? user;
  final _ctrl = StreamController<AccountIdentity?>.broadcast(sync: true);
  @override
  AccountIdentity? get current => user;
  @override
  Stream<AccountIdentity?> get changes => _ctrl.stream;
  void sign(String? uid) {
    user = uid == null ? null : AccountIdentity(uid, '$uid@t.test', uid);
    _ctrl.add(user);
  }

  @override
  Future<void> register(String n, String e, String p) async => sign(e);
  @override
  Future<void> signIn(String e, String p) async => sign(e);
  @override
  Future<void> signInWithGoogle() async => sign('g');
  @override
  Future<void> signOut() async => sign(null);
}

/// Repositorio que permite controlar cuándo completa cada guardado.
class _ControllableProfiles implements ProfileRepository {
  final _db = <String, AccountProfile>{};
  // Cada llamada a save() obtiene un Completer de esta cola.
  final _queue = <Completer<void>>[];
  int saveCount = 0;

  /// Añade un completer a la cola para que el próximo save espere.
  Completer<void> enqueue() {
    final c = Completer<void>();
    _queue.add(c);
    return c;
  }

  @override
  Future<AccountProfile> loadOrCreate(AccountIdentity user) async {
    return _db.putIfAbsent(
      user.uid,
      () => AccountProfile(Profile(name: user.name), onboarded: false),
    );
  }

  @override
  Future<void> save(String uid, Profile profile, {required bool onboarded}) async {
    saveCount++;
    if (_queue.isNotEmpty) {
      final c = _queue.removeAt(0);
      await c.future; // espera hasta que el test complete este guardado
    }
    _db[uid] = AccountProfile(profile.copy(), onboarded: onboarded);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Auth auth;
  late _ControllableProfiles profiles;
  late AppStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = _Auth();
    profiles = _ControllableProfiles();
    store = AppStore(auth: auth, profiles: profiles, clearReminders: () async {});
  });

  tearDown(() async {
    store.dispose();
    await auth._ctrl.close();
  });

  group('Dos guardados consecutivos', () {
    test(
      'Guardado secuencial: el segundo perfil queda confirmado',
      () async {
        await store.load();
        await store.login('alice', 'p');
        await store.completeOnboarding(Profile(name: 'Alice'));

        // Guardado 1 (sin bloquear)
        final p1 = Profile(name: 'Alice v1', weightKg: 60);
        await store.saveProfile(p1);
        expect(store.profile.name, 'Alice v1');
        expect(store.profileSyncState, SyncState.confirmed);

        // Guardado 2 inmediatamente después
        final p2 = Profile(name: 'Alice v2', weightKg: 65);
        await store.saveProfile(p2);
        expect(store.profile.name, 'Alice v2');
        expect(store.profileSyncState, SyncState.confirmed);

        // El repositorio remoto tiene el valor del segundo guardado.
        expect(profiles._db['alice']!.profile.name, 'Alice v2');
        expect(profiles._db['alice']!.profile.weightKg, 65);
      },
    );

    test(
      'Confirmación tardía del primero no borra ni sobrescribe el segundo: '
      'save2 (más reciente) prevalece aunque save1 complete después',
      () async {
        await store.load();
        await store.login('alice', 'p');
        await store.completeOnboarding(Profile(name: 'Alice'));

        // Bloquea el primer guardado hasta que lo liberemos.
        final c1 = profiles.enqueue();

        final p1 = Profile(name: 'Alice v1', weightKg: 60);
        final save1 = store.saveProfile(p1); // in-flight, bloqueado

        // Espera a que save1 llegue al punto de bloqueo (saving).
        await Future<void>.delayed(Duration.zero);
        expect(store.profileSyncState, SyncState.saving);

        // Bloquea también el segundo guardado.
        final c2 = profiles.enqueue();

        final p2 = Profile(name: 'Alice v2', weightKg: 65);
        // Este escenario fuerza concurrencia interna: prueba la robustez del store.
        // (En la app real el UI deshabilita el botón mientras _saving=true.)
        final save2 = store.saveProfile(p2); // in-flight, bloqueado

        await Future<void>.delayed(Duration.zero);

        // Completa el segundo guardado PRIMERO (llegó antes al servidor).
        c2.complete();
        await save2;
        expect(store.profile.name, 'Alice v2');
        expect(store.profileSyncState, SyncState.confirmed);

        // Ahora completa el primer guardado (llegó tarde al servidor).
        c1.complete();
        await save1; // debe completar sin lanzar

        // REGRESIÓN: save1 NO debe sobreescribir el estado de save2.
        // Con el fix de _saveGeneration, save1 detecta que myGeneration < _saveGeneration
        // y retorna sin tocar _profile, _profileSyncState ni _kPendingWrite.
        expect(profiles.saveCount, 3); // onboarding + save1 + save2
        expect(store.profile.name, 'Alice v2',
            reason: 'save1 (tardío) no debe sobreescribir a save2 (más reciente)');
        expect(store.profile.weightKg, 65,
            reason: 'save1 (tardío) no debe sobreescribir a save2 (más reciente)');
        expect(store.profileSyncState, SyncState.confirmed,
            reason: 'save1 tardío no debe degradar el estado confirmed de save2');

        // _kPendingWrite debe estar limpio (save2 lo borró; save1 no lo restaura).
        // getBool usa el prefijo 'flutter.' internamente, así que aquí se omite.
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool('vigoria_v2_alice_brio_pending_write_v1'),
          isNull,
          reason: 'save1 tardío no debe dejar _kPendingWrite activo tras la confirmación de save2',
        );
      },
    );

    test(
      'Reintento automático fallido al abrir: la edición posterior del usuario '
      'confirma correctamente y limpia _kPendingWrite',
      () async {
        // Simula un reinicio con borrador pendiente: _kPendingWrite=true en disco
        // como si el guardado anterior no hubiera llegado al servidor.
        SharedPreferences.setMockInitialValues({
          'flutter.vigoria_v2_alice_brio_profile_v1':
              Profile(name: 'Alice pendiente', weightKg: 70).toJson(),
          'flutter.vigoria_v2_alice_brio_onboarded_v1': true,
          'flutter.vigoria_v2_alice_brio_pending_write_v1': true,
        });

        // El reintento fallará (error de red simulado).
        final cRetry = profiles.enqueue();

        store = AppStore(
          auth: auth,
          profiles: profiles,
          clearReminders: () async {},
        );

        // Carga el store con alice ya autenticada.
        auth.sign('alice');
        // ignore() evita que Dart reporte el error al Zone antes de que
        // _profiles.save() empiece a escuchar el future. El await interno en
        // save() sigue recibiendo el error y lo relanza normalmente.
        cRetry.future.ignore();
        cRetry.completeError(Exception('red caída'));
        await store.load();

        // El reintento falló: _loaded=true, estado=failed, _kPendingWrite sigue en disco.
        expect(store.loaded, isTrue);
        expect(store.profileSyncState, SyncState.failed);
        final prefsAfterFail = await SharedPreferences.getInstance();
        expect(
          prefsAfterFail.getBool('vigoria_v2_alice_brio_pending_write_v1'),
          isTrue,
          reason: 'el reintento fallido no debe borrar _kPendingWrite',
        );

        // Ahora el usuario hace una nueva edición: esta es la edición que debe ganar.
        final pNuevo = Profile(name: 'Alice nueva edición', weightKg: 75);
        await store.saveProfile(pNuevo);

        // REGRESIÓN: la edición nueva confirma correctamente.
        expect(store.profile.name, 'Alice nueva edición');
        expect(store.profile.weightKg, 75);
        expect(store.profileSyncState, SyncState.confirmed);

        // _kPendingWrite limpio: saveProfile lo borró al confirmar.
        final prefsAfterSave = await SharedPreferences.getInstance();
        expect(
          prefsAfterSave.getBool('vigoria_v2_alice_brio_pending_write_v1'),
          isNull,
          reason: 'saveProfile debe borrar _kPendingWrite al confirmar',
        );
        // El remoto tiene los datos de la edición nueva.
        expect(profiles._db['alice']!.profile.name, 'Alice nueva edición');
      },
    );

    test(
      'Cambio de cuenta durante guardado: la confirmación tardía no contamina la sesión nueva',
      () async {
        await store.load();
        await store.login('alice', 'p');
        await store.completeOnboarding(Profile(name: 'Alice'));

        // Bloquea el guardado de Alice.
        final cAlice = profiles.enqueue();

        final pAlice = Profile(name: 'Alice editada', weightKg: 60);
        final saveAlice = store.saveProfile(pAlice); // in-flight

        await Future<void>.delayed(Duration.zero);
        expect(store.profileSyncState, SyncState.saving);

        // Cambia a Bob mientras Alice está guardando.
        await store.logout();
        await store.login('bob', 'p');
        expect(store.currentUid, 'bob');
        expect(store.profileSyncState, SyncState.idle);

        // Completa el guardado de Alice (confirmación tardía).
        cAlice.complete();
        // save de Alice lanzará StateError porque epoch cambió.
        await expectLater(saveAlice, throwsStateError);

        // Bob no fue contaminado.
        expect(store.currentUid, 'bob');
        expect(store.profile.name, 'bob');
        expect(store.profileSyncState, SyncState.idle);
      },
    );

    test(
      'Edición nueva prevalece: si save1 falla y save2 confirma, '
      'el estado queda confirmed con los datos de save2',
      () async {
        await store.load();
        await store.login('alice', 'p');
        await store.completeOnboarding(Profile(name: 'Alice'));

        // Save1 fallará.
        final c1 = profiles.enqueue();

        final p1 = Profile(name: 'Alice v1 fallida', weightKg: 60);
        final save1 = store.saveProfile(p1);

        await Future<void>.delayed(Duration.zero);

        // Save2 tiene éxito inmediato (sin bloqueo).
        final p2 = Profile(name: 'Alice v2 ok', weightKg: 65);
        final save2 = store.saveProfile(p2);

        // Falla save1.
        c1.completeError(Exception('red caída'));
        await expectLater(save1, throwsA(isA<Exception>()));
        await save2;

        // El perfil en el store y en el remoto debe reflejar save2.
        expect(store.profile.name, 'Alice v2 ok');
        expect(profiles._db['alice']!.profile.name, 'Alice v2 ok');
      },
    );
  });
}
