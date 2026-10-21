import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/exercise_log.dart';
import '../models/workout.dart';
import '../services/store.dart';
import 'workout_session_page.dart';

/// Detalle de una rutina: lista de ejercicios y botón para marcarla completada.
class WorkoutDetailPage extends StatelessWidget {
  final Workout workout;
  const WorkoutDetailPage({super.key, required this.workout});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final s = AppStore.instance;
        final done = s.isWorkoutDoneToday(workout.id);
        return Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Text(
                  workout.title,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _chip(Icons.schedule_rounded, '${workout.minutes} min'),
                    const SizedBox(width: 8),
                    _chip(
                      workout.needsGym
                          ? Icons.fitness_center_rounded
                          : Icons.home_rounded,
                      workout.needsGym ? 'Gimnasio' : 'En casa',
                    ),
                    const SizedBox(width: 8),
                    _chip(Icons.flag_rounded, workout.focus.split(' · ').first),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Ejercicios',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                ...workout.exercises.asMap().entries.map(
                  (e) => _exercise(context, e.key + 1, e.value),
                ),
                const SizedBox(height: 24),
                // Botón principal: iniciar sesión
                SizedBox(
                  width: double.infinity,
                  child: _StartButton(workout: workout),
                ),
                const SizedBox(height: 10),
                // Marcado rápido (retrocompatible con el flujo anterior)
                SizedBox(
                  width: double.infinity,
                  child: done
                      ? OutlinedButton.icon(
                          onPressed: () => s.toggleWorkoutDone(workout.id),
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                          ),
                          label: const Text('Marcado hoy · deshacer'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: const BorderSide(color: AppColors.success),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () {
                            s.toggleWorkoutDone(workout.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Rutina marcada como hecha.')),
                            );
                          },
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Marcar hecho (sin sesión)'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _exercise(BuildContext context, int n, Exercise e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _showHowTo(context, e),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.asset(
                  'assets/exercises/${e.pose}.png',
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    if (e.note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        e.note,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                    if (e.avoidConditions.any(
                      AppStore.instance.profile.conditions.contains,
                    )) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 12,
                            color: AppColors.warn,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Revisa por tu condición marcada',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.warn,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                e.sets,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppColors.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHowTo(BuildContext context, Exercise e) {
    final s = AppStore.instance;
    final ctrl = TextEditingController();
    final setsCtrl = TextEditingController();
    final repsCtrl = TextEditingController();
    ExerciseWeightEntry? editing;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final history = s.exerciseWeightHistory(e.name);
          final suggestion = s.suggestNextWeight(e.name);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/exercises/${e.pose}.png',
                          width: 220,
                          height: 220,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        e.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        e.sets,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand,
                        ),
                      ),
                      if (e.note.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          e.note,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _RestTimer(seconds: e.restSeconds),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.show_chart_rounded,
                                  size: 16,
                                  color: AppColors.brand,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Tu progreso',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (history.isEmpty)
                              Text(
                                'Aún no registras peso en este ejercicio.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.muted,
                                ),
                              )
                            else
                              ...history.take(3).map((h) {
                                final i = history.indexOf(h);
                                final prev = i + 1 < history.length
                                    ? history[i + 1]
                                    : null;
                                final diff = prev == null
                                    ? null
                                    : h.kg - prev.kg;
                                final setsReps =
                                    (h.sets != null && h.reps != null)
                                    ? ' · ${h.sets}x${h.reps}'
                                    : '';
                                final isEditing = editing?.date == h.date;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${h.kg.toStringAsFixed(1)} kg$setsReps',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _fmtDate(h.date),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.faint,
                                        ),
                                      ),
                                      if (diff != null && diff != 0) ...[
                                        const SizedBox(width: 8),
                                        Icon(
                                          diff > 0
                                              ? Icons.arrow_upward_rounded
                                              : Icons.arrow_downward_rounded,
                                          size: 13,
                                          color: diff > 0
                                              ? AppColors.success
                                              : AppColors.danger,
                                        ),
                                        Text(
                                          '${diff.abs().toStringAsFixed(1)} kg',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: diff > 0
                                                ? AppColors.success
                                                : AppColors.danger,
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () {
                                          editing = h;
                                          ctrl.text =
                                              h.kg == h.kg.roundToDouble()
                                              ? h.kg.toInt().toString()
                                              : h.kg.toStringAsFixed(1);
                                          setsCtrl.text =
                                              h.sets?.toString() ?? '';
                                          repsCtrl.text =
                                              h.reps?.toString() ?? '';
                                          setSheet(() {});
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(
                                            Icons.edit_outlined,
                                            size: 14,
                                            color: isEditing
                                                ? AppColors.brand
                                                : AppColors.muted,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () {
                                          s.deleteExerciseEntry(e.name, h.date);
                                          if (isEditing) {
                                            editing = null;
                                            ctrl.clear();
                                            setsCtrl.clear();
                                            repsCtrl.clear();
                                          }
                                          setSheet(() {});
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(
                                            Icons.delete_outline_rounded,
                                            size: 14,
                                            color: AppColors.danger,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            if (suggestion != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.brandSoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      '🤖',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        suggestion.message,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.brandDark,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (suggestion.kg != null)
                                      TextButton(
                                        onPressed: () {
                                          ctrl.text = suggestion.kg!
                                              .toStringAsFixed(
                                                suggestion.kg! ==
                                                        suggestion.kg!
                                                            .roundToDouble()
                                                    ? 0
                                                    : 1,
                                              );
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          minimumSize: Size.zero,
                                        ),
                                        child: const Text(
                                          'Usar',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: ctrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      hintText: 'Peso (kg)',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: setsCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      hintText: 'Series',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: repsCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      hintText: 'Reps',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (editing != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 13,
                                    color: AppColors.brand,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Editando el registro de ${_fmtDate(editing!.date)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.brand,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    onTap: () {
                                      editing = null;
                                      ctrl.clear();
                                      setsCtrl.clear();
                                      repsCtrl.clear();
                                      setSheet(() {});
                                    },
                                    child: Text(
                                      'Cancelar',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  final kg = double.tryParse(
                                    ctrl.text.replaceAll(',', '.'),
                                  );
                                  if (kg == null || kg <= 0) return;
                                  final sets = int.tryParse(setsCtrl.text);
                                  final reps = int.tryParse(repsCtrl.text);
                                  if (editing != null) {
                                    s.updateExerciseEntry(
                                      e.name,
                                      editing!.date,
                                      kg: kg,
                                      sets: sets,
                                      reps: reps,
                                    );
                                    editing = null;
                                  } else {
                                    s.logExerciseWeight(
                                      e.name,
                                      kg,
                                      sets: sets,
                                      reps: reps,
                                    );
                                  }
                                  ctrl.clear();
                                  setsCtrl.clear();
                                  repsCtrl.clear();
                                  setSheet(() {});
                                  FocusScope.of(sheetCtx).unfocus();
                                },
                                child: Text(
                                  editing != null ? 'Actualizar' : 'Guardar',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    return '${d.day}/${d.month}';
  }
}

// ── Botón para iniciar una sesión real ──────────────────────────────────────

class _StartButton extends StatefulWidget {
  final Workout workout;
  const _StartButton({required this.workout});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> {
  bool _starting = false;

  Future<void> _start() async {
    if (_starting) return;
    final s = AppStore.instance;
    final uid = s.currentUid;
    final prefs = s.currentPrefs;
    if (uid == null || prefs == null) return;

    final existing = s.sessions.activeSession;
    if (existing != null && existing.workoutId != widget.workout.id) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sesión en curso'),
          content: Text(
              'Tienes una sesión activa de "${existing.workoutTitle}". ¿Qué quieres hacer?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Retomarla')),
            TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelarla e iniciar nueva')),
          ],
        ),
      );
      if (!mounted) return;
      if (resume == null) return;
      if (resume) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const WorkoutSessionPage()));
        return;
      }
      // Cancela la existente
      await s.sessions.cancelSession(prefs);
      if (!mounted) return;
    }

    _starting = true;
    setState(() {});
    try {
      await s.sessions.startSession(widget.workout, uid, prefs);
      if (!mounted) return;
      await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkoutSessionPage()));
      if (!mounted) return;
      // Marcado automático si la sesión se finalizó con éxito
      if (s.sessions.activeSession == null) {
        if (!s.isWorkoutDoneToday(widget.workout.id)) {
          await s.toggleWorkoutDone(widget.workout.id);
        }
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = AppStore.instance.sessions.activeSession != null;
    final sameWorkout =
        AppStore.instance.sessions.activeSession?.workoutId == widget.workout.id;
    return ElevatedButton.icon(
      onPressed: _starting ? null : _start,
      icon: _starting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Icon(hasActive && sameWorkout
              ? Icons.play_arrow_rounded
              : Icons.fitness_center_rounded),
      label: Text(hasActive && sameWorkout
          ? 'Retomar sesión'
          : 'Iniciar entrenamiento'),
    );
  }
}

/// Cronómetro de descanso entre series. Cuenta regresiva simple con
/// play/pausa y reinicio; no depende del resto de la hoja para no perder el
/// tick si se hace scroll.
class _RestTimer extends StatefulWidget {
  final int seconds;
  const _RestTimer({required this.seconds});

  @override
  State<_RestTimer> createState() => _RestTimerState();
}

class _RestTimerState extends State<_RestTimer> {
  Timer? _timer;
  late int _remaining = widget.seconds;
  bool _running = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    if (_remaining <= 0) _remaining = widget.seconds;
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        setState(() {
          _remaining = 0;
          _running = false;
        });
        return;
      }
      setState(() => _remaining--);
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _remaining = widget.seconds;
    });
  }

  String get _fmt {
    final m = _remaining ~/ 60;
    final sec = _remaining % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final finished = !_running && _remaining == 0;
    final label = finished
        ? '¡Descanso terminado! 🔔'
        : _running
        ? 'Descansando… $_fmt'
        : 'Descanso sugerido: ${widget.seconds}s';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: finished ? AppColors.brandSoft : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          if (_running || _remaining != widget.seconds)
            IconButton(
              onPressed: _reset,
              icon: Icon(
                Icons.refresh_rounded,
                size: 18,
                color: AppColors.muted,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Reiniciar',
            ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: _toggle,
            icon: Icon(
              _running
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              size: 30,
              color: AppColors.brand,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: _running ? 'Pausar' : 'Iniciar descanso',
          ),
        ],
      ),
    );
  }
}
