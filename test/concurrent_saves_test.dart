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
      'Guard pre-remoto: save1 no llama a _profiles.save() si save2 ya comenzó '
      'durante las escrituras locales de save1',
      () async {
        await store.load();
        await store.login('alice', 'p');
        await store.completeOnboarding(Profile(name: 'Alice'));
        // saveCount == 1 tras el onboarding.

        final p1 = Profile(name: 'Alice v1 vieja', weightKg: 60);
        final p2 = Profile(name: 'Alice v2 nueva', weightKg: 65);

        // Lanza los dos guardados sin await entre ellos.
        // save1 ejecuta sincrónicamente hasta su primer await (cache.setString),
        // luego save2 comienza y en su primer statement síncrono incrementa
        // _saveGeneration a 2. Cuando save1 reanuda y llega al guard pre-remoto
        // (que está ANTES de llamar a _profiles.save()), detecta 1 != 2 y aborta.
        final save1 = store.saveProfile(p1);
        final save2 = store.saveProfile(p2);

        await save1; // completa sin error (aborto limpio)
        await save2; // confirma normalmente

        // REGRESIÓN: el servidor solo recibió el guardado de save2.
        // save1 fue abortado por el guard pre-remoto antes de llamar a _profiles.save().
        expect(
          profiles.saveCount,
          2, // onboarding + save2 únicamente; save1 nunca llamó al repositorio
          reason: 'El guard pre-remoto debe evitar que save1 escriba en el servidor',
        );
        expect(store.profile.name, 'Alice v2 nueva');
        expect(store.profileSyncState, SyncState.confirmed);
      },
    );

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
      'Cola serializa escrituras: save2 espera a save1 y el servidor queda '
      'con la edición más reciente (Alice v2)',
      () async {
        await store.load();
        await store.login('alice', 'p');
        await store.completeOnboarding(Profile(name: 'Alice'));

        // Bloquea save1 en Firestore.
        final c1 = profiles.enqueue();

        final p1 = Profile(name: 'Alice v1', weightKg: 60);
        final save1 = store.saveProfile(p1); // in-flight, bloqueado en c1

        await Future<void>.delayed(Duration.zero);
        expect(store.profileSyncState, SyncState.saving);

        // save2 comienza antes de que save1 termine.
        // La cola lo hace esperar al slot de save1 antes de escribir en Firestore.
        final p2 = Profile(name: 'Alice v2', weightKg: 65);
        final save2 = store.saveProfile(p2);

        // Encola c2: save2 lo dequeue cuando llegue a _profiles.save() tras la cola.
        final c2 = profiles.enqueue();

        await Future<void>.delayed(Duration.zero);

        // Completa save1: la cola libera a save2.
        c1.complete();
        await save1; // save1 completa sin tocar el estado local (generation guard)

        // save2 ahora está en _profiles.save() esperando c2.
        c2.complete();
        await save2;

        // REGRESIÓN: el servidor debe tener los datos de save2, no de save1.
        // Con la cola, save2 siempre escribe DESPUÉS de save1 → prevalece.
        expect(profiles.saveCount, 3, reason: 'onboarding + save1 + save2');
        expect(
          profiles._db['alice']!.profile.name,
          'Alice v2',
          reason: 'El servidor debe tener la edición más reciente',
        );
        expect(profiles._db['alice']!.profile.weightKg, 65);
        expect(store.profile.name, 'Alice v2');
        expect(store.profile.weightKg, 65);
        expect(store.profileSyncState, SyncState.confirmed);

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool('vigoria_v2_alice_brio_pending_write_v1'),
          isNull,
          reason: 'save2 confirmó y borró _kPendingWrite',
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
      'Logout + login misma cuenta: epoch protege el estado local; '
      'limitación documentada: sin control de versiones transaccional el remoto '
      'puede quedar con datos viejos',
      () async {
        await store.load();
        await store.login('alice', 'p');
        await store.completeOnboarding(Profile(name: 'Alice'));

        // Bloquea el guardado antiguo (sesión 1).
        final cOld = profiles.enqueue();

        final pOld = Profile(name: 'Alice vieja', weightKg: 60);
        final saveOld = store.saveProfile(pOld); // in-flight en sesión 1

        await Future<void>.delayed(Duration.zero);
        expect(store.profileSyncState, SyncState.saving);

        // La nueva sesión verá pendingWrite=true (escrito por el save anterior)
        // y ejecutará un reintento automático. Bloqueamos ese reintento para
        // poder controlar el orden de las escrituras remotas.
        final cRetry = profiles.enqueue();

        await store.logout();

        // login() inicia _restoreAccount, que bloquea en cRetry.
        // No hacemos await para poder controlar la secuencia.
        final loginFut = store.login('alice', 'p');
        await Future<void>.delayed(Duration.zero); // dejar que empiece el reintento

        // PROTEGIDO: aunque una sesión esté en vuelo, la nueva sesión empieza
        // con epoch distinto y el estado local es independiente.
        expect(store.currentUid, 'alice');

        // Completamos el reintento de la nueva sesión (escribe 'Alice vieja' — el borrador pendiente).
        cRetry.complete();
        await loginFut; // _restoreAccount termina: pendingWrite limpio, confirmed

        expect(store.profileSyncState, SyncState.confirmed);

        // La nueva sesión guarda datos distintos.
        final pNew = Profile(name: 'Alice nueva', weightKg: 65);
        await store.saveProfile(pNew);
        expect(store.profile.name, 'Alice nueva');
        expect(store.profileSyncState, SyncState.confirmed);

        // Ahora completa la escritura antigua (ya desconectada de la cola nueva).
        // En el mock, _profiles.save() de cOld sobreescribe _db con 'Alice vieja'.
        // En Firestore real, si la transacción antigua llega al servidor después
        // de que la nueva ya confirmó, el servidor queda con datos viejos.
        cOld.complete();
        await expectLater(saveOld, throwsStateError,
            reason: 'Epoch cambió: la escritura antigua no actualiza el estado local');

        // ESTADO LOCAL: protegido por epoch — siempre refleja la sesión activa.
        expect(store.profile.name, 'Alice nueva',
            reason: 'Epoch protege el estado local');
        expect(store.profileSyncState, SyncState.confirmed);

        // LIMITACIÓN REMOTA (demostrada con el mock): la escritura antigua que
        // completó después sobreescribió _db. En Firestore real, la protección
        // completa requiere control de versiones transaccional (campo version +
        // conditional write). Documentado en docs/SPRINT_2.md.
        expect(profiles._db['alice']!.profile.name, 'Alice vieja',
            reason:
                'LIMITACIÓN: la escritura antigua completó después y sobreescribió '
                'el contenido remoto. El estado local está correcto, el remoto no.');
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
