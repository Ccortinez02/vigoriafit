import 'dart:convert';

import '../data/workouts.dart';
import '../models/workout.dart';
import '../models/workout_session.dart';

/// Asignación de una rutina a un grupo por parte del entrenador.
class Assignment {
  final String id;
  final String groupId;
  final String trainerId;
  final String workoutId;
  final String workoutTitle;

  /// Snapshot de los ejercicios en el momento de la asignación.
  /// Cada mapa contiene: name, sets, note, restSeconds, trackingType (index).
  final List<Map<String, dynamic>> exercisesSnapshot;

  final DateTime startAt;
  final DateTime? endAt;

  /// Días por semana recomendados (1–7).
  final int daysPerWeek;

  /// Zona horaria del grupo (ej. 'America/Santiago').
  final String timezone;

  /// 'active' | 'inactive'
  final String status;

  final DateTime createdAt;

  const Assignment({
    required this.id,
    required this.groupId,
    required this.trainerId,
    required this.workoutId,
    required this.workoutTitle,
    required this.exercisesSnapshot,
    required this.startAt,
    this.endAt,
    required this.daysPerWeek,
    required this.timezone,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'groupId': groupId,
        'trainerId': trainerId,
        'workoutId': workoutId,
        'workoutTitle': workoutTitle,
        'exercisesSnapshot': exercisesSnapshot,
        'startAt': startAt.toIso8601String(),
        if (endAt != null) 'endAt': endAt!.toIso8601String(),
        'daysPerWeek': daysPerWeek,
        'timezone': timezone,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Assignment.fromMap(Map<String, dynamic> m) => Assignment(
        id: m['id'] as String,
        groupId: m['groupId'] as String,
        trainerId: m['trainerId'] as String,
        workoutId: m['workoutId'] as String,
        workoutTitle: m['workoutTitle'] as String,
        exercisesSnapshot: (m['exercisesSnapshot'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        startAt: DateTime.parse(m['startAt'] as String),
        endAt: m['endAt'] != null ? DateTime.parse(m['endAt'] as String) : null,
        daysPerWeek: m['daysPerWeek'] as int,
        timezone: m['timezone'] as String,
        status: m['status'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
      );

  String toJson() => jsonEncode(toMap());

  factory Assignment.fromJson(String s) =>
      Assignment.fromMap(jsonDecode(s) as Map<String, dynamic>);

  /// Indica si la asignación está dentro de su ventana de vigencia temporal.
  bool isEffective([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (status != 'active') return false;
    if (startAt.isAfter(current)) return false; // Asignación futura
    if (endAt != null && endAt!.isBefore(current)) return false; // Asignación vencida
    return true;
  }

  /// Indica si la asignación está programada para iniciar en el futuro.
  bool isFuture([DateTime? now]) {
    final current = now ?? DateTime.now();
    return status == 'active' && startAt.isAfter(current);
  }

  /// Indica si la asignación ya venció según su endAt o startAt.
  bool isExpired([DateTime? now]) {
    final current = now ?? DateTime.now();
    final effectiveEnd = endAt ?? startAt;
    return effectiveEnd.isBefore(current);
  }

  /// Indica si la asignación está retrasada (pasada pero dentro del límite de 3 días acumulables).
  bool isOverdue([DateTime? now]) {
    final current = now ?? DateTime.now();
    final effectiveEnd = endAt ?? startAt;
    final minDate = DateTime(current.year, current.month, current.day).subtract(const Duration(days: 3));
    return effectiveEnd.isBefore(current) && !effectiveEnd.isBefore(minDate);
  }

  /// Indica si la asignación está dentro de la ventana permitida:
  /// - No tiene más de 3 días de retraso hacia el pasado.
  /// - No está adelantada por más de 7 días hacia el futuro.
  bool isWithinWindow([DateTime? now]) {
    final current = now ?? DateTime.now();
    final effectiveEnd = endAt ?? startAt;
    final minDate = DateTime(current.year, current.month, current.day).subtract(const Duration(days: 3));
    if (effectiveEnd.isBefore(minDate)) return false; // Retrasada por más de 3 días
    final maxDate = DateTime(current.year, current.month, current.day).add(const Duration(days: 7, hours: 23, minutes: 59, seconds: 59));
    if (startAt.isAfter(maxDate)) return false; // Más de 7 días adelantada
    return true;
  }

  /// Indica si la asignación excedió los 3 días de retraso y debe purgarse.
  bool isPurgeable([DateTime? now]) {
    final current = now ?? DateTime.now();
    final effectiveEnd = endAt ?? startAt;
    final minDate = DateTime(current.year, current.month, current.day).subtract(const Duration(days: 3));
    return effectiveEnd.isBefore(minDate);
  }

  /// Construye un snapshot de ejercicios a partir de la lista de [Exercise].
  static List<Map<String, dynamic>> exerciseSnapshotFrom(
    List<Exercise> exercises,
  ) =>
      exercises
          .map((e) => {
                'name': e.name,
                'sets': e.sets,
                'note': e.note,
                'restSeconds': e.restSeconds,
                'trackingType': e.trackingType.index,
              })
          .toList();

  /// Construye una copia del [catalogWorkout] con los ejercicios del snapshot.
  /// Usa el snapshot como fuente de verdad para sets/note/restSeconds/trackingType
  /// y el catálogo para pose e ilustración (preserva las imágenes de ejercicio).
  Workout workoutFromSnapshot(Workout catalogWorkout) {
    final allCatalogExercises = Workouts.all
        .expand((w) => w.exercises)
        .toList();
    final exercises = exercisesSnapshot.map((e) {
      final name = e['name'] as String? ?? '';
      final catalogEx = allCatalogExercises
          .where((ex) => ex.name == name)
          .firstOrNull;
      return Exercise(
        name,
        e['sets'] as String? ?? '',
        e['note'] as String? ?? '',
        catalogEx?.pose ?? 'stretch',
        catalogEx?.avoidConditions ?? const [],
        (e['restSeconds'] as num?)?.toInt() ?? 60,
        TrackingType.values[
          ((e['trackingType'] as int?) ?? 0)
              .clamp(0, TrackingType.values.length - 1)],
      );
    }).toList();

    return Workout(
      id: catalogWorkout.id,
      title: catalogWorkout.title,
      focus: catalogWorkout.focus,
      minutes: catalogWorkout.minutes,
      needsGym: catalogWorkout.needsGym,
      goal: catalogWorkout.goal,
      level: catalogWorkout.level,
      exercises: exercises,
    );
  }
}
