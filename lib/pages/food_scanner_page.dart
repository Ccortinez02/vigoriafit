import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../core/ai_config.dart';
import '../core/theme.dart';
import '../data/food_catalog.dart';
import '../data/nutrition.dart';
import '../models/food_record.dart';
import '../services/ai_adapter.dart';
import '../services/store.dart';

const _uuid = Uuid();

enum _ScanState { idle, picking, analyzing, reviewing, saving }

class _EditableProposal {
  final String itemId;
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  String unit;
  FoodProposal proposal;
  bool fromCatalog;

  _EditableProposal(this.proposal)
      : itemId = _uuid.v4(),
        nameCtrl = TextEditingController(text: proposal.suggestedName),
        qtyCtrl = TextEditingController(text: proposal.estimatedQty.toStringAsFixed(0)),
        unit = proposal.estimatedUnit,
        fromCatalog = proposal.fromCatalog;

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
  }

  double get qty => double.tryParse(qtyCtrl.text) ?? proposal.estimatedQty;
  String get name => nameCtrl.text.trim();

  double? get kcal {
    final q = qty;
    final k = proposal.kcalEstimated;
    if (k == null) return null;
    final refQty = proposal.estimatedQty;
    return refQty > 0 ? k * q / refQty : k;
  }

  double? get protein {
    final q = qty;
    final p = proposal.proteinEstimated;
    if (p == null) return null;
    final refQty = proposal.estimatedQty;
    return refQty > 0 ? p * q / refQty : p;
  }

  double? get carbs {
    final q = qty;
    final c = proposal.carbsEstimated;
    if (c == null) return null;
    final refQty = proposal.estimatedQty;
    return refQty > 0 ? c * q / refQty : c;
  }

  double? get fat {
    final q = qty;
    final f = proposal.fatEstimated;
    if (f == null) return null;
    final refQty = proposal.estimatedQty;
    return refQty > 0 ? f * q / refQty : f;
  }
}

/// Escáner de comida con IA: saca/elige una foto, la IA analiza y el usuario
/// revisa y corrige antes de guardar.
class FoodScannerPage extends StatefulWidget {
  const FoodScannerPage({super.key});

  @override
  State<FoodScannerPage> createState() => _FoodScannerPageState();
}

class _FoodScannerPageState extends State<FoodScannerPage> {
  final _picker = ImagePicker();
  final _adapter = kUseGeminiAI ? GeminiAdapter() : MockAiAdapter(injectError: AiError.noConfig);

  _ScanState _state = _ScanState.idle;
  Uint8List? _bytes;
  AiException? _lastError;
  bool _consentShown = false;

  List<_EditableProposal> _proposals = [];
  MealType _mealType = MealType.almuerzo;
  final DateTime _consumedAt = DateTime.now();

  @override
  void dispose() {
    for (final p in _proposals) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _bytes = bytes;
        _lastError = null;
        _consentShown = false;
        _state = _ScanState.picking;
        for (final p in _proposals) {
          p.dispose();
        }
        _proposals = [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastError = const AiException(AiError.unknown, 'No pude abrir la imagen.'));
    }
  }

  Future<void> _analyze() async {
    if (_bytes == null) return;
    setState(() {
      _state = _ScanState.analyzing;
      _lastError = null;
    });
    try {
      final reqId = _uuid.v4();
      final res = await _adapter.analyzeFood(_bytes!, requestId: reqId);
      if (!mounted) return;
      setState(() {
        for (final p in _proposals) {
          p.dispose();
        }
        _proposals = res.proposals.map(_EditableProposal.new).toList();
        _state = _ScanState.reviewing;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = e;
        _state = _ScanState.idle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = const AiException(AiError.unknown);
        _state = _ScanState.idle;
      });
    }
  }

  Future<void> _save() async {
    final store = AppStore.instance;
    setState(() => _state = _ScanState.saving);

    final now = DateTime.now();
    final errors = <String>[];

    for (final ep in _proposals) {
      if (ep.name.isEmpty) continue;
      final qty = ep.qty;
      if (qty <= 0) continue;

      // Build FoodRecord from catalog or AI estimate
      FoodRecord record;
      if (ep.fromCatalog && ep.proposal.catalogId != null) {
        final cat = FoodCatalog.all.firstWhere(
          (c) => c.id == ep.proposal.catalogId,
          orElse: () => FoodCatalog.all.first,
        );
        record = FoodRecord(
          id:         ep.itemId,
          uid:        store.currentUid ?? '',
          foodId:     cat.id,
          foodName:   ep.name,
          refQty:     cat.refQty,
          refUnit:    cat.refUnit,
          kcalRef:    cat.kcal,
          proteinRef: cat.proteinG,
          carbsRef:   cat.carbsG,
          fatRef:     cat.fatG,
          quantity:   qty,
          unit:       ep.unit,
          mealType:   _mealType,
          consumedAt: _consumedAt,
          createdAt:  now,
          updatedAt:  now,
        );
      } else {
        // AI estimate: use estimated values as reference per qty
        final kcalRef    = ep.proposal.kcalEstimated    ?? 0;
        final proteinRef = ep.proposal.proteinEstimated  ?? 0;
        final carbsRef   = ep.proposal.carbsEstimated    ?? 0;
        final fatRef     = ep.proposal.fatEstimated      ?? 0;
        final refQty     = ep.proposal.estimatedQty;

        record = FoodRecord(
          id:         ep.itemId,
          uid:        store.currentUid ?? '',
          foodId:     'ai_${ep.itemId}',
          foodName:   ep.name,
          refQty:     refQty > 0 ? refQty : qty,
          refUnit:    ep.unit,
          kcalRef:    kcalRef,
          proteinRef: proteinRef,
          carbsRef:   carbsRef,
          fatRef:     fatRef,
          quantity:   qty,
          unit:       ep.unit,
          mealType:   _mealType,
          consumedAt: _consumedAt,
          createdAt:  now,
          updatedAt:  now,
          aiSource:   'AI estimate',
        );
      }

      try {
        await store.foods.add(record);
      } catch (_) {
        errors.add(ep.name);
      }
    }

    if (!mounted) return;
    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_proposals.length} alimento(s) registrado(s) 🍽️')),
      );
      Navigator.of(context).pop();
    } else {
      setState(() => _state = _ScanState.reviewing);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: ${errors.join(", ")}')),
      );
    }
  }

  String _errorMsg(AiException e) => switch (e.kind) {
    AiError.noConfig      => 'Necesitas configurar la IA para el escáner. Puedes registrar manualmente.',
    AiError.noNetwork     => 'Sin conexión. Revisa el internet e intenta de nuevo.',
    AiError.timeout       => 'La IA tardó demasiado. Intenta de nuevo.',
    AiError.invalidResponse => 'No pude leer la respuesta. La IA puede no haber reconocido la comida.',
    AiError.blocked       => 'No puedo analizar esa imagen.',
    _                     => 'Error inesperado. Intenta de nuevo.',
  };

  bool _canRetry(AiException e) =>
      e.kind == AiError.noNetwork || e.kind == AiError.timeout || e.kind == AiError.invalidResponse;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escáner de comida',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: SafeArea(
        top: false,
        child: _state == _ScanState.reviewing
            ? _reviewBody()
            : _scanBody(),
      ),
    );
  }

  Widget _scanBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            const Text('📸', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Saca una foto a tu plato y la IA estima sus nutrientes.',
                style: TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.35),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Imagen
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
              image: _bytes != null
                  ? DecorationImage(image: MemoryImage(_bytes!), fit: BoxFit.cover)
                  : null,
            ),
            child: _bytes == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restaurant_rounded, size: 44, color: AppColors.faint),
                        const SizedBox(height: 10),
                        Text('Aún no hay foto', style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),

        // Botones cámara / galería
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _state == _ScanState.analyzing ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded),
                label: const Text('Cámara'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _state == _ScanState.analyzing ? null : () => _pick(ImageSource.gallery),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppColors.line),
                  foregroundColor: AppColors.ink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                icon: const Icon(Icons.image_rounded),
                label: const Text('Galería'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_state == _ScanState.analyzing) _analyzingCard(),
        if (_lastError != null) _errorCard(_lastError!),
        if (_bytes != null && _state == _ScanState.picking && !_consentShown) _consentCard(),
      ],
    );
  }

  Widget _consentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'La foto se enviará a Google Gemini para análisis. '
            'No se guarda en nuestros servidores.',
            style: TextStyle(fontSize: 13, color: AppColors.brandDark, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() => _consentShown = true);
                _analyze();
              },
              child: const Text('Analizar foto'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _analyzingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.brand),
          ),
          const SizedBox(width: 14),
          Text('Analizando con IA…',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brandDark)),
        ],
      ),
    );
  }

  Widget _errorCard(AiException e) {
    final msg = _errorMsg(e);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.warn),
              const SizedBox(width: 12),
              Expanded(child: Text(msg, style: TextStyle(fontSize: 13, color: AppColors.ink))),
            ],
          ),
          const SizedBox(height: 12),
          if (e.kind == AiError.noConfig)
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Registrar manual'),
            )
          else if (_canRetry(e))
            ElevatedButton(
              onPressed: _analyze,
              child: const Text('Reintentar'),
            )
          else if (e.kind == AiError.blocked)
            OutlinedButton(
              onPressed: () => setState(() {
                _bytes = null;
                _lastError = null;
                _state = _ScanState.idle;
              }),
              child: const Text('Tomar otra foto'),
            ),
        ],
      ),
    );
  }

  // ── Pantalla de revisión ────────────────────────────────────────────────────

  Widget _reviewBody() {
    final totalKcal = _proposals.fold<double>(0, (s, p) => s + (p.kcal ?? 0));
    final totalProtein = _proposals.fold<double>(0, (s, p) => s + (p.protein ?? 0));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              Text('Revisa y corrige',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 4),
              Text('Edita nombre, cantidad y unidad antes de guardar.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 16),

              // Imagen pequeña
              if (_bytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(_bytes!, height: 160, width: double.infinity, fit: BoxFit.cover),
                ),
              const SizedBox(height: 16),

              // Ítems
              ...List.generate(_proposals.length, (i) => _proposalTile(i)),

              // Agregar alimento
              TextButton.icon(
                onPressed: () => setState(() {
                  _proposals.add(_EditableProposal(const FoodProposal(
                    suggestedName: '',
                    estimatedQty: 100,
                    estimatedUnit: 'g',
                  )));
                }),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Agregar alimento'),
              ),

              const SizedBox(height: 16),

              // Comida tipo
              _fieldLabel('Tipo de comida'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: MealType.values.map((m) => ChoiceChip(
                  label: Text('${m.emoji} ${m.label}'),
                  selected: _mealType == m,
                  onSelected: (_) => setState(() => _mealType = m),
                )).toList(),
              ),
              const SizedBox(height: 16),

              // Totales
              if (totalKcal > 0 || totalProtein > 0) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _totalChip('🔥', '${totalKcal.round()} kcal', 'Total'),
                      _totalChip('🥩', '${totalProtein.round()} g', 'Proteína'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),

        // Botones
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _state = _ScanState.idle;
                    _lastError = null;
                    _bytes = null;
                    _consentShown = false;
                    for (final p in _proposals) {
                      p.dispose();
                    }
                    _proposals = [];
                  }),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _state == _ScanState.saving ? null : _save,
                  child: _state == _ScanState.saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Guardar ${_proposals.length} alimento(s)'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _proposalTile(int i) {
    final ep = _proposals[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              Expanded(
                child: TextField(
                  controller: ep.nameCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Nombre',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.close_rounded, color: AppColors.muted),
                onPressed: () => setState(() {
                  _proposals[i].dispose();
                  _proposals.removeAt(i);
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 100,
                child: TextField(
                  controller: ep.qtyCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Cantidad',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: ep.unit,
                underline: const SizedBox(),
                onChanged: (v) => setState(() => ep.unit = v!),
                items: ['g', 'ml', 'unidad']
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
              ),
              const Spacer(),
              if (ep.fromCatalog)
                _badge('Del catálogo', AppColors.brand)
              else
                _badge('Estimado', AppColors.muted),
            ],
          ),
          if (ep.kcal != null || ep.protein != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (ep.kcal != null)
                  Text('🔥 ${ep.kcal!.round()} kcal',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                if (ep.protein != null)
                  Text('🥩 ${ep.protein!.round()} g prot',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                if (ep.carbs != null)
                  Text('🍞 ${ep.carbs!.round()} g carb',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                if (ep.fat != null)
                  Text('🥑 ${ep.fat!.round()} g gras',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _fieldLabel(String text) =>
      Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink));

  Widget _totalChip(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
  }
}
