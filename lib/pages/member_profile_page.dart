import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/workouts.dart';
import '../models/assignment.dart';
import '../models/workout.dart';
import '../models/workout_session.dart';
import '../services/trainer_service.dart';

/// Página de perfil de un alumno para el entrenador.
/// Permite ver su información de grupo, adherencia y el detalle
/// de los ejercicios y series que realizó en las rutinas asignadas.
class MemberProfilePage extends StatefulWidget {
  final String groupId;
  final GroupMember member;
  final Assignment? activeAssignment;

  const MemberProfilePage({
    super.key,
    required this.groupId,
    required this.member,
    this.activeAssignment,
  });

  @override
  State<MemberProfilePage> createState() => _MemberProfilePageState();
}

class _MemberProfilePageState extends State<MemberProfilePage> {
  bool _loading = true;
  List<Map<String, dynamic>> _completions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await TrainerService.getMemberCompletions(
        widget.groupId,
        widget.member.userId,
      );
      if (mounted) {
        setState(() {
          _completions = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudieron cargar los entrenamientos';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final a = widget.activeAssignment;
    final daysPerWeek = a?.daysPerWeek ?? 0;
    final daysSince = m.lastWorkoutAt == null
        ? null
        : DateTime.now().difference(m.lastWorkoutAt!).inDays;
    final noActivity = m.lastWorkoutAt == null;
    final warn = daysSince != null && daysSince >= 5;
    final adherencePct = daysPerWeek > 0
        ? (m.trainingDaysThisWeek / daysPerWeek * 100).clamp(0, 100).round()
        : null;

    final joinDateFmt = DateFormat("d 'de' MMMM y", 'es').format(m.joinedAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          m.name.isNotEmpty ? m.name : 'Perfil de alumno',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            // Cabecera del alumno
            Container(
              padding: const EdgeInsets.all(18),
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
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.name.isNotEmpty ? m.name : 'Sin nombre',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Miembro desde el $joinDateFmt',
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Resumen de adherencia
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (warn || noActivity) ? AppColors.surface : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: (warn || noActivity) ? AppColors.warn : AppColors.line,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        (warn || noActivity)
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 20,
                        color: (warn || noActivity) ? AppColors.warn : AppColors.brand,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Cumplimiento de la semana',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    noActivity
                        ? 'El alumno aún no ha registrado entrenamientos en este grupo.'
                        : adherencePct != null
                            ? '$adherencePct% completado esta semana (${m.trainingDaysThisWeek} de $daysPerWeek días asignados). Último entreno hace $daysSince días.'
                            : '${m.trainingDaysThisWeek} entrenamientos esta semana. Último entreno hace $daysSince días.',
                    style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Título de la sección de historial
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Registro de ejercicios',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  '${_completions.length} ${_completions.length == 1 ? 'sesión' : 'sesiones'}',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Lista de entrenamientos
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                ),
              )
            else if (_completions.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.fitness_center_rounded, size: 40, color: AppColors.faint),
                      const SizedBox(height: 10),
                      Text(
                        'No hay registros de ejercicios aún.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._completions.map((c) => _buildCompletionCard(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionCard(Map<String, dynamic> c) {
    final title = c['workoutTitle'] as String? ?? 'Entrenamiento';
    final completedAt = (c['completedAt'] as Timestamp?)?.toDate();
    final dateStr = completedAt != null
        ? DateFormat("EEEE d 'de' MMMM, HH:mm", 'es').format(completedAt)
        : 'Fecha no disponible';

    final exercisesRaw = c['exercises'] as List<dynamic>?;
    final exercises = <SessionExercise>[];
    if (exercisesRaw != null) {
      for (final item in exercisesRaw) {
        if (item is Map) {
          try {
            exercises.add(SessionExercise.fromMap(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
    }

    final workoutId = c['workoutId'] as String? ?? '';
    final catalogWorkout = Workouts.byId(workoutId);
    final totalExCount = exercises.isNotEmpty ? exercises.length : catalogWorkout.exercises.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.brand,
              size: 22,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.ink,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$dateStr · $totalExCount ejercicios',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          children: [
            Divider(color: AppColors.line),
            const SizedBox(height: 8),
            if (exercises.isNotEmpty)
              ...exercises.map((ex) => _buildExerciseDetail(ex))
            else
              ...catalogWorkout.exercises.map((ex) => _buildCatalogExerciseDetail(ex)),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogExerciseDetail(Exercise ex) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/exercises/${ex.pose}.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.fitness_center_rounded,
                size: 20,
                color: AppColors.brand,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ex.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  ex.sets,
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Completado ✓',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.brandDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseDetail(SessionExercise ex) {
    final doneSeries =
        ex.series.where((s) => s.status == SeriesStatus.done).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/exercises/${ex.pose}.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.fitness_center_rounded,
                    size: 20,
                    color: AppColors.brand,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ex.exerciseName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                '${doneSeries.length} / ${ex.series.length} series',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: doneSeries.length == ex.series.length
                      ? AppColors.brand
                      : AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: ex.series.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final s = entry.value;
                final isDone = s.status == SeriesStatus.done;
                String desc = 'Serie $idx';
                if (s.reps != null && s.reps! > 0) {
                  desc += ': ${s.reps} reps';
                }
                if (s.loadKg != null && s.loadKg! > 0) {
                  desc += ' · ${s.loadKg!.toStringAsFixed(s.loadKg! % 1 == 0 ? 0 : 1)} kg';
                }
                if (s.durationSec != null && s.durationSec! > 0) {
                  desc += ': ${s.durationSec}s';
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDone ? AppColors.brandSoft : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDone ? AppColors.brand.withValues(alpha: 0.3) : AppColors.line,
                    ),
                  ),
                  child: Text(
                    desc,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isDone ? FontWeight.w700 : FontWeight.w500,
                      color: isDone ? AppColors.brandDark : AppColors.muted,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
