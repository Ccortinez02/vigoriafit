import 'dart:convert';

/// Tipo de registro de un ejercicio durante la sesión.
enum TrackingType {
  /// Solo repeticiones (e.g. crunch, jumping jacks).
  reps,

  /// Repeticiones + carga opcional (e.g. press banca, sentadilla).
  repsAndLoad,

  /// Duración en segundos (e.g. plancha, cardio).
  duration,
}

/// Estado de una sesión de entrenamiento (flujo de ejecución).
enum WorkoutStatus { active, finished, cancelled }

/// Estado de persistencia/sincronización de una sesión.
enum SessionSyncState { local, pending, confirmed, failed }

/// Estado de una serie individual.
enum SeriesStatus { pending, done, skipped }

/// Una serie registrada durante la sesión. La identidad (id) es estable
/// y se genera una sola vez; se usa para evitar duplicados en reintento.
class SeriesEntry {
  final String id;
  final int setIndex;
  final TrackingType type;
  int? reps;
  double? loadKg;
  int? durationSec;
  SeriesStatus status;

  SeriesEntry({
    required this.id,
    required this.setIndex,
    required this.type,
    this.reps,
    this.loadKg,
    this.durationSec,
    this.status = SeriesStatus.pending,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'si': setIndex,
        'ty': type.index,
        if (reps != null) 'r': reps,
        if (loadKg != null) 'k': loadKg,
        if (durationSec != null) 'd': durationSec,
        'st': status.index,
      };

  factory SeriesEntry.fromMap(Map<String, dynamic> m) => SeriesEntry(
        id: m['id'] as String,
        setIndex: m['si'] as int,
        type: TrackingType.values[(m['ty'] as int).clamp(0, 2)],
        reps: (m['r'] as num?)?.toInt(),
        loadKg: (m['k'] as num?)?.toDouble(),
        durationSec: (m['d'] as num?)?.toInt(),
        status: SeriesStatus.values[(m['st'] as int? ?? 0).clamp(0, 2)],
      );

  SeriesEntry copyWith({
    int? reps,
    double? loadKg,
    int? durationSec,
    SeriesStatus? status,
  }) =>
      SeriesEntry(
        id: id,
        setIndex: setIndex,
        type: type,
        reps: reps ?? this.reps,
        loadKg: loadKg ?? this.loadKg,
        durationSec: durationSec ?? this.durationSec,
        status: status ?? this.status,
      );
}

/// Ejercicio dentro de una sesión activa, con instantánea de sus datos
/// para que el historial siga siendo legible aunque cambie el catálogo.
class SessionExercise {
  final int exerciseIndex;
  final String exerciseName;
  final String setsTarget;
  final String pose;
  final TrackingType trackingType;
  final int restSeconds;
  final List<SeriesEntry> series;

  SessionExercise({
    required this.exerciseIndex,
    required this.exerciseName,
    required this.setsTarget,
    required this.pose,
    required this.trackingType,
    required this.restSeconds,
    List<SeriesEntry>? series,
  }) : series = series ?? [];

  int get doneSeries => series.where((s) => s.status == SeriesStatus.done).length;

  Map<String, dynamic> toMap() => {
        'ei': exerciseIndex,
        'n': exerciseName,
        'st': setsTarget,
        'po': pose,
        'ty': trackingType.index,
        'rs': restSeconds,
        'sr': series.map((s) => s.toMap()).toList(),
      };

  factory SessionExercise.fromMap(Map<String, dynamic> m) => SessionExercise(
        exerciseIndex: m['ei'] as int,
        exerciseName: m['n'] as String,
        setsTarget: m['st'] as String,
        pose: m['po'] as String? ?? 'stretch',
        trackingType: TrackingType.values[(m['ty'] as int? ?? 0).clamp(0, 2)],
        restSeconds: m['rs'] as int? ?? 60,
        series: (m['sr'] as List<dynamic>?)
                ?.map((e) => SeriesEntry.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// Sesión completa de entrenamiento. El id es estable y se genera una sola
/// vez; no cambia durante reintentos de sincronización ni al finalizar.
class WorkoutSession {
  final String id;
  final String uid;
  final String workoutId;
  final String workoutTitle;
  final DateTime startedAt;
  WorkoutStatus status;
  final List<SessionExercise> exercises;
  DateTime? finishedAt;
  SessionSyncState syncState;

  /// ID de la asignación del entrenador, si la sesión corresponde a una.
  final String? assignmentId;

  /// ID del grupo al que pertenece la asignación.
  final String? groupId;

  WorkoutSession({
    required this.id,
    required this.uid,
    required this.workoutId,
    required this.workoutTitle,
    required this.startedAt,
    this.status = WorkoutStatus.active,
    List<SessionExercise>? exercises,
    this.finishedAt,
    this.syncState = SessionSyncState.local,
    this.assignmentId,
    this.groupId,
  }) : exercises = exercises ?? [];

  int get totalDoneSeries =>
      exercises.fold(0, (s, e) => s + e.doneSeries);

  bool get isActive => status == WorkoutStatus.active;
  bool get isFinished => status == WorkoutStatus.finished;

  /// Añade una serie al ejercicio correspondiente, ignorando duplicados por id.
  void addSeries(int exerciseIndex, SeriesEntry entry) {
    if (exerciseIndex < 0 || exerciseIndex >= exercises.length) return;
    final ex = exercises[exerciseIndex];
    if (ex.series.any((s) => s.id == entry.id)) return;
    ex.series.add(entry);
  }

  /// Reemplaza una serie existente por id. No-op si no existe.
  void updateSeries(int exerciseIndex, SeriesEntry updated) {
    if (exerciseIndex < 0 || exerciseIndex >= exercises.length) return;
    final ex = exercises[exerciseIndex];
    final i = ex.series.indexWhere((s) => s.id == updated.id);
    if (i >= 0) ex.series[i] = updated;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'wid': workoutId,
        'wt': workoutTitle,
        'sa': startedAt.toIso8601String(),
        'st': status.index,
        'ex': exercises.map((e) => e.toMap()).toList(),
        if (finishedAt != null) 'fa': finishedAt!.toIso8601String(),
        'ss': syncState.index,
        if (assignmentId != null) 'aid': assignmentId,
        if (groupId != null) 'gid': groupId,
      };

  factory WorkoutSession.fromMap(Map<String, dynamic> m) => WorkoutSession(
        id: m['id'] as String,
        uid: m['uid'] as String,
        workoutId: m['wid'] as String,
        workoutTitle: m['wt'] as String,
        startedAt: DateTime.parse(m['sa'] as String),
        status: WorkoutStatus.values[(m['st'] as int? ?? 0).clamp(0, 2)],
        exercises: (m['ex'] as List<dynamic>?)
                ?.map((e) => SessionExercise.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [],
        finishedAt:
            m['fa'] != null ? DateTime.parse(m['fa'] as String) : null,
        syncState:
            SessionSyncState.values[(m['ss'] as int? ?? 0).clamp(0, 3)],
        assignmentId: m['aid'] as String?,
        groupId: m['gid'] as String?,
      );

  String toJson() => jsonEncode(toMap());

  factory WorkoutSession.fromJson(String s) =>
      WorkoutSession.fromMap(jsonDecode(s) as Map<String, dynamic>);
}
