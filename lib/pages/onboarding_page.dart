import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/profile.dart';
import '../services/store.dart';

/// Onboarding en pasos: nombre → objetivo → nivel → datos del cuerpo.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pc = PageController();
  final _profile = Profile();
  final _name = TextEditingController();
  int _step = 0;
  static const _steps = 5;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    // El nombre ya viene del registro; se puede confirmar/editar.
    _name.text = AppStore.instance.profile.name;
  }

  @override
  void dispose() {
    _pc.dispose();
    _name.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && _name.text.trim().isEmpty) {
      _snack('Escribe tu nombre para empezar 🙂');
      return;
    }
    if (_step < _steps - 1) {
      setState(() => _step++);
      _pc.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step == 0) {
      // En el primer paso no hay paso anterior dentro del onboarding:
      // "volver" te saca al login (por si te equivocaste de cuenta).
      AppStore.instance.logout();
      return;
    }
    setState(() => _step--);
    _pc.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    if (_saving) return;
    _profile.name = _name.text.trim();
    if (_profile.targetWeightKg == 0)
      _profile.targetWeightKg = _profile.weightKg;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await AppStore.instance.completeOnboarding(_profile);
      // El "gate" de main.dart cambia a RootPage automáticamente.
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError =
              'No se pudo guardar el perfil. Revisa la conexión e inténtalo nuevamente.';
        });
      }
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Barra de progreso + volver
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.ink,
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: (_step + 1) / _steps,
                        minHeight: 7,
                        backgroundColor: AppColors.line,
                        color: AppColors.brand,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pc,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _stepName(),
                  _stepGoal(),
                  _stepLevel(),
                  _stepBody(),
                  _stepHealth(),
                ],
              ),
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5544B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFE5544B).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: Color(0xFFE5544B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _saveError!,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFE5544B)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _next,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          _step == _steps - 1 ? '¡Empezar!' : 'Continuar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: child,
  );

  Widget _title(String t, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          height: 1.15,
        ),
      ),
      const SizedBox(height: 8),
      Text(sub, style: TextStyle(fontSize: 14.5, color: AppColors.muted)),
      const SizedBox(height: 24),
    ],
  );

  // Paso 1: nombre
  Widget _stepName() => _pad(
    ListView(
      children: [
        const SizedBox(height: 20),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.brand, AppColors.brandDark],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Colors.white,
              size: 50,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: Text(
            'VigoriaFit',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Tu vida saludable, con IA',
            style: TextStyle(fontSize: 14.5, color: AppColors.muted),
          ),
        ),
        const SizedBox(height: 40),
        Text(
          '¿Cómo te llamas?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Tu nombre',
            prefixIcon: Icon(Icons.person_rounded),
          ),
        ),
      ],
    ),
  );

  // Paso 2: objetivo
  Widget _stepGoal() => _pad(
    ListView(
      children: [
        const SizedBox(height: 10),
        _title(
          '¿Cuál es tu objetivo?',
          'Con esto personalizo tus rutinas, '
              'comidas y consejos.',
        ),
        ...Goal.values.map(
          (g) => _choiceCard(
            selected: _profile.goal == g,
            emoji: g.emoji,
            title: g.label,
            subtitle: g.desc,
            onTap: () => setState(() => _profile.goal = g),
          ),
        ),
      ],
    ),
  );

  // Paso 3: nivel
  Widget _stepLevel() => _pad(
    ListView(
      children: [
        const SizedBox(height: 10),
        _title(
          '¿Cuál es tu nivel?',
          'Para ajustar la dificultad de tus '
              'entrenamientos.',
        ),
        ...Level.values.map(
          (l) => _choiceCard(
            selected: _profile.level == l,
            emoji: switch (l) {
              Level.beginner => '🌱',
              Level.intermediate => '💪',
              Level.advanced => '🏆',
            },
            title: l.label,
            subtitle: l.desc,
            onTap: () => setState(() => _profile.level = l),
          ),
        ),
      ],
    ),
  );

  // Paso 4: datos del cuerpo
  Widget _stepBody() => _pad(
    ListView(
      children: [
        const SizedBox(height: 10),
        _title(
          'Cuéntame de ti',
          'Con esto calculo tus calorías, proteína e '
              'IMC. Puedes cambiarlo luego.',
        ),
        _numberRow(
          'Edad',
          '${_profile.age}',
          'años',
          () => _pick(
            'Edad',
            _profile.age.toDouble(),
            12,
            90,
            1,
            (v) => _profile.age = v.round(),
          ),
        ),
        _numberRow(
          'Estatura',
          '${_profile.heightCm.round()}',
          'cm',
          () => _pick(
            'Estatura (cm)',
            _profile.heightCm,
            130,
            220,
            1,
            (v) => _profile.heightCm = v,
          ),
        ),
        _numberRow(
          'Peso actual',
          '${_profile.weightKg.round()}',
          'kg',
          () => _pick(
            'Peso actual (kg)',
            _profile.weightKg,
            35,
            200,
            1,
            (v) => _profile.weightKg = v,
          ),
        ),
        _numberRow(
          'Peso meta',
          '${_profile.targetWeightKg.round()}',
          'kg',
          () => _pick(
            'Peso meta (kg)',
            _profile.targetWeightKg,
            35,
            200,
            1,
            (v) => _profile.targetWeightKg = v,
          ),
        ),
        const SizedBox(height: 8),
        _numberRow(
          'Días por semana',
          '${_profile.daysPerWeek}',
          'días',
          () => _pick(
            'Días por semana',
            _profile.daysPerWeek.toDouble(),
            1,
            7,
            1,
            (v) => _profile.daysPerWeek = v.round(),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _profile.hasGym,
          activeColor: AppColors.brand,
          title: Text(
            'Tengo acceso a gimnasio',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
          subtitle: Text(
            'Si no, te doy rutinas para hacer en casa.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          onChanged: (v) => setState(() => _profile.hasGym = v),
        ),
      ],
    ),
  );

  // Paso 5: salud (opcional)
  Widget _stepHealth() => _pad(
    ListView(
      children: [
        const SizedBox(height: 10),
        _title(
          '¿Alguna condición o alergia?',
          'Con esto ajusto comidas, suplementos y ejercicios para que sean '
              'seguros para ti. Es opcional — puedes saltarlo.',
        ),
        Text(
          'Condiciones de salud',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: HealthCondition.values.map((c) {
            final selected = _profile.conditions.contains(c);
            return _multiChip(c.label, selected, () {
              setState(() {
                if (selected) {
                  _profile.conditions.remove(c);
                } else {
                  _profile.conditions.add(c);
                }
              });
            });
          }).toList(),
        ),
        const SizedBox(height: 22),
        Text(
          'Alergias / intolerancias',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: Allergy.values.map((a) {
            final selected = _profile.allergies.contains(a);
            return _multiChip(a.label, selected, () {
              setState(() {
                if (selected) {
                  _profile.allergies.remove(a);
                } else {
                  _profile.allergies.add(a);
                }
              });
            });
          }).toList(),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Esta información es orientativa y no reemplaza a un profesional '
            'de la salud. Ante cualquier duda médica, consulta a tu médico.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.muted,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _multiChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: AppColors.brandDark,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.brandDark : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceCard({
    required bool selected,
    required String emoji,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: AppColors.brand),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberRow(
    String label,
    String value,
    String unit,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(
    String title,
    double initial,
    double min,
    double max,
    double step,
    ValueChanged<double> onSet,
  ) async {
    double val = initial.clamp(min, max);
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${val.round()}',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand,
                  ),
                ),
                Slider(
                  value: val,
                  min: min,
                  max: max,
                  divisions: ((max - min) / step).round(),
                  activeColor: AppColors.brand,
                  onChanged: (v) => setSheet(() => val = v),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => onSet(val));
                      Navigator.pop(context);
                    },
                    child: const Text('Listo'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
