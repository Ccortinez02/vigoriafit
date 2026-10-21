import 'profile.dart';
import 'workout_session.dart';

/// Un ejercicio dentro de una rutina.
class Exercise {
  final String name;
  final String sets; // ej: "3 x 12" o "30 seg"
  final String note;
  /// Clave de la ilustración en assets/exercises/<pose>.png.
  final String pose;
  /// Condiciones/lesiones con las que conviene evitar o adaptar.
  /// Orientativo, no reemplaza a un profesional de la salud.
  final List<HealthCondition> avoidConditions;
  /// Descanso sugerido entre series, en segundos.
  final int restSeconds;
  /// Tipo de registro durante la sesión.
  final TrackingType trackingType;

  const Exercise(
    this.name,
    this.sets, [
    this.note = '',
    this.pose = 'stretch',
    this.avoidConditions = const [],
    this.restSeconds = 60,
    this.trackingType = TrackingType.reps,
  ]);
}

/// Una rutina de entrenamiento sugerida.
class Workout {
  final String id;
  final String title;
  final String focus; // ej: "Tren superior", "Full body"
  final int minutes;
  final bool needsGym;
  final Goal goal;
  /// Nivel mínimo recomendado. null = apto para todos los niveles.
  final Level? level;
  final List<Exercise> exercises;

  const Workout({
    required this.id,
    required this.title,
    required this.focus,
    required this.minutes,
    required this.needsGym,
    required this.goal,
    this.level,
    required this.exercises,
  });
}
