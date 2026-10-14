import '../models/profile.dart';
import '../models/workout.dart';
import '../models/workout_session.dart';

/// Catálogo de rutinas de VigoriaFit y selección según el perfil del usuario.
class Workouts {
  Workouts._();

  static const List<Workout> all = [
    // ── En casa (sin gym) ──────────────────────────────────────────────────
    Workout(
      id: 'home_fullbody',
      title: 'Full body en casa',
      focus: 'Cuerpo completo · sin equipo',
      minutes: 30,
      needsGym: false,
      goal: Goal.health,
      exercises: [
        Exercise('Sentadillas', '3 x 15', '', 'squat', [],
            60, TrackingType.reps),
        Exercise('Flexiones (o de rodillas)', '3 x 10', '', 'pushup', [],
            60, TrackingType.reps),
        Exercise('Plancha', '3 x 30 seg', '', 'plank', [],
            45, TrackingType.duration),
        Exercise('Zancadas', '3 x 12 c/pierna', '', 'lunge', [],
            60, TrackingType.reps),
        Exercise('Puente de glúteo', '3 x 15', '', 'glute_bridge', [],
            45, TrackingType.reps),
        Exercise('Mountain climbers', '3 x 30 seg', '',
            'mountain_climber', [HealthCondition.lesionRodilla],
            45, TrackingType.duration),
      ],
    ),
    Workout(
      id: 'home_hiit',
      title: 'HIIT quema grasa',
      focus: 'Cardio intenso · sin equipo',
      minutes: 20,
      needsGym: false,
      goal: Goal.loseFat,
      level: Level.intermediate,
      exercises: [
        Exercise('Jumping jacks', '40 seg',
            'Descansa 20 seg entre cada uno', 'jumping_jack',
            [HealthCondition.lesionRodilla], 20, TrackingType.duration),
        Exercise('Burpees', '40 seg', '', 'squat',
            [HealthCondition.lesionRodilla], 20, TrackingType.duration),
        Exercise('Rodillas al pecho', '40 seg', '', 'run',
            [HealthCondition.lesionRodilla], 20, TrackingType.duration),
        Exercise('Sentadilla con salto', '40 seg', '', 'squat',
            [HealthCondition.lesionRodilla], 20, TrackingType.duration),
        Exercise('Plancha con toque de hombro', '40 seg', '', 'plank', [],
            20, TrackingType.duration),
        Exercise('Repetir el circuito', '4 vueltas', '', 'run', [],
            60, TrackingType.reps),
      ],
    ),
    Workout(
      id: 'home_core',
      title: 'Core y abdomen',
      focus: 'Zona media · sin equipo',
      minutes: 15,
      needsGym: false,
      goal: Goal.maintain,
      exercises: [
        Exercise('Crunch', '3 x 20', '', 'crunch', [],
            45, TrackingType.reps),
        Exercise('Elevación de piernas', '3 x 15', '', 'crunch', [],
            45, TrackingType.reps),
        Exercise('Plancha lateral', '3 x 25 seg c/lado', '', 'plank', [],
            45, TrackingType.duration),
        Exercise('Bicicleta', '3 x 30 seg', '', 'crunch', [],
            45, TrackingType.duration),
        Exercise('Plancha', '3 x 40 seg', '', 'plank', [],
            45, TrackingType.duration),
      ],
    ),
    // ── En gimnasio ────────────────────────────────────────────────────────
    Workout(
      id: 'gym_upper',
      title: 'Tren superior',
      focus: 'Pecho, espalda y brazos · gym',
      minutes: 50,
      needsGym: true,
      goal: Goal.gainMuscle,
      level: Level.intermediate,
      exercises: [
        Exercise('Press banca', '4 x 8-10', '', 'bench_press', [],
            90, TrackingType.repsAndLoad),
        Exercise('Remo con barra', '4 x 10', '', 'row',
            [HealthCondition.lesionEspalda], 90, TrackingType.repsAndLoad),
        Exercise('Press militar', '3 x 10', '', 'shoulder_press', [],
            90, TrackingType.repsAndLoad),
        Exercise('Jalón al pecho', '3 x 12', '', 'row', [],
            75, TrackingType.repsAndLoad),
        Exercise('Curl bíceps', '3 x 12', '', 'bicep_curl', [],
            60, TrackingType.repsAndLoad),
        Exercise('Extensión tríceps polea', '3 x 12', '', 'bicep_curl', [],
            60, TrackingType.repsAndLoad),
      ],
    ),
    Workout(
      id: 'gym_lower',
      title: 'Tren inferior',
      focus: 'Piernas y glúteo · gym',
      minutes: 50,
      needsGym: true,
      goal: Goal.gainMuscle,
      level: Level.intermediate,
      exercises: [
        Exercise('Sentadilla con barra', '4 x 8-10', '', 'squat', [],
            120, TrackingType.repsAndLoad),
        Exercise('Prensa', '4 x 12', '', 'squat', [],
            90, TrackingType.repsAndLoad),
        Exercise('Peso muerto rumano', '3 x 10', '', 'deadlift',
            [HealthCondition.lesionEspalda], 90, TrackingType.repsAndLoad),
        Exercise('Extensión de cuádriceps', '3 x 15', '', 'calf_raise', [],
            60, TrackingType.repsAndLoad),
        Exercise('Curl femoral', '3 x 15', '', 'calf_raise', [],
            60, TrackingType.repsAndLoad),
        Exercise('Elevación de gemelos', '4 x 20', '', 'calf_raise', [],
            45, TrackingType.repsAndLoad),
      ],
    ),
    Workout(
      id: 'gym_fullbody',
      title: 'Full body gym',
      focus: 'Cuerpo completo · gym',
      minutes: 45,
      needsGym: true,
      goal: Goal.health,
      exercises: [
        Exercise('Sentadilla', '3 x 10', '', 'squat', [],
            90, TrackingType.repsAndLoad),
        Exercise('Press banca', '3 x 10', '', 'bench_press', [],
            90, TrackingType.repsAndLoad),
        Exercise('Remo máquina', '3 x 12', '', 'row', [],
            75, TrackingType.repsAndLoad),
        Exercise('Press hombro mancuernas', '3 x 12', '', 'shoulder_press',
            [], 75, TrackingType.repsAndLoad),
        Exercise('Plancha', '3 x 40 seg', '', 'plank', [],
            45, TrackingType.duration),
        Exercise('Cardio (cinta/elíptica)', '10 min', '', 'run', [],
            0, TrackingType.duration),
      ],
    ),
    Workout(
      id: 'gym_cardio',
      title: 'Cardio + tonificación',
      focus: 'Quema grasa · gym',
      minutes: 40,
      needsGym: true,
      goal: Goal.loseFat,
      exercises: [
        Exercise('Cinta o elíptica', '15 min', 'Ritmo moderado-alto', 'run',
            [], 60, TrackingType.duration),
        Exercise('Sentadilla goblet', '3 x 15', '', 'squat', [],
            60, TrackingType.repsAndLoad),
        Exercise('Remo máquina', '3 x 15', '', 'row', [],
            60, TrackingType.repsAndLoad),
        Exercise('Press hombro', '3 x 12', '', 'shoulder_press', [],
            60, TrackingType.repsAndLoad),
        Exercise('Abdominales en máquina', '3 x 20', '', 'crunch', [],
            45, TrackingType.repsAndLoad),
      ],
    ),
    Workout(
      id: 'home_mobility',
      title: 'Movilidad y estiramiento',
      focus: 'Recuperación · sin equipo',
      minutes: 15,
      needsGym: false,
      goal: Goal.health,
      exercises: [
        Exercise('Estiramiento de cuello y hombros', '2 min', '', 'stretch',
            [], 30, TrackingType.duration),
        Exercise('Gato-camello', '10 reps', '', 'cat_cow', [],
            30, TrackingType.reps),
        Exercise('Estiramiento de isquiotibiales', '30 seg c/lado', '',
            'stretch', [], 20, TrackingType.duration),
        Exercise('Rotación de cadera', '10 c/lado', '', 'cat_cow', [],
            30, TrackingType.reps),
        Exercise('Respiración profunda', '2 min', '', 'breathing', [],
            0, TrackingType.duration),
      ],
    ),
  ];

  static Workout byId(String id) =>
      all.firstWhere((w) => w.id == id, orElse: () => all.first);

  /// Rutinas recomendadas para el perfil: filtra por lugar (gym/casa) y ordena
  /// poniendo primero las que calzan con el objetivo del usuario.
  static List<Workout> forProfile(Profile p) {
    final pool = all.where((w) => p.hasGym || !w.needsGym).toList();
    pool.sort((a, b) {
      final aw = a.goal == p.goal ? 0 : 1;
      final bw = b.goal == p.goal ? 0 : 1;
      return aw.compareTo(bw);
    });
    return pool;
  }

  /// Filtra por criterios separados: objetivo, nivel y equipamiento.
  /// Cada criterio es independiente. Si no hay resultados, devuelve lista vacía
  /// (no relaja filtros silenciosamente).
  static List<Workout> filtered({
    bool? needsGym,
    Goal? goal,
    Level? level,
    Profile? profile,
  }) {
    var pool = all.toList();

    // Equipamiento
    if (needsGym != null) {
      pool = pool.where((w) => w.needsGym == needsGym).toList();
    } else if (profile != null) {
      pool = pool.where((w) => profile.hasGym || !w.needsGym).toList();
    }

    // Objetivo
    if (goal != null) {
      pool = pool.where((w) => w.goal == goal).toList();
    }

    // Nivel: incluye rutinas sin nivel especificado y las del nivel solicitado
    if (level != null) {
      pool = pool.where((w) => w.level == null || w.level == level).toList();
    }

    // Filtro de salud: excluye ejercicios que el perfil debería evitar
    // (la lista de rutinas no se altera; la UI ya los marca con advertencia)

    // Ordenar: primero las que calzan con el objetivo del perfil
    if (profile != null) {
      pool.sort((a, b) {
        final ag = a.goal == profile.goal ? 0 : 1;
        final bg = b.goal == profile.goal ? 0 : 1;
        return ag.compareTo(bg);
      });
    }
    return pool;
  }

  /// Rutina "de hoy": la primera recomendada para el perfil.
  static Workout todayFor(Profile p) => forProfile(p).first;
}
