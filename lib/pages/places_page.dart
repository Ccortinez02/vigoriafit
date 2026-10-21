import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../models/place.dart';
import '../services/places.dart';

/// Encuentra gimnasios y tiendas de suplementos cerca del usuario, usando
/// datos abiertos de OpenStreetMap.
class PlacesPage extends StatefulWidget {
  final PlaceKind initialKind;
  const PlacesPage({super.key, this.initialKind = PlaceKind.gym});

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

enum _Status { idle, locating, loading, denied, deniedForever, serviceDisabled, error, ok }

// Barrios de Santiago con coordenadas aproximadas al centro de cada uno.
const _santiagoBarios = <String, (double, double)>{
  'Santiago Centro': (-33.4569, -70.6483),
  'Providencia': (-33.4327, -70.6093),
  'Las Condes': (-33.4106, -70.5703),
  'Ñuñoa': (-33.4569, -70.5988),
  'Maipú': (-33.5115, -70.7584),
  'La Florida': (-33.5194, -70.5883),
  'Puente Alto': (-33.6116, -70.5754),
  'Peñalolén': (-33.4795, -70.5338),
  'Macul': (-33.4835, -70.5998),
  'San Miguel': (-33.4990, -70.6523),
  'La Reina': (-33.4440, -70.5530),
  'Vitacura': (-33.3920, -70.5800),
  'Lo Barnechea': (-33.3527, -70.5221),
  'Huechuraba': (-33.3709, -70.6531),
  'Quilicura': (-33.3580, -70.7280),
  'Recoleta': (-33.4091, -70.6463),
  'Renca': (-33.4006, -70.7152),
  'Estación Central': (-33.4615, -70.6927),
  'Pudahuel': (-33.4340, -70.7619),
  'Lo Espejo': (-33.5211, -70.6964),
  'El Bosque': (-33.5559, -70.6558),
  'San Ramón': (-33.5374, -70.6394),
  'La Granja': (-33.5268, -70.6173),
  'La Cisterna': (-33.5252, -70.6618),
  'Pedro Aguirre Cerda': (-33.4925, -70.6706),
  'Cerrillos': (-33.4980, -70.7282),
  'Lo Prado': (-33.4485, -70.7238),
  'Cerro Navia': (-33.4290, -70.7363),
  'Conchalí': (-33.3912, -70.6805),
  'Independencia': (-33.4220, -70.6558),
};

class _PlacesPageState extends State<PlacesPage> {
  late PlaceKind _kind = widget.initialKind;
  _Status _status = _Status.idle;
  List<NearbyPlace> _places = [];
  Position? _pos;
  double _radius = 5;
  bool _manualMode = false;
  String? _selectedBarrio;
  final _addressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _status = _Status.locating);
    final (pos, result) = await Places.currentPositionWithReason();
    if (!mounted) return;
    if (result == LocationResult.ok && pos != null) {
      _pos = pos;
      _manualMode = false;
      await _search();
    } else {
      setState(() {
        switch (result) {
          case LocationResult.deniedForever:
            _status = _Status.deniedForever;
          case LocationResult.serviceDisabled:
            _status = _Status.serviceDisabled;
          default:
            _status = _Status.denied;
        }
      });
    }
  }

  Future<void> _search() async {
    if (_pos == null) return;
    setState(() => _status = _Status.loading);
    try {
      final places = await Places.search(
        lat: _pos!.latitude,
        lon: _pos!.longitude,
        kind: _kind,
        radiusKm: _radius.clamp(1, 30),
      );
      if (!mounted) return;
      setState(() {
        _places = places;
        _status = _Status.ok;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _Status.error);
    }
  }

  void _applyManualBarrio(String barrio) {
    final coords = _santiagoBarios[barrio];
    if (coords == null) return;
    _pos = Position(
      latitude: coords.$1,
      longitude: coords.$2,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    _manualMode = true;
    _search();
  }

  Future<void> _openDirections(NearbyPlace p) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lon}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cerca de ti',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: _segmented(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _radiusSelector(),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _segmented() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _segBtn('🏋️ Gimnasios', PlaceKind.gym),
          _segBtn('💊 Suplementos', PlaceKind.supplementStore),
        ],
      ),
    );
  }

  Widget _segBtn(String label, PlaceKind kind) {
    final active = _kind == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_kind == kind) return;
          setState(() => _kind = kind);
          if (_pos != null) _search();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: active ? Border.all(color: AppColors.line) : null,
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: active ? AppColors.ink : AppColors.muted)),
        ),
      ),
    );
  }

  static const _radiusOptions = [5.0, 10.0, 15.0, 20.0, 30.0];

  Widget _radiusSelector() {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _radiusOptions.map((r) {
          final active = _radius == r;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                if (active) return;
                setState(() => _radius = r);
                if (_pos != null) _search();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? AppColors.brand : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: active ? AppColors.brand : AppColors.line),
                ),
                alignment: Alignment.center,
                child: Text('${r.round()} km',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : AppColors.muted)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _body() {
    switch (_status) {
      case _Status.idle:
      case _Status.locating:
        return _center(spinner: true, text: 'Buscando tu ubicación…');
      case _Status.loading:
        return _center(spinner: true, text: 'Buscando cerca de ti…');
      case _Status.denied:
        return _center(
          icon: Icons.location_off_rounded,
          text: 'Se necesita permiso de ubicación.\nPuedes activarlo o elegir tu barrio.',
          extras: [
            ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _showManualPicker,
              child: const Text('Elegir barrio manualmente'),
            ),
          ],
        );
      case _Status.deniedForever:
        return _center(
          icon: Icons.location_disabled_rounded,
          text: 'El permiso de ubicación está bloqueado permanentemente. '
              'Actívalo en Ajustes o elige tu barrio.',
          extras: [
            ElevatedButton(
              onPressed: Geolocator.openAppSettings,
              child: const Text('Abrir Ajustes'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _showManualPicker,
              child: const Text('Elegir barrio manualmente'),
            ),
          ],
        );
      case _Status.serviceDisabled:
        return _center(
          icon: Icons.gps_off_rounded,
          text: 'El GPS está desactivado en tu dispositivo.\n'
              'Actívalo o elige tu barrio.',
          extras: [
            ElevatedButton(
              onPressed: () async {
                await Geolocator.openLocationSettings();
                _load();
              },
              child: const Text('Abrir ajustes GPS'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _showManualPicker,
              child: const Text('Elegir barrio manualmente'),
            ),
          ],
        );
      case _Status.error:
        return _center(
          icon: Icons.error_outline_rounded,
          text: 'Ocurrió un problema al buscar. Inténtalo de nuevo.',
          extras: [
            ElevatedButton(onPressed: _search, child: const Text('Reintentar')),
          ],
        );
      case _Status.ok:
        return Column(
          children: [
            if (_manualMode && _selectedBarrio != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.place_rounded, size: 14, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Text(
                      'Mostrando cerca de $_selectedBarrio',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _showManualPicker,
                      child: Text(
                        'Cambiar',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_places.isEmpty)
              Expanded(
                child: _center(
                  icon: Icons.search_off_rounded,
                  text:
                      'No encontré ${_kind == PlaceKind.gym ? 'gimnasios' : 'tiendas de suplementos'} '
                      'a ${_radius.round()} km.\nProbá un rango más amplio arriba.',
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      '${_places.length} ${_kind == PlaceKind.gym ? 'gimnasios' : 'lugares'} a ${_radius.round()} km o menos',
                      style: TextStyle(fontSize: 12, color: AppColors.faint)),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: _places.length,
                  itemBuilder: (_, i) => _placeCard(_places[i]),
                ),
              ),
            ],
          ],
        );
    }
  }

  void _showManualPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        String? selected = _selectedBarrio;
        final barrios = _santiagoBarios.keys.toList()..sort();
        return StatefulBuilder(
          builder: (ctx2, setSheet) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Elige tu barrio',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Santiago, Región Metropolitana',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      itemCount: barrios.length,
                      itemBuilder: (_, i) {
                        final b = barrios[i];
                        final isSelected = b == selected;
                        return GestureDetector(
                          onTap: () => setSheet(() => selected = b),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.brandSoft
                                  : AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.brand
                                    : AppColors.line,
                              ),
                            ),
                            child: Text(
                              b,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.brandDark
                                    : AppColors.ink,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selected == null
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              setState(() => _selectedBarrio = selected);
                              _applyManualBarrio(selected!);
                            },
                      child: const Text('Buscar en este barrio'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _center({
    bool spinner = false,
    IconData? icon,
    required String text,
    List<Widget>? extras,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: AppColors.brand),
              )
            else if (icon != null)
              Icon(icon, size: 42, color: AppColors.faint),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.35)),
            if (extras != null) ...[
              const SizedBox(height: 16),
              ...extras,
            ],
          ],
        ),
      ),
    );
  }

  Widget _placeCard(NearbyPlace p) {
    final isGym = p.kind == PlaceKind.gym;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isGym ? AppColors.brandSoft : AppColors.mintSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
                isGym
                    ? Icons.fitness_center_rounded
                    : Icons.medication_rounded,
                color: isGym ? AppColors.brand : AppColors.mint,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                if (p.address != null)
                  Text(p.address!,
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                Text('${p.distanceKm.toStringAsFixed(1)} km',
                    style: TextStyle(fontSize: 11.5, color: AppColors.faint)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _openDirections(p),
            icon: const Icon(Icons.directions_rounded, color: AppColors.brand),
          ),
        ],
      ),
    );
  }
}
