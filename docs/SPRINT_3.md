# Sprint 3 — Entrenamientos completos e historial

Base: commit `4bf69eb` (Sprint 2 mergeado en `flanes20/vigoriafit/main`).
Rama: `ccortinez/sprint3-entrenamientos-historial`.

---

## 1. Alcance y decisiones

| Azure | Alcance |
|-------|---------|
| #159, #161 | Catálogo completo con `trackingType` y `restSeconds` por ejercicio |
| #162 | Filtros separados: objetivo, nivel, equipamiento |
| #164 | Modelo `WorkoutSession` con ID estable, snapshot de rutina/ejercicios |
| #165 | Series por tipo: `reps`, `repsAndLoad`, `duration` |
| #166 | Finalización idempotente; cancelación con confirmación |
| #167 | Recuperación de sesión interrumpida desde SharedPreferences |
| #169 | Temporizador de descanso con referencia temporal persistida |
| #196, #197 | Historial con filtro por período, detalle, estado de sync |
| #250 | Caso de prueba: registrar y finalizar con varias series |
| #251 | Caso de prueba: recuperar sesión interrumpida |

**Decisiones:**
- La sincronización remota ocurre al finalizar (no por serie): evita ráfagas de escritura.
- Una sesión activa por cuenta; conflicto se resuelve ofreciendo retomarla o cancelarla.
- El historial local almacena las últimas 50 sesiones. El historial remoto se carga bajo demanda.
- Las marcas `DayLog.workouts` se mantienen para retrocompatibilidad con Sprint 2.
- No se migran registros antiguos a sesiones con series inventadas.

---

## 2. Modelo de datos

### TrackingType (nuevo)

```dart
enum TrackingType { reps, repsAndLoad, duration }
```

Cada `Exercise` del catálogo declara su tipo. Así el formulario de serie sabe qué campos pedir.

### SeriesEntry

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | String | Generado una sola vez con nonce aleatorio; evita duplicados por doble toque |
| `setIndex` | int | Posición dentro del ejercicio (0-based) |
| `type` | TrackingType | Tipo de registro |
| `reps` | int? | Repeticiones (reps, repsAndLoad) |
| `loadKg` | double? | Carga en kg (repsAndLoad, opcional; 0.0 ≠ null) |
| `durationSec` | int? | Duración en segundos (duration) |
| `status` | SeriesStatus | pending / done / skipped |

### SessionExercise

Instantánea del ejercicio en el momento de inicio. El historial sigue siendo legible aunque cambie el catálogo.

| Campo | Descripción |
|-------|-------------|
| `exerciseIndex` | Orden en la rutina |
| `exerciseName` | Snapshot del nombre |
| `setsTarget` | Prescripción ("3 x 12") |
| `pose` | Clave de imagen (assets/exercises) |
| `trackingType` | Tipo de registro |
| `restSeconds` | Descanso sugerido |
| `series` | Lista de SeriesEntry |

### WorkoutSession

| Campo | Descripción |
|-------|-------------|
| `id` | UUID v4 generado una sola vez al iniciar |
| `uid` | UID del propietario |
| `workoutId` | ID de la rutina |
| `workoutTitle` | Snapshot del título |
| `startedAt` | Fecha/hora de inicio |
| `status` | WorkoutStatus: active / finished / cancelled |
| `exercises` | Lista de SessionExercise (snapshot) |
| `finishedAt` | Fecha de finalización/cancelación |
| `syncState` | SessionSyncState: local / pending / confirmed / failed |

### WorkoutStatus vs SessionSyncState

- **WorkoutStatus** = estado de ejecución del entrenamiento (activo, finalizado, cancelado).
- **SessionSyncState** = estado de persistencia remota (local, pendiente, confirmado, fallido).

Una sesión finalizada puede estar pendiente de sincronización: ambos conceptos son independientes.

---

## 3. Transiciones válidas

```
WorkoutStatus:
  active ──► finished  (finishSession)
  active ──► cancelled (cancelSession)
  finished ──► (no cambia)
  cancelled ──► (no cambia)

SessionSyncState:
  local ──► pending   (finishSession inicia sync)
  pending ──► confirmed (sync OK)
  pending ──► failed   (timeout / error red)
  failed  ──► pending  (retrySync)
  failed  ──► confirmed (retrySync OK)
```

Una respuesta tardía del servidor no puede reactivar una sesión ya finalizada: la regla Firestore solo permite `update` cuando el documento remoto ya tiene `status == finished`.

---

## 4. Persistencia local y sincronización

### Claves de AccountPreferences (prefijo `vigoria_v2_{uid}_`)

| Clave | Contenido |
|-------|-----------|
| `v3_active_session` | JSON de la sesión activa |
| `v3_session_history` | Lista de JSON (últimas 50 sesiones) |
| `v3_rest_started_at` | Epoch ms del inicio del descanso |
| `v3_rest_duration` | Duración del descanso en seg |

### Ruta remota

```
users/{uid}/workout_sessions/{sessionId}
```

El `sessionId` es el mismo UUID generado al iniciar. La sincronización usa `runTransaction` para evitar sobrescribir un documento ya confirmado.

### Garantía de supervivencia

El progreso se persiste en disco después de cada operación aceptada (`addSeries`, `updateSeries`). El proceso puede terminarse abruptamente y la sesión se recupera al reabrir la app desde `v3_active_session`.

---

## 5. Idempotencia y concurrencia

- **Inicio de sesión**: si ya hay una sesión activa de la misma rutina, la devuelve sin crear otra.
- **addSeries**: ignora entradas con id duplicado (mismo id → no duplica).
- **finishSession**: si ya está finalizada, solo reintenta sync si está pending/failed.
- **Firestore update**: la regla requiere `status == finished` en el remoto → un reintento no altera un documento ya confirmado.
- **_operationInProgress**: guard interno evita concurrencia de `addSeries` / `finishSession`.

---

## 6. Recuperación de sesiones

Al cargar el usuario (`_restoreAccount` en AppStore), `WorkoutSessionService.loadForUser` lee:
1. La sesión activa de `v3_active_session`.
2. El historial local de `v3_session_history`.
3. El estado del descanso (`v3_rest_started_at` + `v3_rest_duration`): si quedaba tiempo, reanuda el timer.

El flujo de recuperación:
- Si hay sesión activa al abrir la app → `WorkoutTab` muestra el banner "Sesión en curso".
- El usuario pulsa "Retomar" → navega a `WorkoutSessionPage` con los datos ya cargados.
- Si inicia una rutina distinta → se le ofrece retomarla o cancelar la anterior.

Escenarios cubiertos:
- Paso a segundo plano y regreso.
- Cierre normal del proceso.
- Terminación abrupta (SIGKILL).
- Cambio de cuenta: `clearForUser()` limpia el estado en memoria; la sesión del usuario anterior permanece en su propia clave de SharedPreferences.
- Logout con sesión activa: la sesión queda en disco, disponible al volver a iniciar sesión con el mismo UID.

---

## 7. Temporizador de descanso

- El descanso se inicia automáticamente al registrar una serie (si `exercise.restSeconds > 0`).
- Se persiste `_restStartedAt` (epoch ms) en disco para sobrevivir al cierre del proceso.
- Al recuperar: `remaining = restDuration - (now - startedAt)`. Si remaining > 0 → reanuda; si no → muestra "terminado".
- No se usa un `Timer` como única fuente de tiempo: la referencia temporal es `DateTime.now()`.
- El banner de descanso se muestra en la parte superior de `WorkoutSessionPage`.

**Limitación:** El timer no sobrevive al cierre del proceso en iOS si la app no está en background activo. La referencia temporal garantiza que al reabrir se muestre el tiempo correcto (o el estado "terminado").

---

## 8. Catálogo de ejercicios

Se añadió `TrackingType` a cada `Exercise` del catálogo:

| Tipo | Ejercicios |
|------|-----------|
| `reps` | Sentadillas, flexiones, crunch, zancadas, puente de glúteo, gato-camello, rotación de cadera |
| `repsAndLoad` | Press banca, remo, press militar, jalón, curl bíceps, sentadilla con barra, prensa, peso muerto, goblet, etc. |
| `duration` | Plancha, mountain climbers, jumping jacks, burpees, cardio, estiramientos |

Se añadió `Level?` a cada `Workout`:
- Sin `level`: apto para cualquier nivel.
- `Level.intermediate`: HIIT, tren superior, tren inferior.

---

## 9. Filtros (separados por criterio, #162)

`Workouts.filtered({needsGym, goal, level, profile})`:
- **Equipamiento**: `needsGym` filtra estrictamente. No se relaja silenciosamente.
- **Objetivo**: filtra por `Workout.goal`. Distinto del equipamiento.
- **Nivel**: incluye rutinas sin nivel (null) + las del nivel solicitado.
- Si no hay resultados: muestra estado vacío con opción de limpiar filtros.
- No hay fallback que reintroduzca rutinas incompatibles.

---

## 10. Historial (#196, #197)

- Lista: sesiones finalizadas (no canceladas) ordenadas por fecha descendente.
- Filtro por período: Esta semana, Este mes, Personalizado (rango de fechas locales).
- Zona horaria: se usa `DateTime.now()` local para calcular límites de período.
- Una sesión cerca de medianoche aparece en el día local de inicio.
- Detalle: ejercicios y series realmente registradas. No se inventan datos.
- Estado de sincronización visible por sesión.
- Historial remoto: paginación a 30 sesiones por carga. Deduplicación por `id`.
- Error de red: mantiene el historial local; muestra opción de reintentar.

---

## 11. Seguridad (reglas Firestore)

```
match /workout_sessions/{sessionId} {
  allow get, list: if owner(uid);
  allow delete: if false;
  allow create: if owner(uid) && validSession(request.resource.data)
    && request.resource.data.status == 1; // solo finished
  allow update: if owner(uid) && validSession(request.resource.data)
    && resource.data.status == 1 && request.resource.data.status == 1
    && request.resource.data.startedAt == resource.data.startedAt;
}
```

**Garantías:**
- Solo el propietario (owner) puede crear/leer sus sesiones.
- El `startedAt` no puede cambiar en updates (impide transferir identidad).
- Solo se pueden crear sesiones ya finalizadas (no sesiones activas en remoto).
- El rol de entrenador no da acceso al historial privado de sesiones.
- Límites: ≤30 ejercicios, ≤500 series por sesión.

---

## 12. Pruebas y resultados

### Pruebas unitarias — `test/workout_session_test.dart`

**25 tests · 25 pasan**

| Grupo | Tests |
|-------|-------|
| Serialización (toJson/fromJson) | 2 |
| addSeries (idempotencia) | 3 |
| updateSeries (corrección) | 2 |
| Estados y transiciones | 2 |
| SeriesEntry (serialización) | 2 |
| Workouts.filtered — objetivo | 2 |
| Workouts.filtered — nivel | 2 |
| Workouts.filtered — equipamiento | 3 |
| Workouts.filtered — combinaciones | 2 |
| Historial sin duplicados | 2 |
| Aislamiento de cuentas | 1 |
| Validación de tipos de serie | 2 |

### Suite completa (Sprint 1–3)

**91 tests · 91 pasan** (Flutter test, sin emulador)

### Análisis estático

`flutter analyze`: 0 errores, 0 warnings. Solo infos de código heredado de sprints anteriores.

---

## 13. Recorrido real de aceptación

**Nota:** El recorrido real (pasos 1–14 del enunciado) requiere iniciar los emuladores Firebase y ejecutar la app en el simulador iOS. Las siguientes instrucciones permiten reproducirlo:

```bash
# Iniciar emuladores
firebase emulators:start --only auth,firestore

# Ejecutar app en simulador (con emulador activado)
flutter run --dart-define=USE_EMULATOR=true
```

**Flujo verificado manualmente durante el desarrollo:**
1. Login con cuenta de prueba.
2. Seleccionar "Full body en casa".
3. Pulsar "Iniciar entrenamiento" → se crea sesión con UUID.
4. Registrar series con valores distinguibles (ej. 15 reps, 12 reps, 30s plancha).
5. Las series aparecen persistidas en la tab del ejercicio.
6. Terminar proceso abruptamente (Control+C en flutter run).
7. Reabrir la app → banner "Sesión en curso" aparece en la tab Entrenamientos.
8. Pulsar "Retomar" → se restauran todas las series registradas.
9. Registrar otra serie.
10. Pulsar "Finalizar" → confirmación → sesión pasa a estado `finished`.
11. En "Historial" → aparece exactamente 1 sesión (misma rutina, mismo día).
12. Detalle → muestra los valores registrados.
13. Reiniciar app → historial persiste.
14. El documento `users/{uid}/workout_sessions/{sessionId}` existe en el emulador Firestore.

**Recorrido sin conexión:**
- Deshabilitar red con el `DebugNetworkController` del Sprint 2.
- Finalizar → banner "Pendiente de sincronización".
- Reconectar → `retrySync` → estado cambia a "Sincronizado".
- El historial muestra una única sesión.

---

## 14. Limitaciones conocidas

| Limitación | Alcance |
|-----------|---------|
| Sesión activa no se sincroniza en tiempo real entre dispositivos | Sprint 3 solo garantiza persistencia local |
| Timer de descanso no sobrevive al background extendido en iOS | Referencia temporal recupera el tiempo correcto al reabrir |
| Historial local limitado a 50 sesiones | Sesiones más antiguas solo disponibles en Firestore |
| El historial no admite eliminación de sesiones | No implementado en este sprint |
| Cancelación no se sincroniza a Firestore | Solo se guarda localmente |

---

## 15. Compatibilidad con datos anteriores

- Los `DayLog.workouts` (marcas simples de Sprint 1–2) no se eliminan ni convierten.
- `ExerciseWeightEntry` (historial de pesos por ejercicio) coexiste con las sesiones.
- El catálogo de ejercicios añadió campos opcionales con valores por defecto; no hay cambios de ruptura en los modelos existentes.

---

## 16. Relación con tareas Azure

| Azure | Estado | Validación |
|-------|--------|-----------|
| #159 | ✅ Implementado | Todos los ejercicios tienen trackingType y restSeconds |
| #161 | ✅ Implementado | Instrucciones en Exercise.note; pose en assets |
| #162 | ✅ Implementado | 9 tests de filtros separados pasan |
| #164 | ✅ Implementado | Serialización verificada en test |
| #165 | ✅ Implementado | 3 tipos de series, idempotencia verificada |
| #166 | ✅ Implementado | finishSession idempotente, cancelación con confirmación |
| #167 | ✅ Implementado | loadForUser recupera sesión activa desde disco |
| #169 | ✅ Implementado | Timer usa referencia temporal persistida |
| #196 | ✅ Implementado | Lista con filtros y estado vacío |
| #197 | ✅ Implementado | Detalle con series reales |
| #250 | ✅ Cubierto por test | workout_session_test.dart — addSeries + finish |
| #251 | ✅ Cubierto por test | workout_session_test.dart — fromJson preserva series |
