/// Configuración pública de Firebase AI Logic — versionada en Git.
///
/// No contiene secretos. La autenticación usa Firebase Auth + App Check;
/// no se incrusta ninguna API key en el cliente.
///
/// Modelo: gemini-3.8-flash
/// — estable, último Gemini 3.x Flash.
/// — Soporta texto, visión y salida estructurada (responseSchema).
/// — Ver modelos disponibles: https://firebase.google.com/docs/ai-logic/models
/// — gemini-2.0-flash retirado el 1-jun-2026; gemini-4-argon requiere Blaze plan.
///
/// Firebase AI Logic siempre está disponible cuando Firebase está inicializado
/// y el servicio está habilitado en la consola.
/// Pasos de configuración: docs/APP_CHECK_SETUP.md
const String kGeminiModel = 'gemini-3.8-flash';

/// true cuando Firebase AI Logic debe usarse como backend de IA.
/// En esta arquitectura (Firebase AI Logic), siempre es true una vez que
/// Firebase está inicializado. El fallback local se activa cuando el servicio
/// no está disponible (AiError), no cuando esta flag es false.
const bool kUseGeminiAI = true;
