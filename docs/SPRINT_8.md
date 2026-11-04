# Sprint 8 — Eliminación de datos, pruebas piloto y entrega

## Resumen del sprint

**Rama:** `ccortinez/sprint8-eliminacion-piloto-entrega`  
**Base:** Sprint 7 (`ccortinez/sprint7-coach-reconocimiento-ia`)  
**Fecha:** Noviembre 2026

---

## Bugs corregidos

### Bug 2 — `startAt`/`createdAt` como Timestamp en `trainer_service.dart`

**Problema:** `createAssignment` enviaba `startAt.toIso8601String()` y `now.toIso8601String()` (strings), pero las reglas de Firestore requerían `d.startAt is timestamp` y `d.createdAt is timestamp`.

**Corrección:**
- `startAt` → `FieldValue.serverTimestamp()` (cumple `startAt == request.time`)
- `createdAt` → `FieldValue.serverTimestamp()` (cumple `createdAt == request.time`)
- `endAt` → `Timestamp.fromDate(endAt!)` si el entrenador lo especifica
- Se agregó `_normalizeAssignmentData()` para convertir Timestamps a ISO al leer desde Firestore
- `getActiveAssignment` y `watchActiveAssignment` usan el normalizador

### Bug 3 — `aiSource` rechazado por reglas Firestore

**Problema:** `FoodRecord.toMap()` incluye `aiSource` condicionalmente, pero la función `validFoodRecord` en `firestore.rules` no lo incluía en `hasOnly([...])`. Cualquier registro con `aiSource != null` era rechazado por Firestore.

**Corrección:** Se agregó `'aiSource'` al `hasOnly([...])` en `validFoodRecord`. El campo es opcional (puede estar ausente); la regla solo impide campos no listados.

### Bug 4 — Adherencia % sin calcular en trainer_page

**Problema:** El tile de cada alumno mostraba solo el número bruto de entrenamientos de la semana sin porcentaje relativo al objetivo.

**Corrección:** Se pasa `daysPerWeek` de la asignación activa al método `_memberTile`. Ahora muestra: `"75% esta semana (3 de 4 días) · último hace 2 días"`.

### Bug 5 — `workout.exercises` vs `exercisesSnapshot` en la vista del alumno

**Problema:** Al pulsar "Ver rutina" desde la vista del alumno en `join_group_page.dart`, se navegaba a `WorkoutDetailPage` con el Workout del catálogo actual, que puede haber cambiado desde la asignación.

**Corrección:**
- Se agregó `workoutFromSnapshot(Workout catalogWorkout)` a `Assignment`. Reconstruye un `Workout` usando el snapshot de ejercicios (fuente de verdad para sets/series/descanso) y el catálogo solo para datos visuales (imagen `pose`, `avoidConditions`).
- `join_group_page.dart` ahora usa `a.workoutFromSnapshot(workout)` en lugar de `workout` al abrir `WorkoutDetailPage`.

### Bug 6 — fechas de consumo

**Estado:** No es un bug. `food_service._toFirestore()` ya convierte `consumedAt`, `createdAt` y `updatedAt` a `Timestamp.fromDate()` antes de enviar a Firestore. `FoodRecord.toMap()` guarda ISO strings solo para persistencia local (SharedPreferences).

---

## Eliminación de cuenta (#270)

### Flujo cliente

1. El usuario abre **Configuración** → **Eliminar cuenta**.
2. Se muestra un `AlertDialog` con advertencia y campo de contraseña.
3. Si confirma, se reautentica con `EmailAuthProvider.credential` + `reauthenticateWithCredential`.
4. Si la reautenticación falla, se muestra error y el proceso se cancela.
5. Si tiene éxito, se llama `AppStore.instance.deleteAccount()` que:
   - Borra en batch desde Firestore: `food_records`, `water_records`, `workout_sessions`, `private/health_profile` y el documento raíz `users/{uid}`.
   - Elimina el usuario de Firebase Auth (`user.delete()`).
   - Llama `logout()` para limpiar SharedPreferences y el estado en memoria.
6. La app navega al inicio de sesión.

### Cambios en Firestore rules

```
// users/{uid}: se permitió delete para el propietario
allow delete: if owner(uid);

// users/{uid}/private/{id}: se permitió delete para health_profile
allow delete: if owner(uid) && id == 'health_profile';

// users/{uid}/workout_sessions: se permitió delete para el propietario
allow delete: if owner(uid);
```

> **Importante:** Desplegar las reglas actualizadas antes de que los usuarios usen la eliminación de cuenta:
> ```bash
> firebase deploy --only firestore:rules --project vigoria-fe224
> ```

---

## Flujo E2E — del registro al coach IA (#267)

1. **Registro:** `AuthPage` → introducir email/contraseña → "Crear cuenta".
2. **Onboarding:** Nombre, objetivo, nivel, equipamiento, datos de salud.
3. **Pantalla principal:** `RootPage` → tabs Hoy / Entrenos / Nutrición / Progreso.
4. **Entrenamiento:** Tab Hoy → "Empezar entreno" → `WorkoutSessionPage` → completar series → finalizar.
5. **Nutrición:** Tab Nutrición → escáner de alimentos → foto → Gemini Vision analiza → confirmar → guardar registro.
6. **Coach IA:** Tab Hoy → botón Coach → escribir pregunta → `CoachService` llama Firebase AI Logic (`gemini-3.8-flash`) → respuesta en pantalla.
7. **Progreso:** Tab Progreso → ver peso, rachas, logros.
8. **Perfil/Configuración:** Icono de engranaje → editar nombre, unidades, recordatorios, o eliminar cuenta.

---

## Build Android (#269)

> **Requisito:** Android SDK instalado (no disponible en este equipo de desarrollo; la máquina de CI/CD o el desarrollador de Android debe ejecutar el build).

### APK de debug para piloto
```bash
cd /path/to/vigoriafit
flutter build apk --debug --dart-define=USE_EMULATOR=false
# Salida: build/app/outputs/flutter-apk/app-debug.apk
```

### APK de release (requiere keystore)
```bash
flutter build apk --release --dart-define=USE_EMULATOR=false
# Salida: build/app/outputs/flutter-apk/app-release.apk
# IMPORTANTE: NO subir el keystore al repositorio.
```

### Distribución del APK al piloto
1. **Firebase App Distribution (recomendado):**
   ```bash
   firebase appdistribution:distribute build/app/outputs/flutter-apk/app-debug.apk \
     --app <ANDROID_APP_ID> \
     --groups "piloto" \
     --release-notes "Sprint 8: coach IA, scanner de alimentos, eliminación de cuenta"
   ```
2. **Alternativa:** Compartir el APK directamente por WhatsApp/email con los participantes del piloto. Los dispositivos Android deben tener habilitada la instalación de fuentes desconocidas.

### Build iOS para piloto
```bash
flutter build ipa --export-method development
# Para TestFlight se requiere cuenta de Apple Developer.
# Para pruebas directas, instalar en dispositivos registrados con:
# xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app
```

---

## Preparación del piloto (#91)

### Participantes sugeridos
- 3–5 usuarios con dispositivos Android e iOS
- Mezcla de niveles: principiante, intermedio, avanzado

### Datos sintéticos para pruebas (NO usar datos reales)
- Email: `piloto1@test.vigoriafit.dev`, `piloto2@test.vigoriafit.dev`, ...
- El emulador Firebase permite probar el flujo completo sin afectar producción:
  ```bash
  flutter run --dart-define=USE_EMULATOR=true
  ```

### Métricas a recopilar durante el piloto
- ¿El scanner de alimentos reconoce la foto correctamente?
- ¿El coach IA responde en < 5 segundos?
- ¿La eliminación de cuenta funciona sin errores?
- ¿Se sincronizan los datos correctamente entre sesiones?

---

## Tests (#90)

### Nuevos tests añadidos

**`test/account_deletion_test.dart`:**
- Verifica que cancelar el diálogo no llama `deleteAccount`
- Verifica que contraseña vacía no dispara el borrado
- Verifica que `FoodRecord.toMap()` NO incluye `aiSource` cuando es null (Bug 3)
- Verifica que `FoodRecord.toMap()` SÍ incluye `aiSource` cuando tiene valor
- Verifica que todos los campos requeridos por Firestore están presentes

### Ejecutar tests
```bash
flutter test
```

---

## Criterios de cierre del sprint

- [x] Bug 2: `startAt`/`createdAt` como Timestamp
- [x] Bug 3: `aiSource` en reglas Firestore
- [x] Bug 4: Adherencia % en trainer page
- [x] Bug 5: `exercisesSnapshot` al ver rutina asignada
- [ ] Bug 6: N/A (ya estaba correcto)
- [x] Eliminación de cuenta (#270) con reautenticación
- [x] Reglas Firestore actualizadas (delete permitido para owner)
- [x] Tests (#90)
- [ ] APK Android (#269) — requiere Android SDK en máquina de build
- [x] Docs Sprint 8 (#89)
- [ ] PR creado y aprobado
- [ ] `firestore:rules` desplegado en producción (`vigoria-fe224`)
