# Sprint 5 — Alimentación e Hidratación

## Resumen

Sprint 5 añade un sistema completo de registro de comidas e hidratación con catálogo nutricional verificado, CRUD offline-first y sincronización a Firestore.

---

## Ítems implementados

| Azure # | Descripción |
|---------|-------------|
| #255    | Recalculación proporcional de nutrientes al editar cantidad |
| #257    | Corrección del total de agua por edición o eliminación de registros |

---

## Arquitectura

### Capa de datos

```
lib/
  data/
    food_catalog.dart     — Catálogo estático con 20 alimentos (fuente USDA FDC)
  models/
    food_record.dart      — Registro de comida con snapshot nutricional
    water_record.dart     — Registro de consumo de agua (ml)
  services/
    food_service.dart     — CRUD + persistencia local + sync Firestore
    water_service.dart    — CRUD + persistencia local + sync Firestore + meta diaria
    store.dart            — Integra FoodService y WaterService al ciclo de sesión
```

### Persistencia

- **Local**: SharedPreferences, clave con prefijo UID para aislamiento entre cuentas.
- **Remota**: Firestore `users/{uid}/food_records/{id}` y `users/{uid}/water_records/{id}`, best-effort silencioso (no bloquea la UI).
- **Fuente de verdad**: la lista local. Los totales se derivan siempre de los registros vigentes, no de acumuladores independientes.

---

## Modelos

### FoodRecord

```dart
FoodRecord({
  id, uid, foodId, foodName,
  refQty, refUnit,          // referencia del catálogo (snapshot)
  kcalRef, proteinRef, carbsRef, fatRef,
  quantity, unit,           // cantidad realmente consumida
  mealType, consumedAt, createdAt, updatedAt,
})

// Getters proporcionales (#255)
double get kcal     => kcalRef    * quantity / refQty;
double get proteinG => proteinRef * quantity / refQty;
double get carbsG   => carbsRef   * quantity / refQty;
double get fatG     => fatRef     * quantity / refQty;
```

- `id` generado en cliente (UUID v4) → sin duplicados en reintentos.
- `copyWith(quantity:)` recalcula automáticamente todos los nutrientes.
- Serialización: `qty` → cantidad, `meal` → índice de `MealType`.

### WaterRecord

```dart
WaterRecord({id, uid, amountMl, recordedAt, createdAt, updatedAt})
```

- `amountMl` siempre > 0.
- El total diario es `sum(vigentes)`, no un acumulador (#257).
- Serialización: campo `ml` en Firestore.

### FoodCatalogItem

20 alimentos con nutrientes verificados en USDA FDC:
pollo pechuga, salmón, atún, huevo, leche, yogurt, queso fresco, arroz, avena, pan integral, brócoli, zanahoria, tomate, papa, plátano, manzana, palta, aceite de oliva, almendras.

Cada ítem incluye: kcal, proteína, carbs, grasa, fibra*, azúcar*, grasa saturada*, sodio*, alérgenos, fuente USDA.

---

## UI

### NutritionTab (lib/pages/nutrition_page.dart)

Tres pestañas: **Comidas**, **Agua**, **Suplementos**.

**Comidas**
- Resumen del día: kcal consumidas vs. meta, barra de progreso, chips de macros (P/C/G).
- Lista de registros con deslizamiento para eliminar y botón de edición.
- Sheet de registro: búsqueda en catálogo, selección de cantidad + momento, preview nutricional proporcional antes de guardar.
- Advertencias de alergias: `FoodCatalog.search(query, profile: profile)` filtra según el perfil del usuario.

**Agua**
- Barra de progreso en ml.
- Botones rápidos: +200, +250, +500 ml, y "Otro" para cantidad libre.
- Edición y eliminación de registros individuales.
- Meta ajustable con persistencia en SharedPreferences.

### TodayPage (lib/pages/today_page.dart)

La tarjeta de agua usa `waters.totalMlForDay(today)` y `waterGoalMl` en lugar del conteo de vasos previo.

---

## Reglas de Firestore

```
match /users/{uid}/food_records/{rid} {
  allow get, list: if owner(uid);
  allow delete:    if owner(uid);
  allow create:    if owner(uid) && validFoodRecord(d) && d.id == rid;
  allow update:    if owner(uid) && validFoodRecord(d) && d.id == resource.data.id
                   && d.createdAt == resource.data.createdAt;
}
match /users/{uid}/water_records/{rid} {
  // idéntica estructura
}
```

`validFoodRecord` valida: uid, cantidades positivas, rango de mealType (0-4), claves exactas.
`validWaterRecord` valida: uid, ml > 0, claves exactas.

---

## Tests

### Flutter (125 en total, +27 nuevos)

| Archivo | Tests | Cobertura |
|---------|-------|-----------|
| `test/food_record_test.dart` | 14 | Cálculo proporcional (#255), copyWith, serialización, aislamiento UID |
| `test/water_record_test.dart` | 13 | Suma diaria (#257), corrección por edición/borrado, serialización, meta |

### Firestore rules (18 en total, +6 nuevos)

| Test | Qué verifica |
|------|-------------|
| `owner creates, reads and deletes own food_records` | Acceso del propietario y denegación a otros |
| `food_record update` | Inmutabilidad de `id` y `createdAt` |
| `food_record validation` | qty ≤ 0, uid ajeno, id != path, meal fuera de rango |
| `owner creates, reads and deletes own water_records` | Idem para agua |
| `water_record update (#257)` | Corrección de ml; id inmutable |
| `water_record validation` | ml ≤ 0, uid ajeno, id != path, campo extra |

---

## Restricciones de seguridad

- Sin push, PR ni merge sin instrucción explícita posterior.
- Sin modificación de datos, reglas ni permisos de Firebase producción.
- Los tests de Firestore se ejecutan contra el emulador local (`demo-vigoriafit`, puerto 8080).
