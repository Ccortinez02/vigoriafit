import '../models/profile.dart';

enum MealType { desayuno, almuerzo, snack, cena }

extension MealTypeX on MealType {
  String get label => switch (this) {
        MealType.desayuno => 'Desayuno',
        MealType.almuerzo => 'Almuerzo',
        MealType.snack => 'Snack',
        MealType.cena => 'Cena',
      };
  String get emoji => switch (this) {
        MealType.desayuno => '🌅',
        MealType.almuerzo => '🍽️',
        MealType.snack => '🍎',
        MealType.cena => '🌙',
      };
}

/// Una idea de comida con calorías y proteína aproximadas.
class MealIdea {
  final String name;
  final int kcal;
  final int protein; // g
  final MealType type;
  final List<Goal> goals;
  /// Clave de la foto en assets/food/<image>.jpg
  final String image;
  /// Alérgenos que contiene (para ocultarla si el usuario es alérgico).
  final List<Allergy> allergens;
  /// Notas dietéticas simples usadas para condiciones de salud
  /// (`highSugar`, `highPotassium`). Orientativo, no clínico.
  final List<String> dietFlags;

  const MealIdea(this.name, this.kcal, this.protein, this.type, this.goals,
      this.image,
      {this.allergens = const [], this.dietFlags = const []});
}

/// Ideas de comida con base chilena, orientativas.
class Nutrition {
  Nutrition._();

  static const List<MealIdea> all = [
    // Desayunos
    MealIdea('Huevos revueltos con palta y pan integral', 380, 22,
        MealType.desayuno, [Goal.gainMuscle, Goal.maintain, Goal.health],
        'eggs_avocado_toast',
        allergens: [Allergy.huevo, Allergy.gluten]),
    MealIdea('Yogurt natural con avena y fruta', 300, 18, MealType.desayuno,
        [Goal.loseFat, Goal.health, Goal.maintain], 'yogurt_oats_fruit',
        allergens: [Allergy.lactosa]),
    MealIdea('Tostadas integrales con queso fresco y tomate', 320, 16,
        MealType.desayuno, [Goal.loseFat, Goal.maintain], 'toast_cheese_tomato',
        allergens: [Allergy.gluten, Allergy.lactosa]),
    MealIdea('Batido de plátano, leche y avena', 350, 20, MealType.desayuno,
        [Goal.gainMuscle], 'banana_oat_smoothie',
        allergens: [Allergy.lactosa], dietFlags: ['highSugar']),
    // Almuerzos
    MealIdea('Pollo a la plancha con arroz y ensalada', 520, 40,
        MealType.almuerzo, [Goal.gainMuscle, Goal.maintain], 'chicken_rice_salad'),
    MealIdea('Carne magra con puré de papas y verduras', 560, 38,
        MealType.almuerzo, [Goal.gainMuscle, Goal.maintain], 'beef_mash_veggies',
        allergens: [Allergy.lactosa]),
    MealIdea('Ensalada grande con atún y huevo', 380, 32, MealType.almuerzo,
        [Goal.loseFat, Goal.health], 'tuna_egg_salad',
        allergens: [Allergy.huevo, Allergy.mariscos]),
    MealIdea('Porotos con riendas (porción moderada)', 450, 20,
        MealType.almuerzo, [Goal.maintain, Goal.health], 'beans_stew',
        dietFlags: ['highPotassium']),
    MealIdea('Salmón al horno con quinoa y brócoli', 540, 36, MealType.almuerzo,
        [Goal.health, Goal.gainMuscle], 'salmon_quinoa_broccoli'),
    // Snacks
    MealIdea('Puñado de almendras', 160, 6, MealType.snack,
        [Goal.health, Goal.maintain, Goal.gainMuscle], 'almonds',
        allergens: [Allergy.frutosSecos]),
    MealIdea('Manzana con mantequilla de maní', 200, 6, MealType.snack,
        [Goal.maintain, Goal.health], 'apple_peanut_butter',
        allergens: [Allergy.frutosSecos]),
    MealIdea('Yogurt griego con miel', 180, 15, MealType.snack,
        [Goal.gainMuscle, Goal.loseFat], 'greek_yogurt_honey',
        allergens: [Allergy.lactosa], dietFlags: ['highSugar']),
    MealIdea('Zanahoria y apio con hummus', 130, 5, MealType.snack,
        [Goal.loseFat, Goal.health], 'carrot_celery_hummus'),
    // Cenas
    MealIdea('Tortilla de verduras con ensalada', 340, 20, MealType.cena,
        [Goal.loseFat, Goal.health, Goal.maintain], 'veggie_omelette',
        allergens: [Allergy.huevo]),
    MealIdea('Pechuga de pollo con verduras salteadas', 400, 38, MealType.cena,
        [Goal.gainMuscle, Goal.loseFat], 'chicken_sauteed_veggies'),
    MealIdea('Sopa de verduras con pan integral', 300, 12, MealType.cena,
        [Goal.loseFat, Goal.health], 'veggie_soup_bread',
        allergens: [Allergy.gluten]),
  ];

  /// Devuelve ideas de comida para el objetivo y tipo indicados, filtradas
  /// por las restricciones del perfil cuando se proporciona.
  ///
  /// **Sin perfil:** devuelve todos los ítems del tipo que coinciden con el
  /// objetivo. Si no hay ninguno, amplía al tipo completo (sin objetivo).
  ///
  /// **Con perfil:** aplica [_isSafe] y devuelve solo los ítems seguros.
  /// Si ninguno pasa el filtro, devuelve lista vacía — nunca hace fallback
  /// que reintroduzca un alimento excluido.
  static List<MealIdea> forGoalAndType(Goal g, MealType t, {Profile? profile}) {
    var list = all.where((m) => m.type == t && m.goals.contains(g)).toList();
    if (list.isEmpty) list = all.where((m) => m.type == t).toList();
    if (profile != null) {
      // Retorna solo los seguros; lista vacía si todos están excluidos.
      return list.where((m) => _isSafe(m, profile)).toList();
    }
    return list;
  }

  /// Regla F1: excluye alérgenos declarados por el usuario.
  /// Regla F2: excluye 'highSugar' para diabetes y prediabetes.
  /// Regla F3: excluye 'highPotassium' para enfermedad renal.
  /// Comportamiento ante datos faltantes: si un campo de alimento no está
  /// declarado (lista vacía), no se activa ninguna exclusión.
  /// Prioridad: todas las reglas son de exclusión estricta; una coincidencia
  /// es suficiente para excluir, independientemente de otras reglas.
  /// Fuente: enums del modelo; sin validación clínica externa.
  static bool _isSafe(MealIdea m, Profile p) {
    if (m.allergens.any(p.allergies.contains)) return false;
    if (m.dietFlags.contains('highSugar') &&
        (p.conditions.contains(HealthCondition.diabetes) ||
            p.conditions.contains(HealthCondition.prediabetes))) {
      return false;
    }
    if (m.dietFlags.contains('highPotassium') &&
        p.conditions.contains(HealthCondition.enfermedadRenal)) {
      return false;
    }
    return true;
  }

  /// Un menú del día (1 idea por tipo de comida) para el objetivo, filtrado
  /// por alergias/condiciones si se entrega el perfil.
  ///
  /// Si un tipo de comida no tiene alternativas seguras, no aparece en el mapa.
  /// El llamador debe verificar si la clave existe antes de acceder.
  static Map<MealType, MealIdea> dayMenu(Goal g, {int seed = 0, Profile? profile}) {
    final menu = <MealType, MealIdea>{};
    for (final t in MealType.values) {
      final opts = forGoalAndType(g, t, profile: profile);
      if (opts.isNotEmpty) menu[t] = opts[seed % opts.length];
    }
    return menu;
  }

  static const List<String> tips = [
    'Toma agua antes de cada comida: ayuda a la saciedad. 💧',
    'Prioriza proteína en cada comida para cuidar tu músculo.',
    'Verduras a la mitad del plato: llenan y aportan fibra. 🥦',
    'El mejor "quemagrasa" es dormir bien y moverte a diario.',
    'No existe la comida prohibida: es cosa de porciones y frecuencia.',
    'Camina 8.000-10.000 pasos al día; suma más de lo que crees. 🚶',
  ];
}
