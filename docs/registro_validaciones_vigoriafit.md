# Registro de Validaciones VigoriaFit — Sprint 3

## Estado de Ejecución por Caso

| ID | Prioridad | Nombre / Acción | Estado | Observaciones / Arreglos |
|---|---|---|---|---|
| **S3-01** | P1 | Catálogo e imágenes de ejercicios | **Aprobado con observaciones** | Mapeo de poses corregido en código (`Burpees` -> `pushup`, `Rodillas al pecho` -> `mountain_climber`, etc.). Descripciones añadidas a todos los ejercicios. Queda pendiente reemplazo visual de archivos PNG en `assets/exercises/`. |
| **S3-02** | P1 | Filtros de rutinas | **Aprobado** | Filtros funcionando correctamente sin anomalías. |
| **S3-03** | P0 | Manejo de sesión única / activa | **Aprobado** | Sesión única respetada; manejo de concurrencia correcto. |
| **S3-04** | P0 | Registro de series y cancelación | **Aprobado con observaciones** | Corregido: cancelar sesión ya no la marca como hecha. Eliminado botón duplicado de finalizar. Notificación persistente en segundo plano dejada pendiente de validación según permisos de dispositivo. |
| **S3-05** | P1 | Inputs inválidos en descanso | **Aprobado** | Corregido: bloqueo estricto de caracteres no numéricos, símbolos, decimales y negativos. Límites forzados: 0-60 minutos y 0-59 segundos. |
| **S3-06** | P0 | Pulsación rápida y reintentos al guardar | **Aprobado** | Sin duplicación de series ni finalizaciones erróneas. |
| **S3-07** | P0 | Recuperación tras cierre forzoso | **Aprobado** | Persistencia local recupera la sesión activa correctamente. |
| **S3-08** | P0 | Interrupciones al guardar en historial | **Aprobado** | Guardado íntegro sin inconsistencias. |
| **S3-09** | P1 | Temporizador en segundo plano / reinicio | **Aprobado** | Corregido: se reanuda el cálculo real desde la marca persistida tras cerrar/reabrir la app, soportando conteo en negativo y alarma persistente. |
| **S3-10** | P1 | Cancelar entrenamiento | **Aprobado** | Flujo de confirmación correcto; cancelar no suma como completado. |
| **S3-11** | P0 | Finalizar sin red (Offline) | **Pendiente** | Pendiente de comprobación manual en modo avión. |
| **S3-12** | P1 | Filtros del Historial | **Aprobado con observaciones** | Orden cronológico descendente y detalle de series/cargas exactos validados. Filtro temporal (semana/mes) validado parcialmente debido a falta de datos en fechas anteriores. |
| **S3-13** | P0 | Límite local de sesiones (recorte a 50) | **Aprobado** | Validado mediante suite de tests automatizada (`workout_session_test.dart`): el algoritmo preserva las 50 más recientes y conserva intactas las pendientes/fallidas. |
| **S3-14** | P0 | Aislamiento de sesiones entre cuentas | **Pendiente** | Pendiente de comprobación mediante intercambio de sesiones entre cuentas A y B. |
| **S3-15** | P0 | Reglas Firestore de inmutabilidad | **Aprobado** | Auditado y verificado en `firestore.rules`: lectura/listado exclusivo por `owner(uid)` (línea 100); borrado por `owner(uid)` conforme al Sprint 8 (línea 101); creación restringida a `status == 1` (finished, línea 105); e inmutabilidad absoluta con `allow update: if false;` (línea 108). Suites de reglas cubiertas en `workout_sessions.test.cjs`. |
| **S3-16** | P1 | Snapshot de rutina frente a cambios | **Aprobado** | Todo funcionó correctamente. El historial se lee bien, los datos se guardan de forma fidedigna sin información alterada ni inventada, y las sesiones conservan su snapshot inmutable ante cambios. |

---

# Registro de Validaciones VigoriaFit — Sprint 4

## Estado de Ejecución por Caso

| ID | Prioridad | Nombre / Acción | Estado | Observaciones / Arreglos |
|---|---|---|---|---|
| **S4-01** | P0 | Autoridad del rol de entrenador y acceso de alumno | **Aprobado** | Se verificó que una cuenta de alumno no puede autoconcederse el rol de entrenador desde la UI (el switch está restringido por autorización administrativa) y solo tiene acceso a unirse a grupos con código. |
| **S4-02** | P0 | Creación de grupo y generación de código único | **Aprobado** | Con la cuenta de entrenador autorizada, se accedió al Panel de Entrenador y se creó el grupo exitosamente en Firestore, generando de forma inmediata el código PIN de invitación único de 6 dígitos. |
| **S4-03** | P1 | Unirse a grupo con código | **Aprobado** | Validación de PIN inválido con alertas correspondientes. Unirse con PIN correcto vincula al alumno al grupo, carga la rutina asignada y muestra el nombre del entrenador. Requiere índice compuesto en Firestore (`assignments`: `status ASC` + `createdAt DESC`). Corrección de regla de lectura en `completions` (`resource == null`) para permitir comprobación de idempotencia en transacciones. El alumno completa la rutina y se registra el cumplimiento (`completions`) en Firestore para el cálculo de adherencia del entrenador. Se implementó la pantalla de Perfil de Alumno (`MemberProfilePage`) permitiendo al entrenador inspeccionar el listado de ejercicios, series, repeticiones y cargas realizadas por el alumno. Se habilitó sincronización en tiempo real (`watchActiveAssignment`) en la vista del alumno y vinculación de sesión desde el detalle de rutina. Funcionalidad de retiro de alumnos verificada. |
| **S4-04** | P1 | Asignación de rutina versionada | **Pendiente** | Aplazado por el usuario. Pendiente de evaluación posterior. |
| **S4-05** | P1 | Alumno abandona / entrenador retira; revocación de acceso | **Aprobado** | Implementado y validado en dispositivo (commit `feat(S4-05)`). Al retirar un alumno o al salir este del grupo: (1) se elimina el doc `members/{uid}`; (2) se borran todos sus `completions` del grupo en batch, reseteando su historial de adherencia. El alumno ya no ve la rutina asignada. Para evitar que un alumno retirado vuelva a unirse sin consentimiento, se implementó rotación de código de invitación (`rotateCode`): el entrenador genera un nuevo PIN desde el Panel; los alumnos actuales permanecen; el código anterior queda inválido. Cambios en reglas Firestore: `completions allow delete: if groupOwner(gid)` y `groupInvites allow create: if signedIn()` (en lugar de `trainer()`). |
| **S4-06** | P0 | Asignación con payload real y timestamps | **Aprobado** | Se verificó en Firebase Console y en la app que la creación de asignaciones persiste los campos en Firestore con tipos exactos `Timestamp` (`startAt`, `createdAt`), `trainerId` y `groupId` coherentes, snapshot de ejercicios completo y actualización reactiva inmediata en la app del alumno. |
| **S4-07** | P1 | Vigencia temporal, asignaciones futuras y rechazo de fechas inválidas | **Aprobado** | Validado en dispositivo. Se incorporó configuración de fecha de inicio y fecha de fin (opcional) en el diálogo de asignación. Se implementó validación estricta (`endAt > startAt`) que bloquea el envío en la UI y es forzada en `firestore.rules`. El control de vigencia (`isEffective`) previene que asignaciones futuras se muestren como activas para el alumno antes de su fecha de inicio. Se actualizó el banner del entrenador para distinguir asignaciones programadas (futuras) de las activas vigentes. Se corrigió desbordamiento visual en el diálogo al seleccionar fecha de término. |

---

## Cambios de código — 18/19 noviembre 2026 (commit `feat(S4-06, S4-07)`)

### Archivos modificados

| Archivo | Cambio |
|---|---|
| `lib/models/assignment.dart` | Agregados métodos de vigencia temporal `isEffective()`, `isFuture()`, `isExpired()`. |
| `lib/services/trainer_service.dart` | `createAssignment()` valida `endAt > startAt`. `getActiveAssignment()` y `watchActiveAssignment()` filtran por vigencia efectiva (`isEffective`). Añadido `getLatestAssignment()` para vista de gestión del entrenador. |
| `lib/pages/trainer_page.dart` | Diálogo de asignación permite seleccionar fecha de inicio y fin opcional con datepicker. Valida en tiempo real que fin sea posterior a inicio. `_assignmentBanner` diferencia visualmente asignaciones programadas (futuras), activas y vencidas. Corregido overflow en fila de fecha de término. |
| `lib/pages/join_group_page.dart` | `_startAssigned()` valida vigencia (`isEffective`) antes de permitir inicio de sesión. `_noAssignmentCard` clarifica mensaje cuando no hay rutina vigente. |
| `firestore.rules` | `validAssignment()` exige `(!d.keys().hasAny(['endAt']) || (d.endAt is timestamp && d.endAt > d.startAt))` para rechazar fechas inválidas en backend. |

---

## Cambios de código — 18/19 noviembre 2026 (commit `feat(S4-05)`)

### Archivos modificados

| Archivo | Cambio |
|---|---|
| `lib/services/trainer_service.dart` | `leaveGroup()` ahora elimina al miembro y borra todos sus `completions` del grupo (best-effort). Nuevo método `rotateCode()`: genera código único, transacción atómica que actualiza `groups/{gid}.code` y crea nueva entrada en `groupInvites`. |
| `lib/pages/trainer_page.dart` | Nuevo método `_rotateCode()` con diálogo de confirmación. Tarjeta del código muestra dos botones en fila: **Copiar** y **Cambiar**. Variable de estado `_rotatingCode` para indicador de carga. |
| `lib/pages/member_profile_page.dart` | Vista de ejercicios en perfil del alumno: contador de series (`"X series"`) movido al lado derecho del nombre del ejercicio. Chips de reps/kg/duración permanecen debajo. Eliminado el texto duplicado de series que aparecía bajo el nombre. |
| `firestore.rules` | `completions`: `allow delete: if groupOwner(gid)` (antes `delete: if false`). `groupInvites`: `allow create: if signedIn()` (antes `trainer()`). `groups/{gid}`: `allow update` acepta también rotación de `code` (campo único, formato 6 dígitos). |

### Cambios en Firebase Console requeridos (aplicados manualmente)
1. `completions`: `allow update: if false; allow delete: if groupOwner(gid);`
2. `groupInvites`: `allow create: if signedIn() && ...` (reemplaza `trainer()`)
3. `groups/{gid}`: bloque `allow update` expandido con cláusula OR para rotación de código

