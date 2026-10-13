import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/store.dart';

/// Servidor HTTP de prueba exclusivo de modo emulador (USE_EMULATOR=true).
///
/// Escucha en loopback:7777 y permite controlar la conectividad de Firestore
/// y el AppStore desde scripts externos sin modificar el firewall del sistema.
///
/// Rutas disponibles (GET):
///   /firestore/disable          → FirebaseFirestore.instance.disableNetwork()
///   /firestore/enable           → FirebaseFirestore.instance.enableNetwork()
///   /firestore/status           → {"network_enabled": bool}
///   /firestore/set_start_offline → persiste el flag en SharedPreferences para
///                                  que el próximo arranque empiece sin red
///   /app/retry_profile          → AppStore.instance.retryProfile() (no blocking)
///
/// NO compilar ni activar en producción.
class DebugNetworkController {
  static const _port = 7777;
  static const _kStartOffline = '_debug_start_offline';

  static HttpServer? _server;
  static bool _networkEnabled = true;

  /// Lleva el SDK a un estado de red conocido (habilitado) y luego aplica
  /// el flag de inicio-offline si estaba programado.
  ///
  /// El enableNetwork() inicial es necesario porque en un hot restart de Dart
  /// la instancia nativa de Firebase persiste: _networkEnabled se resetea al
  /// valor por defecto (true) pero el SDK nativo puede tener disableNetwork()
  /// activo de una llamada anterior. Sin el enableNetwork() explícito, el
  /// estado real y el flag Dart divergen silenciosamente.
  ///
  /// Debe llamarse ANTES de AppStore.instance.load().
  static Future<void> applyStartupFlags() async {
    // Sincronizar al estado conocido antes de leer el flag.
    await FirebaseFirestore.instance.enableNetwork();
    _networkEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kStartOffline) == true) {
      await prefs.remove(_kStartOffline);
      await FirebaseFirestore.instance.disableNetwork();
      _networkEnabled = false;
    }
  }

  /// Inicia el servidor HTTP. Debe llamarse después de applyStartupFlags()
  /// y antes de AppStore.instance.load() para que el servidor esté disponible
  /// durante la restauración del perfil.
  static Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    _server!.listen(_handle, onError: (_) {});
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static Future<void> _handle(HttpRequest req) async {
    req.response.headers.add('Content-Type', 'application/json');
    try {
      switch (req.uri.path) {
        case '/firestore/disable':
          await FirebaseFirestore.instance.disableNetwork();
          _networkEnabled = false;
          req.response.write('{"network":"disabled"}');
        case '/firestore/enable':
          await FirebaseFirestore.instance.enableNetwork();
          _networkEnabled = true;
          req.response.write('{"network":"enabled"}');
        case '/firestore/status':
          req.response
              .write('{"network_enabled":${_networkEnabled.toString()}}');
        case '/firestore/set_start_offline':
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_kStartOffline, true);
          req.response.write('{"scheduled":true}');
        case '/app/retry_profile':
          // No esperamos a que termine: respondemos inmediatamente.
          unawaited(AppStore.instance.retryProfile());
          req.response.write('{"triggered":true}');
        default:
          req.response.statusCode = HttpStatus.notFound;
          req.response.write('{"error":"not_found"}');
      }
    } catch (e) {
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.write('{"error":"${e.toString().replaceAll('"', "'")}"}');
    } finally {
      await req.response.close();
    }
  }
}
