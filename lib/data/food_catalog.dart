import '../models/profile.dart';

/// Un alimento del catálogo con información nutricional verificable.
///
/// Convenciones:
/// - Los nutrientes corresponden a [refQty] en [refUnit] y la [preparation] indicada.
/// - null significa dato desconocido, NO dato cero.
/// - 0.0 significa dato conocido y efectivamente cero.
/// - Las calorías provienen de la fuente; no se recalculan desde macros.
class FoodCatalogItem {
  final String id;
  final String name;
  final String? brand;
  final String preparation;
  final double refQty;
  final String refUnit;
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final List<Allergy> allergens;
  final String source;
  final double? fiberG;
  final double? sugarG;
  final double? saturatedFatG;
  final double? sodiumMg;

  const FoodCatalogItem({
    required this.id,
    required this.name,
    this.brand,
    required this.preparation,
    required this.refQty,
    required this.refUnit,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.allergens = const [],
    required this.source,
    this.fiberG,
    this.sugarG,
    this.saturatedFatG,
    this.sodiumMg,
  });
}

/// Catálogo estático de alimentos con nutrientes verificados por 100 g o 100 ml.
///
/// Fuentes: USDA FoodData Central (FDC). Los IDs FDC son los identificadores
/// originales del sistema de la USDA. Consultados en octubre 2025.
class FoodCatalog {
  FoodCatalog._();

  static const List<FoodCatalogItem> all = [
    // ── Proteínas ─────────────────────────────────────────────────────────
    FoodCatalogItem(
      id: 'pollo_pechuga_cocida',
      name: 'Pechuga de pollo',
      preparation: 'cocida',
      refQty: 100,
      refUnit: 'g',
      kcal: 165,
      proteinG: 31.0,
      carbsG: 0.0,
      fatG: 3.6,
      fiberG: 0.0,
      sugarG: 0.0,
      saturatedFatG: 1.0,
      sodiumMg: 74,
      source: 'USDA FDC #171477',
    ),
    FoodCatalogItem(
      id: 'salmon_cocido',
      name: 'Salmón del Atlántico',
      preparation: 'cocido',
      refQty: 100,
      refUnit: 'g',
      kcal: 206,
      proteinG: 20.4,
      carbsG: 0.0,
      fatG: 13.4,
      fiberG: 0.0,
      sugarG: 0.0,
      saturatedFatG: 3.1,
      sodiumMg: 59,
      source: 'USDA FDC #175168',
    ),
    FoodCatalogItem(
      id: 'atun_agua',
      name: 'Atún en agua',
      preparation: 'enlatado, escurrido',
      refQty: 100,
      refUnit: 'g',
      kcal: 116,
      proteinG: 25.5,
      carbsG: 0.0,
      fatG: 0.8,
      fiberG: 0.0,
      sugarG: 0.0,
      saturatedFatG: 0.2,
      sodiumMg: 333,
      allergens: [Allergy.mariscos],
      source: 'USDA FDC #171986',
    ),
    FoodCatalogItem(
      id: 'huevo_cocido',
      name: 'Huevo entero',
      preparation: 'cocido',
      refQty: 100,
      refUnit: 'g',
      kcal: 155,
      proteinG: 12.6,
      carbsG: 1.1,
      fatG: 10.6,
      fiberG: 0.0,
      sugarG: 1.1,
      saturatedFatG: 3.3,
      sodiumMg: 124,
      allergens: [Allergy.huevo],
      source: 'USDA FDC #173424',
    ),

    // ── Lácteos ───────────────────────────────────────────────────────────
    FoodCatalogItem(
      id: 'leche_entera',
      name: 'Leche entera',
      preparation: 'líquida',
      refQty: 100,
      refUnit: 'ml',
      kcal: 61,
      proteinG: 3.2,
      carbsG: 4.8,
      fatG: 3.3,
      fiberG: 0.0,
      sugarG: 4.8,
      saturatedFatG: 1.9,
      sodiumMg: 44,
      allergens: [Allergy.lactosa],
      source: 'USDA FDC #171265',
    ),
    FoodCatalogItem(
      id: 'yogurt_natural',
      name: 'Yogurt natural',
      preparation: 'natural, sin azúcar',
      refQty: 100,
      refUnit: 'g',
      kcal: 59,
      proteinG: 3.5,
      carbsG: 3.6,
      fatG: 3.3,
      fiberG: 0.0,
      sugarG: 3.2,
      saturatedFatG: 2.1,
      sodiumMg: 36,
      allergens: [Allergy.lactosa],
      source: 'USDA FDC #171284',
    ),
    FoodCatalogItem(
      id: 'queso_fresco',
      name: 'Queso fresco',
      preparation: 'natural',
      refQty: 100,
      refUnit: 'g',
      kcal: 264,
      proteinG: 18.0,
      carbsG: 1.3,
      fatG: 21.0,
      fiberG: 0.0,
      sugarG: 0.5,
      saturatedFatG: 13.0,
      sodiumMg: 653,
      allergens: [Allergy.lactosa],
      source: 'USDA FDC #173429',
    ),

    // ── Cereales / harinas ─────────────────────────────────────────────────
    FoodCatalogItem(
      id: 'arroz_cocido',
      name: 'Arroz blanco',
      preparation: 'cocido',
      refQty: 100,
      refUnit: 'g',
      kcal: 130,
      proteinG: 2.7,
      carbsG: 28.2,
      fatG: 0.3,
      fiberG: 0.4,
      sugarG: 0.0,
      saturatedFatG: 0.1,
      sodiumMg: 1,
      source: 'USDA FDC #168878',
    ),
    FoodCatalogItem(
      id: 'avena',
      name: 'Avena',
      preparation: 'cruda',
      refQty: 100,
      refUnit: 'g',
      kcal: 389,
      proteinG: 16.9,
      carbsG: 66.3,
      fatG: 6.9,
      fiberG: 10.6,
      sugarG: 0.0,
      saturatedFatG: 1.2,
      sodiumMg: 2,
      allergens: [Allergy.gluten],
      source: 'USDA FDC #173904',
    ),
    FoodCatalogItem(
      id: 'pan_integral',
      name: 'Pan integral de trigo',
      preparation: 'natural',
      refQty: 100,
      refUnit: 'g',
      kcal: 247,
      proteinG: 13.0,
      carbsG: 41.3,
      fatG: 3.5,
      fiberG: 6.0,
      sugarG: 5.7,
      saturatedFatG: 0.7,
      sodiumMg: 473,
      allergens: [Allergy.gluten],
      source: 'USDA FDC #172686',
    ),

    // ── Verduras ──────────────────────────────────────────────────────────
    FoodCatalogItem(
      id: 'brocoli_cocido',
      name: 'Brócoli',
      preparation: 'cocido',
      refQty: 100,
      refUnit: 'g',
      kcal: 35,
      proteinG: 2.4,
      carbsG: 7.2,
      fatG: 0.4,
      fiberG: 3.3,
      sugarG: 1.7,
      saturatedFatG: 0.0,
      sodiumMg: 41,
      source: 'USDA FDC #170379',
    ),
    FoodCatalogItem(
      id: 'zanahoria_cruda',
      name: 'Zanahoria',
      preparation: 'cruda',
      refQty: 100,
      refUnit: 'g',
      kcal: 41,
      proteinG: 0.9,
      carbsG: 9.6,
      fatG: 0.2,
      fiberG: 2.8,
      sugarG: 4.7,
      saturatedFatG: 0.0,
      sodiumMg: 69,
      source: 'USDA FDC #170393',
    ),
    FoodCatalogItem(
      id: 'tomate',
      name: 'Tomate',
      preparation: 'crudo',
      refQty: 100,
      refUnit: 'g',
      kcal: 18,
      proteinG: 0.9,
      carbsG: 3.9,
      fatG: 0.2,
      fiberG: 1.2,
      sugarG: 2.6,
      saturatedFatG: 0.0,
      sodiumMg: 5,
      source: 'USDA FDC #170457',
    ),
    FoodCatalogItem(
      id: 'papa_cocida',
      name: 'Papa blanca',
      preparation: 'cocida',
      refQty: 100,
      refUnit: 'g',
      kcal: 87,
      proteinG: 1.9,
      carbsG: 20.1,
      fatG: 0.1,
      fiberG: 1.8,
      sugarG: 0.9,
      saturatedFatG: 0.0,
      sodiumMg: 5,
      source: 'USDA FDC #170438',
    ),

    // ── Frutas ────────────────────────────────────────────────────────────
    FoodCatalogItem(
      id: 'platano',
      name: 'Plátano',
      preparation: 'crudo',
      refQty: 100,
      refUnit: 'g',
      kcal: 89,
      proteinG: 1.1,
      carbsG: 22.8,
      fatG: 0.3,
      fiberG: 2.6,
      sugarG: 12.2,
      saturatedFatG: 0.1,
      sodiumMg: 1,
      source: 'USDA FDC #173944',
    ),
    FoodCatalogItem(
      id: 'manzana',
      name: 'Manzana',
      preparation: 'cruda, con cáscara',
      refQty: 100,
      refUnit: 'g',
      kcal: 52,
      proteinG: 0.3,
      carbsG: 13.8,
      fatG: 0.2,
      fiberG: 2.4,
      sugarG: 10.4,
      saturatedFatG: 0.0,
      sodiumMg: 1,
      source: 'USDA FDC #171688',
    ),
    FoodCatalogItem(
      id: 'palta',
      name: 'Palta / Aguacate',
      preparation: 'cruda',
      refQty: 100,
      refUnit: 'g',
      kcal: 160,
      proteinG: 2.0,
      carbsG: 8.5,
      fatG: 14.7,
      fiberG: 6.7,
      sugarG: 0.7,
      saturatedFatG: 2.1,
      sodiumMg: 7,
      source: 'USDA FDC #171706',
    ),

    // ── Grasas / semillas ─────────────────────────────────────────────────
    FoodCatalogItem(
      id: 'aceite_oliva',
      name: 'Aceite de oliva',
      preparation: 'virgen extra',
      refQty: 100,
      refUnit: 'ml',
      kcal: 884,
      proteinG: 0.0,
      carbsG: 0.0,
      fatG: 100.0,
      fiberG: 0.0,
      sugarG: 0.0,
      saturatedFatG: 13.8,
      sodiumMg: 2,
      source: 'USDA FDC #171413',
    ),
    FoodCatalogItem(
      id: 'almendras',
      name: 'Almendras',
      preparation: 'crudas',
      refQty: 100,
      refUnit: 'g',
      kcal: 579,
      proteinG: 21.2,
      carbsG: 21.6,
      fatG: 49.9,
      fiberG: 12.5,
      sugarG: 3.9,
      saturatedFatG: 3.8,
      sodiumMg: 1,
      allergens: [Allergy.frutosSecos],
      source: 'USDA FDC #170567',
    ),
  ];

  // ── Búsqueda ──────────────────────────────────────────────────────────────

  /// Normaliza texto eliminando tildes y pasando a minúsculas.
  static String _normalize(String s) {
    const from = 'áéíóúàèìòùäëïöüÁÉÍÓÚÀÈÌÒÙÄËÏÖÜ';
    const to   = 'aeiouaeiouaeiouAEIOUAEIOUAEIOU';
    var r = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      r = r.replaceAll(from[i], to[i % to.length]);
    }
    return r;
  }

  /// Busca en el catálogo por nombre (y marca si existe).
  ///
  /// Si se entrega [profile], excluye los ítems con alérgenos declarados.
  /// Nunca hace fallback que reintroduzca alimentos excluidos.
  static List<FoodCatalogItem> search(String query, {Profile? profile}) {
    final q = _normalize(query.trim());
    if (q.isEmpty) {
      if (profile == null) return List.unmodifiable(all);
      return all.where((i) => _isSafe(i, profile)).toList();
    }
    return all.where((item) {
      final match = _normalize(item.name).contains(q) ||
          (item.brand != null && _normalize(item.brand!).contains(q)) ||
          _normalize(item.preparation).contains(q);
      if (!match) return false;
      if (profile != null && !_isSafe(item, profile)) return false;
      return true;
    }).toList();
  }

  static FoodCatalogItem? byId(String id) {
    try {
      return all.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Devuelve true si el alimento es compatible con las restricciones del perfil.
  /// Regla: alérgenos declarados por el usuario excluyen el alimento.
  static bool _isSafe(FoodCatalogItem item, Profile p) {
    if (item.allergens.any(p.allergies.contains)) return false;
    return true;
  }
}
