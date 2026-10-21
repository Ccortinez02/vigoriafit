import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../data/food_catalog.dart';
import '../data/nutrition.dart';
import '../data/supplements.dart';
import '../models/food_record.dart';
import '../models/place.dart';
import '../models/profile.dart';
import '../models/water_record.dart';
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
  int _tab = 0; // 0=comidas, 1=agua, 2=suplementos
  int _menuSeed = 0;
  List<NearbyPlace>? _nearbyStores;

  @override
  void initState() {
    super.initState();
    _loadNearbyStores();
  }

  Future<void> _loadNearbyStores() async {
    final pos = await Places.currentPosition();
    if (pos == null || !mounted) return;
    final places = await Places.search(
      lat: pos.latitude, lon: pos.longitude,
      kind: PlaceKind.supplementStore, radiusKm: 5,
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
                Text('Nutrición',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 14),
                _scannerCard(context),
                const SizedBox(height: 14),
                _segmented(),
                const SizedBox(height: 16),
                if (_tab == 0) ..._foodTab(p)
                else if (_tab == 1) ..._waterTab()
                else ..._supplements(p.goal),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Pestañas ─────────────────────────────────────────────────────────────

  List<Widget> _foodTab(Profile p) {
    final s = AppStore.instance;
    final today = DateTime.now();
    final records = s.foods.forDay(today);
    final kcal    = s.foods.kcalForDay(today);
    final prot    = s.foods.proteinForDay(today);
    final carbs   = s.foods.carbsForDay(today);
    final fat     = s.foods.fatForDay(today);

    return [
      // Metas
      Row(children: [
        _metricTile('🔥', '${p.dailyKcal}', 'kcal / día'),
        const SizedBox(width: 10),
        _metricTile('🥩', '${p.proteinGrams} g', 'proteína'),
        const SizedBox(width: 10),
        _metricTile('💧', '${p.waterGoal}', 'vasos'),
      ]),
      const SizedBox(height: 6),
      Text('Estimaciones para tu objetivo (${p.goal.label.toLowerCase()}). Son orientativas.',
          style: TextStyle(fontSize: 11.5, color: AppColors.faint)),
      const SizedBox(height: 16),

      // Resumen del día
      _dailySummaryCard(kcal: kcal, prot: prot, carbs: carbs, fat: fat, goal: p.dailyKcal),
      const SizedBox(height: 12),

      // Lista de registros de hoy
      if (records.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Aún no registraste nada hoy.',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
        )
      else ...[
        Text('Registrado hoy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 6),
        ...records.map((r) => _foodRecordTile(r)),
      ],
      const SizedBox(height: 12),

      // Botón registrar
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _openFoodSheet(context),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Registrar comida'),
        ),
      ),
      const SizedBox(height: 24),

      // Menú sugerido
      Row(children: [
        Text('Menú sugerido', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const Spacer(),
        TextButton.icon(
          onPressed: () => setState(() => _menuSeed++),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Cambiar'),
          style: TextButton.styleFrom(foregroundColor: AppColors.brand),
        ),
      ]),
      const SizedBox(height: 6),
      ..._meals(p.goal),
    ];
  }

  List<Widget> _waterTab() {
    final s     = AppStore.instance;
    final today = DateTime.now();
    final totalMl = s.waters.totalMlForDay(today);
    final goalMl  = s.waterGoalMl;
    final records = s.waters.forDay(today);

    return [
      _waterSummaryCard(totalMl: totalMl, goalMl: goalMl),
      const SizedBox(height: 12),

      // Botones rápidos
      Row(children: [
        for (final ml in [200, 250, 500]) ...[
          Expanded(child: OutlinedButton(
            onPressed: () => _addWater(ml),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.water),
              foregroundColor: AppColors.water,
            ),
            child: Text('+$ml ml'),
          )),
          const SizedBox(width: 8),
        ],
        Expanded(child: ElevatedButton(
          onPressed: () => _customWaterDialog(context),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.water),
          child: const Text('Otro'),
        )),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        const Spacer(),
        TextButton.icon(
          onPressed: () => _adjustGoalDialog(context, goalMl),
          icon: const Icon(Icons.tune_rounded, size: 15),
          label: const Text('Ajustar meta'),
          style: TextButton.styleFrom(foregroundColor: AppColors.muted),
        ),
      ]),
      const SizedBox(height: 8),

      if (records.isEmpty)
        Text('No hay registros de agua hoy.',
            style: TextStyle(fontSize: 13, color: AppColors.muted))
      else ...[
        Text('Registros de hoy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 6),
        ...records.map((r) => _waterRecordTile(r)),
      ],
    ];
  }

  // ── Widgets de resumen ────────────────────────────────────────────────────

  Widget _dailySummaryCard({
    required double kcal, required double prot,
    required double carbs, required double fat, required int goal,
  }) {
    final fmtD = (double v) => v.toStringAsFixed(1);
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
          Row(children: [
            Text('Consumido hoy',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const Spacer(),
            Text('${kcal.toStringAsFixed(0)} / $goal kcal',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (kcal / goal).clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: AppColors.line,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _macroChip('P', '${fmtD(prot)} g', AppColors.protein),
            const SizedBox(width: 8),
            _macroChip('C', '${fmtD(carbs)} g', AppColors.brand),
            const SizedBox(width: 8),
            _macroChip('G', '${fmtD(fat)} g', AppColors.warn),
          ]),
        ],
      ),
    );
  }

  Widget _macroChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$label $value',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _waterSummaryCard({required int totalMl, required int goalMl}) {
    final pct = (totalMl / goalMl).clamp(0, 1).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.water_drop_rounded, color: AppColors.water),
          const SizedBox(width: 10),
          Expanded(child: Text('$totalMl ml de $goalMl ml',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink))),
          if (totalMl >= goalMl)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('¡Meta alcanzada!',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success)),
            ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 9,
            backgroundColor: AppColors.line,
            color: AppColors.water,
          ),
        ),
      ]),
    );
  }

  // ── Tiles de registros ────────────────────────────────────────────────────

  Widget _foodRecordTile(FoodRecord r) {
    return Dismissible(
      key: Key(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.danger,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Eliminar registro'),
            content: Text('¿Eliminar "${r.foodName}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => AppStore.instance.foods.delete(r.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(r.mealType.emoji,
                style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.foodName,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
            Text('${r.quantity.toStringAsFixed(0)} ${r.unit} · '
                '${r.kcal.toStringAsFixed(0)} kcal · '
                'P ${r.proteinG.toStringAsFixed(1)} g',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ])),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 16),
            color: AppColors.muted,
            visualDensity: VisualDensity.compact,
            onPressed: () => _openFoodSheet(context, editing: r),
          ),
        ]),
      ),
    );
  }

  Widget _waterRecordTile(WaterRecord r) {
    final fmt = DateFormat('HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(children: [
        const Icon(Icons.water_drop_rounded, size: 16, color: AppColors.water),
        const SizedBox(width: 8),
        Expanded(child: Text('${r.amountMl} ml · ${fmt.format(r.recordedAt)}',
            style: TextStyle(fontSize: 13, color: AppColors.ink))),
        IconButton(
          icon: const Icon(Icons.edit_rounded, size: 16),
          color: AppColors.muted,
          visualDensity: VisualDensity.compact,
          onPressed: () => _editWaterDialog(context, r),
        ),
        IconButton(
          icon: const Icon(Icons.delete_rounded, size: 16),
          color: AppColors.danger,
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Eliminar'),
                content: Text('¿Eliminar el registro de ${r.amountMl} ml?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
            );
            if (ok == true) AppStore.instance.waters.delete(r.id);
          },
        ),
      ]),
    );
  }

  // ── Acciones de agua ──────────────────────────────────────────────────────

  Future<void> _addWater(int ml) async {
    try {
      await AppStore.instance.waters.add(ml);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _customWaterDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cantidad personalizada'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Mililitros', suffixText: 'ml'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
        ],
      ),
    );
    if (ok != true) return;
    final ml = int.tryParse(ctrl.text.trim());
    if (ml == null || ml <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa una cantidad válida en ml.')));
      }
      return;
    }
    await _addWater(ml);
  }

  Future<void> _editWaterDialog(BuildContext context, WaterRecord r) async {
    final ctrl = TextEditingController(text: '${r.amountMl}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar registro de agua'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Mililitros', suffixText: 'ml'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final ml = int.tryParse(ctrl.text.trim());
    if (ml == null || ml <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa una cantidad válida en ml.')));
      }
      return;
    }
    try {
      await AppStore.instance.waters.update(r.id, amountMl: ml);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _adjustGoalDialog(BuildContext context, int currentGoal) async {
    final ctrl = TextEditingController(text: '$currentGoal');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Meta diaria de agua'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Mililitros', suffixText: 'ml'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final ml = int.tryParse(ctrl.text.trim());
    if (ml == null || ml <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa una cantidad válida.')));
      }
      return;
    }
    try {
      await AppStore.instance.setWaterGoalMl(ml);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ── Sheet de registro de comida ───────────────────────────────────────────

  Future<void> _openFoodSheet(BuildContext context, {FoodRecord? editing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _FoodLogSheet(editing: editing),
    );
  }

  // ── Scanner card ──────────────────────────────────────────────────────────

  Widget _scannerCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FoodScannerPage())),
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
        child: Row(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Escanear comida',
                  style: TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('IA',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 2),
            Text('Foto a tu plato → calorías al instante',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ]),
      ),
    );
  }

  // ── Segmented ─────────────────────────────────────────────────────────────

  Widget _segmented() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        _segBtn('🍽️ Comidas', 0),
        _segBtn('💧 Agua', 1),
        _segBtn('💊 Suplementos', 2),
      ]),
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
          child: Text(label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: active ? AppColors.ink : AppColors.muted,
              )),
        ),
      ),
    );
  }

  // ── Menús sugeridos ───────────────────────────────────────────────────────

  List<Widget> _meals(Goal goal) {
    final menu = Nutrition.dayMenu(goal, seed: _menuSeed, profile: AppStore.instance.profile);
    final types = MealType.values.where((t) => menu.containsKey(t)).toList();
    if (types.isEmpty) return [_emptyFilterResult()];
    return [
      ...types.map((t) => _mealCard(t, menu[t]!)),
      if (types.length < MealType.values.length)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            'Algunas comidas no tienen alternativas con tus restricciones actuales.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
    ];
  }

  Widget _emptyFilterResult() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: [
        const Text('🚫', style: TextStyle(fontSize: 32)),
        const SizedBox(height: 8),
        Text('Sin alternativas disponibles',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text('Ninguna comida del catálogo es compatible con tus restricciones actuales. '
            'Revisa tus alergias y condiciones en Ajustes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted)),
      ]),
    );
  }

  Widget _mealCard(MealType t, MealIdea m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image.asset('assets/food/${m.image}.jpg',
                width: 64, height: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t.emoji} ${t.label}',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(m.name,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 6),
            Row(children: [
              _tag('${m.kcal} kcal', AppColors.brand),
              const SizedBox(width: 6),
              _tag('${m.protein} g prot', AppColors.protein),
            ]),
          ])),
        ]),
      ),
    );
  }

  // ── Suplementos ───────────────────────────────────────────────────────────

  List<Widget> _supplements(Goal goal) {
    final list = Supplements.forGoal(goal);
    return [
      Row(children: [
        Expanded(child: Text('Suplementos para tu objetivo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink))),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PlacesPage(initialKind: PlaceKind.supplementStore))),
          icon: const Icon(Icons.storefront_rounded, size: 16),
          label: const Text('Dónde comprar'),
          style: TextButton.styleFrom(foregroundColor: AppColors.brand),
        ),
      ]),
      const SizedBox(height: 4),
      Text('Primero la comida real; los suplementos solo complementan.',
          style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
      const SizedBox(height: 14),
      _nearbyStoresCard(),
      const SizedBox(height: 14),
      ...list.map((s) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Image.asset('assets/supplements/${s.image}.jpg',
                height: 130, width: double.infinity, fit: BoxFit.cover),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(s.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.name,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink))),
                ]),
                const SizedBox(height: 10),
                Text(s.benefit,
                    style: TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.35)),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 14, color: AppColors.mint),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.timing,
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w500))),
                ]),
                if (s.cautionNote != null &&
                    s.cautionFor.any(AppStore.instance.profile.conditions.contains)) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warn.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warn),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.cautionNote!,
                          style: TextStyle(fontSize: 11.5, color: AppColors.ink, height: 1.3))),
                    ]),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      )),
    ];
  }

  Widget _nearbyStoresCard() {
    if (_nearbyStores == null) return const SizedBox.shrink();
    final nearest = _nearbyStores!.take(3).toList();
    if (nearest.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.mintSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.storefront_rounded, size: 16, color: AppColors.mint),
          const SizedBox(width: 6),
          Text('Cerca de ti ahora',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ]),
        const SizedBox(height: 8),
        ...nearest.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            onTap: () => launchUrl(
              Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lon}'),
              mode: LaunchMode.externalApplication,
            ),
            child: Row(children: [
              Expanded(child: Text(p.name, style: TextStyle(fontSize: 12.5, color: AppColors.ink))),
              Text('${p.distanceKm.toStringAsFixed(1)} km',
                  style: TextStyle(fontSize: 11.5, color: AppColors.faint)),
              Icon(Icons.chevron_right_rounded, size: 15, color: AppColors.faint),
            ]),
          ),
        )),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _metricTile(String emoji, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
        ]),
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Sheet para registrar o editar una comida
// ════════════════════════════════════════════════════════════════════════════

class _FoodLogSheet extends StatefulWidget {
  const _FoodLogSheet({this.editing});
  final FoodRecord? editing;

  @override
  State<_FoodLogSheet> createState() => _FoodLogSheetState();
}

class _FoodLogSheetState extends State<_FoodLogSheet> {
  static const _uuid = Uuid();

  final _searchCtrl = TextEditingController();
  final _qtyCtrl    = TextEditingController();

  FoodCatalogItem? _selected;
  MealType _mealType = MealType.almuerzo;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _selected = FoodCatalog.byId(e.foodId);
      _qtyCtrl.text = e.quantity.toStringAsFixed(
          e.quantity == e.quantity.roundToDouble() ? 0 : 1);
      _mealType = e.mealType;
    }
    _searchCtrl.addListener(() => setState(() {}));
    _qtyCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  double? get _qty {
    final v = double.tryParse(_qtyCtrl.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0 || !v.isFinite) return null;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppStore.instance.profile;
    final results = _selected == null
        ? FoodCatalog.search(_searchCtrl.text, profile: profile)
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.editing == null ? 'Registrar comida' : 'Editar registro',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 14),

              // Búsqueda o alimento seleccionado
              if (_selected == null) ...[
                TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Buscar alimento...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          })
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                if (results != null && results.isEmpty)
                  Text('Sin resultados para "${_searchCtrl.text}".',
                      style: TextStyle(fontSize: 13, color: AppColors.muted)),
                if (results != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final item = results[i];
                        return ListTile(
                          dense: true,
                          title: Text(item.name),
                          subtitle: Text('${item.preparation} · ${item.refQty.toStringAsFixed(0)} ${item.refUnit} → ${item.kcal.toStringAsFixed(0)} kcal'),
                          onTap: () {
                            setState(() => _selected = item);
                            _searchCtrl.clear();
                          },
                        );
                      },
                    ),
                  ),
              ] else ...[
                _selectedCard(_selected!),
                const SizedBox(height: 12),

                // Cantidad
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Cantidad',
                        suffixText: _selected!.refUnit,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<MealType>(
                      value: _mealType,
                      decoration: const InputDecoration(labelText: 'Momento'),
                      items: MealType.values.map((t) => DropdownMenuItem(
                        value: t,
                        child: Text('${t.emoji} ${t.label}'),
                      )).toList(),
                      onChanged: (v) { if (v != null) setState(() => _mealType = v); },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),

                // Preview de nutrientes
                if (_qty != null) _nutrientPreview(_selected!, _qty!),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => setState(() => _selected = null),
                  child: const Text('Cambiar alimento'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('Guardar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedCard(FoodCatalogItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.name,
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brandDark)),
        Text('${item.preparation} · ref: ${item.refQty.toStringAsFixed(0)} ${item.refUnit}',
            style: TextStyle(fontSize: 12, color: AppColors.brandDark)),
        const SizedBox(height: 4),
        Text('${item.kcal.toStringAsFixed(0)} kcal · '
            'P ${item.proteinG.toStringAsFixed(1)} g · '
            'C ${item.carbsG.toStringAsFixed(1)} g · '
            'G ${item.fatG.toStringAsFixed(1)} g',
            style: TextStyle(fontSize: 11.5, color: AppColors.brandDark)),
        Text('Fuente: ${item.source}',
            style: TextStyle(fontSize: 10.5, color: AppColors.brandDark.withValues(alpha: 0.7))),
      ]),
    );
  }

  Widget _nutrientPreview(FoodCatalogItem item, double qty) {
    final kcal  = item.kcal    * qty / item.refQty;
    final prot  = item.proteinG * qty / item.refQty;
    final carbs = item.carbsG  * qty / item.refQty;
    final fat   = item.fatG    * qty / item.refQty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _pvItem('Kcal', kcal.toStringAsFixed(0), AppColors.brand),
        _pvItem('Prot', '${prot.toStringAsFixed(1)} g', AppColors.protein),
        _pvItem('Carbs', '${carbs.toStringAsFixed(1)} g', AppColors.brand),
        _pvItem('Grasa', '${fat.toStringAsFixed(1)} g', AppColors.warn),
      ]),
    );
  }

  Widget _pvItem(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      Text(label, style: TextStyle(fontSize: 10, color: AppColors.muted)),
    ]);
  }

  Future<void> _save() async {
    final item = _selected;
    if (item == null) return;
    final qty = _qty;
    if (qty == null) {
      setState(() => _error = 'Ingresa una cantidad válida mayor que 0.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final now  = DateTime.now();
      final uid  = AppStore.instance.currentUid ?? '';
      final s    = AppStore.instance.foods;
      final edit = widget.editing;
      if (edit != null) {
        final updated = edit.copyWith(
          quantity:   qty,
          mealType:   _mealType,
          updatedAt:  now,
        );
        await s.update(updated);
      } else {
        final record = FoodRecord(
          id:         _uuid.v4(),
          uid:        uid,
          foodId:     item.id,
          foodName:   item.name,
          refQty:     item.refQty,
          refUnit:    item.refUnit,
          kcalRef:    item.kcal,
          proteinRef: item.proteinG,
          carbsRef:   item.carbsG,
          fatRef:     item.fatG,
          quantity:   qty,
          unit:       item.refUnit,
          mealType:   _mealType,
          consumedAt: now,
          createdAt:  now,
          updatedAt:  now,
        );
        await s.add(record);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = '$e'; });
    }
  }
}
