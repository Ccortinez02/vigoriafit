# Sprint 8 — Eliminación de datos, pruebas piloto y entrega

## Resumen del sprint

**Rama:** `ccortinez/sprint8-eliminacion-piloto-entrega`  
**Base:** Sprint 7 (`ccortinez/sprint7-coach-reconocimiento-ia`)  
**Fecha:** Noviembre 2026

---

## Bugs corregidos

### Bug 1 — Firebase Android lanzaba `UnsupportedError`

**Problema:** `lib/firebase_options.dart` lanzaba `UnsupportedError` para `TargetPlatform.android`. La app no podía inicializarse en Android.

**Corrección:** Se añadió la constante `android` con los datos reales del proyecto `vigoria-fe224` extraídos de `android/app/google-services.json`:
- appId: `1:1092988210930:android:3cea818f005aecff8e4a6b`  
- apiKey: desde `google-services.json` (no es un secreto de cliente)  
- projectId, storageBucket, messagingSenderId del proyecto compartido

**Estado:** Implementado. La inicialización de Firebase en Android ya no lanza error.  
**Validación bloqueada por:** Android SDK no instalado en esta máquina de desarrollo; requiere validación en dispositivo/emulador Android.

---

### Bug 2 — `startAt` sobreescrito por `serverTimestamp()`

**Problema:** `createAssignment` usaba `FieldValue.serverTimestamp()` para `startAt`, ignorando la fecha elegida por el entrenador. No era posible programar asignaciones para fechas futuras.

**Correcciones:**
- `startAt` → `Timestamp.fromDate(startAt)` — conserva la fecha elegida
- `createdAt` → `FieldValue.serverTimestamp()` — el servidor sella la creación
- Regla Firestore: se eliminó la restricción `startAt == request.time` que impedía fechas futuras; solo se mantiene `createdAt == request.time`

**Estado:** Implementado y verificado con `flutter analyze`.

---

### Bug 3 — `aiSource` rechazado por reglas Firestore

**Problema:** `FoodRecord.toMap()` incluye `aiSource` condicionalmente, pero `validFoodRecord` en `firestore.rules` no lo tenía en `hasOnly([...])`.

**Corrección:** Se añadió `'aiSource'` al `hasOnly([...])` de `validFoodRecord`.

**Tests:** `test/account_deletion_test.dart` — 4 tests para `toMap()` verifican que `aiSource` aparece solo cuando no es null, que todos los campos requeridos están presentes, y que no hay campos extra.

---

### Bug 4 — Adherencia contaba sesiones, no días únicos

**Problema:** `membersWithAdherence` hacía `m.workoutsThisWeek++` para cada completion. Si un alumno completaba 2 sesiones en el mismo día, contaba como 2.

**Corrección:**  
- `GroupMember` ahora usa `Set<String> _trainingDays` (fechas como `'yyyy-MM-dd'`)
- Getter `int get trainingDaysThisWeek => _trainingDays.length`
- Método `recordCompletion(DateTime at)` público — añade la fecha al Set y actualiza `lastWorkoutAt`
- `membersWithAdherence` llama `m.recordCompletion(at)` en lugar de `m.workoutsThisWeek++`
- `trainer_page.dart` usa `m.trainingDaysThisWeek` en lugar de `m.workoutsThisWeek`

**Tests:** 5 tests en `test/account_deletion_test.dart` cubren: mismo día, días distintos, orden inverso, cero completions, clampeo a 100%.

---

### Bug 5 — `_startAssigned` pasaba la rutina del catálogo, no el snapshot

**Problema:** Al pulsar "Iniciar" en la vista del alumno, `_startAssigned` pasaba `workout` (del catálogo actual) a `startSession`. Si el entrenador editaba la rutina después de asignarla, el alumno entrenaba con la versión nueva.

**Corrección:** `join_group_page.dart` ahora usa `a.workoutFromSnapshot(workout)` tanto en "Ver rutina" (ya estaba) como en "Iniciar" (corregido).

---

### Bug 6 — Fechas de consumo en `food_records`

**Estado:** No era un bug. `food_service._toFirestore()` ya convierte `consumedAt`, `createdAt` y `updatedAt` a `Timestamp.fromDate()` antes de enviar a Firestore. `FoodRecord.toMap()` usa ISO strings solo para persistencia local.

---

## Eliminación de cuenta (#270)

### Flujo cliente (revisado)

1. El usuario abre **Configuración** → **Eliminar cuenta**.
2. Se detecta el proveedor: `firebase_auth` / `google.com`.
3. Para cuentas **email/password**: diálogo con campo de contraseña.  
   Para cuentas **Google**: diálogo de confirmación; re-auth con `reauthenticateWithProvider(GoogleAuthProvider())`.
4. Reautenticación fallida → error visible, proceso cancelado.
5. Reautenticación exitosa → `AppStore.deleteAccount()`:
   - Sale del grupo (si el usuario es miembro) antes del borrado.
   - Borra `food_records`, `water_records`, `workout_sessions` en lotes de máx. 400 ops (límite Firestore: 500).
   - Borra `private/health_profile` y el documento raíz `users/{uid}`.
   - Limpia SharedPreferences del usuario (`AccountPreferences.clearAll()`) para evitar que escrituras en caché recreen datos.
   - Elimina la cuenta de Firebase Auth (`user.delete()`).
   - Reinicia el estado en memoria sin llamar `_auth.signOut()` (la cuenta ya no existe).
6. La app navega al inicio de sesión.

### Cambios en Firestore rules

```
// users/{uid}: delete permitido para el propietario
allow delete: if owner(uid);

// users/{uid}/private/{id}: delete permitido para health_profile
allow delete: if owner(uid) && id == 'health_profile';

// users/{uid}/workout_sessions: delete permitido para el propietario
allow delete: if owner(uid);

// groups/{gid}/members/{uid}: delete permitido para el propio miembro o el entrenador
allow delete: if owner(uid) || groupOwner(gid);

// groups/{gid}/assignments: startAt puede ser fecha futura (no se restringe a request.time)
// createdAt sí debe ser request.time
```

> **Pendiente de despliegue:** `firebase deploy --only firestore:rules --project vigoria-fe224`

### Política para grupos propietarios

Si el usuario a eliminar es el **entrenador** de un grupo, la eliminación de su cuenta **no** elimina el grupo ni sus miembros. Esta operación requiere privilegios de servidor (Admin SDK) no disponibles en el cliente. Se documenta como limitación conocida: el grupo queda huérfano. La gestión de grupos huérfanos es responsabilidad del equipo de operaciones.

---

## Flujo E2E — del registro al coach IA (#267)

1. **Registro:** `AuthPage` → email/contraseña o Google → "Crear cuenta".
2. **Onboarding:** Nombre, objetivo, nivel, equipamiento, datos de salud.
3. **Pantalla principal:** `RootPage` → tabs Hoy / Entrenos / Nutrición / Progreso.
4. **Entrenamiento libre:** Tab Hoy → "Empezar entreno" → `WorkoutSessionPage` → completar series → finalizar.
5. **Entrenamiento asignado:** Tab Perfil/Grupo → "Iniciar" rutina asignada → snapshot de ejercicios → completar → cumplimiento registrado en `groups/{gid}/completions`.
6. **Nutrición:** Tab Nutrición → escáner de alimentos → foto → Gemini Vision analiza → confirmar → guardar registro con `aiSource: 'gemini-3.8-flash'`.
7. **Coach IA:** Tab Hoy → botón Coach → pregunta → `CoachService` → Firebase AI Logic (`gemini-3.8-flash`) → respuesta.
8. **Progreso:** Tab Progreso → peso, rachas, logros.
9. **Configuración:** Icono engranaje → editar nombre, unidades, recordatorios, o eliminar cuenta.

---

## Build Android (#269)

> **Bloqueo:** Android SDK no instalado en esta máquina de desarrollo. El build debe ejecutarse en la máquina de CI/CD o en la estación del desarrollador Android.

### APK de debug para piloto

```bash
cd /path/to/vigoriafit
flutter build apk --debug --dart-define=USE_EMULATOR=false
# Salida: build/app/outputs/flutter-apk/app-debug.apk
```

### APK de release (requiere keystore externo)

```bash
flutter build apk --release --dart-define=USE_EMULATOR=false
# IMPORTANTE: NO añadir el keystore al repositorio.
# Configurar firma en android/key.properties (fuera del repo).
```

### Distribución del APK al piloto

1. **Firebase App Distribution (recomendado):**
   ```bash
   firebase appdistribution:distribute build/app/outputs/flutter-apk/app-debug.apk \
     --app 1:1092988210930:android:3cea818f005aecff8e4a6b \
     --groups "piloto" \
     --release-notes "Sprint 8: coach IA, scanner, eliminación de cuenta"
   ```
2. **Alternativa:** Compartir el APK directamente. Los dispositivos deben tener habilitada la instalación de fuentes desconocidas.

### Build iOS para piloto

```bash
flutter build ipa --export-method development
# Para TestFlight se requiere cuenta de Apple Developer.
```

---

## Preparación del piloto (#91)

### Escala real del piloto

El compromiso académico es un piloto de **al menos 15 participantes**. La propuesta de 3–5 personas en versiones anteriores era una **prueba preliminar**, no el piloto completo.

| Fase | Participantes | Objetivo |
|---|---|---|
| Prueba preliminar | 3–5 | Detectar errores críticos de flujo |
| Piloto real | ≥15 | Validar métricas de uso y usabilidad |

### Métricas comprometidas

| Métrica | Objetivo |
|---|---|
| Coach IA — tiempo de respuesta p95 | ≤10 s |
| Coach IA — timeout configurado | 30 s |
| Scanner de alimentos — tasa de reconocimiento | Medir durante piloto |
| Eliminación de cuenta — éxito | 100% sin datos residuales |
| Sincronización de datos | Sin pérdida al cambiar sesión |

### Aviso de privacidad

Antes de incorporar participantes al piloto:
- Las fotos de alimentos se envían a Google AI (Gemini) para análisis.
- El coach recibe contexto del perfil (nombre, objetivo, nivel, días de entrenamiento) pero **no** condiciones médicas ni alergias.
- El usuario puede eliminar todos sus datos desde Configuración.

### Criterios de entrada

- Dispositivo Android ≥ API 24 o iOS ≥ 14.
- Conexión a internet durante el uso del coach y el scanner.
- Cuenta registrada con datos sintéticos (NO datos personales reales durante validación).

---

## Tests (#90)

### Resultados de ejecución

```
flutter test test/account_deletion_test.dart --reporter=compact
+15: All tests passed!
```

**15 tests pasan:**

| Grupo | Tests |
|---|---|
| `FoodRecord.toMap — aiSource` | 4 |
| `Adherencia — días únicos` | 5 |
| `Assignment.workoutFromSnapshot` | 3 |
| `Eliminación de cuenta — lógica cliente` | 3 |

**Entorno de ejecución:**
- Flutter: `flutter --version` (ver repositorio)
- Plataforma: macOS, sin emuladores Firebase (tests de lógica pura)

### Tests pendientes (requieren emulador Firebase)

- Verificar reglas Firestore para `deleteAccount` real
- Verificar que `aiSource` pasa validación de reglas en create/update
- Verificar que `startAt` futuro es aceptado por las nuevas reglas de assignment

---

## Criterios de cierre del sprint

| Requisito / Tarea | ID Azure | Estado | Evidencia | Bloqueo / Acción restante |
|---|---|---|---|---|
| Bug 1: Firebase Android configura correctamente | — | **Parcial** | Código implementado; sin UnsupportedError | Validar en dispositivo/emulador Android (SDK no disponible) |
| Bug 2: startAt conserva fecha elegida | — | **Implementado** | Código + analyzer limpio | Desplegar reglas Firestore |
| Bug 3: aiSource en reglas Firestore | — | **Implementado** | 4 tests pasan | Desplegar reglas Firestore |
| Bug 4: Adherencia días únicos | — | **Implementado** | 5 tests pasan | — |
| Bug 5: _startAssigned usa snapshot | — | **Implementado** | Código verificado | — |
| Eliminación de cuenta (#270) | #270 | **Implementado** | Flujo email + Google; batch paginado; SharedPrefs limpio | Desplegar reglas Firestore; validar con emulador |
| Reglas Firestore actualizadas | — | **Pendiente de despliegue** | Archivo modificado en repo | `firebase deploy --only firestore:rules --project vigoria-fe224` |
| Tests (#90) | #90 | **Implementado** | 15 tests pasan | Tests de integración pendientes (emulador) |
| APK Android (#269) | #269 | **Bloqueado** | — | Android SDK no disponible en esta máquina |
| iOS build | — | **Parcial** | Funciona en simulador | Build de distribución requiere cuenta Apple Developer |
| Docs Sprint 8 (#89) | #89 | **Implementado** | Este documento | — |
| Piloto ≥15 participantes (#91) | #91 | **Pendiente** | Paquete preparado | Ejecutar piloto real; prueba preliminar (3–5) como primer paso |
| PR creado y aprobado | — | **Pendiente** | — | Crear PR a `flanes20/vigoriafit` |

**El Sprint 8 no puede declararse completo** hasta que:
1. Las reglas Firestore sean desplegadas en producción.
2. El piloto real (≥15 participantes) sea ejecutado.
3. Los recorridos E2E sean validados en dispositivos Android e iOS reales.
