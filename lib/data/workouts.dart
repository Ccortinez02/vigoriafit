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
        Exercise('Sentadillas', '3 x 15', '', 'squat', [], 60,
            TrackingType.reps,
            'De pie, pies al ancho de hombros. Baja flexionando rodillas hasta '
            '90° o más, mantén el pecho erguido y rodillas alineadas con pies. '
            'Empuja el suelo al subir.'),
        Exercise('Flexiones (o de rodillas)', '3 x 10', '', 'pushup', [], 60,
            TrackingType.reps,
            'Manos al ancho de hombros, cuerpo en línea recta. Baja el pecho '
            'hasta casi tocar el suelo y empuja hacia arriba. Si es difícil, '
            'apoya las rodillas.'),
        Exercise('Plancha', '3 x 30 seg', '', 'plank', [], 45,
            TrackingType.duration,
            'Apoya antebrazos y puntas de pies. Mantén cuerpo rígido en línea '
            'recta de cabeza a talones. Contrae abdomen y glúteos. No dejes '
            'caer las caderas.'),
        Exercise('Zancadas', '3 x 12 c/pierna', '', 'lunge', [], 60,
            TrackingType.reps,
            'De pie, da un paso adelante y baja hasta que ambas rodillas formen '
            '90°. La rodilla trasera casi toca el suelo. Vuelve a la posición '
            'inicial y alterna piernas.'),
        Exercise('Puente de glúteo', '3 x 15', '', 'glute_bridge', [], 45,
            TrackingType.reps,
            'Acostado boca arriba, rodillas dobladas, pies apoyados. Eleva las '
            'caderas apretando glúteos hasta alinear hombros-caderas-rodillas. '
            'Baja lentamente.'),
        Exercise('Mountain climbers', '3 x 30 seg', '', 'mountain_climber',
            [HealthCondition.lesionRodilla], 45, TrackingType.duration,
            'En posición de plancha alta, alterna llevando rodillas al pecho de '
            'forma rápida y continua. Mantén caderas niveladas y core firme.'),
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
        Exercise('Jumping jacks', '40 seg', 'Descansa 20 seg entre cada uno',
            'jumping_jack', [HealthCondition.lesionRodilla], 20,
            TrackingType.duration,
            'De pie, salta abriendo piernas y brazos simultáneamente, luego '
            'vuelve a la posición inicial. Mantén un ritmo constante.'),
        Exercise('Burpees', '40 seg', '', 'pushup',
            [HealthCondition.lesionRodilla], 20, TrackingType.duration,
            'Desde de pie: agáchate, apoya manos, salta pies atrás a plancha, '
            'haz una flexión opcional, salta pies al pecho y salta arriba '
            'con brazos extendidos.'),
        Exercise('Rodillas al pecho', '40 seg', '', 'mountain_climber',
            [HealthCondition.lesionRodilla], 20, TrackingType.duration,
            'De pie, corre en el lugar levantando las rodillas hasta la altura '
            'de la cadera lo más rápido posible. Mantén el torso erguido.'),
        Exercise('Sentadilla con salto', '40 seg', '', 'squat',
            [HealthCondition.lesionRodilla], 20, TrackingType.duration,
            'Realiza una sentadilla completa y al subir explota hacia arriba en '
            'un salto. Aterriza suave con rodillas ligeramente flexionadas.'),
        Exercise('Plancha con toque de hombro', '40 seg', '', 'plank', [], 20,
            TrackingType.duration,
            'En plancha alta (brazos extendidos), toca el hombro opuesto con '
            'una mano alternando lados. Mantén caderas lo más estables posible.'),
        Exercise('Repetir el circuito', '4 vueltas', '', 'run', [], 60,
            TrackingType.reps,
            'Completa todos los ejercicios anteriores como un circuito. Descansa '
            '60-90 segundos entre cada vuelta completa.'),
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
        Exercise('Crunch', '3 x 20', '', 'crunch', [], 45, TrackingType.reps,
            'Acostado boca arriba, rodillas dobladas. Eleva los hombros del '
            'suelo contrayendo el abdomen. No jales el cuello con las manos. '
            'Baja controlado.'),
        Exercise('Elevación de piernas', '3 x 15', '', 'crunch', [], 45,
            TrackingType.reps,
            'Acostado boca arriba, manos bajo los glúteos. Eleva las piernas '
            'juntas hasta 90° y baja lentamente sin que toquen el suelo. '
            'Mantén la zona lumbar pegada al piso.'),
        Exercise('Plancha lateral', '3 x 25 seg c/lado', '', 'plank', [], 45,
            TrackingType.duration,
            'Apoya un antebrazo y el borde exterior del pie. Eleva la cadera '
            'formando una línea recta. Mantén el core activo y repite del '
            'otro lado.'),
        Exercise('Bicicleta', '3 x 30 seg', '', 'crunch', [], 45,
            TrackingType.duration,
            'Acostado, manos detrás de la cabeza. Lleva codo derecho hacia '
            'rodilla izquierda mientras extiendes la pierna derecha. Alterna '
            'de forma continua.'),
        Exercise('Plancha', '3 x 40 seg', '', 'plank', [], 45,
            TrackingType.duration,
            'Apoya antebrazos y puntas de pies. Mantén cuerpo rígido en línea '
            'recta de cabeza a talones. Contrae abdomen y glúteos. No dejes '
            'caer las caderas.'),
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
        Exercise('Press banca', '4 x 8-10', '', 'bench_press', [], 90,
            TrackingType.repsAndLoad,
            'Acostado en el banco, agarra la barra al ancho de hombros. Baja '
            'la barra controlado hasta el pecho y empuja hacia arriba. Mantén '
            'los pies firmes en el suelo.'),
        Exercise('Remo con barra', '4 x 10', '', 'row',
            [HealthCondition.lesionEspalda], 90, TrackingType.repsAndLoad,
            'Inclinado hacia adelante ~45°, agarra la barra. Lleva la barra '
            'hacia el abdomen apretando la espalda. Baja controlado. Mantén '
            'la espalda recta durante todo el movimiento.'),
        Exercise('Press militar', '3 x 10', '', 'shoulder_press', [], 90,
            TrackingType.repsAndLoad,
            'De pie o sentado, barra o mancuernas a nivel de hombros. Empuja '
            'hacia arriba hasta extender los brazos. Baja controlado hasta la '
            'altura de la barbilla.'),
        Exercise('Jalón al pecho', '3 x 12', '', 'shoulder_press', [], 75,
            TrackingType.repsAndLoad,
            'Sentado en la máquina de jalón, agarra la barra ancha. Jala hacia '
            'el pecho apretando los codos hacia abajo. Extiende los brazos '
            'lentamente al soltar.'),
        Exercise('Curl bíceps', '3 x 12', '', 'bicep_curl', [], 60,
            TrackingType.repsAndLoad,
            'De pie, mancuernas o barra con agarre supino. Flexiona los codos '
            'llevando el peso al hombro. No balancees el torso. Baja lentamente.'),
        Exercise('Extensión tríceps polea', '3 x 12', '', 'row', [], 60,
            TrackingType.repsAndLoad,
            'De pie frente a la polea alta, agarra la cuerda con ambas manos. '
            'Extiende los codos hacia abajo manteniendo los brazos pegados al '
            'cuerpo. Regresa controlado.'),
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
        Exercise('Sentadilla con barra', '4 x 8-10', '', 'squat', [], 120,
            TrackingType.repsAndLoad,
            'Barra sobre trapecios, pies al ancho de hombros. Baja con el '
            'pecho erguido hasta que muslos queden paralelos al suelo. Empuja '
            'desde los talones al subir.'),
        Exercise('Prensa', '4 x 12', '', 'squat', [], 90,
            TrackingType.repsAndLoad,
            'Sentado en la máquina, pies al ancho de hombros en la plataforma. '
            'Baja el peso flexionando rodillas a 90° y empuja hasta casi '
            'extender las piernas (sin bloquear rodillas).'),
        Exercise('Peso muerto rumano', '3 x 10', '', 'deadlift',
            [HealthCondition.lesionEspalda], 90, TrackingType.repsAndLoad,
            'De pie, barra frente a muslos. Desliza la barra por las piernas '
            'inclinando el torso hacia adelante con la espalda recta. Baja '
            'hasta sentir estiramiento en isquiotibiales, luego sube.'),
        Exercise('Extensión de cuádriceps', '3 x 15', '', 'squat', [], 60,
            TrackingType.repsAndLoad,
            'Sentado en la máquina de extensión, extiende las piernas hasta '
            'alinearlas con el torso. Mantén un segundo en la cima y baja '
            'controlado. No bloquees las rodillas.'),
        Exercise('Curl femoral', '3 x 15', '', 'deadlift', [], 60,
            TrackingType.repsAndLoad,
            'Acostado boca abajo en la máquina, flexiona las rodillas llevando '
            'los talones hacia los glúteos. Baja controlado sin rebotar.'),
        Exercise('Elevación de gemelos', '4 x 20', '', 'calf_raise', [], 45,
            TrackingType.repsAndLoad,
            'De pie en la máquina o escalón, eleva los talones lo máximo '
            'posible contrayendo los gemelos. Baja lentamente hasta sentir '
            'estiramiento completo.'),
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
        Exercise('Sentadilla', '3 x 10', '', 'squat', [], 90,
            TrackingType.repsAndLoad,
            'Barra sobre trapecios o mancuernas a los lados. Baja con pecho '
            'erguido hasta 90° de rodilla y empuja desde los talones al subir.'),
        Exercise('Press banca', '3 x 10', '', 'bench_press', [], 90,
            TrackingType.repsAndLoad,
            'Acostado en el banco, baja la barra o mancuernas controlado hasta '
            'el pecho y empuja hacia arriba. Mantén los pies firmes en el suelo.'),
        Exercise('Remo máquina', '3 x 12', '', 'row', [], 75,
            TrackingType.repsAndLoad,
            'Sentado en la máquina de remo, jala los agarres hacia el abdomen '
            'apretando los omóplatos. Extiende los brazos controlado al soltar.'),
        Exercise('Press hombro mancuernas', '3 x 12', '', 'shoulder_press',
            [], 75, TrackingType.repsAndLoad,
            'Sentado o de pie, mancuernas a nivel de hombros. Empuja hacia '
            'arriba hasta casi extender los brazos. Baja controlado.'),
        Exercise('Plancha', '3 x 40 seg', '', 'plank', [], 45,
            TrackingType.duration,
            'Apoya antebrazos y puntas de pies. Mantén cuerpo rígido en línea '
            'recta. Contrae abdomen y glúteos durante todo el tiempo.'),
        Exercise('Cardio (cinta/elíptica)', '10 min', '', 'run', [], 0,
            TrackingType.duration,
            'Realiza 10 minutos de cardio a ritmo moderado (zona 2: puedes '
            'mantener una conversación). Ideal para activar o como vuelta a la calma.'),
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
            [], 60, TrackingType.duration,
            'Mantén una intensidad moderada-alta donde puedas hablar con '
            'esfuerzo. Alterna intervalos de 2 min rápido y 1 min moderado '
            'para maximizar la quema de calorías.'),
        Exercise('Sentadilla goblet', '3 x 15', '', 'squat', [], 60,
            TrackingType.repsAndLoad,
            'Sostén una mancuerna o kettlebell con ambas manos frente al pecho. '
            'Realiza sentadilla profunda manteniendo el torso erguido y los '
            'codos entre las rodillas.'),
        Exercise('Remo máquina', '3 x 15', '', 'row', [], 60,
            TrackingType.repsAndLoad,
            'Sentado en la máquina de remo, jala los agarres hacia el abdomen '
            'apretando los omóplatos. Extiende los brazos controlado al soltar.'),
        Exercise('Press hombro', '3 x 12', '', 'shoulder_press', [], 60,
            TrackingType.repsAndLoad,
            'Sentado o de pie con mancuernas a nivel de hombros. Empuja hacia '
            'arriba hasta casi extender los brazos. Baja controlado hasta '
            'la altura de los oídos.'),
        Exercise('Abdominales en máquina', '3 x 20', '', 'crunch', [], 45,
            TrackingType.repsAndLoad,
            'Sentado en la máquina de abdominales, ajusta el peso. Flexiona '
            'el torso contrayendo el abdomen y regresa controlado a la posición '
            'inicial.'),
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
            [], 30, TrackingType.duration,
            'Inclina la cabeza hacia un lado sosteniendo con la mano opuesta. '
            'Mantén 20-30 seg. Realiza círculos lentos de hombros hacia '
            'adelante y atrás.'),
        Exercise('Gato-camello', '10 reps', '', 'cat_cow', [], 30,
            TrackingType.reps,
            'En cuatro apoyos, alterna arquear la espalda hacia el techo '
            '(gato) y hundirla hacia el suelo (camello). Sincroniza con la '
            'respiración. Mueve toda la columna.'),
        Exercise('Estiramiento de isquiotibiales', '30 seg c/lado', '',
            'stretch', [], 20, TrackingType.duration,
            'Acostado, lleva una pierna hacia el pecho con las manos detrás '
            'del muslo. O sentado, estira las piernas y alcanza los pies. '
            'Mantén la espalda recta.'),
        Exercise('Rotación de cadera', '10 c/lado', '', 'cat_cow', [], 30,
            TrackingType.reps,
            'De pie, manos en la cadera. Realiza círculos amplios con las '
            'caderas en sentido horario y luego antihorario. Mantén los pies '
            'fijos en el suelo.'),
        Exercise('Respiración profunda', '2 min', '', 'breathing', [], 0,
            TrackingType.duration,
            'Siéntate o acuéstate cómodamente. Inhala profundo por la nariz '
            '4 seg, mantén 2 seg, exhala lentamente por la boca 6 seg. '
            'Repite relajando el cuerpo progresivamente.'),
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
