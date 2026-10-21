import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/data/nutrition.dart';
import 'package:vigoriafit/models/food_record.dart';

void main() {
  // Referencia: pollo pechuga cocida - 100 g → 165 kcal, 31 g prot, 0 g carbs, 3.57 g grasa
  FoodRecord makeRecord({
    String id = 'r1',
    String uid = 'u1',
    double refQty = 100,
    double kcalRef = 165,
    double proteinRef = 31,
    double carbsRef = 0,
    double fatRef = 3.57,
    double quantity = 150,
    MealType mealType = MealType.almuerzo,
  }) {
    final now = DateTime(2024, 6, 1, 12);
    return FoodRecord(
      id: id,
      uid: uid,
      foodId: 'pollo_pechuga_cocida',
      foodName: 'Pollo pechuga cocida',
      refQty: refQty,
      refUnit: 'g',
      kcalRef: kcalRef,
      proteinRef: proteinRef,
      carbsRef: carbsRef,
      fatRef: fatRef,
      quantity: quantity,
      unit: 'g',
      mealType: mealType,
      consumedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('Cálculo proporcional', () {
    test('kcal se escala con la cantidad (#255)', () {
      final r = makeRecord(quantity: 150);
      expect(r.kcal, closeTo(165 * 150 / 100, 0.01)); // 247.5
    });

    test('proteína se escala con la cantidad (#255)', () {
      final r = makeRecord(quantity: 200);
      expect(r.proteinG, closeTo(31 * 200 / 100, 0.01)); // 62
    });

    test('carbs se escala con la cantidad', () {
      final r = makeRecord(carbsRef: 50, quantity: 300);
      expect(r.carbsG, closeTo(50 * 300 / 100, 0.01)); // 150
    });

    test('grasa se escala con la cantidad', () {
      final r = makeRecord(quantity: 50);
      expect(r.fatG, closeTo(3.57 * 50 / 100, 0.01)); // 1.785
    });

    test('cálculo exacto para cantidad igual a refQty', () {
      final r = makeRecord(quantity: 100);
      expect(r.kcal,     closeTo(165, 0.001));
      expect(r.proteinG, closeTo(31,  0.001));
      expect(r.carbsG,   closeTo(0,   0.001));
      expect(r.fatG,     closeTo(3.57, 0.001));
    });

    test('recalcula al editar cantidad con copyWith (#255)', () {
      final original = makeRecord(quantity: 100);
      final edited   = original.copyWith(quantity: 250);
      expect(edited.kcal,     closeTo(165 * 250 / 100, 0.01));
      expect(edited.proteinG, closeTo(31  * 250 / 100, 0.01));
    });
  });

  group('copyWith', () {
    test('conserva campos no modificados', () {
      final r = makeRecord();
      final c = r.copyWith(quantity: 200);
      expect(c.id,       r.id);
      expect(c.uid,      r.uid);
      expect(c.foodId,   r.foodId);
      expect(c.kcalRef,  r.kcalRef);
      expect(c.mealType, r.mealType);
    });

    test('actualiza mealType', () {
      final r = makeRecord(mealType: MealType.desayuno);
      final c = r.copyWith(mealType: MealType.cena);
      expect(c.mealType, MealType.cena);
    });

    test('actualiza updatedAt', () {
      final r   = makeRecord();
      final now = DateTime(2025, 1, 1);
      final c   = r.copyWith(updatedAt: now);
      expect(c.updatedAt, now);
      expect(c.createdAt, r.createdAt);
    });
  });

  group('Serialización', () {
    test('toMap / fromMap es simétrico', () {
      final r = makeRecord();
      final m = r.toMap();
      final r2 = FoodRecord.fromMap(m);
      expect(r2.id,         r.id);
      expect(r2.quantity,   r.quantity);
      expect(r2.mealType,   r.mealType);
      expect(r2.kcal,       closeTo(r.kcal, 0.001));
    });

    test('toJson / fromJson es simétrico', () {
      final r  = makeRecord(quantity: 300);
      final r2 = FoodRecord.fromJson(r.toJson());
      expect(r2.quantity,   r.quantity);
      expect(r2.proteinG,   closeTo(r.proteinG, 0.001));
    });

    test('clave qty en mapa serializado', () {
      final m = makeRecord().toMap();
      expect(m.containsKey('qty'),  isTrue);
      expect(m.containsKey('meal'), isTrue);
    });
  });

  group('Aislamiento por uid', () {
    test('registros de distintos usuarios no se mezclan', () {
      final u1 = makeRecord(uid: 'user_a');
      final u2 = makeRecord(uid: 'user_b', quantity: 200);
      expect(u1.uid, isNot(u2.uid));
      expect(u1.kcal, isNot(closeTo(u2.kcal, 0.001)));
    });
  });

  group('Totales diarios derivados', () {
    test('suma de kcal de varios registros del mismo día', () {
      final records = [
        makeRecord(quantity: 100, kcalRef: 165),
        makeRecord(quantity: 50,  kcalRef: 200, carbsRef: 30),
        makeRecord(quantity: 200, kcalRef: 80,  proteinRef: 5),
      ];
      final totalKcal = records.fold<double>(0, (s, r) => s + r.kcal);
      expect(totalKcal, closeTo(165 + 100 + 160, 0.1));
    });
  });
}
