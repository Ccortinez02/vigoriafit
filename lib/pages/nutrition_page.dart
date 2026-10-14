import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../data/nutrition.dart';
import '../data/supplements.dart';
import '../models/logs.dart';
import '../models/place.dart';
import '../models/profile.dart';
import '../services/places.dart';
import '../services/store.dart';
import 'food_scanner_page.dart';
import 'places_page.dart';

class NutritionTab extends StatefulWidget {
  const NutritionTab({super.key});

  @override
  State<NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<NutritionTab> {
  int _tab = 0; // 0 = comidas, 1 = suplementos
  int _menuSeed = 0;
  List<NearbyPlace>? _nearbyStores; // null = aún cargando/no pedido

  @override
  void initState() {
    super.initState();
    _loadNearbyStores();
  }

  Future<void> _loadNearbyStores() async {
    final pos = await Places.currentPosition();
    if (pos == null || !mounted) return;
    final places = await Places.search(
      lat: pos.latitude,
      lon: pos.longitude,
      kind: PlaceKind.supplementStore,
      radiusKm: 5,
    );
    if (mounted) setState(() => _nearbyStores = places);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final p = AppStore.instance.profile;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  'Nutrición',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 14),

                // Escáner de comida IA (función estrella)
                _scannerCard(context),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _manualLogDialog,
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: const Text('Registrar manual'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.muted,
                    ),
                  ),
                ),
                _consumedToday(),
                const SizedBox(height: 16),

                // Metas del día
                Row(
                  children: [
                    _metric('🔥', '${p.dailyKcal}', 'kcal / día'),
                    const SizedBox(width: 10),
                    _metric('🥩', '${p.proteinGrams} g', 'proteína'),
                    const SizedBox(width: 10),
                    _metric('💧', '${p.waterGoal}', 'vasos agua'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Estimaciones para tu objetivo (${p.goal.label.toLowerCase()}). '
                  'Son orientativas.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.faint),
                ),
                const SizedBox(height: 18),

                // Selector
                _segmented(),
                const SizedBox(height: 16),

                if (_tab == 0) ..._meals(p.goal) else ..._supplements(p.goal),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _scannerCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const FoodScannerPage())),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.brand, AppColors.brandDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.photo_camera_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Escanear comida',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'IA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Foto a tu plato → calorías al instante',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Future<void> _manualLogDialog() async {
    final nameCtrl = TextEditingController();
    final kcalCtrl = TextEditingController();
    final protCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registrar comida',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: '¿Qué comiste?',
                    prefixIcon: Icon(Icons.restaurant_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: kcalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Calorías',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: protCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Proteína (g)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      final kcal = int.tryParse(kcalCtrl.text) ?? 0;
                      final prot = int.tryParse(protCtrl.text) ?? 0;
                      if (name.isEmpty || kcal <= 0) return;
                      AppStore.instance.addFood(FoodEntry(name, kcal, prot));
                      Navigator.pop(ctx);
                    },
                    child: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _consumedToday() {
    final s = AppStore.instance;
    final p = s.profile;
    final kcal = s.kcalToday;
    final foods = s.today.foods;
    if (foods.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Consumido hoy',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                '$kcal / ${p.dailyKcal} kcal · ${s.proteinToday} g prot',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (kcal / p.dailyKcal).clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: AppColors.line,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: 6),
          ...foods.asMap().entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.value.name,
                      style: TextStyle(fontSize: 12.5, color: AppColors.ink),
                    ),
                  ),
                  Text(
                    '${e.value.kcal} kcal',
                    style: TextStyle(fontSize: 12, color: AppColors.faint),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.faint,
                    ),
                    onPressed: () => s.removeFood(e.key),
                  ),
                ],
              ),
            ),
          ),
        ],
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
        children: [_segBtn('🍽️ Comidas', 0), _segBtn('💊 Suplementos', 1)],
      ),
    );
  }

  Widget _segBtn(String label, int i) {
    final active = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: active ? Border.all(color: AppColors.line) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: active ? AppColors.ink : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _meals(Goal goal) {
    final menu = Nutrition.dayMenu(
      goal,
      seed: _menuSeed,
      profile: AppStore.instance.profile,
    );
    final availableTypes = MealType.values.where((t) => menu.containsKey(t)).toList();
    return [
      Row(
        children: [
          Text(
            'Menú sugerido',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _menuSeed++),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Cambiar'),
            style: TextButton.styleFrom(foregroundColor: AppColors.brand),
          ),
        ],
      ),
      const SizedBox(height: 6),
      if (availableTypes.isEmpty)
        _emptyFilterResult()
      else ...[
        ...availableTypes.map((t) => _mealCard(t, menu[t]!)),
        if (availableTypes.length < MealType.values.length)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'Algunas comidas no tienen alternativas con tus restricciones actuales.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
      ],
    ];
  }

  Widget _emptyFilterResult() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Text('🚫', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            'Sin alternativas disponibles',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ninguna comida del catálogo es compatible con tus restricciones '
            'actuales. Revisa tus alergias y condiciones en Ajustes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _mealCard(MealType t, MealIdea m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset(
                'assets/food/${m.image}.jpg',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.emoji} ${t.label}',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    m.name,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _tag('${m.kcal} kcal', AppColors.brand),
                      const SizedBox(width: 6),
                      _tag('${m.protein} g prot', AppColors.protein),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _supplements(Goal goal) {
    final list = Supplements.forGoal(goal);
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              'Suplementos para tu objetivo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const PlacesPage(initialKind: PlaceKind.supplementStore),
              ),
            ),
            icon: const Icon(Icons.storefront_rounded, size: 16),
            label: const Text('Dónde comprar'),
            style: TextButton.styleFrom(foregroundColor: AppColors.brand),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Primero la comida real; los suplementos solo complementan.',
        style: TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
      const SizedBox(height: 14),
      _nearbyStoresCard(),
      const SizedBox(height: 14),
      ...list.map(
        (s) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  child: Image.asset(
                    'assets/supplements/${s.image}.jpg',
                    height: 130,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(s.emoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.benefit,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.ink,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: AppColors.mint,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.timing,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (s.cautionNote != null &&
                          s.cautionFor.any(
                            AppStore.instance.profile.conditions.contains,
                          )) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.warn.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: AppColors.warn,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.cautionNote!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.ink,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  /// Farmacias/tiendas más cercanas donde comprar suplementos, según la
  /// ubicación real del usuario (mismos datos que "Cerca de ti").
  Widget _nearbyStoresCard() {
    if (_nearbyStores == null) return const SizedBox.shrink();
    final nearest = _nearbyStores!.take(3).toList();
    if (nearest.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.mintSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 16,
                color: AppColors.mint,
              ),
              const SizedBox(width: 6),
              Text(
                'Cerca de ti ahora',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...nearest.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: () => launchUrl(
                  Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lon}',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        style: TextStyle(fontSize: 12.5, color: AppColors.ink),
                      ),
                    ),
                    Text(
                      '${p.distanceKm.toStringAsFixed(1)} km',
                      style: TextStyle(fontSize: 11.5, color: AppColors.faint),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: AppColors.faint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String emoji, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
