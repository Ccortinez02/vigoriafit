import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../data/workouts.dart';
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../models/workout.dart';
import '../services/store.dart';
import '../services/trainer_service.dart';
import 'member_profile_page.dart';

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
        TrainerService.getLatestAssignment(groupId),
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

    // Paso 2: configurar días por semana y fechas de vigencia
    int daysPerWeek = 3;
    DateTime startAt = DateTime.now();
    DateTime? endAt;
    final dateFmt = DateFormat('d/MM/yyyy', 'es');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isInvalidEnd = endAt != null && !endAt!.isAfter(startAt);
          return AlertDialog(
            title: const Text('Configurar asignación'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chosen.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Días por semana: $daysPerWeek',
                    style: TextStyle(color: AppColors.ink),
                  ),
                  Slider(
                    value: daysPerWeek.toDouble(),
                    min: 1,
                    max: 7,
                    divisions: 6,
                    label: '$daysPerWeek',
                    activeColor: AppColors.brand,
                    onChanged: (v) => setDialogState(() => daysPerWeek = v.round()),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Fecha de inicio:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: startAt,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => startAt = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(dateFmt.format(startAt)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Fecha de término (opcional):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (endAt != null)
                        TextButton(
                          onPressed: () => setDialogState(() => endAt = null),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Quitar', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: endAt ?? startAt.add(const Duration(days: 7)),
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => endAt = picked);
                      }
                    },
                    icon: const Icon(Icons.event_rounded, size: 16),
                    label: Text(endAt != null ? dateFmt.format(endAt!) : 'Sin término fijo'),
                  ),
                  if (isInvalidEnd)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'La fecha de término debe ser posterior a la fecha de inicio.',
                        style: TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: isInvalidEnd ? null : () => Navigator.pop(ctx, true),
                child: const Text('Asignar'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await TrainerService.createAssignment(
        groupId,
        chosen,
        daysPerWeek: daysPerWeek,
        startAt: startAt,
        endAt: endAt,
      );
      if (mounted) {
        final isFut = startAt.isAfter(DateTime.now());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFut
                  ? '"${chosen.title}" programada para iniciar el ${dateFmt.format(startAt)}'
                  : '"${chosen.title}" asignada al grupo — $daysPerWeek días/semana',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la asignación: $e')),
        );
      }
    }
    await _refresh();
  }

  bool _rotatingCode = false;

  Future<void> _rotateCode() async {
    final groupId = AppStore.instance.groupId;
    if (groupId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar código del grupo'),
        content: const Text(
          'Se generará un nuevo código. Los alumnos actuales permanecen en el grupo, '
          'pero nadie podrá unirse con el código anterior.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cambiar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _rotatingCode = true);
    try {
      final newCode = await TrainerService.rotateCode(groupId);
      await AppStore.instance.setMyGroup(groupId, newCode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nuevo código: $newCode 🔑')),
        );
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cambiar el código.')),
        );
      }
    } finally {
      if (mounted) setState(() => _rotatingCode = false);
    }
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                      label: const Text('Copiar'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _rotatingCode ? null : _rotateCode,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      icon: _rotatingCode
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Cambiar'),
                    ),
                  ],
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
            ..._members.map((m) => _memberTile(m, _activeAssignment?.daysPerWeek ?? 0)),
        ],
      ),
    );
  }

  Widget _assignmentBanner(Assignment a) {
    final fmt = DateFormat('d MMM', 'es');
    final isFuture = a.isFuture();
    final isExpired = a.isExpired();

    String title;
    String subtitle;
    Color iconColor;
    IconData icon;

    if (isFuture) {
      title = 'Asignación programada: ${a.workoutTitle}';
      subtitle = 'Inicia el ${fmt.format(a.startAt)}${a.endAt != null ? ' · Termina el ${fmt.format(a.endAt!)}' : ''} · ${a.daysPerWeek} días/sem';
      iconColor = AppColors.warn;
      icon = Icons.schedule_rounded;
    } else if (isExpired) {
      title = 'Asignación finalizada: ${a.workoutTitle}';
      subtitle = 'Venció el ${fmt.format(a.endAt!)} · ${a.daysPerWeek} días/sem';
      iconColor = AppColors.muted;
      icon = Icons.event_busy_rounded;
    } else {
      title = 'Asignación activa: ${a.workoutTitle}';
      subtitle = 'Desde ${fmt.format(a.startAt)}${a.endAt != null ? ' hasta el ${fmt.format(a.endAt!)}' : ''} · ${a.daysPerWeek} días/sem';
      iconColor = AppColors.brand;
      icon = Icons.fitness_center_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFuture ? AppColors.surfaceAlt : AppColors.brandSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isFuture ? AppColors.ink : AppColors.brandDark,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isFuture
                        ? AppColors.muted
                        : AppColors.brandDark.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(GroupMember m, int daysPerWeek) {
    final noActivity = m.lastWorkoutAt == null;
    final daysSince = m.lastWorkoutAt == null
        ? null
        : DateTime.now().difference(m.lastWorkoutAt!).inDays;
    final warn = daysSince != null && daysSince >= 5;
    final adherencePct = daysPerWeek > 0
        ? (m.trainingDaysThisWeek / daysPerWeek * 100).clamp(0, 100).round()
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (warn || noActivity) ? AppColors.warn : AppColors.line,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            final gid = AppStore.instance.groupId;
            if (gid == null) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MemberProfilePage(
                  groupId: gid,
                  member: m,
                  activeAssignment: _activeAssignment,
                ),
              ),
            ).then((_) => _refresh());
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                            : adherencePct != null
                                ? '$adherencePct% esta semana (${m.trainingDaysThisWeek} de $daysPerWeek días) · último hace $daysSince días'
                                : '${m.trainingDaysThisWeek} esta semana · último hace $daysSince días',
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
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
