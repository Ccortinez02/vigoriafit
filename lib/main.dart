import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'core/theme.dart';
import 'debug/network_controller.dart';
import 'pages/auth_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/root_page.dart';
import 'services/notifications.dart';
import 'services/store.dart';

// Activado con --dart-define=USE_EMULATOR=true. Nunca activar en producción.
const _useEmulator = bool.fromEnvironment('USE_EMULATOR');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  StackTrace? startupStack;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (_useEmulator) {
      await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
      FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
      // Aplicar flags de prueba ANTES de cargar el perfil para que el estado
      // de red esté listo cuando _restoreAccount empiece a llamar a Firestore.
      await DebugNetworkController.applyStartupFlags();
      await DebugNetworkController.start();
    }
    await initializeDateFormatting('es', null);
    // En modo emulador no se solicitan permisos de notificaciones para no
    // bloquear la UI con el diálogo del sistema durante pruebas automatizadas.
    if (!_useEmulator) await Notifications.init();
    await AppStore.instance.load();
  } catch (e, st) {
    startupError = e;
    startupStack = st;
  }
  runApp(
    startupError != null
        ? _StartupErrorApp(error: startupError, stack: startupStack)
        : const VigoriaFitApp(),
  );
}

/// Si algo falla al iniciar (Firebase, datos guardados, notificaciones),
/// mostramos el error en pantalla en vez de dejar que el proceso se cierre
/// solo — así se puede diagnosticar con una simple captura de pantalla.
class _StartupErrorApp extends StatelessWidget {
  final Object? error;
  final StackTrace? stack;
  const _StartupErrorApp({required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF141110),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VigoriaFit no pudo iniciar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    '$error',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    '$stack',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VigoriaFitApp extends StatelessWidget {
  const VigoriaFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        return MaterialApp(
          key: ValueKey(AppStore.instance.currentUid),
          title: 'VigoriaFit',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: AppStore.instance.themeMode,
          builder: (context, child) {
            // La barra de navegación del sistema (abajo) y la de estado
            // (arriba) también deben seguir el tema, si no quedan negras
            // incluso en modo claro.
            SystemChrome.setSystemUIOverlayStyle(
              SystemUiOverlayStyle(
                systemNavigationBarColor: AppColors.bg,
                systemNavigationBarIconBrightness: AppColors.dark
                    ? Brightness.light
                    : Brightness.dark,
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: AppColors.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
            );
            return child!;
          },
          home: Builder(
            builder: (_) {
              final s = AppStore.instance;
              if (!s.loaded) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (s.sessionError != null) {
                return Scaffold(
                  body: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(s.sessionError!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: s.retryProfile,
                              child: const Text('Reintentar'),
                            ),
                            TextButton(
                              onPressed: s.logout,
                              child: const Text('Cerrar sesión'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
              if (!s.authed) return const AuthPage();
              if (!s.onboarded) return const OnboardingPage();
              return const RootPage();
            },
          ),
        );
      },
    );
  }
}
