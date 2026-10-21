# Sprint 6 — Progreso, lugares cercanos y logros

## Resumen

Sprint enfocado en visibilidad del progreso del usuario (peso corporal y cargas de ejercicio), localización de lugares cercanos con fallback manual, y sistema de logros idempotente.

---

## Funcionalidades implementadas

### 1. Mediciones de peso — editar y eliminar (#198)

**`lib/services/store.dart`**

- `updateWeight(String dayKeyStr, double newKg)` — edita una medición existente por clave de día. Valida `newKg.isFinite && newKg > 0 && newKg < 500` y lanza `ArgumentError` si el valor es inválido. Actualiza `profile.weightKg` si era la última entrada.
- `deleteWeight(String dayKeyStr)` — elimina una medición por clave de día. Si quedan entradas, actualiza `profile.weightKg` a la última restante.

**`lib/pages/progress_page.dart`**

- Historial de peso con lista de las últimas 10 mediciones: fecha + valor + botones editar / eliminar.
- Editar abre un bottom sheet con `TextField` numérico (teclado decimal) pre-relleno con el valor actual.
- Eliminar pide confirmación con `AlertDialog` antes de llamar a `deleteWeight`.
- El botón "Registrar peso de hoy" también usa `TextField` numérico (sin slider).

### 2. Gráfico de evolución de cargas (#199, #200)

**`lib/pages/progress_page.dart`**

- Sección "Evolución de cargas" con selector de ejercicio por chips horizontales.
- Chips derivados de la intersección entre sesiones completadas (`.history`) y ejercicios con historial de carga en el store.
- Gráfico de línea con `fl_chart` (`LineChart`) para el ejercicio seleccionado, eje Y con valores en la unidad del usuario (kg o lb).

### 3. Sugerencia de carga progresiva (#171)

**`lib/services/progression_engine.dart`** (nuevo)

Clase estática `ProgressionEngine` con método `suggest(history, {units})` que implementa la regla de sobrecarga progresiva:

| Condición | Resultado |
|-----------|-----------|
| < 2 entradas válidas (kg > 0) | `insufficient` |
| última kg == anterior | `increase` (+2.5 kg / +5 lb) |
| última kg > anterior | `maintain` (consolida) |
| última kg < anterior | `decrease` (bajó intencionalmente) |

`suggestedKg` siempre se expresa en kg internamente. La UI convierte a lb si el usuario usa sistema imperial.

**`lib/pages/progress_page.dart`**

- Tarjeta de sugerencia sobre el gráfico de cargas: icono + titular + motivo + datos usados + aviso de que es orientativa (no prescripción clínica).

### 4. Permiso de ubicación con resultado explícito (#229, #260)

**`lib/services/places.dart`**

- Nuevo enum `LocationResult { ok, denied, deniedForever, serviceDisabled, timeout }`.
- Nuevo método `currentPositionWithReason()` → `(Position?, LocationResult)`.
  - `serviceDisabled` si el GPS está apagado.
  - `deniedForever` si el permiso está bloqueado permanente.
  - `denied` si el usuario negó en el diálogo.
  - `timeout` si el GPS no responde y no hay última posición conocida.
  - `ok` con `Position` en cualquier éxito (incluyendo fallback a `getLastKnownPosition()`).
- Se mantiene `currentPosition()` por compatibilidad retroactiva (delega internamente).

### 5. Fallback manual y UI de permiso diferenciada (#230, #231, #232)

**`lib/pages/places_page.dart`**

- Tres estados distintos para fallo de ubicación:
  - `denied` — botón "Reintentar" + "Elegir barrio manualmente".
  - `deniedForever` — botón "Abrir Ajustes" (`Geolocator.openAppSettings()`) + "Elegir barrio manualmente".
  - `serviceDisabled` — botón "Abrir ajustes GPS" (`Geolocator.openLocationSettings()`) + "Elegir barrio manualmente".
- Picker de barrio: bottom sheet con lista scrollable de 30 barrios de la Región Metropolitana (coordenadas OSM). Ninguna petición de red.
- Banner "Mostrando cerca de \<barrio\>" cuando se usa el modo manual, con opción de cambiar.
- Radio máximo: 30 km (capped en `_search` con `.clamp(1, 30)`).

### 6. Logros — condiciones e idempotencia (#201, #202, #203)

**`lib/services/store.dart`**

- `_notifiedAchievements: Set<String>` persistido en SharedPreferences (`brio_achievements_v1`).
- Se limpia al cerrar sesión (`_acceptSession`).
- `checkNewAchievements()` — devuelve solo logros recién desbloqueados (no en `_notifiedAchievements`), agrega los nuevos al set y persiste. Idempotente: llamarlo dos veces consecutivas en el mismo estado no vuelve a emitir los mismos logros.

**`lib/data/achievements.dart`** — sin cambios en Sprint 6 (catálogo ya completo desde Sprint anterior).

---

## Tests nuevos

| Archivo | Tests | Qué verifica |
|---------|-------|--------------|
| `test/weight_edit_test.dart` | 10 | add/update/delete de `WeightEntry`, deduplicación por día, validación de rango |
| `test/progression_test.dart` | 9 | Los 4 casos de `ProgressionEngine` (insufficient/increase/maintain/decrease), step imperial, descarte de kg=0, formato dataUsed |
| `test/achievements_test.dart` | 8 | Condiciones de cada logro relevante, idempotencia del filtro por `_notifiedAchievements` |

Total suite: **153 tests, todos verdes**.  
Firestore: **18 tests, todos verdes** (sin regresiones de sprints anteriores).

---

## Sin cambios

- No se modificaron reglas de Firestore (Sprint 6 no introduce colecciones nuevas en el backend).
- No se cambiaron permisos IAM ni datos de producción.
- No se hizo push, PR ni merge.
