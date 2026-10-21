# Sprint 4 — Entrenadores, grupos y cumplimiento

## Azure items implementados

| ID | Título |
|----|--------|
| #107 | Modelo `Assignment` versionado |
| #109 | `TrainerService.createAssignment` |
| #111 | `TrainerService.getActiveAssignment` / `watchActiveAssignment` |
| #173 | Integración de `assignmentId` y `groupId` en `WorkoutSession` |
| #188 | `logCompletion` idempotente (sessionId como doc ID) |
| #189 | Llamada a `logCompletion` desde `_syncSession` |
| #190 | UI: asignación activa en `join_group_page.dart` |
| #191 | UI: botón "Iniciar rutina asignada" con `assignmentId` y `groupId` |
| #192 | UI: banner de asignación activa en `trainer_page.dart` |
| #193 | UI: creación de asignación versioned (reemplaza `assignWorkout`) |
| #194 | UI: botón "Retirar" por miembro (`removeMember`) |
| #195 | Reglas Firestore para `assignments` y `completions` idempotentes |

## Acceptance tests verificados

| ID | Descripción | Estado |
|----|-------------|--------|
| #248 | Solo el dueño del grupo puede administrarlo (no-owner bloqueado) | ✅ test Firestore `ordinary user cannot create a trainer group` |
| #252 | Código de invitación válido/inválido | ✅ test Firestore `invitation lookup allows join` |
| #253 | El alumno ve la rutina asignada por su entrenador | ✅ `join_group_page.dart` muestra assignment activo |
| #254 | Solo se registra un completion por sesión (idempotencia) | ✅ test Firestore `completion ownership` + regla `allow update: if false` |

## Modelo de datos

### `Assignment` (`lib/models/assignment.dart`)

```
groups/{gid}/assignments/{aid}
  groupId: string        — referencia al grupo
  trainerId: string      — UID del entrenador (Auth)
  workoutId: string      — ID del catálogo de rutinas
  workoutTitle: string   — snapshot del título (200 chars)
  exercisesSnapshot: []  — snapshot de ejercicios al momento de asignar
  startAt: timestamp     — inicio de la planificación
  endAt?: timestamp      — fin opcional
  daysPerWeek: int 1–7  — frecuencia semanal
  timezone: string       — 'America/Santiago'
  status: 'active'|'inactive'
  createdAt: timestamp
```

**Versionado:** cada llamada a `createAssignment` genera un documento nuevo. El historial de asignaciones se conserva completo. Solo `status` puede modificarse después de crear.

### `WorkoutSession` (campos nuevos)

```
users/{uid}/workout_sessions/{sessionId}
  ...campos existentes...
  aid?: string  — assignmentId (si viene de una asignación)
  gid?: string  — groupId (si viene de un grupo)
```

### `Completion` (idempotente)

```
groups/{gid}/completions/{sessionId}
  sessionId: string     — doc ID == sessionId (garantía de idempotencia)
  userId: string
  userName: string
  workoutId: string
  workoutTitle: string
  completedAt: timestamp
  assignmentId?: string
```

## Permisos (reglas Firestore)

| Recurso | Crear | Leer | Actualizar | Borrar |
|---------|-------|------|------------|--------|
| `groups/{gid}` | trainer (claim) | owner \| member | groupOwner (solo campos de asignación legacy) | ❌ |
| `groups/{gid}/members/{uid}` | owner (con código válido) | owner \| groupOwner | ❌ | owner \| groupOwner |
| `groups/{gid}/assignments/{aid}` | groupOwner + validación completa | groupOwner \| member | groupOwner (solo `status`) | ❌ |
| `groups/{gid}/completions/{sid}` | member (sid==sessionId, userId==auth.uid) | groupOwner \| owner-del-completion | ❌ | ❌ |

**El claim `trainer`** viene exclusivamente del JWT de Firebase Auth (`request.auth.token.get('trainer', false)`). No es un campo en el perfil del usuario.

## Flujo session → completion

```
startSession(workout, uid, prefs, assignmentId?, groupId?)
  → WorkoutSession creado con aid + gid

finishSession()
  → _syncSession() escribe en users/{uid}/workout_sessions/{id}
  → si session.groupId != null:
      TrainerService.logCompletion(groupId, sessionId, uid, userName, workout, assignmentId?)
        → transacción: si doc no existe → set; si existe → return (idempotente)
```

## Idempotencia de completions

El `sessionId` (UUID generado en cliente) actúa como ID del documento en `completions`. Las reglas verifican `sid == request.resource.data.sessionId` y `allow update: if false`. Un reintento de sync:
1. La transacción en `logCompletion` lee el doc primero; si existe, retorna sin error.
2. Si la transacción llega a Firestore igualmente, las reglas bloquean el `update`.

## Tests

- `test/firestore/access.test.cjs` — 12 tests de reglas Firestore (node:test + @firebase/rules-unit-testing)
- `test/` — 98 tests Flutter (unit)
