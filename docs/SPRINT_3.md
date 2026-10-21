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
| #196 | Historial de sesiones con filtro por período (#196) y detalle de series (#197) |
| #250 | Caso de prueba: registrar y finalizar con varias series |
| #251 | Caso de prueba: recuperar sesión interrumpida |

**Decisiones:**
- La sincronización remota ocurre al finalizar (no por serie): evita ráfagas de escritura.
- Una sesión activa por cuenta; conflicto se resuelve ofreciendo retomarla o cancelarla.
- El historial local almacena las últimas 50 sesiones **confirmadas o canceladas**. Las sesiones con sync pendiente o fallido siempre se conservan independientemente del límite.
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

---

## 4. Persistencia local y sincronización

### Claves de AccountPreferences (prefijo `vigoria_v2_{uid}_`)

| Clave | Contenido |
|-------|-----------|
| `v3_active_session` | JSON de la sesión activa |
| `v3_session_history` | Lista de JSON (historial) |
| `v3_rest_started_at` | Epoch ms del inicio del descanso |
| `v3_rest_duration` | Duración del descanso en seg |

### Ruta remota

```
users/{uid}/workout_sessions/{sessionId}
```

El `sessionId` es el mismo UUID generado al iniciar. La sincronización usa `runTransaction` con `tx.set`: si el documento ya existe (intento anterior exitoso), la transacción es un no-op. Las sesiones son inmutables en Firestore una vez escritas.

### Garantía de supervivencia

El progreso se persiste en disco después de cada operación (`addSeries`, `updateSeries`). El estado `finished` se escribe en `v3_active_session` **antes** de añadir al historial. Si el proceso termina en ese intervalo, `loadForUser` detecta que la sesión activa tiene `status != active` y la mueve al historial automáticamente al reabrir.

---

## 5. Recuperación de crash — flujo completo

`finishSession` escribe en este orden:
1. `_persistActive(prefs)` — escribe sesión con `status=finished` en `v3_active_session`
2. `_addToLocalHistory` + `_persistHistory(prefs)` — añade al historial y persiste
3. `_syncSession` — intenta Firestore
4. `prefs.remove(_kActiveSession)` — borra la sesión activa

**Crash entre 1 y 2:** `v3_active_session` tiene `status=finished` pero `v3_session_history` no tiene la sesión.
- Al reabrir: `loadForUser` carga el historial primero, luego detecta que `_active.status != active`, la añade al historial (dedup por id) y borra `v3_active_session`.
- Resultado: sesión aparece en historial con `syncState=pending`; el usuario puede reintentar sync.

**Crash entre 2 y 4:** `v3_active_session` y `v3_session_history` tienen ambos la sesión.
- Al reabrir: `_addToLocalHistory` hace `removeWhere(id)` antes de insertar → dedup.
- Resultado: una sola entrada en historial, `_active=null`.

**Crash entre 3 y 4:** idem a crash entre 2 y 4.

---

## 6. Límite de historial local

El límite de 50 entradas aplica **solo** a sesiones con `syncState ∈ {local, confirmed}` o canceladas. Las sesiones con `syncState ∈ {pending, failed}` siempre se conservan, independientemente de cuántas sesiones confirmadas existan.

Algoritmo en `_persistHistory` y `_trimHistory`:
```dart
final needsSync = _history.where(_needsSync).toList();     // siempre conservadas
final rest = _history.where(not _needsSync).take(50);      // limitadas a 50
final toSave = [...needsSync, ...rest]..sort(...);
```

---

## 7. Idempotencia y concurrencia

- **Inicio de sesión**: si ya hay una sesión activa de la misma rutina, la devuelve sin crear otra.
- **addSeries**: ignora entradas con id duplicado (mismo id → no inserta).
- **finishSession**: si `_active.status == finished` (e.g. llamada doble dentro de la misma ejecución), completa las operaciones pendientes de historial/limpieza antes de reintentar sync.
- **Firestore**: sesiones inmutables una vez creadas; `allow update: if false`. El reintento hace `tx.set` solo si el doc no existe; si existe, la transacción termina sin escribir.
- **`_operationInProgress`**: guard impide concurrencia de `addSeries`/`finishSession`/`cancelSession`.
- **`finishedAt ??=`**: el operador null-aware garantiza que el timestamp original no se sobreescribe en reintentos.

---

## 8. Temporizador de descanso

El temporizador tiene dos componentes con responsabilidades distintas:

- **`_restStartedAt` (epoch ms en disco)**: referencia temporal que permite calcular el tiempo transcurrido en cualquier momento, incluso después de reabrir la app. Esta referencia **sí sobrevive al cierre del proceso**.
- **`Timer.periodic` (`_restTicker`)**: dispara `notifyListeners()` cada segundo para actualizar la UI. **No sobrevive al cierre del proceso**: al reabrir, el ticker ya no corre.

Al recuperar:
```
remaining = restDuration - (DateTime.now() - _restStartedAt).inSeconds
```
Si `remaining > 0`: se crea un nuevo ticker con ese tiempo restante.
Si `remaining <= 0`: se muestra el estado "terminado" sin ticker.

**Limitación conocida**: entre el cierre y la reapertura de la app, la cuenta regresiva no avanza visualmente. Al reabrir, el tiempo mostrado es correcto, pero el usuario no recibe notificación al llegar a cero mientras la app está cerrada.

---

## 9. Catálogo de ejercicios

Se añadió `TrackingType` a cada `Exercise` del catálogo:

| Tipo | Ejemplos |
|------|---------|
| `reps` | Sentadillas, flexiones, crunch, zancadas, puente de glúteo |
| `repsAndLoad` | Press banca, remo, press militar, jalón, curl bíceps, sentadilla con barra |
| `duration` | Plancha, mountain climbers, jumping jacks, burpees, estiramientos |

Se añadió `Level?` a cada `Workout`:
- `null`: apto para cualquier nivel.
- `Level.intermediate`: HIIT, tren superior/inferior.

---

## 10. Filtros (#162)

`Workouts.filtered({needsGym, goal, level, profile})`: cada dimensión se aplica de forma independiente. Retorna lista vacía si no hay coincidencia — sin fallback silencioso.

---

## 11. Historial (#196, #197)

- **#196**: historial de sesiones finalizadas (no canceladas), ordenado por fecha descendente.
- **#197**: filtro por período (Esta semana, Este mes, Personalizado). Zona horaria local.
- Detalle: series realmente registradas durante la sesión (snapshot).
- Estado de sincronización visible por sesión, con opción de reintento para `failed`.
- Deduplicación por `id` al combinar historial local y remoto.

---

## 12. Seguridad — reglas Firestore

```
match /workout_sessions/{sessionId} {
  allow get, list: if owner(uid);
  allow delete: if false;
  allow create: if owner(uid) && validSession(request.resource.data)
    && request.resource.data.status == 1; // solo finished
  allow update: if false; // inmutables una vez creadas
}
```

**Garantías verificables:**
- Solo el propietario puede crear/leer sus sesiones.
- Solo se crean sesiones finalizadas (`status == 1`).
- Una vez creado, el documento no puede modificarse.
- La función `validSession` valida tipos y límites de los campos de primer nivel; los datos anidados (ejercicios, series) no son validados por las reglas — dependen de la validación en cliente. Esta es una limitación conocida de la complejidad de CEL.

**Validación de las reglas:** pendiente de ejecución con Firebase Emulator Suite (ver sección 14).

---

## 13. Pruebas ejecutadas

### Pruebas unitarias Flutter — resultados confirmados

**32 tests nuevos (Sprint 3) + 66 tests anteriores (Sprint 1–2) = 98 total · 98 pasan**

Ejecutado con: `flutter test` en rama `ccortinez/sprint3-entrenamientos-historial`, sin emulador.

| Grupo | Tests | Estado |
|-------|-------|--------|
| Crash recovery — sesión huérfana en disco | 3 | ✅ |
| Límite historial — sesiones pending conservadas | 2 | ✅ |
| Idempotencia — modelo de sesión | 2 | ✅ |
| WorkoutSession — serialización | 2 | ✅ |
| addSeries — idempotencia | 3 | ✅ |
| updateSeries | 2 | ✅ |
| Estados y transiciones | 2 | ✅ |
| SeriesEntry — serialización | 2 | ✅ |
| Workouts.filtered — objetivo | 2 | ✅ |
| Workouts.filtered — nivel | 2 | ✅ |
| Workouts.filtered — equipamiento | 3 | ✅ |
| Workouts.filtered — combinaciones | 2 | ✅ |
| Historial sin duplicados | 2 | ✅ |
| Aislamiento de cuentas | 1 | ✅ |
| Validación de tipos de serie | 2 | ✅ |

**Análisis estático:** `flutter analyze` — 0 errores, 0 warnings. Las 18 `info` son heredadas de sprints anteriores (deprecaciones de SDK, estilos de código).

### Pruebas de reglas Firestore — pendientes

Las siguientes pruebas requieren ejecutar **Firebase Emulator Suite** (`firebase emulators:start --only firestore`) y el runner de reglas (`firebase emulate:exec` o `jest` con `@firebase/rules-unit-testing`). No han sido ejecutadas en esta sesión.

Escenarios a cubrir:
- [ ] Propietario crea sesión válida con `status=1` → permitido
- [ ] Propietario intenta crear sesión con `status=0` (active) → denegado
- [ ] Propietario intenta actualizar sesión existente → denegado
- [ ] Propietario intenta borrar sesión → denegado
- [ ] Cuenta distinta intenta leer sesión ajena → denegado
- [ ] Usuario anónimo → denegado
- [ ] Token de entrenador sin ser propietario → denegado
- [ ] Escritura con campo `exercises` con más de 30 elementos → denegado
- [ ] Escritura con `totalSeries` > 500 → denegado
- [ ] Escritura omitiendo campo requerido (`workoutId`) → denegado

### Recorrido real de aceptación — pendiente

El recorrido en iOS Simulator con Firebase Emulator no ha sido ejecutado en esta sesión. Requiere:

```bash
# Terminal 1
firebase emulators:start --only auth,firestore

# Terminal 2
flutter run --dart-define=USE_EMULATOR=true
```

Pasos a verificar manualmente:
1. Login con cuenta de prueba (solo emulador).
2. Iniciar una rutina; anotar el UUID de sesión en el log de Flutter.
3. Registrar series con valores distinguibles (ej. 15 reps, 60 kg; 30 s plancha).
4. Verificar que las series aparecen en la tab del ejercicio.
5. Terminar el proceso mediante el cierre del simulador (no Control+C del runner — el cierre del simulador simula más fielmente una terminación abrupta que interrumpir el runner de Flutter).
6. Reabrir la app (re-lanzar desde Xcode o `flutter run`).
7. Verificar: el banner "Sesión en curso" aparece con el mismo UUID.
8. Navegar a la sesión; verificar que las series registradas están presentes.
9. Añadir otra serie; finalizar con confirmación.
10. En Historial: exactamente 1 entrada con ese UUID.
11. En Firestore Emulator UI (localhost:4000): exactamente 1 documento `users/{uid}/workout_sessions/{sessionId}`.
12. Repetir desde paso 2 con red deshabilitada (DebugNetworkController): verificar estado `pending` en historial, reconectar, verificar `confirmed` y documento único en Firestore.

---

## 14. Estado de Azure #250 y #251

**#250 — Completar sesión con varias series:**
- Cubierto por los tests de modelo: `addSeries` con ids distintos acumula series, `totalDoneSeries` las contabiliza correctamente.
- El flujo completo (registrar → finalizar → verificar en historial y Firestore) requiere el recorrido real (sección 13, pendiente).

**#251 — Recuperar sesión interrumpida:**
- La serialización `toJson/fromJson` preserva todas las series y el syncState (verificado en tests).
- El mecanismo de recuperación real en `loadForUser` detecta sesiones huérfanas (status != active en disco) y las mueve al historial. El algoritmo de dedup por id evita duplicados si la sesión ya estaba parcialmente en historial.
- **La verificación de que la sesión se recupera con el mismo UUID y todas las series tras un cierre real del proceso requiere el recorrido en simulador (sección 13, pendiente).** Los tests de modelo verifican el algoritmo pero no el flujo completo de iOS/SharedPreferences.

---

## 15. Limitaciones conocidas

| Limitación | Alcance |
|-----------|---------|
| Sesión activa no se sincroniza entre dispositivos | Sprint 3 garantiza solo persistencia local |
| El ticker del temporizador no corre mientras la app está cerrada | La referencia temporal permite mostrar el tiempo correcto al reabrir, pero sin notificación al llegar a cero |
| Validación de datos anidados (ejercicios, series) no cubierta por reglas Firestore | Depende de validación en cliente |
| Cancelación no se sincroniza a Firestore | Solo historial local |
| Cambio de cuenta mientras una sync está en vuelo puede causar race condition | La sesión en vuelo se completa con los datos correctos pero el historial de la cuenta nueva puede no reflejarlo hasta recargar |

---

## 16. Compatibilidad con datos anteriores

- Los `DayLog.workouts` (marcas simples de Sprint 1–2) no se eliminan ni convierten.
- `ExerciseWeightEntry` coexiste con las sesiones.
- El catálogo añadió campos con valores por defecto; no hay cambios de ruptura.

---

## 17. Relación con tareas Azure

| Azure | Estado | Evidencia |
|-------|--------|-----------|
| #159 | ✅ Implementado | Todos los ejercicios del catálogo tienen `trackingType` y `restSeconds` explícitos |
| #161 | ✅ Implementado | `Exercise.note` contiene instrucciones; `pose` apunta a assets |
| #162 | ✅ Implementado | 9 tests de filtros separados pasan; `Workouts.filtered()` no relaja restricciones |
| #164 | ✅ Implementado | Serialización `toJson/fromJson` verificada en tests; ID estable UUID v4 |
| #165 | ✅ Implementado | 3 tipos de serie; idempotencia de `addSeries` verificada en tests |
| #166 | ✅ Implementado | `finishSession` idempotente con `_operationInProgress` y `finishedAt ??=`; cancelación con confirmación UI |
| #167 | ✅ Implementado | `loadForUser` recupera sesiones huérfanas (finished en activa) y las mueve al historial |
| #169 | ✅ Implementado | `_restStartedAt` persiste en disco; recovery calcula `remaining` desde referencia temporal |
| #196 | ✅ Implementado | Historial de sesiones finalizadas con deduplicación por id |
| #197 | ✅ Implementado | Filtro por período (Esta semana, Este mes, Personalizado) con fechas locales |
| #250 | 🔶 Parcial | Algoritmo verificado en tests de modelo; recorrido real en simulador pendiente |
| #251 | 🔶 Parcial | Serialización y dedup verificados; recorrido en simulador con cierre real del proceso pendiente |
