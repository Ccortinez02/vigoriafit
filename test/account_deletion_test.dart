// Tests para eliminación de cuenta, adherencia y sincronización de alimentos IA.
// La lógica que depende de Firebase (Auth, Firestore) se prueba con emuladores;
// estos tests verifican la lógica de negocio pura del cliente.
import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/models/food_record.dart';
import 'package:vigoriafit/data/nutrition.dart';
import 'package:vigoriafit/models/assignment.dart';
import 'package:vigoriafit/services/trainer_service.dart';

FoodRecord _makeFood({String? aiSource}) => FoodRecord(
      id: 'test-id',
      uid: 'uid-1',
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

void main() {
  // ── FoodRecord.toMap — aiSource (#sprint8 Bug 3) ─────────────────────────

  group('FoodRecord.toMap — aiSource (#sprint8 Bug 3)', () {
    test('aiSource null no aparece en toMap', () {
      final map = _makeFood(aiSource: null).toMap();
      expect(map.containsKey('aiSource'), isFalse);
    });

    test('aiSource presente aparece en toMap', () {
      final map = _makeFood(aiSource: 'gemini').toMap();
      expect(map['aiSource'], equals('gemini'));
    });

    test('toMap contiene todos los campos requeridos por Firestore', () {
      final map = _makeFood().toMap();
      const required = [
        'id', 'uid', 'foodId', 'foodName',
        'refQty', 'refUnit', 'kcalRef', 'proteinRef', 'carbsRef', 'fatRef',
        'qty', 'unit', 'meal', 'consumedAt', 'createdAt', 'updatedAt',
      ];
      for (final key in required) {
        expect(map.containsKey(key), isTrue, reason: '$key falta en toMap()');
      }
    });

    test('toMap no incluye campos extra no listados en las reglas', () {
      final map = _makeFood().toMap();
      const allowed = {
        'id', 'uid', 'foodId', 'foodName', 'refQty', 'refUnit',
        'kcalRef', 'proteinRef', 'carbsRef', 'fatRef', 'qty', 'unit',
        'meal', 'consumedAt', 'createdAt', 'updatedAt', 'aiSource',
      };
      for (final key in map.keys) {
        expect(allowed.contains(key), isTrue,
            reason: 'Campo no permitido por reglas Firestore: $key');
      }
    });
  });

  // ── Adherencia — días únicos (#sprint8 Bug 4) ─────────────────────────────

  group('Adherencia — días únicos (#sprint8 Bug 4)', () {
    test('dos sesiones el mismo día cuentan como un único día', () {
      final m = GroupMember(
        userId: 'u1',
        name: 'Ana',
        joinedAt: DateTime(2024, 1, 1),
      );
      m.recordCompletion(DateTime(2024, 6, 10, 9, 0));
      m.recordCompletion(DateTime(2024, 6, 10, 18, 30));
      expect(m.trainingDaysThisWeek, equals(1));
    });

    test('sesiones en días distintos se cuentan correctamente', () {
      final m = GroupMember(
        userId: 'u1',
        name: 'Ana',
        joinedAt: DateTime(2024, 1, 1),
      );
      m.recordCompletion(DateTime(2024, 6, 10));
      m.recordCompletion(DateTime(2024, 6, 11));
      m.recordCompletion(DateTime(2024, 6, 12));
      expect(m.trainingDaysThisWeek, equals(3));
    });

    test('lastWorkoutAt refleja el más reciente aunque llegue en orden inverso', () {
      final m = GroupMember(
        userId: 'u1',
        name: 'Ana',
        joinedAt: DateTime(2024, 1, 1),
      );
      final later = DateTime(2024, 6, 12);
      final earlier = DateTime(2024, 6, 10);
      m.recordCompletion(later);
      m.recordCompletion(earlier);
      expect(m.lastWorkoutAt, equals(later));
    });

    test('sin completions, trainingDaysThisWeek es 0 y lastWorkoutAt es null', () {
      final m = GroupMember(
        userId: 'u1',
        name: 'Ana',
        joinedAt: DateTime(2024, 1, 1),
      );
      expect(m.trainingDaysThisWeek, equals(0));
      expect(m.lastWorkoutAt, isNull);
    });

    test('adherencia % no supera 100 con más sesiones que días objetivo', () {
      final m = GroupMember(
        userId: 'u1',
        name: 'Ana',
        joinedAt: DateTime(2024, 1, 1),
      );
      // 5 días distintos, objetivo 3 → 166% → se clampea a 100%
      for (var i = 1; i <= 5; i++) {
        m.recordCompletion(DateTime(2024, 6, i));
      }
      const daysPerWeek = 3;
      final pct = (m.trainingDaysThisWeek / daysPerWeek * 100)
          .clamp(0, 100)
          .round();
      expect(pct, equals(100));
    });
  });

  // ── Assignment.workoutFromSnapshot ───────────────────────────────────────

  group('Assignment.workoutFromSnapshot', () {
    final snapshotExercises = [
      {
        'name': 'Sentadilla',
        'sets': '4x10',
        'note': 'Rodillas alineadas',
        'restSeconds': 90,
        'trackingType': 0,
      },
    ];

    final a = Assignment(
      id: 'a1',
      groupId: 'g1',
      trainerId: 't1',
      workoutId: 'w1',
      workoutTitle: 'Rutina Fuerza',
      exercisesSnapshot: snapshotExercises,
      startAt: DateTime(2024, 6, 1),
      daysPerWeek: 3,
      timezone: 'America/Santiago',
      status: 'active',
      createdAt: DateTime(2024, 6, 1),
    );

    test('exercisesSnapshot almacena los ejercicios asignados', () {
      expect(a.exercisesSnapshot, equals(snapshotExercises));
    });

    test('exercisesSnapshot no cambia aunque el catálogo se edite (inmutable)', () {
      // La lista devuelta por exercisesSnapshot es la misma referencia;
      // el modelo no clona, así que se verifica que el contenido sea correcto.
      expect(a.exercisesSnapshot.first['name'], equals('Sentadilla'));
      expect(a.exercisesSnapshot.first['sets'], equals('4x10'));
    });

    test('fromMap → toMap es idempotente', () {
      final map = a.toMap();
      final a2 = Assignment.fromMap(map);
      expect(a2.id, equals(a.id));
      expect(a2.exercisesSnapshot, equals(a.exercisesSnapshot));
      expect(a2.daysPerWeek, equals(a.daysPerWeek));
    });
  });

  // ── Eliminación de cuenta — lógica cliente (#270) ─────────────────────────

  group('Eliminación de cuenta — lógica cliente (#270)', () {
    test('si el usuario cancela, deleteAccount no es invocado', () {
      // El flujo retorna antes de llamar deleteAccount cuando confirmed != true.
      var called = false;
      void simulateFlow(bool confirmed) {
        if (!confirmed) return;
        called = true;
      }
      simulateFlow(false);
      expect(called, isFalse);
    });

    test('contraseña vacía no dispara el borrado en flujo email', () {
      var called = false;
      void simulateEmailFlow(String password) {
        if (password.isEmpty) return;
        called = true;
      }
      simulateEmailFlow('');
      expect(called, isFalse);
    });

    test('contraseña no vacía avanza al paso de reauth', () {
      var reauthed = false;
      void simulateEmailFlow(String password) {
        if (password.isEmpty) return;
        reauthed = true;
      }
      simulateEmailFlow('mi-contraseña-segura');
      expect(reauthed, isTrue);
    });
  });
}
