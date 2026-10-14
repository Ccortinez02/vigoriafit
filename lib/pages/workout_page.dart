import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/workouts.dart';
import '../models/place.dart';
import '../models/profile.dart';
import '../models/workout.dart';
import '../services/store.dart';
import '../services/trainer_service.dart';
import 'places_page.dart';
import 'workout_detail_page.dart';
import 'workout_history_page.dart';
import 'workout_session_page.dart';

class WorkoutTab extends StatefulWidget {
  const WorkoutTab({super.key});

  @override
  State<WorkoutTab> createState() => _WorkoutTabState();
}

class _WorkoutTabState extends State<WorkoutTab> {
  Goal? _goalFilter;
  Level? _levelFilter;
  bool? _gymFilter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [AppStore.instance, AppStore.instance.sessions]),
      builder: (context, _) {
        final s = AppStore.instance;
        final p = s.profile;

        // Aplicar filtros separados
        final list = Workouts.filtered(
          profile: p,
          goal: _goalFilter,
          level: _levelFilter,
          needsGym: _gymFilter,
        );

        final activeSession = s.sessions.activeSession;

        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Entrenamientos',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history_rounded),
                      tooltip: 'Historial',
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const WorkoutHistoryPage())),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  const PlacesPage(initialKind: PlaceKind.gym))),
                      icon: const Icon(Icons.place_rounded, size: 16),
                      label: const Text('Cerca'),
                      style:
                          TextButton.styleFrom(foregroundColor: AppColors.brand),
                    ),
                  ],
                ),

                // Banner de sesión activa
                if (activeSession != null) ...[
                  const SizedBox(height: 12),
                  _ActiveSessionBanner(session: activeSession),
                ],

                // Filtros separados
                const SizedBox(height: 12),
                _FilterBar(
                  profile: p,
                  selectedGoal: _goalFilter,
                  selectedLevel: _levelFilter,
                  selectedGym: _gymFilter,
                  onGoalChanged: (g) => setState(() => _goalFilter = g),
                  onLevelChanged: (l) => setState(() => _levelFilter = l),
                  onGymChanged: (g) => setState(() => _gymFilter = g),
                ),

                if (s.inGroup && !s.isTrainer) ...[
                  const SizedBox(height: 14),
                  _assignedBanner(context, s),
                ],
                const SizedBox(height: 12),

                // Lista de rutinas
                if (list.isEmpty)
                  _EmptyFilter(
                    onClear: () => setState(() {
                      _goalFilter = null;
                      _levelFilter = null;
                      _gymFilter = null;
                    }),
                  )
                else
                  ...list.map((w) => _card(context, w, s.isWorkoutDoneToday(w.id))),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _assignedBanner(BuildContext context, AppStore s) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: TrainerService.getGroup(s.groupId!),
      builder: (context, snap) {
        final assignedId = snap.data?['assignedWorkoutId'] as String?;
        final assignedTitle = snap.data?['assignedWorkoutTitle'] as String?;
        final trainerName = snap.data?['trainerName'] as String?;
        if (assignedId == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              final w = Workouts.byId(assignedId);
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => WorkoutDetailPage(workout: w)));
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.brand, AppColors.brandDark],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assignment_turned_in_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            trainerName != null
                                ? 'Tu entrenador $trainerName te asignó:'
                                : 'Tu entrenador te asignó:',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(assignedTitle ?? '',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, Workout w, bool done) {
    final recommended = w.goal == AppStore.instance.profile.goal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => WorkoutDetailPage(workout: w))),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: done ? AppColors.mintSoft : AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                    done
                        ? Icons.check_circle_rounded
                        : Icons.fitness_center_rounded,
                    color: done ? AppColors.success : AppColors.brand),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(w.title,
                              style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandSoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Para ti',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.brandDark,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('${w.minutes} min · ${w.exercises.length} ejercicios · ${w.focus}',
                        style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Banner de sesión activa ──────────────────────────────────────────────────

class _ActiveSessionBanner extends StatelessWidget {
  final dynamic session; // WorkoutSession

  const _ActiveSessionBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkoutSessionPage())),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.brandSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.play_circle_fill_rounded,
                color: AppColors.brand, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sesión en curso',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.brandDark,
                          fontWeight: FontWeight.w600)),
                  Text(session.workoutTitle,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                ],
              ),
            ),
            Text('Retomar',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: AppColors.brand),
          ],
        ),
      ),
    );
  }
}

// ── Barra de filtros ─────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final Profile profile;
  final Goal? selectedGoal;
  final Level? selectedLevel;
  final bool? selectedGym;
  final ValueChanged<Goal?> onGoalChanged;
  final ValueChanged<Level?> onLevelChanged;
  final ValueChanged<bool?> onGymChanged;

  const _FilterBar({
    required this.profile,
    required this.selectedGoal,
    required this.selectedLevel,
    required this.selectedGym,
    required this.onGoalChanged,
    required this.onLevelChanged,
    required this.onGymChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        selectedGoal != null || selectedLevel != null || selectedGym != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Objetivo
              _DropdownChip<Goal>(
                label: selectedGoal?.label ?? 'Objetivo',
                values: Goal.values,
                selected: selectedGoal,
                labelFor: (g) => g.label,
                onSelected: onGoalChanged,
              ),
              const SizedBox(width: 8),
              // Nivel
              _DropdownChip<Level>(
                label: selectedLevel?.label ?? 'Nivel',
                values: Level.values,
                selected: selectedLevel,
                labelFor: (l) => l.label,
                onSelected: onLevelChanged,
              ),
              const SizedBox(width: 8),
              // Equipamiento
              _DropdownChip<bool>(
                label: selectedGym == null
                    ? 'Equipamiento'
                    : selectedGym!
                        ? 'Gimnasio'
                        : 'En casa',
                values: const [true, false],
                selected: selectedGym,
                labelFor: (b) => b ? 'Gimnasio' : 'En casa',
                onSelected: onGymChanged,
              ),
              if (hasFilters) ...[
                const SizedBox(width: 8),
                ActionChip(
                  label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    onGoalChanged(null);
                    onLevelChanged(null);
                    onGymChanged(null);
                  },
                  avatar: const Icon(Icons.close_rounded, size: 14),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DropdownChip<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final T? selected;
  final String Function(T) labelFor;
  final ValueChanged<T?> onSelected;

  const _DropdownChip({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down_rounded, size: 16),
        ],
      ),
      selected: selected != null,
      selectedColor: AppColors.brandSoft,
      checkmarkColor: AppColors.brand,
      onSelected: (_) async {
        final result = await showModalBottomSheet<T>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ListTile(
                  title: Text('Todos', style: TextStyle(color: AppColors.muted)),
                  onTap: () => Navigator.pop(ctx, null),
                ),
                const Divider(height: 1),
                ...values.map((v) => ListTile(
                      title: Text(labelFor(v)),
                      trailing: selected == v
                          ? const Icon(Icons.check_rounded,
                              color: AppColors.brand)
                          : null,
                      onTap: () => Navigator.pop(ctx, v),
                    )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        // null means "Todos" was selected (clear filter)
        onSelected(result);
      },
    );
  }
}

// ── Estado vacío con filtros activos ─────────────────────────────────────────

class _EmptyFilter extends StatelessWidget {
  final VoidCallback onClear;

  const _EmptyFilter({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.filter_list_off_rounded,
                size: 48, color: AppColors.faint),
            const SizedBox(height: 12),
            Text(
              'No hay rutinas con estos filtros.',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onClear,
              child: const Text('Limpiar filtros'),
            ),
          ],
        ),
      ),
    );
  }
}
