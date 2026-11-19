import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/workouts.dart';
import '../models/assignment.dart';
import '../services/store.dart';
import '../services/trainer_service.dart';
import 'workout_detail_page.dart';
import 'workout_session_page.dart';

/// El alumno ingresa el código de 6 dígitos que le dio su entrenador para
/// unirse al grupo, y desde acá ve qué rutina le asignaron.
class JoinGroupPage extends StatefulWidget {
  const JoinGroupPage({super.key});

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  Map<String, dynamic>? _group;
  List<Assignment> _assignments = [];
  StreamSubscription<List<Assignment>>? _assignmentsSub;

  @override
  void initState() {
    super.initState();
    if (AppStore.instance.inGroup) {
      _loadGroup();
      _subscribeAssignment();
    }
  }

  void _subscribeAssignment() {
    final groupId = AppStore.instance.groupId;
    if (groupId == null) return;
    _assignmentsSub?.cancel();
    _assignmentsSub = TrainerService.watchGroupAssignments(groupId).listen((list) {
      if (mounted) setState(() => _assignments = list);
    });
  }

  @override
  void dispose() {
    _assignmentsSub?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGroup() async {
    final groupId = AppStore.instance.groupId;
    if (groupId == null) return;
    final results = await Future.wait([
      TrainerService.getGroup(groupId),
      TrainerService.getGroupAssignments(groupId),
    ]);
    if (mounted) {
      setState(() {
        _group = results[0] as Map<String, dynamic>?;
        _assignments = results[1] as List<Assignment>;
      });
    }
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El código tiene 6 dígitos.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final s = AppStore.instance;
      final uid = s.currentUid;
      final groupId = await TrainerService.joinGroup(
        code,
        s.localUserId,
        s.profile.name,
      );
      if (groupId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No encontré ese código. Revísalo.')),
          );
        }
        return;
      }
      if (!mounted || s.currentUid != uid) return;
      await s.setMyGroup(groupId, code);
      await _loadGroup();
      _subscribeAssignment();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pude unirme. Revisa tu internet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final s = AppStore.instance;
    final groupId = s.groupId;
    final uid = s.currentUid;
    if (groupId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del grupo'),
        content: const Text(
          'Ya no podrás ver la rutina asignada por tu entrenador. '
          'Tu historial personal de sesiones se conserva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await TrainerService.leaveGroup(groupId, s.localUserId);
      if (!mounted || s.currentUid != uid) return;
      _assignmentsSub?.cancel();
      await s.leaveGroup();
      if (mounted) setState(() { _group = null; _assignments = []; });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo salir del grupo. Inténtalo nuevamente.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inGroup = AppStore.instance.inGroup;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mi grupo',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: SafeArea(top: false, child: inGroup ? _groupView() : _joinView()),
    );
  }

  Widget _joinView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_rounded, size: 48, color: AppColors.brand),
            const SizedBox(height: 16),
            Text(
              'Únete al grupo de tu entrenador',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pídele el código de 6 dígitos e ingrésalo aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '000000',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _join,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Unirme'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupView() {
    final trainerName = _group?['trainerName'] as String?;
    return RefreshIndicator(
      onRefresh: _loadGroup,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_rounded, color: AppColors.brandDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Entrenador: ${trainerName ?? '—'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Planificación asignada',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (_assignments.isNotEmpty)
                Text(
                  '${_assignments.length} ${_assignments.length == 1 ? 'rutina' : 'rutinas'}',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_assignments.isEmpty)
            _noAssignmentCard()
          else
            ..._assignments.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _assignmentCard(a),
                )),
          const SizedBox(height: 30),
          TextButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Salir del grupo'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
  }

  Widget _noAssignmentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        'Tu entrenador todavía no te asignó ninguna rutina vigente.',
        style: TextStyle(fontSize: 13, color: AppColors.muted),
      ),
    );
  }

  Widget _assignmentCard(Assignment a) {
    final fmt = DateFormat('d MMM', 'es');
    final workout = Workouts.byId(a.workoutId);
    final groupId = AppStore.instance.groupId;
    final isFuture = a.isFuture();
    final isOverdue = a.isOverdue();
    final isEffective = a.isEffective();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOverdue ? Colors.orange.withValues(alpha: 0.5) : AppColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera con nombre de rutina y badge de estado
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? Colors.orange.withValues(alpha: 0.15)
                        : (isFuture ? AppColors.surfaceAlt : AppColors.brandSoft),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isOverdue
                        ? Icons.history_rounded
                        : (isFuture ? Icons.schedule_rounded : Icons.fitness_center_rounded),
                    size: 18,
                    color: isOverdue
                        ? Colors.deepOrange
                        : (isFuture ? AppColors.muted : AppColors.brand),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.workoutTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        '${workout.minutes} min · ${workout.focus}',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isEffective
                        ? AppColors.brandSoft
                        : (isOverdue ? Colors.orange.withValues(alpha: 0.15) : AppColors.surfaceAlt),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isEffective ? 'Activa hoy' : (isOverdue ? 'Retrasada' : 'Programada'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isEffective
                          ? AppColors.brandDark
                          : (isOverdue ? Colors.deepOrange : AppColors.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Detalle de la asignación
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(
                  Icons.calendar_today_rounded,
                  'Desde ${fmt.format(a.startAt)}',
                ),
                _chip(
                  Icons.repeat_rounded,
                  '${a.daysPerWeek} días/semana',
                ),
                if (a.endAt != null)
                  _chip(
                    Icons.event_rounded,
                    'Hasta ${fmt.format(a.endAt!)}',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Botones: ver detalle + iniciar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WorkoutDetailPage(
                          workout: a.workoutFromSnapshot(workout),
                          assignmentId: a.id,
                          groupId: groupId,
                        ),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.brand),
                      foregroundColor: AppColors.brand,
                    ),
                    child: const Text('Ver rutina'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _startAssigned(workout, a, groupId),
                    icon: Icon(
                      isFuture ? Icons.lock_clock_rounded : Icons.play_arrow_rounded,
                      size: 18,
                    ),
                    label: Text(isFuture ? 'Programada' : 'Iniciar'),
                    style: isFuture
                        ? ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surfaceAlt,
                            foregroundColor: AppColors.muted,
                            elevation: 0,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.muted),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _startAssigned(dynamic workout, Assignment a, String? groupId) async {
    if (groupId == null) return;
    if (a.isFuture()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Esta rutina está programada para iniciar el ${DateFormat("d 'de' MMMM", "es").format(a.startAt)}.',
          ),
        ),
      );
      return;
    }
    if (a.isPurgeable()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta rutina ya expiró (más de 3 días de retraso).'),
        ),
      );
      return;
    }
    final s = AppStore.instance;
    final prefs = s.currentPrefs;
    final uid = s.currentUid;
    if (prefs == null || uid == null) return;

    // Si hay sesión activa de la misma rutina, ir directamente
    final active = s.sessions.activeSession;
    if (active != null && active.workoutId == workout.id && active.uid == uid) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkoutSessionPage()),
      );
      return;
    }
    // Si hay sesión de otra rutina, avisar
    if (active != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ya tienes "${active.workoutTitle}" activa. Termínala o cancélala primero.',
          ),
        ),
      );
      return;
    }

    try {
      final snapshotWorkout = a.workoutFromSnapshot(workout);
      await s.sessions.startSession(
        snapshotWorkout,
        uid,
        prefs,
        assignmentId: a.id,
        groupId: groupId,
      );
      if (!mounted || s.currentUid != uid) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkoutSessionPage()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}
