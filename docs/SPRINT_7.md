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
| – | Corrección modelo: `gemini-3.5-flash-lite` → `gemini-1.5-flash` | ✅ |
| – | Adaptador de IA con interfaz `AiAdapter` | ✅ |
| – | `GeminiAdapter`: cliente real `google_generative_ai ^0.4.6` | ✅ |
| – | `MockAiAdapter`: respuestas predefinidas + inyección de errores | ✅ |
| – | `CoachService`: historial (máx 10 pares), request IDs, fallback local | ✅ |
| – | Contexto del coach: campos limitados, sin nombre/UID/email | ✅ |
| #237 | Scanner: estado `idle→picking→analyzing→reviewing→saving` | ✅ |
| #238 | Fase reviewing: edición de nombre, cantidad y unidad | ✅ |
| #239 | Guardar desde reviewing con `FoodService.add()` | ✅ |
| #211 | Idempotencia: `operationId` por ítem evita duplicados | ✅ |
| #233 | Snap catálogo o `aiSource: 'AI estimate'` en `FoodRecord` | ✅ |
| #256 | qty editada en revisión se propaga correctamente al guardar | ✅ |
| #258 | Errores diferenciados en scanner y coach con mensajes por tipo | ✅ |
| #259 | Prompt coach incluye defensa contra jailbreak | ✅ |
| – | Aviso de consentimiento antes de enviar foto a Gemini | ✅ |
| – | Banner de disclaimer en coach (primera vez por sesión) | ✅ |
| – | `aiSource` en `FoodRecord` (backward compat: null = manual) | ✅ |
| – | `docs/SPRINT_7.md` | ✅ |
| #244 | Configuración específica Android (permisos de cámara) | ⏳ Pendiente |
| – | Integración real con API key de Gemini | ⏳ Pendiente (key vacía) |

## C. Arquitectura

```
lib/
  core/
    secrets.dart           # kGeminiApiKey (vacía), kGeminiModel ('gemini-1.5-flash')
  services/
    ai_adapter.dart        # AiAdapter, GeminiAdapter, MockAiAdapter, FoodProposal, FoodAnalysisResult
    coach_service.dart     # CoachService (historial, request IDs, contexto limitado)
    coach.dart             # Intacto: answer(), generateWeekPlan(), _ruleWeekPlan() (fallback)
  models/
    food_record.dart       # + aiSource: String? (campo opcional)
  pages/
    coach_page.dart        # CoachTab refactorizado con errores diferenciados
    food_scanner_page.dart # Flujo completo reviewing + save
```

**SDK**: `google_generative_ai: ^0.4.6` (instalado desde Sprint anterior)  
**Modelo**: `gemini-1.5-flash` — soporta visión, nivel gratuito en AI Studio, estable a julio 2025  
**Historial**: máximo 10 pares (20 mensajes) enviados al modelo; el más antiguo se descarta  
**Request IDs**: UUID v4 por mensaje; respuestas de un ID antiguo se descartan (evita condiciones de carrera)

## D. Datos y privacidad

**Enviado a Google Gemini cuando hay API key:**
- Foto del plato (bytes JPEG comprimidos a 70% calidad, max 1024px ancho)
- Prompt de análisis nutricional (texto en español)
- Mensajes de chat del usuario
- Contexto del usuario: objetivo, nivel, días/semana, equipo, condiciones de salud, alergias, racha, entrenos, kcal y agua del día

**Excluido explícitamente del contexto:**
- Nombre completo del usuario
- Correo electrónico
- UID de Firebase Auth
- Ubicación GPS
- Historial completo de registros
- Datos de otros usuarios

**Política de fotografías:**
- Sin API key configurada: el escáner muestra error `noConfig`, no se envía nada
- Con API key: se muestra aviso de consentimiento antes de cada nueva foto
- No se guardan las fotos en los servidores de VigoriaFit (solo se envían a Gemini)
- No se procesan fotos de personas, solo de alimentos

## E. Archivos modificados / creados

| Archivo | Acción |
|---|---|
| `lib/core/secrets.dart` | Modificado: modelo corregido |
| `lib/models/food_record.dart` | Modificado: campo `aiSource` opcional |
| `lib/services/ai_adapter.dart` | **Nuevo**: adaptador IA con errores tipificados |
| `lib/services/coach_service.dart` | **Nuevo**: CoachService con contexto limitado |
| `lib/pages/coach_page.dart` | Reescrito: errores diferenciados, disclaimer, retry |
| `lib/pages/food_scanner_page.dart` | Reescrito: flujo reviewing completo |
| `test/food_analysis_test.dart` | **Nuevo**: 17 tests del parseador y MockAdapter |
| `test/coach_test.dart` | **Nuevo**: 12 tests de CoachService |
| `docs/SPRINT_7.md` | **Nuevo**: este documento |

## F. Validaciones

```
flutter analyze lib/       → 0 errores, 0 warnings
flutter test               → 182/182 tests passed
node --test test/firestore/access.test.cjs → 18/18 passed
```

**Integración real con Gemini**: BLOQUEADA — `kGeminiApiKey` está vacío.  
El código es funcional pero no se puede probar end-to-end sin una API key real.

## G. Pendientes técnicos

- **#244 Android**: agregar permisos de cámara en `android/app/src/main/AndroidManifest.xml`
  ```xml
  <uses-permission android:name="android.permission.CAMERA"/>
  <uses-feature android:name="android.hardware.camera" android:required="false"/>
  ```
- **Integración real**: requiere API key de AI Studio (ver sección H)
- **Persistencia de historial**: el historial de chat no se persiste entre sesiones (v1)
- **Optimización de imágenes**: compresión JPEG actual funciona; no se implementó recorte inteligente
- **Streaming**: las respuestas de Gemini no usan streaming (se esperan completas)

## H. Acciones que necesita el usuario

1. **Obtener API key gratuita**:  
   Ir a [aistudio.google.com/apikey](https://aistudio.google.com/apikey) → "Create API key"  
   (No requiere tarjeta de crédito para el nivel free)

2. **Configurar la key**:  
   Abrir `lib/core/secrets.dart` y reemplazar:
   ```dart
   const String kGeminiApiKey = '';
   // por:
   const String kGeminiApiKey = 'TU_API_KEY_AQUI';
   ```

3. **Verificar el modelo**:  
   En AI Studio, confirmar que `gemini-1.5-flash` está disponible con esa key  
   (Alternativa: `gemini-1.5-pro` para respuestas de mayor calidad)

4. **Probar con datos sintéticos**:  
   - Abrir Coach → preguntar "¿qué como hoy?" → verificar respuesta en español
   - Abrir escáner → seleccionar foto de alimento → revisar propuestas → guardar
   - Verificar que el registro aparece en la pestaña Nutrición

## I. Criterio de cierre

El Sprint 7 está listo para pruebas de integración cuando:
- [ ] El usuario configuró `kGeminiApiKey` con una key válida
- [ ] El coach responde en español con el perfil del usuario
- [ ] El escáner analiza fotos y muestra la pantalla de revisión
- [ ] Los alimentos guardados aparecen en Nutrición con `aiSource: 'AI estimate'` cuando corresponde
- [ ] Permisos de Android configurados (#244)
