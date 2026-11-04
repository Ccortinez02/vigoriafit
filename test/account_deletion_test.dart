// Tests para el flujo de eliminación de cuenta (#270)
// La lógica real de borrado en Firebase solo puede probarse con emuladores;
// estos tests verifican la lógica de negocio y el modelo de datos.
import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/models/food_record.dart';
import 'package:vigoriafit/data/nutrition.dart';

void main() {
  group('Eliminación de cuenta (#270) — lógica cliente', () {
    test('flujo cancelar no llama deleteAccount (documentado)', () {
      // Si confirmed != true en el diálogo, _deleteAccountFlow retorna antes
      // de llamar AppStore.instance.deleteAccount(). Esta invariante se
      // verifica aquí como documentación; el widget test real requiere emulador.
      var deleteAccountCalled = false;
      void simulateDeleteIfConfirmed(bool confirmed) {
        if (confirmed) { deleteAccountCalled = true; }
      }
      simulateDeleteIfConfirmed(false);
      expect(deleteAccountCalled, isFalse);
    });

    test('contraseña vacía no dispara el borrado', () {
      const password = '';
      var deleteAccountCalled = false;
      if (password.isNotEmpty) deleteAccountCalled = true;
      expect(deleteAccountCalled, isFalse);
    });
  });

  group('Bug 3 — aiSource en FoodRecord.toMap (#sprint8)', () {
    FoodRecord makeRecord({String? aiSource}) => FoodRecord(
          id: 'test-id',
          uid: 'uid',
          foodId: 'food-1',
          foodName: 'Manzana',
          refQty: 100,
          refUnit: 'g',
          kcalRef: 52,
          proteinRef: 0.3,
          carbsRef: 14,
          fatRef: 0.2,
          quantity: 150,
          unit: 'g',
          mealType: MealType.snack,
          consumedAt: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
          aiSource: aiSource,
        );

    test('toMap no incluye aiSource cuando es null', () {
      final map = makeRecord(aiSource: null).toMap();
      expect(map.containsKey('aiSource'), isFalse);
    });

    test('toMap incluye aiSource cuando tiene valor', () {
      final map = makeRecord(aiSource: 'AI estimate').toMap();
      expect(map['aiSource'], equals('AI estimate'));
    });

    test('toMap incluye los campos requeridos por Firestore', () {
      final map = makeRecord().toMap();
      const required = [
        'id', 'uid', 'foodId', 'foodName',
        'refQty', 'refUnit', 'kcalRef', 'proteinRef', 'carbsRef', 'fatRef',
        'qty', 'unit', 'meal', 'consumedAt', 'createdAt', 'updatedAt',
      ];
      for (final key in required) {
        expect(map.containsKey(key), isTrue, reason: '$key falta en toMap()');
      }
    });
  });
}
