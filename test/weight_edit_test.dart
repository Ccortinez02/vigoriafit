import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/models/logs.dart';

// Simula la lógica interna del store para add/update/delete de WeightEntry.
List<WeightEntry> addWeight(List<WeightEntry> list, double kg, DateTime date) {
  final k = dayKey(date);
  final result = list.where((w) => dayKey(w.date) != k).toList();
  result.add(WeightEntry(date, kg));
  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
}

List<WeightEntry> updateWeight(List<WeightEntry> list, String dk, double newKg) {
  if (!newKg.isFinite || newKg <= 0 || newKg >= 500) {
    throw ArgumentError('Peso inválido: $newKg');
  }
  return list.map((w) => dayKey(w.date) == dk ? WeightEntry(w.date, newKg) : w).toList();
}

List<WeightEntry> deleteWeight(List<WeightEntry> list, String dk) {
  return list.where((w) => dayKey(w.date) != dk).toList();
}

void main() {
  final d1 = DateTime(2024, 6, 1);
  final d2 = DateTime(2024, 6, 2);

  group('addWeight', () {
    test('registra una entrada nueva', () {
      final result = addWeight([], 70.0, d1);
      expect(result.length, 1);
      expect(result.first.kg, 70.0);
    });

    test('reemplaza entrada del mismo día (sin duplicados)', () {
      var list = addWeight([], 70.0, d1);
      list = addWeight(list, 72.0, d1);
      expect(list.length, 1);
      expect(list.first.kg, 72.0);
    });

    test('permite múltiples días distintos', () {
      var list = addWeight([], 70.0, d1);
      list = addWeight(list, 71.0, d2);
      expect(list.length, 2);
    });
  });

  group('updateWeight', () {
    test('edita el kg de la entrada del día', () {
      final list = [WeightEntry(d1, 70.0), WeightEntry(d2, 71.0)];
      final updated = updateWeight(list, dayKey(d1), 68.5);
      expect(updated.firstWhere((w) => dayKey(w.date) == dayKey(d1)).kg, 68.5);
      expect(updated.firstWhere((w) => dayKey(w.date) == dayKey(d2)).kg, 71.0);
    });

    test('rechaza valor negativo', () {
      final list = [WeightEntry(d1, 70.0)];
      expect(() => updateWeight(list, dayKey(d1), -1), throwsArgumentError);
    });

    test('rechaza cero', () {
      final list = [WeightEntry(d1, 70.0)];
      expect(() => updateWeight(list, dayKey(d1), 0), throwsArgumentError);
    });

    test('rechaza 500 kg o más', () {
      final list = [WeightEntry(d1, 70.0)];
      expect(() => updateWeight(list, dayKey(d1), 500), throwsArgumentError);
    });

    test('rechaza NaN', () {
      final list = [WeightEntry(d1, 70.0)];
      expect(() => updateWeight(list, dayKey(d1), double.nan), throwsArgumentError);
    });
  });

  group('deleteWeight', () {
    test('elimina la entrada del día indicado', () {
      final list = [WeightEntry(d1, 70.0), WeightEntry(d2, 71.0)];
      final result = deleteWeight(list, dayKey(d1));
      expect(result.length, 1);
      expect(dayKey(result.first.date), dayKey(d2));
    });

    test('dayKey inexistente es no-op', () {
      final list = [WeightEntry(d1, 70.0)];
      final result = deleteWeight(list, '1990-01-01');
      expect(result.length, 1);
    });

    test('eliminar la última entrada deja lista vacía', () {
      final list = [WeightEntry(d1, 70.0)];
      final result = deleteWeight(list, dayKey(d1));
      expect(result.isEmpty, true);
    });
  });
}
