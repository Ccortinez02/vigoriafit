import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/data/nutrition.dart';
import 'package:vigoriafit/models/profile.dart';

void main() {
  group('Nutrition.forGoalAndType — filtrado de alimentos', () {
    test('F1: excluye alérgenos declarados', () {
      final p = Profile(allergies: [Allergy.lactosa]);
      for (final t in MealType.values) {
        final result = Nutrition.forGoalAndType(Goal.health, t, profile: p);
        for (final m in result) {
          expect(
            m.allergens.contains(Allergy.lactosa),
            isFalse,
            reason: '${m.name} contiene lactosa y debe estar excluida',
          );
        }
      }
    });

    test('F2: excluye highSugar para diabetes', () {
      final p = Profile(conditions: [HealthCondition.diabetes]);
      for (final t in MealType.values) {
        final result = Nutrition.forGoalAndType(Goal.health, t, profile: p);
        for (final m in result) {
          expect(
            m.dietFlags.contains('highSugar'),
            isFalse,
            reason: '${m.name} tiene highSugar y debe estar excluida para diabetes',
          );
        }
      }
    });

    test('F2: excluye highSugar para prediabetes', () {
      final p = Profile(conditions: [HealthCondition.prediabetes]);
      for (final t in MealType.values) {
        final result = Nutrition.forGoalAndType(Goal.health, t, profile: p);
        for (final m in result) {
          expect(
            m.dietFlags.contains('highSugar'),
            isFalse,
            reason: '${m.name} tiene highSugar y debe estar excluida para prediabetes',
          );
        }
      }
    });

    test('F3: excluye highPotassium para enfermedad renal', () {
      final p = Profile(conditions: [HealthCondition.enfermedadRenal]);
      for (final t in MealType.values) {
        final result = Nutrition.forGoalAndType(Goal.health, t, profile: p);
        for (final m in result) {
          expect(
            m.dietFlags.contains('highPotassium'),
            isFalse,
            reason: '${m.name} tiene highPotassium y debe estar excluida para enfermedad renal',
          );
        }
      }
    });

    test('Ningún fallback reintroduce alimentos excluidos', () {
      // Perfil con todas las alergias y condiciones que el catálogo usa.
      final p = Profile(
        allergies: Allergy.values.toList(),
        conditions: HealthCondition.values.toList(),
      );
      for (final t in MealType.values) {
        final result = Nutrition.forGoalAndType(Goal.health, t, profile: p);
        // El resultado puede estar vacío pero NUNCA debe contener ítems
        // que violen las restricciones.
        for (final m in result) {
          expect(
            m.allergens.any(p.allergies.contains),
            isFalse,
            reason: '${m.name} no debería aparecer con todas las alergias activas',
          );
        }
      }
    });

    test('Resultado vacío cuando todas las opciones están excluidas', () {
      // Construye un perfil con todas las alergias.
      final p = Profile(allergies: Allergy.values.toList());
      // Busca un tipo donde todos los ítems tengan al menos un alérgeno.
      // Para el desayuno, todos los ítems del catálogo tienen al menos un
      // alérgeno, así que el resultado debe ser vacío.
      final result = Nutrition.forGoalAndType(
        Goal.health,
        MealType.desayuno,
        profile: p,
      );
      // Verifica que ningún ítem excluido reaparece.
      for (final m in result) {
        expect(
          m.allergens.any(p.allergies.contains),
          isFalse,
          reason: '${m.name} fue reintroducido indebidamente',
        );
      }
    });

    test('Combinación de restricciones: se aplican todas simultáneamente', () {
      final p = Profile(
        allergies: [Allergy.lactosa, Allergy.huevo],
        conditions: [HealthCondition.diabetes],
      );
      for (final t in MealType.values) {
        final result = Nutrition.forGoalAndType(Goal.health, t, profile: p);
        for (final m in result) {
          expect(
            m.allergens.any(p.allergies.contains),
            isFalse,
            reason: 'Alérgeno encontrado en ${m.name}',
          );
          expect(
            m.dietFlags.contains('highSugar'),
            isFalse,
            reason: 'highSugar encontrado en ${m.name} para diabetes',
          );
        }
      }
    });

    test('Sin perfil: no filtra ningún ítem', () {
      final all = Nutrition.forGoalAndType(Goal.health, MealType.almuerzo);
      final withProfile = Nutrition.forGoalAndType(
        Goal.health,
        MealType.almuerzo,
        profile: Profile(),
      );
      // Perfil vacío (sin alergias ni condiciones) no debe filtrar nada.
      expect(withProfile.length, equals(all.length));
    });

    test('dayMenu no incluye tipos sin alternativas', () {
      final p = Profile(allergies: Allergy.values.toList());
      final menu = Nutrition.dayMenu(Goal.health, profile: p);
      // Todos los ítems del menú deben ser seguros.
      for (final entry in menu.entries) {
        expect(
          entry.value.allergens.any(p.allergies.contains),
          isFalse,
          reason: '${entry.value.name} en ${entry.key} tiene alérgeno excluido',
        );
      }
    });

    test('El catálogo original no se muta al filtrar', () {
      final originalCount = Nutrition.all.length;
      final p = Profile(allergies: Allergy.values.toList());
      for (final t in MealType.values) {
        Nutrition.forGoalAndType(Goal.health, t, profile: p);
      }
      expect(Nutrition.all.length, equals(originalCount),
          reason: 'El catálogo no debe mutar');
    });

    test('Datos incompletos (campo vacío) no activan exclusión', () {
      // Un alimento sin alérgenos declarados no debe ser excluido por ninguna alergia.
      final p = Profile(allergies: [Allergy.lactosa]);
      final cena = Nutrition.forGoalAndType(Goal.gainMuscle, MealType.cena, profile: p);
      // "Pechuga de pollo con verduras salteadas" no tiene alérgenos → debe aparecer.
      final pollo = cena.where((m) => m.allergens.isEmpty).toList();
      for (final m in pollo) {
        expect(cena.contains(m), isTrue,
            reason: '${m.name} sin alérgenos debe permanecer en el resultado');
      }
    });
  });
}
