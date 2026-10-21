# Sprint 7 — Coach y reconocimiento de comidas con IA

## A. Estado general

| Campo | Valor |
|---|---|
| Rama | `ccortinez/sprint7-coach-reconocimiento-ia` |
| Base | `main` (commit `11a9b29`, Sprint 6 incluido) |
| Estado | Implementado localmente — **sin push ni PR por instrucción del usuario** |

## B. Ítems implementados

| ID | Descripción | Estado |
|---|---|---|
| – | Migración a Firebase AI Logic (`firebase_ai: ^2.3.0`) | ✅ |
| – | Eliminada API key del cliente (`kGeminiApiKey` removido) | ✅ |
| – | Modelo actualizado a `gemini-3.8-flash` (estable, último Gemini 3.x Flash) | ✅ |
| – | Adaptador de IA con interfaz `AiAdapter` | ✅ |
| – | `GeminiAdapter`: cliente Firebase AI Logic, sin API key en binario | ✅ |
| – | `MockAiAdapter`: respuestas predefinidas + inyección de errores | ✅ |
| – | `CoachService`: historial (máx 10 pares), request IDs, fallback local | ✅ |
| – | Contexto del coach: sin nombre/UID/email/condiciones/alergias | ✅ |
| #228 | Historial en memoria (v1): `clearHistory()` inicia nueva conv., `dispose()` invalida pendientes | ✅ (documentado) |
| #237 | Scanner: estado `idle→picking→analyzing→reviewing→saving` + permisos iOS | ✅ |
| #238 | Fase reviewing: edición de nombre, cantidad y unidad | ✅ |
| #239 | Guardar desde reviewing con `FoodService.add()` | ✅ |
| #211 | Idempotencia: ID estable por ítem evita duplicados | ✅ |
| #233 | Snap catálogo o `aiSource: 'AI estimate'` en `FoodRecord` | ✅ |
| #256 | Flujo completo: qty editada → FoodRecord → totales una sola vez | ✅ |
| #258 | Errores diferenciados en scanner y coach con mensajes por tipo | ✅ |
| #259 | Comportamiento ante jailbreak: `blocked` → mensaje de error, sin fallback | ✅ |
| – | Aviso de consentimiento antes de enviar foto al proveedor | ✅ |
| – | Banner de disclaimer en coach (primera vez por sesión) | ✅ |
| – | `aiSource` en `FoodRecord` (backward compat: null = manual) | ✅ |
| – | App Check: paquete añadido, documentado, NO activado en producción | ✅ |
| – | `docs/APP_CHECK_SETUP.md` | ✅ |
| – | `docs/SPRINT_7.md` | ✅ |
| #244 | Pertenece a **hidratación** (no al scanner de comida). Ver sprint correspondiente. | — |
| – | Integración real con Gemini | ⏳ Pendiente (requiere habilitación en Firebase Console) |

## C. Arquitectura

```
lib/
  core/
    secrets.dart           # kGeminiModel ('gemini-3.8-flash'); sin API key
  services/
    ai_adapter.dart        # AiAdapter, GeminiAdapter (firebase_ai), MockAiAdapter
    coach_service.dart     # CoachService: historial, request IDs, contexto sin PII
    coach.dart             # answer(), generateWeekPlan(), _ruleWeekPlan() (fallback local)
  models/
    food_record.dart       # + aiSource: String? (campo opcional)
  pages/
    coach_page.dart        # Errores diferenciados, disclaimer, retry
    food_scanner_page.dart # Flujo completo reviewing + save
docs/
  APP_CHECK_SETUP.md       # Pasos de consola para App Check (sin gasto)
```

**SDK**: `firebase_ai: ^2.3.0` (Firebase AI Logic — Google AI backend)  
**Modelo**: `gemini-3.8-flash` — estable, último Gemini 3.x Flash, soporta texto + visión + salida estructurada (responseSchema)  
**Modelos retirados**: `gemini-1.5-flash` y `gemini-1.5-pro` (jul-2025), `gemini-2.0-flash` (jun-2026). Ver https://firebase.google.com/docs/ai-logic/models  
**Sin API key en cliente**: la autenticación la gestiona Firebase Auth; no hay secretos en el binario  
**Historial**: máximo 10 pares (20 mensajes) enviados al modelo; el más antiguo se descarta  
**Request IDs**: UUID v4 por mensaje; respuestas de un ID antiguo se descartan  

## D. Datos y privacidad

**Enviado a Google (vía Firebase AI Logic cuando el servicio está habilitado):**
- Foto del plato (bytes JPEG)
- Prompt de análisis nutricional (texto en español)
- Mensajes de chat del usuario
- Contexto acotado: objetivo, nivel, días/semana, equipo, racha, entrenos semana, kcal del día, agua del día

**Excluido explícitamente del contexto enviado al proveedor:**
- Nombre completo del usuario
- Correo electrónico
- UID de Firebase Auth
- Condiciones de salud (usadas solo en filtros locales del catálogo)
- Alergias (usadas solo en filtros locales del catálogo)
- Ubicación GPS
- Historial completo de registros

**Política de fotografías:**
- Sin Firebase AI Logic habilitado: el escáner muestra error `noConfig`, no se envía nada
- Con servicio habilitado: se muestra aviso de consentimiento antes de enviar cada foto
- No se guardan fotos en servidores de VigoriaFit (solo se envían a Google vía Firebase)

## E. Archivos modificados / creados

| Archivo | Acción |
|---|---|
| `pubspec.yaml` | `firebase_ai: ^2.3.0`, `firebase_app_check: ^0.3.2`; removido `google_generative_ai` |
| `lib/core/secrets.dart` | Solo `kGeminiModel`; `kGeminiApiKey` eliminado; `kUseGeminiAI = true` constante |
| `lib/models/food_record.dart` | Campo `aiSource: String?` opcional |
| `lib/services/ai_adapter.dart` | Reescrito: usa `firebase_ai`; manejo de `FirebaseAIException` |
| `lib/services/coach.dart` | Removidos `reply()`, `analyzeFood()`, `_askGemini*`; mantenidos `answer()`, `generateWeekPlan()`, `_ruleWeekPlan()` |
| `lib/services/coach_service.dart` | Condiciones/alergias excluidas del contexto; docstring #228 en `_history` |
| `lib/services/food_service.dart` | `_syncRecord()` envuelto en try-catch (robusto ante Firebase no inicializado) |
| `lib/pages/coach_page.dart` | Errores diferenciados, disclaimer descartable, badge "Respuesta local", retry |
| `lib/pages/food_scanner_page.dart` | Flujo reviewing: edición nombre/qty/unidad, badges, totales en tiempo real, consentimiento foto |
| `ios/Runner/Info.plist` | `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription` |
| `test/food_analysis_test.dart` | Tests #256a (proporcional), #256b (FoodService integración + idempotencia), #258 |
| `test/coach_test.dart` | Tests #259: comportamiento `blocked`, privacidad de contexto |
| `docs/APP_CHECK_SETUP.md` | **Nuevo**: instrucciones de consola por plataforma |
| `docs/SPRINT_7.md` | Este documento |

## F. Validaciones

```
flutter analyze lib/       → 0 errores (26 info/warning preexistentes en otros archivos)
flutter test               → 192/192 tests passed
node --test test/firestore/access.test.cjs → 18/18 passed
```

**Integración real con Gemini**: BLOQUEADA — requiere habilitar Firebase AI Logic en la consola  
(ver sección H). Sin esa habilitación, `GeminiAdapter` lanzará `FirebaseAIException` en producción  
y el coach caerá al fallback local. En tests, `MockAiAdapter` cubre todos los casos.

## G. Estado individual de issues

| Issue | Estado | Evidencia |
|---|---|---|
| **#256** | ✅ Probado flujo completo | Test #256a: cálculo proporcional. Test #256b: `FoodService.add()` con qty editada, `kcalForDay` correcto, doble guardado no duplica |
| **#257** | ✅ (Sprint 5) | Reglas Firestore y `WaterService.update()` ya cubrían este caso |
| **#258** | ✅ MockAdapter con `noNetwork` lanza `AiException` | Test en `food_analysis_test.dart` |
| **#259** | ✅ Comportamiento probado con MockAdapter | `blocked` → texto de error específico, no cae en fallback local. `noNetwork` → fallback local. Instrucción en systemPrompt verificada por test separado |
| **#228** | ✅ Documentado alcance v1 | Docstring en `_history`; `clearHistory()` = nueva conv.; `dispose()` invalida pendientes; sin datos en Firestore |
| **#237** | ✅ Permisos iOS añadidos | `NSCameraUsageDescription` y `NSPhotoLibraryUsageDescription` en Info.plist. Flujo `picking→analyzing→reviewing` |
| **#244** | — | Pertenece a **hidratación**, no al scanner. No es un pendiente de este sprint. |

## H. Acciones pendientes del usuario (sin gasto)

### 1. Habilitar Firebase AI Logic en la consola

1. [Firebase Console](https://console.firebase.google.com) → proyecto `vigoria-fe224`
2. **Build → AI Logic** (o "Gemini API")
3. **Get started** → **Google AI (Gemini Developer API)** → **Enable**
4. El plan gratuito de Google AI **no requiere billing**. No seleccionar Vertex AI.

### 2. Registrar debug token de App Check (para probar con IA real en simulador)

Ver `docs/APP_CHECK_SETUP.md` — pasos completos sin gasto.

### 3. Validar permisos iOS en simulador real

Los permisos se declaran en `Info.plist`. Para confirmar que el diálogo aparece:
- Ejecutar en simulador iOS (no en test headless)
- Abrir el scanner → elegir galería o cámara → el SO debe pedir permiso

### 4. Configurar permisos Android (si se usa en Android)

En `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-feature android:name="android.hardware.camera" android:required="false"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
```
El plugin `image_picker` gestiona el permiso en runtime a partir de Android 13.

## I. Criterio de cierre

**INTEGRACIÓN REAL NO VALIDADA** — pendiente de habilitar Firebase AI Logic en consola y ejecutar
solicitudes contra el modelo `gemini-3.8-flash` con datos sintéticos. No declarar integración válida
hasta ejecutar correctamente:

- [ ] Firebase AI Logic habilitado en Firebase Console → Google AI → `gemini-3.8-flash` (Paso H.1)
- [ ] Consulta de texto al coach con perfil sintético → respuesta en español
- [ ] Foto de alimento sintética → JSON con `items` validado por `_parseAnalysis`
- [ ] Respuesta estructurada del análisis coincide con el `_foodResponseSchema` declarado
- [ ] Coach responde sin incluir condiciones de salud ni alergias (verificado por test de privacidad)
- [ ] Scanner muestra pantalla de revisión con alimentos editables antes de guardar
- [ ] Alimentos guardados aparecen en Nutrición con `aiSource: 'AI estimate'`
- [ ] Doble guardado no duplica registros en Nutrición
- [ ] Mensaje de jailbreak devuelve error `blocked` → texto específico (sin consejo local)

**Si falla al conectar:** distinguir el error con `AiError`:
- `noConfig` → Firebase AI Logic no habilitado, App Check bloqueando, o modelo no disponible
- `quota` → límite gratuito alcanzado
- `noNetwork` → sin conexión
- `blocked` → imagen o mensaje rechazado por filtro de contenido
- `invalidResponse` → JSON fuera del esquema esperado

**Streaming** y **recorte inteligente de imágenes** no son criterios de aceptación de este sprint.
