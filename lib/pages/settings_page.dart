import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/profile.dart';
import '../services/notifications.dart';
import '../services/store.dart';
import '../services/sync_state.dart';
import '../services/unit_system.dart';
import 'join_group_page.dart';
import 'trainer_page.dart';

const _themeLabels = {
  ThemeMode.system: 'Sistema',
  ThemeMode.light: 'Claro',
  ThemeMode.dark: 'Oscuro',
};

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Profile _p;
  late final TextEditingController _name;
  bool _saving = false;
  SyncState _syncState = SyncState.idle;

  @override
  void initState() {
    super.initState();
    _p = AppStore.instance.profile.copy();
    _name = TextEditingController(text: _p.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe tu nombre para guardar.')),
      );
      return;
    }
    _p.name = name;
    setState(() {
      _saving = true;
      _syncState = SyncState.saving;
    });
    try {
      await AppStore.instance.saveProfile(_p);
      if (!mounted) return;
      setState(() => _syncState = SyncState.confirmed);
      // Breve pausa para que el usuario vea "Cambios guardados." antes de salir.
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final isPermission = e.toString().contains('PERMISSION_DENIED') ||
          e.toString().contains('permission-denied');
      setState(() {
        _syncState = isPermission ? SyncState.rejected : SyncState.failed;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Todo el contenido escucha AppStore para que, si el usuario cambia de
    // tema aquí mismo, los colores (etiquetas, fondos) se actualicen al
    // instante en vez de quedarse con los del tema anterior.
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ajustes',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _label('Apariencia'),
          const SizedBox(height: 10),
          _themeSelector(),
          const SizedBox(height: 16),
          _unitsSelector(),
          const SizedBox(height: 26),

          _trainerSection(),
          const SizedBox(height: 26),

          _label('Recordatorios'),
          const SizedBox(height: 10),
          _reminders(),
          const SizedBox(height: 26),

          _label('Tu perfil'),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              prefixIcon: Icon(Icons.person_rounded),
            ),
          ),
          const SizedBox(height: 18),

          _sub('Objetivo'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: Goal.values
                .map(
                  (g) => _chip(
                    '${g.emoji} ${g.label}',
                    _p.goal == g,
                    () => setState(() => _p.goal = g),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),

          _sub('Nivel'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: Level.values
                .map(
                  (l) => _chip(
                    l.label,
                    _p.level == l,
                    () => setState(() => _p.level = l),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _p.hasGym,
            activeColor: AppColors.brand,
            title: Text(
              'Tengo acceso a gimnasio',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            onChanged: (v) => setState(() => _p.hasGym = v),
          ),
          _sliderTile(
            'Días por semana',
            _p.daysPerWeek.toDouble(),
            1,
            7,
            (v) => setState(() => _p.daysPerWeek = v.round()),
            '${_p.daysPerWeek}',
          ),

          const SizedBox(height: 26),
          _sub('Tu cuerpo'),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final u = AppStore.instance.units;
            return Column(
              children: [
                _sliderTile(
                  'Edad',
                  _p.age.toDouble(),
                  12,
                  90,
                  (v) => setState(() => _p.age = v.round()),
                  '${_p.age} años',
                ),
                _sliderTile(
                  'Estatura',
                  u.displayHeight(_p.heightCm),
                  u.heightMin,
                  u.heightMax,
                  (v) => setState(() => _p.heightCm = u.canonicalHeight(v)),
                  u.formatHeight(_p.heightCm),
                ),
                _sliderTile(
                  'Peso actual',
                  u.displayWeight(_p.weightKg),
                  u.weightMin,
                  u.weightMax,
                  (v) => setState(() => _p.weightKg = u.canonicalWeight(v)),
                  u.formatWeight(_p.weightKg),
                ),
                _sliderTile(
                  'Peso meta',
                  u.displayWeight(_p.targetWeightKg),
                  u.weightMin,
                  u.weightMax,
                  (v) =>
                      setState(() => _p.targetWeightKg = u.canonicalWeight(v)),
                  u.formatWeight(_p.targetWeightKg),
                ),
              ],
            );
          }),

          const SizedBox(height: 26),
          _sub('Condiciones de salud'),
          const SizedBox(height: 4),
          Text(
            'Ajusta comidas, suplementos y ejercicios para que sean seguros.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: HealthCondition.values.map((c) {
              final selected = _p.conditions.contains(c);
              return _chip(
                c.label,
                selected,
                () => setState(() {
                  if (selected) {
                    _p.conditions.remove(c);
                  } else {
                    _p.conditions.add(c);
                  }
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _sub('Alergias / intolerancias'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: Allergy.values.map((a) {
              final selected = _p.allergies.contains(a);
              return _chip(
                a.label,
                selected,
                () => setState(() {
                  if (selected) {
                    _p.allergies.remove(a);
                  } else {
                    _p.allergies.add(a);
                  }
                }),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),
          if (_syncState.needsAttention)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _syncState.label,
                        style:
                            TextStyle(fontSize: 13, color: AppColors.danger),
                      ),
                    ),
                    if (_syncState == SyncState.failed)
                      TextButton(
                        onPressed: _save,
                        child: const Text('Reintentar'),
                      ),
                  ],
                ),
              ),
            ),
          if (_syncState == SyncState.confirmed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text(
                    _syncState.label,
                    style:
                        TextStyle(fontSize: 13, color: AppColors.success),
                  ),
                ],
              ),
            ),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.mintSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Text('🤖', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'El Coach usa IA real (Google Gemini). Sus consejos son '
                    'orientativos y no reemplazan a un profesional de la salud.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.ink,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Ilustraciones de ejercicios: wger.de / Everkinetic (CC BY-SA)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: AppColors.faint),
            ),
          ),
          const SizedBox(height: 20),
          if (AppStore.instance.currentEmail != null)
            Center(
              child: Text(
                'Sesión: ${AppStore.instance.currentEmail}',
                style: TextStyle(fontSize: 12, color: AppColors.faint),
              ),
            ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              AppStore.instance.logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
  }

  Widget _reminders() {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final s = AppStore.instance;
        final time = TimeOfDay(hour: s.workoutHour, minute: s.workoutMinute);
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.workoutReminderOn,
                activeColor: AppColors.brand,
                title: Text(
                  'Recordar entrenar',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                subtitle: Text(
                  'Todos los días a las ${time.format(context)} · toca para cambiar la hora',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                onChanged: (v) async {
                  if (v) {
                    final ok = await Notifications.requestPermission();
                    if (!ok) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Activa las notificaciones en Ajustes del sistema.',
                            ),
                          ),
                        );
                      }
                      return;
                    }
                  }
                  await s.setWorkoutReminder(v);
                },
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (picked != null) {
                    // Mantiene el estado activado/desactivado actual: solo
                    // cambia la hora, no fuerza a encender el recordatorio.
                    await s.setWorkoutReminder(
                      s.workoutReminderOn,
                      hour: picked.hour,
                      minute: picked.minute,
                    );
                  }
                },
                icon: const Icon(Icons.schedule_rounded, size: 16),
                label: const Text('Cambiar hora'),
                style: TextButton.styleFrom(foregroundColor: AppColors.brand),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.waterReminderOn,
                activeColor: AppColors.brand,
                title: Text(
                  'Recordar tomar agua',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                subtitle: Text(
                  '3 avisos al día (11:00, 15:30, 19:00)',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                onChanged: (v) async {
                  if (v) {
                    final ok = await Notifications.requestPermission();
                    if (!ok) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Activa las notificaciones en Ajustes del sistema.',
                            ),
                          ),
                        );
                      }
                      return;
                    }
                  }
                  await s.setWaterReminder(v);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _trainerSection() {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final s = AppStore.instance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Modo entrenador'),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.isTrainer,
              activeColor: AppColors.brand,
              title: Text(
                'Soy entrenador',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              subtitle: Text(
                'El acceso de entrenador requiere habilitación del administrador.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              onChanged: null,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => s.isTrainer
                        ? const TrainerPage()
                        : const JoinGroupPage(),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: AppColors.brand),
                  foregroundColor: AppColors.brand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: Icon(
                  s.isTrainer ? Icons.groups_rounded : Icons.group_add_rounded,
                  size: 18,
                ),
                label: Text(s.isTrainer ? 'Panel de entrenador' : 'Mi grupo'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _unitsSelector() {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final current = AppStore.instance.units;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unidades',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: UnitSystem.values.map((u) {
                  final active = u == current;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => AppStore.instance.setUnits(u),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.brand
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          u == UnitSystem.metric ? 'Métrico' : 'Imperial',
                          style: TextStyle(
                            color:
                                active ? Colors.white : AppColors.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                current == UnitSystem.metric
                    ? 'Peso en kg · Estatura en cm'
                    : 'Peso en lb · Estatura en pulgadas',
                style: TextStyle(fontSize: 11.5, color: AppColors.faint),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _themeSelector() {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final current = AppStore.instance.themeMode;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: ThemeMode.values.map((m) {
              final active = m == current;
              return Expanded(
                child: GestureDetector(
                  onTap: () => AppStore.instance.setThemeMode(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? AppColors.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      _themeLabels[m]!,
                      style: TextStyle(
                        color: active ? Colors.white : AppColors.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.brandDark : AppColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _sliderTile(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    String display,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          Text(
            display,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.brand,
            ),
          ),
          SizedBox(
            width: 160,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              activeColor: AppColors.brand,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(
    t,
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    ),
  );

  Widget _sub(String t) => Text(
    t,
    style: TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: AppColors.muted,
    ),
  );
}
