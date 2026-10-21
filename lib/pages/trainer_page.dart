import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../data/workouts.dart';
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../models/workout.dart';
import '../services/store.dart';
import '../services/trainer_service.dart';

/// Panel del entrenador: crea un grupo, comparte el código con sus alumnos,
/// les asigna una rutina del catálogo y ve quién de verdad está entrenando.
class TrainerPage extends StatefulWidget {
  const TrainerPage({super.key});

  @override
  State<TrainerPage> createState() => _TrainerPageState();
}

class _TrainerPageState extends State<TrainerPage> {
  bool _creating = false;
  bool _loadingMembers = false;
  List<GroupMember> _members = [];
  Map<String, dynamic>? _group;
  Assignment? _activeAssignment;

  @override
  void initState() {
    super.initState();
    if (AppStore.instance.groupId != null) _refresh();
  }

  Future<void> _createGroup() async {
    setState(() => _creating = true);
    try {
      final name = AppStore.instance.profile.name;
      final uid = AppStore.instance.currentUid;
      final (groupId, code) = await TrainerService.createGroup(
        name.isEmpty ? 'Entrenador' : name,
      );
      if (!mounted || AppStore.instance.currentUid != uid) return;
      await AppStore.instance.setMyGroup(groupId, code);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pude crear el grupo. Revisa tu internet.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _refresh() async {
    final groupId = AppStore.instance.groupId;
    if (groupId == null) return;
    setState(() => _loadingMembers = true);
    try {
      final results = await Future.wait([
        TrainerService.getGroup(groupId),
        TrainerService.membersWithAdherence(groupId),
        TrainerService.getActiveAssignment(groupId),
      ]);
      if (mounted) {
        setState(() {
          _group = results[0] as Map<String, dynamic>?;
          _members = results[1] as List<GroupMember>;
          _activeAssignment = results[2] as Assignment?;
        });
      }
    } catch (_) {
      // sin conexión: se queda con lo último que tenía
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _createAssignment() async {
    final groupId = AppStore.instance.groupId;
    if (groupId == null) return;

    // Paso 1: elegir rutina
    final chosen = await showModalBottomSheet<Workout>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).padding.bottom + 30,
          ),
          children: [
            Text(
              'Elige una rutina para asignar',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
            const SizedBox(height: 14),
            ...Workouts.all.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(ctx, w),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(w.title, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                              Text('${w.minutes} min · ${w.focus}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AppColors.faint),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    // Paso 2: configurar días por semana
    int daysPerWeek = 3;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Configurar asignación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chosen.title, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
              const SizedBox(height: 16),
              Text('Días por semana: $daysPerWeek', style: TextStyle(color: AppColors.ink)),
              Slider(
                value: daysPerWeek.toDouble(),
                min: 1,
                max: 7,
                divisions: 6,
                label: '$daysPerWeek',
                activeColor: AppColors.brand,
                onChanged: (v) => setDialogState(() => daysPerWeek = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Asignar')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await TrainerService.createAssignment(
        groupId,
        chosen,
        daysPerWeek: daysPerWeek,
        startAt: DateTime.now(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${chosen.title}" asignada al grupo — $daysPerWeek días/semana')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo crear la asignación.')),
        );
      }
    }
    await _refresh();
  }

  Future<void> _removeMember(GroupMember m) async {
    final groupId = AppStore.instance.groupId;
    if (groupId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirar alumno'),
        content: Text('¿Retirar a ${m.name} del grupo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Retirar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await TrainerService.removeMember(groupId, m.userId);
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo retirar al alumno.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGroup = AppStore.instance.groupId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Panel de entrenador',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: SafeArea(
        top: false,
        child: hasGroup ? _groupView() : _createView(),
      ),
    );
  }

  Widget _createView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_rounded, size: 48, color: AppColors.brand),
            const SizedBox(height: 16),
            Text(
              'Crea tu grupo',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vas a recibir un código para compartir con tus alumnos. '
              'Ellos lo ingresan y quedan en tu grupo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _creating ? null : _createGroup,
                child: _creating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Crear grupo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupView() {
    final code = AppStore.instance.groupCode ?? '------';
    final assignedTitle = _group?['assignedWorkoutTitle'] as String?;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.brand, AppColors.brandDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Text(
                  'Código de tu grupo',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 6),
                Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Código copiado 📋')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copiar código'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_activeAssignment != null) _assignmentBanner(_activeAssignment!),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _createAssignment,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: AppColors.brand),
                foregroundColor: AppColors.brand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.assignment_rounded, size: 18),
              label: Text(
                assignedTitle == null
                    ? 'Asignar una rutina al grupo'
                    : 'Nueva asignación (actual: $assignedTitle)',
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Text(
                'Tus alumnos (${_members.length})',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              if (_loadingMembers)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brand,
                  ),
                )
              else
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: AppColors.brand,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Todavía no se une nadie. Comparte el código de arriba.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            )
          else
            ..._members.map(_memberTile),
        ],
      ),
    );
  }

  Widget _assignmentBanner(Assignment a) {
    final fmt = DateFormat('d MMM', 'es');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fitness_center_rounded, size: 18, color: AppColors.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asignación activa: ${a.workoutTitle}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.brandDark),
                ),
                Text(
                  'Desde ${fmt.format(a.startAt)} · ${a.daysPerWeek} días/semana',
                  style: TextStyle(fontSize: 12, color: AppColors.brandDark.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(GroupMember m) {
    final noActivity = m.lastWorkoutAt == null;
    final daysSince = m.lastWorkoutAt == null
        ? null
        : DateTime.now().difference(m.lastWorkoutAt!).inDays;
    final warn = daysSince != null && daysSince >= 5;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (warn || noActivity) ? AppColors.warn : AppColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.brandDark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  noActivity
                      ? 'Sin entrenamientos registrados aún'
                      : '${m.workoutsThisWeek} esta semana · último hace $daysSince días',
                  style: TextStyle(
                    fontSize: 12,
                    color: (warn || noActivity)
                        ? AppColors.warn
                        : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (warn || noActivity)
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppColors.warn,
            ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _removeMember(m),
            icon: const Icon(Icons.person_remove_rounded, size: 18),
            color: AppColors.danger,
            tooltip: 'Retirar alumno',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
