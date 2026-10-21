import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/models/exercise_log.dart';
import 'package:vigoriafit/services/progression_engine.dart';
import 'package:vigoriafit/services/unit_system.dart';

ExerciseWeightEntry e(double kg, {int? sets, int? reps}) {
  return ExerciseWeightEntry(DateTime(2024, 6, 1), kg, sets: sets, reps: reps);
}

void main() {
  group('ProgressionEngine.suggest()', () {
    test('historial vacío → insufficient', () {
      final r = ProgressionEngine.suggest([]);
      expect(r.kind, ProgressionKind.insufficient);
    });

    test('una sola entrada → insufficient', () {
      final r = ProgressionEngine.suggest([e(50)]);
      expect(r.kind, ProgressionKind.insufficient);
    });

    test('dos sesiones iguales → increase (+2.5 kg métrico)', () {
      final r = ProgressionEngine.suggest([e(50), e(50)]);
      expect(r.kind, ProgressionKind.increase);
      expect(r.suggestedKg, closeTo(52.5, 0.01));
    });

    test('dos sesiones iguales → increase (+5 lb imperial, suggestedKg en kg)', () {
      final r = ProgressionEngine.suggest([e(50), e(50)], units: UnitSystem.imperial);
      expect(r.kind, ProgressionKind.increase);
      // step = 5 lb → 5/2.20462 ≈ 2.268 kg
      expect(r.suggestedKg, closeTo(50 + 5 / 2.20462, 0.01));
    });

    test('última > anterior → maintain', () {
      final r = ProgressionEngine.suggest([e(50), e(55)]);
      expect(r.kind, ProgressionKind.maintain);
      expect(r.suggestedKg, 55);
    });

    test('última < anterior → decrease', () {
      final r = ProgressionEngine.suggest([e(55), e(50)]);
      expect(r.kind, ProgressionKind.decrease);
    });

    test('entradas con kg=0 se descartan al contar', () {
      // solo una entrada válida → insufficient
      final r = ProgressionEngine.suggest([e(0), e(0), e(50)]);
      expect(r.kind, ProgressionKind.insufficient);
    });

    test('dataUsed incluye detalle de sesión con sets y reps', () {
      final r = ProgressionEngine.suggest([e(50, sets: 3, reps: 10), e(50, sets: 3, reps: 10)]);
      expect(r.dataUsed, contains('×'));
    });

    test('resultado es consistente con el campo suggestedKg en maintain', () {
      final r = ProgressionEngine.suggest([e(40), e(45)]);
      expect(r.kind, ProgressionKind.maintain);
      expect(r.suggestedKg, 45);
    });
  });
}
