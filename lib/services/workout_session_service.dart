import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/workout.dart';
import '../models/workout_session.dart';
import 'account_preferences.dart';

/// Gestiona sesiones de entrenamiento: inicio, registro de series, finalización,
/// cancelación y recuperación tras interrupción.
///
/// El progreso se persiste localmente en AccountPreferences después de cada
/// operación. La sincronización remota ocurre al finalizar (no por serie).
///
/// Una sesión activa sobrevive al cierre del proceso porque se escribe en disco
/// antes de confirmar la operación. Al retomar, se lee de disco.
class WorkoutSessionService extends ChangeNotifier {
  WorkoutSessionService();

  static const _uuid = Uuid();

  // ── Claves de AccountPreferences ────────────────────────────────────────
  static const _kActiveSession = 'v3_active_session';
  static const _kHistory = 'v3_session_history';
  static const _kRestStartedAt = 'v3_rest_started_at';
  static const _kRestDuration = 'v3_rest_duration';

  static const int _maxLocalHistory = 50;

  WorkoutSession? _active;
  List<WorkoutSession> _history = [];
  SessionSyncState _syncState = SessionSyncState.local;

  // Temporizador de descanso
  DateTime? _restStartedAt;
  int _restDurationSec = 60;
  Timer? _restTicker;
  bool _restRunning = false;

  // Guard contra doble operación simultánea
  bool _operationInProgress = false;

  WorkoutSession? get activeSession => _active;
  List<WorkoutSession> get history => List.unmodifiable(_history);
  SessionSyncState get syncState => _syncState;
  bool get restRunning => _restRunning;
  int get restDurationSec => _restDurationSec;

  int get restRemainingSec {
    if (!_restRunning || _restStartedAt == null) return _restDurationSec;
    final elapsed = DateTime.now().difference(_restStartedAt!).inSeconds;
    return max(0, _restDurationSec - elapsed);
  }

  bool get restFinished =>
      _restRunning == false && _restStartedAt != null && restRemainingSec == 0;

  // ── Carga inicial ────────────────────────────────────────────────────────

  /// Carga la sesión activa y el historial para el usuario actual.
  /// Se llama desde AppStore al establecer sesión.
  Future<void> loadForUser(AccountPreferences prefs) async {
    final raw = prefs.getString(_kActiveSession);
    if (raw != null) {
      try {
        _active = WorkoutSession.fromJson(raw);
      } catch (_) {
        _active = null;
      }
    }
    final list = prefs.getStringList(_kHistory) ?? [];
    _history = [];
    for (final s in list) {
      try {
        _history.add(WorkoutSession.fromJson(s));
      } catch (_) {}
    }
    _history.sort((a, b) => b.startedAt.compareTo(a.startedAt));

    // Recuperar descanso si estaba activo
    final rsa = prefs.getInt(_kRestStartedAt);
    final rd = prefs.getInt(_kRestDuration);
    if (rsa != null && rd != null) {
      _restDurationSec = rd;
      final started = DateTime.fromMillisecondsSinceEpoch(rsa);
      final remaining = rd - DateTime.now().difference(started).inSeconds;
      if (remaining > 0) {
        _restStartedAt = started;
        _restDurationSec = rd;
        _startRestTicker(prefs);
      } else {
        _restStartedAt = started; // fue activo, mostrar "terminado"
        _restRunning = false;
      }
    }

    notifyListeners();
  }

  /// Limpia estado al cerrar sesión o cambiar de cuenta.
  void clearForUser() {
    _active = null;
    _history = [];
    _syncState = SessionSyncState.local;
    _stopRest();
    _restStartedAt = null;
    notifyListeners();
  }

  // ── Inicio de sesión ─────────────────────────────────────────────────────

  /// Inicia una nueva sesión. Si ya hay una activa del mismo usuario, la
  /// devuelve en lugar de crear una duplicada.
  ///
  /// Lanza [StateError] si ya hay una sesión activa de una rutina distinta
  /// (el llamador debe ofrecer retomarla o cancelarla primero).
  Future<WorkoutSession> startSession(
    Workout workout,
    String uid,
    AccountPreferences prefs,
  ) async {
    if (_active != null && _active!.status == WorkoutStatus.active) {
      if (_active!.workoutId == workout.id && _active!.uid == uid) {
        return _active!;
      }
      throw StateError(
        'Ya hay una sesión activa de "${_active!.workoutTitle}". '
        'Retómala o cancélala antes de iniciar otra.',
      );
    }
    final session = WorkoutSession(
      id: _uuid.v4(),
      uid: uid,
      workoutId: workout.id,
      workoutTitle: workout.title,
      startedAt: DateTime.now(),
      exercises: workout.exercises.asMap().entries.map((entry) {
        final e = entry.value;
        return SessionExercise(
          exerciseIndex: entry.key,
          exerciseName: e.name,
          setsTarget: e.sets,
          pose: e.pose,
          trackingType: e.trackingType,
          restSeconds: e.restSeconds,
        );
      }).toList(),
    );
    _active = session;
    _syncState = SessionSyncState.local;
    notifyListeners();
    await _persistActive(prefs);
    return session;
  }

  // ── Registro de series ───────────────────────────────────────────────────

  /// Añade una serie al ejercicio [exerciseIndex]. Idempotente: si la serie
  /// ya existe (mismo id), la ignora. Evita duplicación por doble toque.
  Future<void> addSeries(
    int exerciseIndex,
    SeriesEntry entry,
    AccountPreferences prefs,
  ) async {
    if (_operationInProgress) return;
    _operationInProgress = true;
    try {
      final session = _active;
      if (session == null || !session.isActive) return;
      session.addSeries(exerciseIndex, entry);
      notifyListeners();
      await _persistActive(prefs);
    } finally {
      _operationInProgress = false;
    }
  }

  /// Corrige una serie ya registrada (por id estable). No-op si no existe.
  Future<void> updateSeries(
    int exerciseIndex,
    SeriesEntry updated,
    AccountPreferences prefs,
  ) async {
    final session = _active;
    if (session == null || !session.isActive) return;
    session.updateSeries(exerciseIndex, updated);
    notifyListeners();
    await _persistActive(prefs);
  }

  // ── Finalización idempotente ─────────────────────────────────────────────

  /// Finaliza la sesión activa. Idempotente: llamar dos veces no crea dos
  /// registros ni cambia la fecha de finalización. Si no hay conexión, la
  /// sesión queda en [SessionSyncState.pending] para reintento posterior.
  Future<void> finishSession(
    AccountPreferences prefs,
    FirebaseFirestore db,
  ) async {
    if (_operationInProgress) return;
    final session = _active;
    if (session == null) return;
    // Idempotencia: si ya está finalizada, solo reintentar sync si está pending.
    if (session.status == WorkoutStatus.finished) {
      if (session.syncState == SessionSyncState.pending ||
          session.syncState == SessionSyncState.failed) {
        await _syncSession(session, prefs, db);
      }
      return;
    }

    _operationInProgress = true;
    try {
      session.status = WorkoutStatus.finished;
      session.finishedAt ??= DateTime.now();
      _syncState = SessionSyncState.pending;
      session.syncState = SessionSyncState.pending;
      notifyListeners();

      // Persiste localmente antes de intentar remoto.
      await _persistActive(prefs);

      // Mueve al historial local.
      _addToLocalHistory(session);
      await _persistHistory(prefs);

      // Sincronización remota.
      await _syncSession(session, prefs, db);

      // Limpia sesión activa solo tras confirmar (o anotar fallo).
      _active = null;
      await prefs.remove(_kActiveSession);
      notifyListeners();
    } finally {
      _operationInProgress = false;
    }
  }

  // ── Cancelación ──────────────────────────────────────────────────────────

  /// Cancela la sesión activa. Guarda un registro cancelado (no cuenta como
  /// entrenamiento completado). La cancelación es local; no se sincroniza.
  Future<void> cancelSession(AccountPreferences prefs) async {
    if (_operationInProgress) return;
    final session = _active;
    if (session == null) return;
    if (!session.isActive) return;
    _operationInProgress = true;
    try {
      session.status = WorkoutStatus.cancelled;
      session.finishedAt = DateTime.now();
      session.syncState = SessionSyncState.local;
      _addToLocalHistory(session);
      await _persistHistory(prefs);
      _active = null;
      await prefs.remove(_kActiveSession);
      _stopRest();
      notifyListeners();
    } finally {
      _operationInProgress = false;
    }
  }

  // ── Reintento de sincronización ──────────────────────────────────────────

  /// Reintenta sincronizar una sesión pendiente del historial.
  Future<void> retrySync(
    String sessionId,
    AccountPreferences prefs,
    FirebaseFirestore db,
  ) async {
    final session = _history.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => throw StateError('Sesión no encontrada: $sessionId'),
    );
    if (session.status != WorkoutStatus.finished) return;
    await _syncSession(session, prefs, db);
  }

  // ── Historial remoto ─────────────────────────────────────────────────────

  /// Carga sesiones finalizadas desde Firestore (últimas 30), paginadas.
  /// Combina con historial local; deduplica por id.
  Future<void> fetchRemoteHistory(
    String uid,
    FirebaseFirestore db, {
    DocumentSnapshot? after,
  }) async {
    try {
      var q = db
          .collection('users')
          .doc(uid)
          .collection('workout_sessions')
          .where('status', isEqualTo: WorkoutStatus.finished.index)
          .orderBy('finishedAt', descending: true)
          .limit(30);
      if (after != null) q = q.startAfterDocument(after);
      final snap = await q.get();
      for (final doc in snap.docs) {
        final remote = WorkoutSession.fromMap(
            {...doc.data(), 'id': doc.id, 'uid': uid, 'ss': SessionSyncState.confirmed.index});
        final i = _history.indexWhere((s) => s.id == remote.id);
        if (i >= 0) {
          _history[i] = remote;
        } else {
          _history.add(remote);
        }
      }
      _history.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      notifyListeners();
    } catch (_) {
      // Error de red: mantiene historial local
    }
  }

  // ── Temporizador de descanso ─────────────────────────────────────────────

  void startRest(int durationSec, AccountPreferences prefs) {
    _stopRest();
    _restDurationSec = durationSec;
    _restStartedAt = DateTime.now();
    _restRunning = true;
    _persistRestState(prefs);
    _startRestTicker(prefs);
    notifyListeners();
  }

  void stopRest(AccountPreferences prefs) {
    _stopRest();
    prefs.remove(_kRestStartedAt);
    prefs.remove(_kRestDuration);
    notifyListeners();
  }

  void resetRest(int durationSec, AccountPreferences prefs) {
    startRest(durationSec, prefs);
  }

  void _startRestTicker(AccountPreferences prefs) {
    _restTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (restRemainingSec <= 0) {
        _restTicker?.cancel();
        _restRunning = false;
        prefs.remove(_kRestStartedAt);
        prefs.remove(_kRestDuration);
        notifyListeners();
        return;
      }
      notifyListeners();
    });
    _restRunning = true;
  }

  void _stopRest() {
    _restTicker?.cancel();
    _restTicker = null;
    _restRunning = false;
  }

  Future<void> _persistRestState(AccountPreferences prefs) async {
    await prefs.setInt(
        _kRestStartedAt, _restStartedAt!.millisecondsSinceEpoch);
    await prefs.setInt(_kRestDuration, _restDurationSec);
  }

  // ── Persistencia local ───────────────────────────────────────────────────

  Future<void> _persistActive(AccountPreferences prefs) async {
    final s = _active;
    if (s != null) {
      await prefs.setString(_kActiveSession, s.toJson());
    }
  }

  Future<void> _persistHistory(AccountPreferences prefs) async {
    final list = _history.take(_maxLocalHistory).map((s) => s.toJson()).toList();
    await prefs.setStringList(_kHistory, list);
  }

  void _addToLocalHistory(WorkoutSession session) {
    _history.removeWhere((s) => s.id == session.id);
    _history.insert(0, session);
    if (_history.length > _maxLocalHistory) {
      _history = _history.sublist(0, _maxLocalHistory);
    }
  }

  // ── Sincronización remota ────────────────────────────────────────────────

  Future<void> _syncSession(
    WorkoutSession session,
    AccountPreferences prefs,
    FirebaseFirestore db,
  ) async {
    try {
      final ref = db
          .collection('users')
          .doc(session.uid)
          .collection('workout_sessions')
          .doc(session.id);
      final data = _toFirestoreMap(session);
      await db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          tx.set(ref, data);
        } else {
          // Solo actualiza si el documento remoto también está finalizado o no existe aún.
          final remoteStatus = snap.data()?['status'] as int?;
          if (remoteStatus == WorkoutStatus.finished.index) return;
          tx.update(ref, data);
        }
      }).timeout(const Duration(seconds: 20));

      final i = _history.indexWhere((s) => s.id == session.id);
      if (i >= 0) {
        _history[i].syncState = SessionSyncState.confirmed;
      }
      _syncState = SessionSyncState.confirmed;
      await _persistHistory(prefs);
      notifyListeners();
    } catch (_) {
      final i = _history.indexWhere((s) => s.id == session.id);
      if (i >= 0) {
        _history[i].syncState = SessionSyncState.failed;
      }
      _syncState = SessionSyncState.failed;
      await _persistHistory(prefs);
      notifyListeners();
    }
  }

  Map<String, dynamic> _toFirestoreMap(WorkoutSession s) => {
        'workoutId': s.workoutId,
        'workoutTitle': s.workoutTitle,
        'startedAt': Timestamp.fromDate(s.startedAt),
        'status': s.status.index,
        'exercises': s.exercises.map((e) => e.toMap()).toList(),
        if (s.finishedAt != null)
          'finishedAt': Timestamp.fromDate(s.finishedAt!),
        'totalSeries': s.totalDoneSeries,
      };

  @override
  void dispose() {
    _restTicker?.cancel();
    super.dispose();
  }
}

/// Genera un id estable de serie: combina exerciseIndex, setIndex y un nonce
/// aleatorio para evitar colisiones incluso si se agrega la misma serie dos
/// veces en el mismo segundo.
String generateSeriesId(int exerciseIndex, int setIndex) {
  final nonce = Random.secure().nextInt(0xFFFFFF).toRadixString(16);
  return '${exerciseIndex}_${setIndex}_$nonce';
}
