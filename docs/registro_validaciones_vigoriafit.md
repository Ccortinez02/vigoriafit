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
| **S3-16** | P1 | Snapshot de rutina frente a cambios | **No ejecutado** | — |

