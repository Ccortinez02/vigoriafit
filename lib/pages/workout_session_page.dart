import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../models/workout_session.dart';
import '../services/account_preferences.dart';
import '../services/store.dart';
import '../services/workout_session_service.dart';

/// Pantalla principal de una sesión de entrenamiento activa.
///
/// Muestra ejercicios, series registradas y temporizador de descanso.
/// El usuario navega por los ejercicios con tabs o deslizando.
class WorkoutSessionPage extends StatefulWidget {
  const WorkoutSessionPage({super.key});

  @override
  State<WorkoutSessionPage> createState() => _WorkoutSessionPageState();
}

class _WorkoutSessionPageState extends State<WorkoutSessionPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final WorkoutSessionService _svc;
  late final AccountPreferences _prefs;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _svc = AppStore.instance.sessions;
    _prefs = AppStore.instance.currentPrefs!;
    final session = _svc.activeSession!;
    _tabs = TabController(length: session.exercises.length, vsync: this);
    _startedAt = session.startedAt;
    _elapsed = DateTime.now().difference(_startedAt!);
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_startedAt!);
        });
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  String _fmtElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _finish() async {
    final session = _svc.activeSession;
    if (session == null) return;

    final hasPending = session.exercises.any((e) =>
        e.series.isEmpty ||
        e.series.any((s) => s.status == SeriesStatus.pending));
    bool proceed = true;
    if (hasPending) {
      proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('¿Finalizar entrenamiento?'),
              content: const Text(
                  'Hay ejercicios o series sin completar. Se guardarán con el estado actual.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Seguir entrenando')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Finalizar')),
              ],
            ),
          ) ??
          false;
    } else {
      proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('¿Finalizar entrenamiento?'),
              content: const Text('Todas las series están registradas. ¡Buen trabajo!'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Seguir')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Finalizar')),
              ],
            ),
          ) ??
          false;
    }
    if (!proceed || !mounted) return;

    await _svc.finishSession(_prefs, FirebaseFirestore.instance);
    if (!mounted) return;
    _elapsedTimer?.cancel();
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('¡Entrenamiento completado!')),
    );
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Cancelar entrenamiento?'),
            content: const Text(
                'Se guardará el progreso como sesión cancelada. No contará como entrenamiento completado.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Seguir entrenando')),
              TextButton(
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Cancelar sesión')),
            ],
          ),
        ) ??
        false;
    if (!confirm || !mounted) return;
    await _svc.cancelSession(_prefs);
    if (!mounted) return;
    _elapsedTimer?.cancel();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _svc,
      builder: (context, _) {
        final session = _svc.activeSession;
        if (session == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) await _cancel();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(session.workoutTitle,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _cancel,
              ),
              actions: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      _fmtElapsed(_elapsed),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  tooltip: 'Finalizar',
                  onPressed: _finish,
                ),
              ],
              bottom: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: session.exercises
                    .map((e) => Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (e.doneSeries > 0)
                                const Icon(Icons.check_circle_rounded,
                                    size: 14, color: AppColors.success),
                              if (e.doneSeries > 0) const SizedBox(width: 4),
                              Text(e.exerciseName,
                                  style: const TextStyle(fontSize: 12.5)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            body: Column(
              children: [
                _RestBanner(svc: _svc, prefs: _prefs),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: session.exercises
                        .asMap()
                        .entries
                        .map((entry) => _ExerciseTab(
                              session: session,
                              exercise: entry.value,
                              exerciseIndex: entry.key,
                              svc: _svc,
                              prefs: _prefs,
                              onNextExercise: entry.key <
                                      session.exercises.length - 1
                                  ? () => _tabs.animateTo(entry.key + 1)
                                  : null,
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _finish,
              backgroundColor: AppColors.brand,
              icon: const Icon(Icons.done_all_rounded, color: Colors.white),
              label: const Text('Finalizar',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        );
      },
    );
  }
}

// ── Tab de un ejercicio ───────────────────────────────────────────────────────

class _ExerciseTab extends StatefulWidget {
  final WorkoutSession session;
  final SessionExercise exercise;
  final int exerciseIndex;
  final WorkoutSessionService svc;
  final AccountPreferences prefs;
  final VoidCallback? onNextExercise;

  const _ExerciseTab({
    required this.session,
    required this.exercise,
    required this.exerciseIndex,
    required this.svc,
    required this.prefs,
    this.onNextExercise,
  });

  @override
  State<_ExerciseTab> createState() => _ExerciseTabState();
}

class _ExerciseTabState extends State<_ExerciseTab> {
  final _repsCtrl = TextEditingController();
  final _loadCtrl = TextEditingController();
  final _durCtrl = TextEditingController();
  bool _submitting = false;
  String? _editingId;

  @override
  void dispose() {
    _repsCtrl.dispose();
    _loadCtrl.dispose();
    _durCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final ex = widget.exercise;

    // Validación
    int? reps;
    double? load;
    int? dur;

    if (ex.trackingType == TrackingType.reps ||
        ex.trackingType == TrackingType.repsAndLoad) {
      reps = int.tryParse(_repsCtrl.text.trim());
      if (reps == null || reps <= 0) {
        _showError('Escribe el número de repeticiones.');
        return;
      }
    }
    if (ex.trackingType == TrackingType.repsAndLoad) {
      final txt = _loadCtrl.text.trim().replaceAll(',', '.');
      if (txt.isNotEmpty) {
        load = double.tryParse(txt);
        if (load == null || load < 0) {
          _showError('La carga debe ser un número mayor o igual a cero.');
          return;
        }
      }
    }
    if (ex.trackingType == TrackingType.duration) {
      dur = int.tryParse(_durCtrl.text.trim());
      if (dur == null || dur <= 0) {
        _showError('Escribe la duración en segundos.');
        return;
      }
    }

    _submitting = true;
    try {
      if (_editingId != null) {
        final existing = ex.series.firstWhere((s) => s.id == _editingId);
        final updated = existing.copyWith(
            reps: reps, loadKg: load, durationSec: dur, status: SeriesStatus.done);
        await widget.svc.updateSeries(widget.exerciseIndex, updated, widget.prefs);
      } else {
        final entry = SeriesEntry(
          id: generateSeriesId(widget.exerciseIndex, ex.series.length),
          setIndex: ex.series.length,
          type: ex.trackingType,
          reps: reps,
          loadKg: load,
          durationSec: dur,
          status: SeriesStatus.done,
        );
        await widget.svc.addSeries(widget.exerciseIndex, entry, widget.prefs);
        // Iniciar descanso automáticamente
        if (ex.restSeconds > 0) {
          widget.svc.startRest(ex.restSeconds, widget.prefs);
        }
      }
      _repsCtrl.clear();
      _loadCtrl.clear();
      _durCtrl.clear();
      setState(() => _editingId = null);
      if (mounted) {
        FocusScope.of(context).unfocus();
        HapticFeedback.lightImpact();
      }
    } finally {
      _submitting = false;
    }
  }

  void _startEdit(SeriesEntry s) {
    _editingId = s.id;
    if (s.reps != null) _repsCtrl.text = s.reps.toString();
    if (s.loadKg != null) {
      _loadCtrl.text = s.loadKg! == s.loadKg!.roundToDouble()
          ? s.loadKg!.toInt().toString()
          : s.loadKg!.toStringAsFixed(1);
    }
    if (s.durationSec != null) _durCtrl.text = s.durationSec.toString();
    setState(() {});
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.danger));
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercise;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/exercises/${ex.pose}.png',
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ex.exerciseName,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                  const SizedBox(height: 4),
                  Text(ex.setsTarget,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Series realizadas
        if (ex.series.isNotEmpty) ...[
          Text('Series registradas',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted)),
          const SizedBox(height: 8),
          ...ex.series.map((s) => _SeriesRow(
                series: s,
                isEditing: _editingId == s.id,
                onEdit: () => _startEdit(s),
              )),
          const SizedBox(height: 16),
        ],
        // Formulario de nueva serie / edición
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editingId != null ? 'Corregir serie' : 'Registrar serie',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink),
              ),
              const SizedBox(height: 12),
              _buildInputRow(ex),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_editingId != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _repsCtrl.clear();
                          _loadCtrl.clear();
                          _durCtrl.clear();
                          setState(() => _editingId = null);
                        },
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(_editingId != null ? 'Actualizar' : 'Guardar serie'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (widget.onNextExercise != null)
          TextButton.icon(
            onPressed: widget.onNextExercise,
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Siguiente ejercicio'),
          ),
      ],
    );
  }

  Widget _buildInputRow(SessionExercise ex) {
    return switch (ex.trackingType) {
      TrackingType.reps => _field(_repsCtrl, 'Repeticiones', isInt: true),
      TrackingType.duration => _field(_durCtrl, 'Duración (seg)', isInt: true),
      TrackingType.repsAndLoad => Row(
          children: [
            Expanded(flex: 2, child: _field(_repsCtrl, 'Reps', isInt: true)),
            const SizedBox(width: 10),
            Expanded(
                flex: 3,
                child: _field(_loadCtrl, 'Carga (kg, opcional)',
                    isInt: false, isDecimal: true)),
          ],
        ),
    };
  }

  Widget _field(TextEditingController ctrl, String hint,
      {bool isInt = false, bool isDecimal = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : isInt
              ? TextInputType.number
              : TextInputType.text,
      inputFormatters: isInt
          ? [FilteringTextInputFormatter.digitsOnly]
          : isDecimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))]
              : null,
      decoration: InputDecoration(hintText: hint, isDense: true),
    );
  }
}

// ── Fila de serie registrada ──────────────────────────────────────────────────

class _SeriesRow extends StatelessWidget {
  final SeriesEntry series;
  final bool isEditing;
  final VoidCallback onEdit;

  const _SeriesRow({
    required this.series,
    required this.isEditing,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final label = _buildLabel();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEditing ? AppColors.brand : AppColors.line,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.mintSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${series.setIndex + 1}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.mint),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
            ),
            IconButton(
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined,
                  size: 16,
                  color: isEditing ? AppColors.brand : AppColors.muted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  String _buildLabel() {
    switch (series.type) {
      case TrackingType.reps:
        return '${series.reps ?? 0} reps';
      case TrackingType.repsAndLoad:
        final loadStr =
            series.loadKg != null && series.loadKg! > 0
                ? ' · ${series.loadKg!.toStringAsFixed(series.loadKg! == series.loadKg!.roundToDouble() ? 0 : 1)} kg'
                : '';
        return '${series.reps ?? 0} reps$loadStr';
      case TrackingType.duration:
        final sec = series.durationSec ?? 0;
        if (sec >= 60) {
          final m = sec ~/ 60;
          final s = sec % 60;
          return s > 0 ? '${m}m ${s}s' : '${m}m';
        }
        return '${sec}s';
    }
  }
}

// ── Banner de descanso ────────────────────────────────────────────────────────

class _RestBanner extends StatelessWidget {
  final WorkoutSessionService svc;
  final AccountPreferences prefs;

  const _RestBanner({required this.svc, required this.prefs});

  @override
  Widget build(BuildContext context) {
    if (!svc.restRunning && !svc.restFinished) return const SizedBox.shrink();
    final remaining = svc.restRemainingSec;
    final finished = !svc.restRunning && remaining == 0;
    final m = remaining ~/ 60;
    final s = remaining % 60;
    final label = finished
        ? '¡Descanso terminado!'
        : 'Descansando  $m:${s.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      color: finished ? AppColors.brandSoft : AppColors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(finished ? Icons.notifications_active_rounded : Icons.timer_outlined,
              size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
          ),
          TextButton(
            onPressed: () => svc.stopRest(prefs),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
