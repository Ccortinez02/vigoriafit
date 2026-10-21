# App Check — VigoriaFit

## Qué hace

Verifica que las llamadas a Firebase AI Logic provienen de builds legítimas de la app
(no de scripts o herramientas de terceros). Protege el endpoint de Gemini sin exponer
ninguna API key en el cliente.

## Estado actual

- Paquete `firebase_app_check: ^0.3.2` añadido al proyecto.
- **No activado** en consola ni en el código de arranque de la app.
- Activar sin registrar primero las plataformas bloquea todos los usuarios.

---

## Paso 0: Habilitar Firebase AI Logic (prerequisito)

1. Abre [Firebase Console](https://console.firebase.google.com) → proyecto `vigoria-fe224`
2. En el sidebar: **Build → AI Logic** (puede aparecer como "Gemini API" o "Firebase AI")
3. Haz clic en **Get started** → selecciona **Google AI (Gemini Developer API)**
4. Acepta los términos → **Enable**
5. El plan gratuito de Google AI **no requiere billing habilitado**. No toques Vertex AI.

---

## Paso 1: Configurar App Check por plataforma

### iOS — App Attest (dispositivos reales) + Debug (simulador)

1. Firebase Console → **App Check** → selecciona la app iOS
2. Proveedor: **App Attest** → guarda
3. Para simulador (sin chip Secure Enclave):
   - En Xcode → scheme → **Edit Scheme → Arguments Passed On Launch** → agrega `-FIRDebugEnabled`
   - Ejecuta la app en simulador → copia el token de debug del log de Xcode
   - Firebase Console → App Check → iOS → **Manage debug tokens** → **Add token**
4. **No pulsar "Enforce"** hasta validar en producción.

### Android — Play Integrity (dispositivos reales) + Debug (emulador)

1. Firebase Console → **App Check** → selecciona la app Android
2. Proveedor: **Play Integrity** → pega la clave SHA-256 de Play Console → guarda
3. Para emulador:
   - Mismo proceso de debug token que iOS
4. **No pulsar "Enforce"** hasta validar en producción.

**Gasto**: ninguno. App Attest y Play Integrity son gratuitos.

---

## Paso 2: Activar App Check en el código

En `lib/main.dart`, antes de `runApp()`:

```dart
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

// En initApp(), después de Firebase.initializeApp():
await FirebaseAppCheck.instance.activate(
  androidProvider: kDebugMode
      ? AndroidProvider.debug
      : AndroidProvider.playIntegrity,
  appleProvider: kDebugMode
      ? AppleProvider.debug
      : AppleProvider.appAttest,
);
```

> **Importante**: Registra el debug token del simulador ANTES de activar, o las
> llamadas al coach y al scanner fallarán con `permission-denied`.

---

## Paso 3: Enforce (solo cuando esté probado en producción)

1. Firebase Console → **App Check** → app iOS → **Enforce**
2. Firebase Console → **App Check** → app Android → **Enforce**
3. Con Enforce activo, las llamadas sin token válido son rechazadas por Firebase.

---

## Impacto en desarrollo local

| Escenario | Resultado sin App Check |
|---|---|
| Firebase AI Logic sin App Check | Funciona si Firebase Auth tiene sesión activa |
| App Check activado sin debug token | Llamadas fallan con `permission-denied` |
| App Check enforced + debug token | Funciona en simulador/emulador |
| App Check enforced + build de producción | Funciona con App Attest / Play Integrity |

---

## Sin App Check (estado actual del sprint)

Las llamadas a Firebase AI Logic funcionan si:
1. Firebase está inicializado (`Firebase.initializeApp`)
2. El usuario tiene sesión activa (`FirebaseAuth.instance.currentUser != null`)
3. Firebase AI Logic está habilitado en la consola (Paso 0)

App Check es **recomendado** para producción pero no es necesario para desarrollo local.
