import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';

import '../models/place.dart';

enum LocationResult { ok, denied, deniedForever, serviceDisabled, timeout }

/// Busca gimnasios y tiendas de suplementos/farmacias cercanos.
///
/// Los datos vienen empaquetados con la app (`assets/places/santiago_places.json`,
/// ~600 gimnasios y ~1300 farmacias/tiendas deportivas/de suplementos de la
/// Región Metropolitana, sacados de OpenStreetMap). Se probó primero con
/// consultas en vivo a la API pública de Overpass, pero ese servidor
/// gratuito resultó demasiado inestable (a veces tarda >20s o responde vacío
/// aunque sí haya datos) — igual que con el mapa offline de BiciRadar, es
/// más confiable empaquetar los datos que depender de un servicio externo
/// justo en el momento de usar la app.
class Places {
  Places._();

  static Map<String, List<NearbyPlace>>? _cache;

  static Future<Map<String, List<NearbyPlace>>> _data() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/places/santiago_places.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    _cache = {
      'gym': (json['gyms'] as List)
          .map((e) => _fromJson(e as Map<String, dynamic>, PlaceKind.gym))
          .toList(),
      'supplementStore': (json['supplements'] as List)
          .map((e) => _fromJson(e as Map<String, dynamic>, PlaceKind.supplementStore))
          .toList(),
    };
    return _cache!;
  }

  static NearbyPlace _fromJson(Map<String, dynamic> m, PlaceKind kind) => NearbyPlace(
        name: m['n'] as String,
        kind: kind,
        lat: (m['la'] as num).toDouble(),
        lon: (m['lo'] as num).toDouble(),
        address: m['a'] as String?,
      );

  /// Pide (o verifica) el permiso de ubicación, devuelve posición y motivo.
  ///
  /// Devuelve `(Position, LocationResult.ok)` en caso de éxito.
  /// En cualquier fallo devuelve `(null, <motivo>)` para que la UI
  /// pueda distinguir entre permiso negado permanente (→ openAppSettings),
  /// servicio apagado, o timeout.
  static Future<(Position?, LocationResult)> currentPositionWithReason() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (null, LocationResult.serviceDisabled);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      return (null, LocationResult.deniedForever);
    }
    if (perm == LocationPermission.denied) {
      return (null, LocationResult.denied);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return (pos, LocationResult.ok);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return (last, LocationResult.ok);
      return (null, LocationResult.timeout);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return (last, LocationResult.ok);
      return (null, LocationResult.timeout);
    }
  }

  /// Versión simplificada para compatibilidad retroactiva.
  static Future<Position?> currentPosition() async {
    final (pos, _) = await currentPositionWithReason();
    return pos;
  }

  /// Busca lugares del tipo pedido dentro de [radiusKm] alrededor de
  /// (lat, lon), ordenados por distancia. Instantáneo: no usa internet.
  static Future<List<NearbyPlace>> search({
    required double lat,
    required double lon,
    required PlaceKind kind,
    double radiusKm = 5,
  }) async {
    final all = (await _data())[kind == PlaceKind.gym ? 'gym' : 'supplementStore']!;
    final results = <NearbyPlace>[];
    for (final p in all) {
      final d = _haversineKm(lat, lon, p.lat, p.lon);
      if (d <= radiusKm) {
        results.add(NearbyPlace(
          name: p.name,
          kind: p.kind,
          lat: p.lat,
          lon: p.lon,
          address: p.address,
          distanceKm: d,
        ));
      }
    }
    results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return results;
  }

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double deg) => deg * (pi / 180);
}
