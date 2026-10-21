import '../models/exercise_log.dart';
import 'unit_system.dart';

enum ProgressionKind { increase, maintain, decrease, insufficient }

class ProgressionSuggestion {
  final ProgressionKind kind;
  final double? suggestedKg;
  final String reason;
  final String dataUsed;

  const ProgressionSuggestion({
    required this.kind,
    this.suggestedKg,
    required this.reason,
    required this.dataUsed,
  });
}

/// Regla de progresión de cargas basada en sobrecarga progresiva estándar.
///
/// Entradas: historial cronológico de registros de ejercicio (kg, sets?, reps?).
/// Solo se consideran entradas con kg > 0.
///
/// Regla (heurística orientativa, NO prescripción clínica):
/// - < 2 sesiones con datos válidos → insufficient
/// - últimas 2 sesiones con kg idéntico → increase (+2.5 kg métrico / +5 lb imperial)
/// - última carga > penúltima → maintain (ya subiste, consolida)
/// - última carga < penúltima → decrease (bajaste intencionalmente)
class ProgressionEngine {
  ProgressionEngine._();

  static ProgressionSuggestion suggest(
    List<ExerciseWeightEntry> history, {
    UnitSystem units = UnitSystem.metric,
  }) {
    // Solo entradas con peso registrado
    final valid = history.where((e) => e.kg > 0).toList();
    if (valid.length < 2) {
      return const ProgressionSuggestion(
        kind: ProgressionKind.insufficient,
        reason: 'Historial insuficiente para hacer una sugerencia.',
        dataUsed: 'Se necesitan al menos 2 sesiones con carga registrada.',
      );
    }

    final last = valid[valid.length - 1];
    final prev = valid[valid.length - 2];
    // El step se expresa en lb o kg según la unidad del usuario,
    // pero suggestedKg se devuelve siempre en kg.
    final stepKg = units == UnitSystem.imperial ? 5.0 / 2.20462 : 2.5;

    final lastDisplay = _fmt(last.kg, units);
    final prevDisplay = _fmt(prev.kg, units);
    final unit = units == UnitSystem.imperial ? 'lb' : 'kg';

    final lastDetail = _sessionDetail(last, units);
    final prevDetail = _sessionDetail(prev, units);
    final dataUsed = 'Penúltima: $prevDetail · Última: $lastDetail';

    if (last.kg == prev.kg) {
      final next = last.kg + stepKg;
      return ProgressionSuggestion(
        kind: ProgressionKind.increase,
        suggestedKg: next,
        reason: 'Mantuviste $lastDisplay $unit dos sesiones seguidas.',
        dataUsed: dataUsed,
      );
    }

    if (last.kg > prev.kg) {
      return ProgressionSuggestion(
        kind: ProgressionKind.maintain,
        suggestedKg: last.kg,
        reason:
            'Subiste de $prevDisplay a $lastDisplay $unit. Consolida antes de subir de nuevo.',
        dataUsed: dataUsed,
      );
    }

    // last.kg < prev.kg
    return ProgressionSuggestion(
      kind: ProgressionKind.decrease,
      suggestedKg: last.kg,
      reason:
          'Bajaste de $prevDisplay a $lastDisplay $unit. Puede ser intencional.',
      dataUsed: dataUsed,
    );
  }

  static String _fmt(double kg, UnitSystem units) {
    final v = units == UnitSystem.imperial ? kg * 2.20462 : kg;
    return v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(1);
  }

  static String _sessionDetail(ExerciseWeightEntry e, UnitSystem units) {
    final unit = units == UnitSystem.imperial ? 'lb' : 'kg';
    final w = _fmt(e.kg, units);
    if (e.sets != null && e.reps != null) {
      return '$w $unit × ${e.sets}×${e.reps}';
    }
    return '$w $unit';
  }
}
