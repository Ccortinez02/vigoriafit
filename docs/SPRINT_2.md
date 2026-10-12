# Sprint 2: Perfil, persistencia y funcionamiento ante desconexiones

## Objetivo y alcance

Que el perfil y las preferencias se conserven correctamente y que la app comunique de forma honesta los estados de guardado y los errores, incluso ante desconexiones.

Rama: `ccortinez/sprint2-perfil-persistencia`
Base: `upstream/main` (contiene el Sprint 1 integrado, commit `a59b128`)
Fecha de implementación local: 12 de octubre de 2026.

---

## Matriz de almacenamiento (Paso 2 / #113)

| Información | Fuente principal | Copia local | Acceso sin conexión | Propietario | Sincronización | Migración |
|---|---|---|---|---|---|---|
| Perfil básico (nombre, objetivo, nivel, gym, días) | Firestore `users/{uid}` | SharedPreferences `vigoria_v2_{uid}_brio_profile_v1` | Sí (caché) | UID autenticado | Al guardar (transacción) | No aplica — ya en modelo v2 |
| Antecedentes privados (edad, talla, peso, condiciones, alergias) | Firestore `users/{uid}/private/health_profile` | SharedPreferences (mismo JSON del perfil) | Sí (caché) | UID autenticado | Al guardar (transacción) | No aplica |
| Tema | SharedPreferences `vigoria_v2_{uid}_brio_theme_v1` | — (es local) | Sí | UID autenticado | No se sincroniza entre dispositivos | No aplica |
| Unidades (métrico/imperial) | SharedPreferences `vigoria_v2_{uid}_brio_units_v1` | — (es local) | Sí | UID autenticado | No se sincroniza entre dispositivos | No aplica |
| Borradores de perfil en edición | Memoria (`_p` en la página) | No | Solo en sesión activa | UID actual | No — se descarta al salir | No aplica |
| Estado de sincronización | Memoria (`AppStore._profileSyncState`) | No | No | UID actual | No | No aplica |
| Marcador de migración | SharedPreferences `vigoria_v2_{uid}_brio_migration_v1` | — | Sí | UID autenticado | No | Escrito al primer acceso por UID |
| Registros diarios (agua, comidas, entrenamientos) | SharedPreferences `vigoria_v2_{uid}_brio_daylogs_v1` | — | Sí | UID autenticado | No (fuera de este sprint) | No aplica |
| Historial de peso | SharedPreferences `vigoria_v2_{uid}_brio_weights_v1` | — | Sí | UID autenticado | No (fuera de este sprint) | No aplica |
| Catálogos (ejercicios, alimentos, suplementos) | Bundle de la app | No requiere | Siempre | App | No | No aplica |
| Historial de entrenamientos completos | Fuera del alcance de este sprint | — | — | — | — | — |

**Política de fuente única:** Firestore es la fuente de verdad para el perfil. SharedPreferences es caché de lectura rápida y almacén de preferencias locales. No compiten: SharedPreferences se actualiza siempre después de una confirmación remota (o antes para preservar el borrador ante errores de red).

---

## Modelo de Firestore (sin cambios respecto al Sprint 1)

Las rutas, campos y tipos no cambian en este sprint. Ver `docs/SPRINT_1.md` para el esquema completo.

Cambio de comportamiento: el guardado de perfil ahora escribe localmente **antes** de intentar la transacción remota, para preservar el borrador si el servidor falla.

---

## Estados de sincronización (Paso 4 / #112)

Definidos en `lib/services/sync_state.dart`:

| Estado | Significado | Mensaje al usuario |
|---|---|---|
| `idle` | Sin cambios pendientes | (invisible) |
| `saving` | Operación en curso | "Guardando…" |
| `pending` | Guardado local, sin confirmación remota | "Guardado en este dispositivo. Pendiente de sincronizar." |
| `confirmed` | Servidor confirmó | "Cambios guardados." |
| `failed` | Error recuperable | "No se pudo sincronizar. Reintentar." |
| `rejected` | Rechazado por validación o permisos | Mensaje con invitación a revisar campos |

El estado `pending` está definido para el caso en que el SDK de Firestore encola la escritura offline. En la implementación actual, las transacciones del repositorio fallan explícitamente offline (en vez de encolarse silenciosamente), lo que devuelve `failed`. Si en el futuro se activa la persistencia offline del SDK para perfiles, `pending` pasa a ser el estado correcto durante la espera de confirmación.

---

## Política de guardado y reintentos (Paso 4)

1. El usuario edita en la pantalla → se guarda en memoria como borrador.
2. Al pulsar "Guardar cambios":
   - Se valida que haya nombre.
   - Se deshabilita el botón para prevenir doble envío.
   - Se escribe el borrador en SharedPreferences (preservación ante error).
   - Se inicia la transacción Firestore.
3. Resultado:
   - **Éxito:** `confirmed`, la pantalla cierra brevemente tras mostrar confirmación.
   - **Error de red:** `failed`, el botón "Reintentar" aparece. El borrador permanece en el formulario.
   - **Error de permisos:** `rejected`, se muestra mensaje distinto sin botón de reintento automático.
4. Un reintento llama a `saveProfile` de nuevo con el mismo borrador. La transacción Firestore es idempotente para el mismo contenido.

**Operaciones pendientes de otra cuenta:** al cambiar de cuenta, `_epoch` avanza y cualquier respuesta tardía del servidor no reemplaza el estado de la nueva sesión.

---

## Estrategia de reintentos e idempotencia (#249)

- La transacción Firestore usa `update` sobre el documento ya existente (creado en el primer acceso). No puede crear un segundo documento para el mismo UID.
- Un reintento del mismo borrador produce exactamente una escritura en el servidor.
- Si una edición nueva sustituye a una pendiente anterior, el store conserva el último valor en memoria y en caché local. Un reintento antiguo (si existiera en cola) sería sobrescrito por la edición nueva.
- En la implementación actual no hay cola explícita de reintentos: el usuario activa el reintento manualmente.

---

## Política de conflictos entre dispositivos

Alcance proporcional al sprint: el perfil tiene un campo `updatedAt` (timestamp del servidor). No se implementa resolución automática de conflictos. Si dos dispositivos guardan simultáneamente, el último en confirmar gana (last-writer-wins del servidor). No se detecta ni informa este caso al usuario en este sprint. Se documenta como pendiente.

---

## Migración segura e idempotente (Paso 3 / #108)

**Estado:** mecanismo implementado; datos a migrar: ninguno con propiedad verificable.

Política aplicada:
- Las claves antiguas `brio_*` (sin UID) se conservan sin tocar.
- No se asignan al usuario actual: la coincidencia de sesión no es prueba suficiente de propiedad.
- `_runMigrationIfNeeded` registra la versión completada por UID para garantizar idempotencia.
- Una migración interrumpida puede reanudarse: al reiniciar, si el marcador no alcanzó la versión actual, se vuelve a ejecutar (actualmente sin efecto sobre datos concretos).

Si en el futuro se identifica información con propiedad verificable (por ejemplo, un campo UID dentro de un documento local), se incrementa `_migrationCurrentVersion` y se agrega la lógica de importación en `_runMigrationIfNeeded`.

---

## Onboarding y edición del perfil (Paso 1 / #97, #120)

Mejoras implementadas:

- **Preservación del borrador ante errores:** el borrador permanece en el formulario si el guardado falla; el usuario puede reintentar sin reescribir.
- **Protección contra pulsaciones repetidas:** el botón se deshabilita durante el guardado.
- **Estado visual de guardado:** indicador de carga mientras la operación está en curso.
- **Mensaje de error claro:** se muestra en la pantalla (no solo como SnackBar) para que el usuario lo vea antes de reintentar.
- **El onboarding no reaparece por fallo de consulta:** la lógica en `main.dart` usa `_onboarded` leído desde caché; un error de lectura remota no borra ese flag.

Distinción de estados en la carga inicial:
- Perfil local disponible → se muestra mientras se verifica el remoto.
- Error de lectura con caché → se usa la caché y se muestra aviso de reconexión.
- Perfil inexistente → se crea en el primer acceso (ya implementado en Sprint 1).
- Acceso denegado → `_sessionError` muestra error con opción de reintentar o cerrar sesión.

---

## Preferencias: tema y unidades (Paso 6 / #124)

### Tema
- Tres opciones: sistema, claro, oscuro.
- Persistido por UID en SharedPreferences.
- Recuperado al reiniciar.
- Aislado entre usuarios.
- Implementado desde Sprint 1; sin cambios en este sprint.

### Unidades
- Dos sistemas: Métrico (kg, cm) y Imperial (lb, pulgadas).
- Persistido por UID en SharedPreferences (`vigoria_v2_{uid}_brio_units_v1`).
- Recuperado al reiniciar.
- Aislado entre usuarios.
- **Los datos canónicos siempre se guardan en kg y cm.** La conversión ocurre solo al mostrar y al interpretar la entrada del usuario. Cambiar de sistema no modifica el historial ni los registros almacenados.
- Los sliders de peso y estatura en Ajustes se adaptan al sistema activo: rangos, etiquetas y valores de display se convierten en tiempo real.
- Formato: enteros para métricas redondeadas; pies y pulgadas para estatura imperial.

---

## Filtrado de alimentos (Paso 7 / #98, US37–US39)

### Bug corregido

**Síntoma:** cuando todas las alternativas de una categoría eran excluidas por las restricciones del usuario, el método `forGoalAndType` hacía fallback al catálogo sin filtrar y reintroducía alimentos excluidos.

**Causa:** la línea `if (safe.isNotEmpty) return safe;` devolvía `list` (sin filtrar) cuando `safe` estaba vacío.

**Corrección:** se elimina el fallback. Si `profile != null`, siempre se devuelve `list.where(_isSafe).toList()`, que puede ser una lista vacía.

**`dayMenu`:** ahora omite los tipos de comida sin alternativas en vez de intentar acceder a un índice de una lista vacía (lo que producía un crash).

**UI:** `_NutritionTabState._meals` detecta tipos sin alternativas y muestra el widget `_emptyFilterResult` con un mensaje claro. Si solo algunos tipos son excluidos, muestra los disponibles y un aviso al pie.

### Reglas de filtrado documentadas

| ID | Finalidad | Entradas | Condición | Resultado | Datos faltantes | Prioridad | Fuente | Limitaciones |
|---|---|---|---|---|---|---|---|---|
| F1 | Excluir alérgenos | `MealIdea.allergens`, `Profile.allergies` | Hay intersección entre ambas listas | Excluida | Lista vacía en el alimento → no se excluye | Alta (excl. estricta) | Enums del modelo | Sin validación clínica; depende de la declaración del usuario |
| F2 | Excluir azúcar alta para diabetes/prediabetes | `MealIdea.dietFlags`, `Profile.conditions` | `'highSugar'` en flags y diabetes o prediabetes en condiciones | Excluida | Flag ausente → no se excluye | Alta (excl. estricta) | Enums del modelo | Orientativo; "highSugar" no tiene umbral clínico definido |
| F3 | Excluir potasio alto para enfermedad renal | `MealIdea.dietFlags`, `Profile.conditions` | `'highPotassium'` en flags y enfermedad renal en condiciones | Excluida | Flag ausente → no se excluye | Alta (excl. estricta) | Enums del modelo | Orientativo; no reemplaza indicación médica |

Todas las reglas son de **exclusión estricta**: una coincidencia en cualquiera excluye el ítem. No hay relajación automática de restricciones.

Un alimento no marcado con un flag no se considera "seguro" por ausencia de información; simplemente no activa esa regla específica.

No se presentan contraindicaciones médicas inventadas. Las reglas reutilizan los enums documentados.

**Relación con US37–US39:** estos identificadores de Azure no han podido consultarse en esta implementación. La cobertura implementada corresponde a los tres tipos de restricción descritos en el modelo. Su correspondencia exacta con las historias de usuario queda pendiente de verificación.

---

## Estados de interfaz (Paso 5 / #123)

Pantallas afectadas:

### Ajustes (`settings_page.dart`)
- **Guardando:** botón deshabilitado con spinner.
- **Error recuperable:** banner rojo con botón "Reintentar".
- **Error de permisos:** banner rojo sin botón de reintento.
- **Confirmado:** indicador verde breve antes de cerrar la pantalla.

### Onboarding (`onboarding_page.dart`)
- **Guardando:** botón deshabilitado con spinner.
- **Error:** banner rojo integrado sobre el botón, con el mensaje completo.
- El borrador permanece en los campos al producirse un error.

### Nutrición (`nutrition_page.dart`)
- **Todas las comidas excluidas:** tarjeta con icono 🚫 y explicación.
- **Solo algunas categorías excluidas:** se muestran las disponibles y un aviso al pie.

---

## Pruebas ejecutadas y resultados

### Suite Flutter (adaptadores falsos)

| Suite | Pruebas | Resultado |
|---|---|---|
| `widget_test.dart` | 1 | ✅ |
| `account_isolation_test.dart` | 8 | ✅ |
| `nutrition_filter_test.dart` | 10 | ✅ |
| `unit_system_test.dart` | 13 | ✅ |
| `sync_state_test.dart` | 10 | ✅ |
| `persistence_restart_test.dart` | 17 | ✅ |
| **Total** | **59** | **✅ Todas pasan** |

Comando: `flutter test --no-pub`

### Suite de ediciones concurrentes (adaptadores controlables)

| Suite | Pruebas | Resultado |
|---|---|---|
| `concurrent_saves_test.dart` | 5 | ✅ |

Incluye: guardado secuencial (segundo gana), confirmación tardía fuera de orden — save2 prevalece gracias al contador `_saveGeneration` (regresión del bug corregido), cambio de cuenta durante guardado (epoch protege), save1 falla / save2 confirma (save2 gana), reintento automático fallido seguido de edición nueva (edición limpia `_kPendingWrite` correctamente).

### Pruebas de reglas Firestore (emulador real)

Java 21 instalado (`openjdk@21` via Homebrew). Firebase Emulator Suite activo (Auth :9099, Firestore :8080).

`npm run test:rules` → `node --test test/firestore/*.test.cjs`:

| Test | Resultado |
|---|---|
| owner creates and reads both profile documents | ✅ |
| anonymous and other users cannot read, write, delete or list private data | ✅ |
| trainer role grants no access to student health profile | ✅ |
| cannot self-assign roles or pollute schema on create and update | ✅ |
| validate types, ranges, size and immutable timestamps on updates | ✅ |
| orphan health documents cannot be created | ✅ |
| ordinary user cannot create a trainer group or impersonate its owner | ✅ |
| invitation lookup allows join without exposing group/member listings | ✅ |
| only group trainer assigns routine; ownership cannot change | ✅ |
| completion ownership and leaving a group enforce access | ✅ |
| **Total** | **10 / 10 ✅** |

### Pruebas de integración contra emulador (simulador iOS)

`flutter test integration_test/emulator_offline_test.dart --dart-define=USE_EMULATOR=true -d 497AFAF8...` (iPhone 18 Pro, iOS 27.0):

| Prueba | Resultado |
|---|---|
| Guardado básico: perfil llega a Firestore del emulador | ✅ |
| Dos ediciones consecutivas: la segunda sobreescribe a la primera | ✅ |
| Rechazo de permisos: usuario B no puede escribir perfil de usuario A | ✅ |
| AppStore con emulador: guardado confirma en Firestore | ✅ |
| **Total** | **4 / 4 ✅** |

Distinto de los tests con adaptadores falsos: estos tests usan Firebase SDK real conectado al emulador. Verificado vía REST API del emulador.

### Análisis estático

`flutter analyze --no-pub`: 0 errores, 0 warnings de producción. Solo avisos de deprecación (`withOpacity`, `activeColor`) que también estaban presentes en el Sprint 1 sin cambios del código de esta rama.

### Plataformas

| Plataforma | Compilación | Ejecución funcional |
|---|---|---|
| iOS (Xcode / simulador) | ✅ `flutter build ios --simulator --dart-define=USE_EMULATOR=true` exit 0 | ✅ App instalada y lanzada en iPhone 18 Pro. Verificación visual bloqueada por diálogo de notificaciones de SpringBoard (requiere interacción manual para descartar) |
| Android | No compilado | SDK Android no instalado actualmente en este Mac. No se verificó si estuvo instalado anteriormente. |
| Flutter test (host) | ✅ | ✅ 64 pruebas |
| Reglas Firestore (emulador) | ✅ | ✅ 10 pruebas |
| Integración iOS + emulador | ✅ | ✅ 4 pruebas |

---

## Recorrido manual de aceptación

Para completar la validación se requiere un dispositivo o simulador con Firebase real. Pasos:

1. Instalar pods iOS: `cd ios && pod install`.
2. Abrir en Xcode o `flutter run -d {device_id}`.
3. Registrar cuenta nueva → completar onboarding → reiniciar app → verificar mismo perfil.
4. Editar perfil con conexión → ver "Cambios guardados." → reiniciar → mismo perfil.
5. Editar perfil sin conexión (modo avión) → ver error recuperable → el formulario conserva los cambios.
6. Cambiar a unidades imperiales → los sliders muestran lb/in → guardar → reiniciar → imperial activo.
7. Activar alergia a lactosa → ir a Nutrición → comprobar que yogur y queso no aparecen.
8. Activar todas las alergias → ir a Nutrición → ver tarjeta "Sin alternativas disponibles".
9. Cerrar sesión → abrir otra cuenta → el tema e idioma del otro usuario no contaminan la nueva sesión.

---

## Pendientes y limitaciones

| Elemento | Descripción |
|---|---|
| Pruebas de emulador Firestore | Requieren Java 21 y Firebase CLI disponibles |
| Compilación iOS real | Requiere `pod install` + Xcode en entorno con iOS SDK |
| Compilación Android real | Requiere SDK Android instalado |
| Estado `pending` en modo offline SDK | El SDK puede encolar escrituras; el estado visual sería `pending` en vez de `failed` con persistencia offline activa |
| Resolución de conflictos entre dispositivos | Last-writer-wins; sin detección ni notificación al usuario |
| Historial de peso, comidas y entrenamientos en Firestore | Fuera del alcance de este sprint; siguen en SharedPreferences por UID |
| Correspondencia US37–US39 | Azure no consultable; cobertura documentada por regla implementada |
| Eliminación de cuentas | Fuera del alcance |
| Migración de datos con UID verificable | Mecanismo implementado; no existen datos con propiedad verificable en la instalación local actual |

---

## Relación con los elementos de Azure

| Paso | Azure | Implementado | Probado localmente |
|---|---|---|---|
| 1 — Onboarding y edición del perfil | #97, #120 | Sí | Sí (adaptadores) |
| 2 — Decisión de almacenamiento | #113 | Documentado | — |
| 3 — Migración segura e idempotente | #108 | Mecanismo base | Sí (sin datos a migrar) |
| 4 — Guardado, desconexión y reintentos | #112, #249 | Sí | Sí (adaptadores) |
| 5 — Estados de interfaz | #123 | Sí | Visual pendiente de dispositivo |
| 6 — Preferencias de tema y unidades | #124 | Sí | Sí (adaptadores) |
| 7 — Fallo de filtrado de alimentos | #98 | Sí (bug corregido) | Sí (10 pruebas) |
| 8 — Reglas de filtrado y pruebas | US37–US39 | Documentado | Sí (pruebas de filtrado) |
