import '../data/nutrition.dart';
import '../data/supplements.dart';
import '../data/workouts.dart';
import '../models/profile.dart';
import '../models/week_plan.dart';
import 'store.dart';

/// Coach de vida saludable de VigoriaFit.
///
/// Proporciona respuestas por reglas (offline) como fallback cuando Firebase AI
/// Logic no está disponible. Para IA real usa [CoachService] con [GeminiAdapter].
class Coach {
  Coach._();

  /// Respuesta local por reglas. Siempre disponible sin red ni configuración.
  static String answer(String question) {
    final s = AppStore.instance;
    final p = s.profile;
    final q = _norm(question);

    if (q.isEmpty) return _help();

    if (_any(q, ['hola', 'ola', 'holi', 'buenas', 'buenos dias', 'hey'])) {
      return '¡Hola! 👋 ${_help()}';
    }
    if (_any(q, ['gracias', 'grax', 'thanks'])) {
      return '¡De nada! 💪 Tú puedes, sigue así.';
    }
    if (_any(q, ['como estas', 'que tal', 'que haces', 'todo bien'])) {
      return '¡Con toda la energía! 😄 ¿En qué te ayudo con tu ${p.goal.label.toLowerCase()}?';
    }

    // Proteína
    if (_any(q, ['proteina', 'proteinas'])) {
      return 'Para tu objetivo (${p.goal.label.toLowerCase()}) te sugiero unos '
          '${p.proteinGrams} g de proteína al día. Reparte en tus comidas: '
          'huevos, pollo, atún, legumbres o un batido. 💪';
    }
    // Calorías
    if (_any(q, ['caloria', 'calorias', 'kcal', 'cuanto comer'])) {
      return 'Tu estimación es ~${p.dailyKcal} kcal al día para '
          '${p.goal.label.toLowerCase()}. Es orientativa; ajústala según cómo '
          'te sientas y tu progreso.';
    }
    // Agua
    if (_any(q, ['agua', 'hidrat', 'tomar agua'])) {
      return 'Apunta a ${p.waterGoal} vasos de agua al día. ¡Un vaso antes de cada comida y listo! 💧';
    }
    // Qué comer
    if (_any(q, ['que como', 'que comer', 'comida', 'almuerzo', 'desayuno',
        'cena', 'menu', 'dieta'])) {
      final menu = Nutrition.dayMenu(p.goal);
      final lines = menu.entries
          .map((e) => '${e.key.emoji} ${e.key.label}: ${e.value.name}')
          .join('\n');
      return 'Un menú simple para hoy (${p.goal.label.toLowerCase()}):\n$lines';
    }
    // Suplementos
    if (_any(q, ['suplemento', 'suplementos', 'creatina', 'proteina en polvo',
        'whey', 'que tomar'])) {
      final sup = Supplements.forGoal(p.goal).take(3);
      final lines = sup.map((x) => '${x.emoji} ${x.name}: ${x.benefit}').join('\n');
      return 'Para tu objetivo, lo más útil suele ser:\n$lines\n\n'
          'Recuerda: primero la comida real, los suplementos solo complementan.';
    }
    // Rutina / ejercicio
    if (_any(q, ['rutina', 'entren', 'ejercicio', 'que hago hoy', 'workout'])) {
      final w = Workouts.todayFor(p);
      return 'Hoy te recomiendo: "${w.title}" (${w.minutes} min, ${w.focus}). '
          'Ábrela en la pestaña Entreno y ve marcando. ¡A darle! 🔥';
    }
    // Bajar de peso / grasa
    if (_any(q, ['bajar de peso', 'bajar peso', 'adelgazar', 'quemar grasa',
        'perder grasa'])) {
      return 'Para bajar grasa: leve déficit (~${p.dailyKcal} kcal), harta '
          'proteína (${p.proteinGrams} g), fuerza + algo de cardio, y dormir '
          'bien. Sin apuros: 0,5 kg por semana es un ritmo sano. 🔥';
    }
    // Subir masa
    if (_any(q, ['subir masa', 'ganar musculo', 'masa muscular', 'aumentar musculo'])) {
      return 'Para ganar músculo: come un poco por sobre tu gasto (~${p.dailyKcal} '
          'kcal), ${p.proteinGrams} g de proteína, entrena fuerza 3-4 veces y '
          'sube la carga de a poco. La constancia es la clave. 💪';
    }
    // Motivación
    if (_any(q, ['no tengo ganas', 'flojera', 'desmotiv', 'me cuesta', 'paja'])) {
      return 'Te entiendo. Parte chico: 10 minutos hoy ya es ganar. Llevas '
          '${s.streak} días de racha, no la cortes. Tu yo de mañana te lo va a '
          'agradecer. 🙌';
    }

    return 'Buena pregunta 🤔. Te cuento cómo vas: objetivo ${p.goal.label}, '
        '${s.workoutsThisWeek} entrenos esta semana.\n\nPrueba preguntarme "¿qué como hoy?", '
        '"¿qué suplemento me sirve?", "¿cuánta proteína necesito?" o "¿qué rutina hago?".';
  }

  /// Genera un plan semanal (7 días) por reglas. Usa [CoachService] para plan con IA.
  static Future<WeekPlan> generateWeekPlan() async => _ruleWeekPlan();

  /// Plan de respaldo (sin IA): alterna enfoques usando el catálogo local.
  static WeekPlan _ruleWeekPlan() {
    final p = AppStore.instance.profile;
    const dayNames = [
      'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
    ];
    final focuses = p.hasGym
        ? ['Tren superior', 'Cardio', 'Tren inferior', 'Descanso activo',
            'Full body', 'Core', 'Descanso']
        : ['Full body', 'HIIT', 'Movilidad', 'Descanso activo', 'Full body',
            'Core', 'Descanso'];
    final days = List.generate(7, (i) {
      final rest = focuses[i].toLowerCase().contains('descanso');
      return DayPlan(
        dayNames[i],
        focuses[i],
        rest
            ? 'Camina o estira suave, tu cuerpo también necesita recuperarse.'
            : 'Sigue la rutina sugerida en la pestaña Entreno para hoy.',
        'Prioriza proteína (~${p.proteinGrams} g) y verduras en tus comidas.',
      );
    });
    return WeekPlan(DateTime.now(), days);
  }

  static String _help() =>
      'Soy tu coach 💪. Pregúntame cosas como:\n'
      '• "¿Qué como hoy?"\n'
      '• "¿Qué suplemento me sirve?"\n'
      '• "¿Cuánta proteína necesito?"\n'
      '• "¿Qué rutina hago hoy?"\n'
      '• "No tengo ganas de entrenar"';

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i')
      .replaceAll('ó', 'o').replaceAll('ú', 'u')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _any(String text, List<String> needles) =>
      needles.any((n) => text.contains(n));
}
