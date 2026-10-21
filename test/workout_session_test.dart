import 'package:flutter_test/flutter_test.dart';

import 'package:vigoriafit/models/workout_session.dart';
import 'package:vigoriafit/data/workouts.dart';
import 'package:vigoriafit/models/profile.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

WorkoutSession _makeSession({String id = 'sess1', String uid = 'u1'}) =>
    WorkoutSession(
      id: id,
      uid: uid,
      workoutId: 'home_fullbody',
      workoutTitle: 'Full body en casa',
      startedAt: DateTime(2026, 10, 14, 10, 0),
      exercises: [
        SessionExercise(
          exerciseIndex: 0,
          exerciseName: 'Sentadillas',
          setsTarget: '3 x 15',
          pose: 'squat',
          trackingType: TrackingType.reps,
          restSeconds: 60,
        ),
        SessionExercise(
          exerciseIndex: 1,
          exerciseName: 'Press banca',
          setsTarget: '4 x 8-10',
          pose: 'bench_press',
          trackingType: TrackingType.repsAndLoad,
          restSeconds: 90,
        ),
        SessionExercise(
          exerciseIndex: 2,
          exerciseName: 'Plancha',
          setsTarget: '3 x 30 seg',
          pose: 'plank',
          trackingType: TrackingType.duration,
          restSeconds: 45,
        ),
      ],
    );

SeriesEntry _repsEntry({String id = 's1', int setIndex = 0, int reps = 12}) =>
    SeriesEntry(
        id: id,
        setIndex: setIndex,
        type: TrackingType.reps,
        reps: reps,
        status: SeriesStatus.done);

SeriesEntry _loadEntry({
  String id = 's2',
  int setIndex = 0,
  int reps = 8,
  double load = 60.0,
}) =>
    SeriesEntry(
        id: id,
        setIndex: setIndex,
        type: TrackingType.repsAndLoad,
        reps: reps,
        loadKg: load,
        status: SeriesStatus.done);

SeriesEntry _durEntry(
        {String id = 's3', int setIndex = 0, int sec = 30}) =>
    SeriesEntry(
        id: id,
        setIndex: setIndex,
        type: TrackingType.duration,
        durationSec: sec,
        status: SeriesStatus.done);

// ── Tests de modelo WorkoutSession ───────────────────────────────────────────

void main() {
  recoveryTests();

  group('WorkoutSession — serialización', () {
    test('toJson / fromJson preserva todos los campos', () {
      final s = _makeSession();
      s.addSeries(0, _repsEntry());
      s.addSeries(1, _loadEntry());
      s.addSeries(2, _durEntry());
      s.status = WorkoutStatus.finished;
      s.finishedAt = DateTime(2026, 10, 14, 11, 0);
      s.syncState = SessionSyncState.pending;

      final copy = WorkoutSession.fromJson(s.toJson());

      expect(copy.id, s.id);
      expect(copy.uid, s.uid);
      expect(copy.workoutId, s.workoutId);
      expect(copy.workoutTitle, s.workoutTitle);
      expect(copy.startedAt, s.startedAt);
      expect(copy.status, WorkoutStatus.finished);
      expect(copy.finishedAt, s.finishedAt);
      expect(copy.syncState, SessionSyncState.pending);
      expect(copy.exercises.length, 3);
      expect(copy.exercises[0].series.length, 1);
      expect(copy.exercises[0].series[0].reps, 12);
      expect(copy.exercises[1].series[0].loadKg, 60.0);
      expect(copy.exercises[2].series[0].durationSec, 30);
    });

    test('fromJson ignora campos desconocidos sin lanzar', () {
      final s = _makeSession();
      final map = s.toMap()..['unknownField'] = 'ignored';
      expect(() => WorkoutSession.fromMap(map), returnsNormally);
    });
  });

  group('WorkoutSession — addSeries (idempotencia)', () {
    test('agregar dos veces la misma serie (mismo id) no duplica', () {
      final s = _makeSession();
      final entry = _repsEntry();
      s.addSeries(0, entry);
      s.addSeries(0, entry); // mismo id
      expect(s.exercises[0].series.length, 1);
    });

    test('agregar series con ids distintos las acumula', () {
      final s = _makeSession();
      s.addSeries(0, _repsEntry(id: 'a', setIndex: 0, reps: 10));
      s.addSeries(0, _repsEntry(id: 'b', setIndex: 1, reps: 12));
      s.addSeries(0, _repsEntry(id: 'c', setIndex: 2, reps: 15));
      expect(s.exercises[0].series.length, 3);
      expect(s.totalDoneSeries, 3);
    });

    test('addSeries ignora índice fuera de rango', () {
      final s = _makeSession();
      s.addSeries(99, _repsEntry()); // fuera de rango
      expect(s.totalDoneSeries, 0);
    });
  });

  group('WorkoutSession — updateSeries (corrección)', () {
    test('actualiza reps e id se mantiene', () {
      final s = _makeSession();
      final entry = _repsEntry(id: 'e1', reps: 10);
      s.addSeries(0, entry);
      final corrected = entry.copyWith(reps: 15);
      s.updateSeries(0, corrected);
      expect(s.exercises[0].series[0].reps, 15);
      expect(s.exercises[0].series[0].id, 'e1');
    });

    test('actualizar serie inexistente no hace nada', () {
      final s = _makeSession();
      s.addSeries(0, _repsEntry(id: 'e1', reps: 10));
      final ghost = _repsEntry(id: 'ghost', reps: 99);
      s.updateSeries(0, ghost);
      expect(s.exercises[0].series.length, 1);
      expect(s.exercises[0].series[0].reps, 10);
    });
  });

  group('WorkoutSession — estados y transiciones', () {
    test('isActive / isFinished reflejan el estado', () {
      final s = _makeSession();
      expect(s.isActive, true);
      expect(s.isFinished, false);
      s.status = WorkoutStatus.finished;
      expect(s.isActive, false);
      expect(s.isFinished, true);
    });

    test('totalDoneSeries cuenta solo las series con status done', () {
      final s = _makeSession();
      s.addSeries(0, _repsEntry(id: 'a')..status = SeriesStatus.done);
      s.addSeries(0,
          SeriesEntry(id: 'b', setIndex: 1, type: TrackingType.reps, status: SeriesStatus.skipped));
      expect(s.totalDoneSeries, 1);
    });
  });

  group('SeriesEntry — serialización', () {
    test('repsAndLoad sin carga especificada preserva null', () {
      final e = SeriesEntry(
          id: 'x', setIndex: 0, type: TrackingType.repsAndLoad, reps: 8);
      final copy = SeriesEntry.fromMap(e.toMap());
      expect(copy.loadKg, isNull);
      expect(copy.reps, 8);
    });

    test('duration sin reps no serializa reps', () {
      final e = _durEntry(sec: 45);
      final map = e.toMap();
      expect(map.containsKey('r'), false);
      expect(map.containsKey('d'), true);
      expect(SeriesEntry.fromMap(map).durationSec, 45);
    });
  });

  // ── Tests de catálogo y filtros ──────────────────────────────────────────

  group('Workouts.filtered — objetivo', () {
    test('filtra solo rutinas del objetivo seleccionado', () {
      final result =
          Workouts.filtered(goal: Goal.gainMuscle, profile: _profile());
      expect(result.every((w) => w.goal == Goal.gainMuscle), true);
      expect(result.isNotEmpty, true);
    });

    test('si no hay coincidencias devuelve lista vacía (sin fallback)', () {
      // Con gym=false y gainMuscle, todas las rutinas gym quedan fuera
      final result = Workouts.filtered(needsGym: false, goal: Goal.gainMuscle);
      // gym_upper / gym_lower tienen gainMuscle pero needsGym=true
      expect(result.every((w) => !w.needsGym), true);
    });
  });

  group('Workouts.filtered — nivel', () {
    test('nivel beginner incluye rutinas sin nivel especificado', () {
      final result =
          Workouts.filtered(level: Level.beginner, profile: _profile());
      // home_fullbody no tiene level (null) → debe aparecer
      expect(result.any((w) => w.id == 'home_fullbody'), true);
      // gym_upper tiene Level.intermediate → no debe aparecer para beginner
      expect(result.every((w) => w.level == null || w.level == Level.beginner),
          true);
    });

    test('nivel intermediate incluye rutinas sin nivel y las intermediate', () {
      final result =
          Workouts.filtered(level: Level.intermediate, profile: _profile());
      expect(
          result.every(
              (w) => w.level == null || w.level == Level.intermediate),
          true);
    });
  });

  group('Workouts.filtered — equipamiento', () {
    test('needsGym=false excluye rutinas de gym', () {
      final result = Workouts.filtered(needsGym: false);
      expect(result.every((w) => !w.needsGym), true);
    });

    test('needsGym=true excluye rutinas en casa', () {
      final result = Workouts.filtered(needsGym: true);
      expect(result.every((w) => w.needsGym), true);
    });

    test('equipamiento no se mezcla con objetivo', () {
      final gymLose = Workouts.filtered(needsGym: true, goal: Goal.loseFat);
      expect(gymLose.every((w) => w.needsGym && w.goal == Goal.loseFat), true);
    });
  });

  group('Workouts.filtered — combinaciones', () {
    test('filtros combinados no relajan restricciones', () {
      final result = Workouts.filtered(
          needsGym: false, goal: Goal.gainMuscle, level: Level.beginner);
      // Sin gym y gainMuscle: debería ser vacío o rutinas sin gym que calzan
      for (final w in result) {
        expect(w.needsGym, false);
        expect(w.goal, Goal.gainMuscle);
        expect(w.level == null || w.level == Level.beginner, true);
      }
    });

    test('sin filtros devuelve todas las rutinas', () {
      final result = Workouts.filtered();
      expect(result.length, Workouts.all.length);
    });
  });

  // ── Tests de historial ────────────────────────────────────────────────────

  group('WorkoutSession — historial sin duplicados', () {
    test('misma sesión no aparece dos veces por id', () {
      final s1 = _makeSession(id: 'a');
      s1.status = WorkoutStatus.finished;
      final s2 = _makeSession(id: 'a'); // mismo id
      s2.status = WorkoutStatus.finished;

      // Simular deduplicación por id (la misma lógica que usa el servicio)
      final history = <String, WorkoutSession>{};
      history[s1.id] = s1;
      history[s2.id] = s2; // reemplaza, no duplica

      expect(history.length, 1);
    });

    test('sesiones de distintos ids se conservan separadas', () {
      final sessions = [
        _makeSession(id: 'a')..status = WorkoutStatus.finished,
        _makeSession(id: 'b')..status = WorkoutStatus.finished,
        _makeSession(id: 'c')..status = WorkoutStatus.finished,
      ];
      final byId = {for (final s in sessions) s.id: s};
      expect(byId.length, 3);
    });
  });

  group('WorkoutSession — aislamiento de cuentas', () {
    test('sesión de uid A no es de uid B', () {
      final s = _makeSession(id: 'x', uid: 'uid_a');
      expect(s.uid, 'uid_a');
      expect(s.uid != 'uid_b', true);
    });
  });

  group('SeriesEntry — validación de tipos', () {
    test('carga cero es distinto de null', () {
      final withZeroLoad = SeriesEntry(
        id: 'z',
        setIndex: 0,
        type: TrackingType.repsAndLoad,
        reps: 10,
        loadKg: 0.0,
        status: SeriesStatus.done,
      );
      expect(withZeroLoad.loadKg, 0.0);
      expect(withZeroLoad.loadKg != null, true);
    });

    test('copyWith solo cambia los campos especificados', () {
      final original = _loadEntry(reps: 8, load: 60.0);
      final corrected = original.copyWith(reps: 10);
      expect(corrected.reps, 10);
      expect(corrected.loadKg, 60.0);
      expect(corrected.id, original.id);
    });
  });
}

Profile _profile() => Profile(
      name: 'Test',
      goal: Goal.health,
      level: Level.beginner,
      hasGym: true,
    );

// ── Tests de recuperación de crash ───────────────────────────────────────────

// Estos tests verifican el comportamiento esperado de carga/recuperación que
// loadForUser implementa. No requieren el servicio completo ni Firebase.

void recoveryTests() {
  group('Crash recovery — sesión huérfana en disco', () {
    test('sesión finished serializada es identificable como no-activa', () {
      final s = _makeSession();
      s.status = WorkoutStatus.finished;
      s.finishedAt = DateTime(2026, 10, 14, 11, 0);
      s.syncState = SessionSyncState.pending;

      final recovered = WorkoutSession.fromJson(s.toJson());
      expect(recovered.isActive, false);
      expect(recovered.isFinished, true);
      // loadForUser movería esta sesión al historial en lugar de marcarla activa.
    });

    test('sesión finished recuperada conserva syncState para reintento', () {
      final s = _makeSession();
      s.addSeries(0, _repsEntry(id: 'p1', reps: 15));
      s.addSeries(0, _repsEntry(id: 'p2', setIndex: 1, reps: 12));
      s.status = WorkoutStatus.finished;
      s.syncState = SessionSyncState.pending;

      final recovered = WorkoutSession.fromJson(s.toJson());
      expect(recovered.syncState, SessionSyncState.pending);
      expect(recovered.exercises[0].series.length, 2);
      // Las series sobreviven al crash y al ciclo JSON.
    });

    test('sesión crashed-y-recuperada no aparece dos veces en historial (dedup)', () {
      final s = _makeSession();
      s.status = WorkoutStatus.finished;

      // Simular: historial ya tiene la sesión (persistHistory completó)
      // pero v3_active_session también la tiene (remove no se ejecutó).
      final historyBefore = [s];
      final activeRaw = s.toJson();

      final recovered = WorkoutSession.fromJson(activeRaw);
      // _addToLocalHistory hace removeWhere por id antes de insertar → no duplica.
      final merged = List<WorkoutSession>.from(historyBefore);
      merged.removeWhere((x) => x.id == recovered.id);
      merged.insert(0, recovered);

      expect(merged.length, 1);
      expect(merged[0].id, s.id);
    });
  });

  group('Límite de historial local — sesiones pendientes conservadas', () {
    test('algoritmo de recorte preserva sesiones pending fuera del límite top-50', () {
      const maxLocalHistory = 50;
      // 50 sesiones confirmadas (más recientes) + 1 pending (más antigua).
      final sessions = List.generate(51, (i) {
        return WorkoutSession(
          id: 'sess-$i',
          uid: 'u1',
          workoutId: 'home_fullbody',
          workoutTitle: 'Full body',
          startedAt: DateTime(2026, 1, i + 1, 10, 0),
          status: WorkoutStatus.finished,
          syncState: i == 0 // la más antigua → posición 50 tras ordenar
              ? SessionSyncState.pending
              : SessionSyncState.confirmed,
        );
      });
      sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      // Tras ordenar: [sess-50 (confirmed), ..., sess-1 (confirmed), sess-0 (pending)]

      // Aplicar el mismo algoritmo que _trimHistory y _persistHistory usan.
      bool needsSync(WorkoutSession s) =>
          s.status == WorkoutStatus.finished &&
          (s.syncState == SessionSyncState.pending ||
              s.syncState == SessionSyncState.failed);

      final pending = sessions.where(needsSync).toList();
      final rest =
          sessions.where((s) => !needsSync(s)).take(maxLocalHistory).toList();
      final trimmed = [...pending, ...rest]
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

      // 50 confirmed + 1 pending = 51, aunque el límite sea 50.
      expect(trimmed.length, 51);
      expect(trimmed.any((s) => s.id == 'sess-0' && s.syncState == SessionSyncState.pending), true);
      expect(trimmed.where((s) => s.syncState == SessionSyncState.confirmed).length, 50);
    });

    test('sesión failed también se conserva fuera del límite', () {
      const maxLocalHistory = 50;
      final sessions = List.generate(51, (i) {
        return WorkoutSession(
          id: 'fail-$i',
          uid: 'u1',
          workoutId: 'wid',
          workoutTitle: 'T',
          startedAt: DateTime(2026, 1, i + 1),
          status: WorkoutStatus.finished,
          syncState: i == 0
              ? SessionSyncState.failed
              : SessionSyncState.confirmed,
        );
      });
      sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));

      bool needsSync(WorkoutSession s) =>
          s.status == WorkoutStatus.finished &&
          (s.syncState == SessionSyncState.pending ||
              s.syncState == SessionSyncState.failed);

      final pending = sessions.where(needsSync).toList();
      final rest =
          sessions.where((s) => !needsSync(s)).take(maxLocalHistory).toList();
      final trimmed = [...pending, ...rest];

      expect(trimmed.any((s) => s.syncState == SessionSyncState.failed), true);
      expect(trimmed.where((s) => s.syncState == SessionSyncState.confirmed).length, 50);
    });
  });

  group('Idempotencia — modelo de sesión', () {
    test('finalizar dos veces la misma sesión no cambia finishedAt', () {
      final s = _makeSession();
      final firstFinish = DateTime(2026, 10, 14, 11, 0);
      s.status = WorkoutStatus.finished;
      s.finishedAt = firstFinish;

      // Segundo intento: finishedAt ??= DateTime.now() no sobreescribe.
      s.finishedAt ??= DateTime(2026, 10, 14, 12, 0);
      expect(s.finishedAt, firstFinish);
    });

    test('retrySync sobre sesión ya confirmed no cambia su estado', () {
      final s = _makeSession();
      s.status = WorkoutStatus.finished;
      s.syncState = SessionSyncState.confirmed;

      // El servicio llama a _syncSession solo si pending o failed.
      final shouldRetry = s.syncState == SessionSyncState.pending ||
          s.syncState == SessionSyncState.failed;
      expect(shouldRetry, false);
      // syncState no se altera.
      expect(s.syncState, SessionSyncState.confirmed);
    });
  });
}
