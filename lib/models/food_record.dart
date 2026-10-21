import 'dart:convert';

import '../data/nutrition.dart';

/// Registro de un alimento realmente consumido por un usuario.
///
/// Contiene un snapshot de los datos nutricionales de referencia para que
/// el registro sea comprensible aunque cambie el catálogo.
///
/// Los nutrientes se calculan proporcionalmente:
///   nutriente = nutrienteRef × quantity / refQty
///
/// Esta fórmula solo es válida cuando [quantity] y [refQty] están en la
/// misma unidad, que se garantiza al crear el registro desde el catálogo.
class FoodRecord {
  final String id;        // UUID generado en cliente
  final String uid;       // propietario (UID de Firebase Auth)
  final String foodId;    // id del catálogo al momento del registro
  final String foodName;  // snapshot del nombre
  final double refQty;    // snapshot: cantidad de referencia
  final String refUnit;   // snapshot: unidad de referencia ('g', 'ml', etc.)
  final double kcalRef;   // snapshot: energía por refQty
  final double proteinRef;// snapshot: proteína por refQty
  final double carbsRef;  // snapshot: carbohidratos por refQty
  final double fatRef;    // snapshot: grasa por refQty
  final double quantity;  // cantidad consumida (en refUnit)
  final String unit;      // unidad de la cantidad (igual a refUnit en este sprint)
  final MealType mealType;
  final DateTime consumedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FoodRecord({
    required this.id,
    required this.uid,
    required this.foodId,
    required this.foodName,
    required this.refQty,
    required this.refUnit,
    required this.kcalRef,
    required this.proteinRef,
    required this.carbsRef,
    required this.fatRef,
    required this.quantity,
    required this.unit,
    required this.mealType,
    required this.consumedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── Nutrientes calculados ────────────────────────────────────────────────
  double get kcal     => kcalRef    * quantity / refQty;
  double get proteinG => proteinRef * quantity / refQty;
  double get carbsG   => carbsRef   * quantity / refQty;
  double get fatG     => fatRef     * quantity / refQty;

  // ── Inmutabilidad y actualización ────────────────────────────────────────
  FoodRecord copyWith({
    double?   quantity,
    MealType? mealType,
    DateTime? consumedAt,
    DateTime? updatedAt,
  }) => FoodRecord(
    id:         id,
    uid:        uid,
    foodId:     foodId,
    foodName:   foodName,
    refQty:     refQty,
    refUnit:    refUnit,
    kcalRef:    kcalRef,
    proteinRef: proteinRef,
    carbsRef:   carbsRef,
    fatRef:     fatRef,
    quantity:   quantity   ?? this.quantity,
    unit:       unit,
    mealType:   mealType   ?? this.mealType,
    consumedAt: consumedAt ?? this.consumedAt,
    createdAt:  createdAt,
    updatedAt:  updatedAt  ?? this.updatedAt,
  );

  // ── Serialización ─────────────────────────────────────────────────────────
  Map<String, dynamic> toMap() => {
    'id':         id,
    'uid':        uid,
    'foodId':     foodId,
    'foodName':   foodName,
    'refQty':     refQty,
    'refUnit':    refUnit,
    'kcalRef':    kcalRef,
    'proteinRef': proteinRef,
    'carbsRef':   carbsRef,
    'fatRef':     fatRef,
    'qty':        quantity,
    'unit':       unit,
    'meal':       mealType.index,
    'consumedAt': consumedAt.toIso8601String(),
    'createdAt':  createdAt.toIso8601String(),
    'updatedAt':  updatedAt.toIso8601String(),
  };

  factory FoodRecord.fromMap(Map<String, dynamic> m) => FoodRecord(
    id:         m['id'] as String,
    uid:        m['uid'] as String,
    foodId:     m['foodId'] as String,
    foodName:   m['foodName'] as String,
    refQty:     (m['refQty'] as num).toDouble(),
    refUnit:    m['refUnit'] as String,
    kcalRef:    (m['kcalRef'] as num).toDouble(),
    proteinRef: (m['proteinRef'] as num).toDouble(),
    carbsRef:   (m['carbsRef'] as num).toDouble(),
    fatRef:     (m['fatRef'] as num).toDouble(),
    quantity:   (m['qty'] as num).toDouble(),
    unit:       m['unit'] as String,
    mealType:   MealType.values[(m['meal'] as int).clamp(0, MealType.values.length - 1)],
    consumedAt: DateTime.parse(m['consumedAt'] as String),
    createdAt:  DateTime.parse(m['createdAt'] as String),
    updatedAt:  DateTime.parse(m['updatedAt'] as String),
  );

  String toJson() => jsonEncode(toMap());
  factory FoodRecord.fromJson(String s) => FoodRecord.fromMap(jsonDecode(s) as Map<String, dynamic>);
}
