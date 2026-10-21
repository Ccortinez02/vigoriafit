import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/workout_session.dart';
import '../services/store.dart';
import '../services/workout_session_service.dart';

// ── Períodos de filtro ────────────────────────────────────────────────────────

enum HistoryPeriod { all, week, month, custom }

extension HistoryPeriodX on HistoryPeriod {
  String get label => switch (this) {
        HistoryPeriod.all => 'Todo',
        HistoryPeriod.week => 'Esta semana',
        HistoryPeriod.month => 'Este mes',
        HistoryPeriod.custom => 'Personalizado',
      };

  bool Function(WorkoutSession) get filter {
    final now = DateTime.now();
    return switch (this) {
      HistoryPeriod.all => (_) => true,
      HistoryPeriod.week => (s) {
          final start = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          return !s.startedAt.isBefore(start);
        },
      HistoryPeriod.month => (s) =>
          s.startedAt.year == now.year && s.startedAt.month == now.month,
      HistoryPeriod.custom => (_) => true,
    };
  }
}

// ── Historial ─────────────────────────────────────────────────────────────────

class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({super.key});

  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage> {
  HistoryPeriod _period = HistoryPeriod.all;
  DateTimeRange? _customRange;
  bool _loading = false;

  WorkoutSessionService get _svc => AppStore.instance.sessions;

  List<WorkoutSession> get _filtered {
    var list = _svc.history
        .where((s) => s.status == WorkoutStatus.finished)
        .toList();

    if (_period == HistoryPeriod.custom && _customRange != null) {
      final start = DateTime(_customRange!.start.year,
          _customRange!.start.month, _customRange!.start.day);
      final end = DateTime(_customRange!.end.year, _customRange!.end.month,
              _customRange!.end.day)
          .add(const Duration(days: 1));
      list = list.where((s) => !s.startedAt.isBefore(start) && s.startedAt.isBefore(end)).toList();
    } else {
      list = list.where(_period.filter).toList();
    }

    list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  Future<void> _loadRemote() async {
    final uid = AppStore.instance.currentUid;
    final prefs = AppStore.instance.currentPrefs;
    if (uid == null || prefs == null) return;
    setState(() => _loading = true);
    await _svc.fetchRemoteHistory(uid, FirebaseFirestore.instance);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _loadRemote();
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
      locale: const Locale('es'),
    );
    if (range != null) {
      setState(() {
        _customRange = range;
        _period = HistoryPeriod.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _svc,
      builder: (context, _) {
        final sessions = _filtered;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Historial',
                style: TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Actualizar',
                  onPressed: _loadRemote,
                ),
            ],
          ),
          body: Column(
            children: [
              _PeriodFilter(
                selected: _period,
                customRange: _customRange,
                onChanged: (p) {
                  if (p == HistoryPeriod.custom) {
                    _pickCustomRange();
                  } else {
                    setState(() {
                      _period = p;
                      _customRange = null;
                    });
                  }
                },
              ),
              Expanded(
                child: sessions.isEmpty
                    ? _EmptyState(period: _period)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        itemCount: sessions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) => _SessionCard(
                          session: sessions[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WorkoutSessionDetailPage(
                                  session: sessions[i]),
                            ),
                          ),
                          onRetrySync: sessions[i].syncState ==
                                  SessionSyncState.failed
                              ? () => _svc.retrySync(
                                    sessions[i].id,
                                    AppStore.instance.currentPrefs!,
                                    FirebaseFirestore.instance,
                                  )
                              : null,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Filtro de período ─────────────────────────────────────────────────────────

class _PeriodFilter extends StatelessWidget {
  final HistoryPeriod selected;
  final DateTimeRange? customRange;
  final ValueChanged<HistoryPeriod> onChanged;

  const _PeriodFilter({
    required this.selected,
    required this.customRange,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          ...HistoryPeriod.values.map((p) {
            final isSelected = selected == p &&
                (p != HistoryPeriod.custom || customRange != null);
            final label = p == HistoryPeriod.custom && customRange != null
                ? '${_fmtDate(customRange!.start)} – ${_fmtDate(customRange!.end)}'
                : p.label;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label, style: const TextStyle(fontSize: 12.5)),
                selected: isSelected,
                onSelected: (_) => onChanged(p),
                selectedColor: AppColors.brandSoft,
                checkmarkColor: AppColors.brand,
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      DateFormat('d MMM', 'es').format(d);
}

// ── Tarjeta de sesión ─────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final WorkoutSession session;
  final VoidCallback onTap;
  final VoidCallback? onRetrySync;

  const _SessionCard({
    required this.session,
    required this.onTap,
    this.onRetrySync,
  });

  @override
  Widget build(BuildContext context) {
    final startStr = _fmtDateTime(session.startedAt);
    final duration =
        session.finishedAt?.difference(session.startedAt);
    final durationStr = duration != null ? _fmtDuration(duration) : '';
    final seriesCount = session.totalDoneSeries;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.mintSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.fitness_center_rounded,
                  color: AppColors.mint, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.workoutTitle,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(startStr,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                      if (durationStr.isNotEmpty) ...[
                        Text('  ·  ',
                            style: TextStyle(color: AppColors.faint)),
                        Text(durationStr,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.muted)),
                      ],
                      if (seriesCount > 0) ...[
                        Text('  ·  ',
                            style: TextStyle(color: AppColors.faint)),
                        Text('$seriesCount series',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.muted)),
                      ],
                    ],
                  ),
                  if (session.syncState == SessionSyncState.pending ||
                      session.syncState == SessionSyncState.failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            session.syncState == SessionSyncState.failed
                                ? Icons.error_outline_rounded
                                : Icons.cloud_upload_outlined,
                            size: 13,
                            color: session.syncState == SessionSyncState.failed
                                ? AppColors.danger
                                : AppColors.warn,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            session.syncState == SessionSyncState.failed
                                ? 'Error al sincronizar'
                                : 'Pendiente de sincronización',
                            style: TextStyle(
                              fontSize: 11,
                              color: session.syncState ==
                                      SessionSyncState.failed
                                  ? AppColors.danger
                                  : AppColors.warn,
                            ),
                          ),
                          if (onRetrySync != null) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: onRetrySync,
                              child: Text('Reintentar',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.brand,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.faint),
          ],
        ),
      ),
    );
  }

  String _fmtDateTime(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(d.year, d.month, d.day);
    final time = DateFormat('HH:mm').format(d);
    if (day == today) return 'Hoy $time';
    if (day == yesterday) return 'Ayer $time';
    return '${DateFormat('d MMM', 'es').format(d)} $time';
  }

  String _fmtDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
    }
    return '${d.inMinutes}m';
  }
}

// ── Estado vacío ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final HistoryPeriod period;

  const _EmptyState({required this.period});

  @override
  Widget build(BuildContext context) {
    final msg = period == HistoryPeriod.all
        ? 'Aún no tienes entrenamientos completados.\nInicia una rutina y finalízala para verla aquí.'
        : 'No hay entrenamientos en este período.\nPrueba con otro rango de fechas.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 56, color: AppColors.faint),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detalle de sesión ─────────────────────────────────────────────────────────

class WorkoutSessionDetailPage extends StatelessWidget {
  final WorkoutSession session;

  const WorkoutSessionDetailPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(session.workoutTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _SummaryHeader(session: session),
          const SizedBox(height: 20),
          ...session.exercises.where((e) => e.series.isNotEmpty).map(
                (e) => _ExerciseSection(exercise: e),
              ),
          if (session.exercises.every((e) => e.series.isEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(
                child: Text('No se registraron series en esta sesión.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final WorkoutSession session;

  const _SummaryHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    final duration =
        session.finishedAt?.difference(session.startedAt);
    final doneSeries = session.totalDoneSeries;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_fmtDateTime(session.startedAt),
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 8),
          Row(
            children: [
              _stat(Icons.format_list_numbered_rounded,
                  '$doneSeries series', 'completadas'),
              if (duration != null)
                _stat(Icons.timer_outlined, _fmtDuration(duration), 'duración'),
              _stat(
                Icons.cloud_done_rounded,
                _syncLabel(session.syncState),
                '',
                color: _syncColor(session.syncState),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: color ?? AppColors.brand),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color ?? AppColors.ink)),
          if (label.isNotEmpty)
            Text(label,
                style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime d) =>
      DateFormat("d 'de' MMMM y, HH:mm", 'es').format(d);

  String _fmtDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${(d.inMinutes % 60)}m';
    }
    return '${d.inMinutes}m';
  }

  String _syncLabel(SessionSyncState s) => switch (s) {
        SessionSyncState.local => 'Local',
        SessionSyncState.pending => 'Pendiente',
        SessionSyncState.confirmed => 'Sincronizado',
        SessionSyncState.failed => 'Error sync',
      };

  Color _syncColor(SessionSyncState s) => switch (s) {
        SessionSyncState.local => AppColors.muted,
        SessionSyncState.pending => AppColors.warn,
        SessionSyncState.confirmed => AppColors.success,
        SessionSyncState.failed => AppColors.danger,
      };
}

class _ExerciseSection extends StatelessWidget {
  final SessionExercise exercise;

  const _ExerciseSection({required this.exercise});

  @override
  Widget build(BuildContext context) {
    final doneSeries =
        exercise.series.where((s) => s.status == SeriesStatus.done).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/exercises/${exercise.pose}.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.exerciseName,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    Text('Objetivo: ${exercise.setsTarget}',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mintSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${doneSeries.length} series',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mint)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...doneSeries.map((s) => _seriesRow(s)),
        ],
      ),
    );
  }

  Widget _seriesRow(SeriesEntry s) {
    final label = _seriesLabel(s);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5, left: 52),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(6)),
            child: Center(
              child: Text('${s.setIndex + 1}',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
            ),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink)),
        ],
      ),
    );
  }

  String _seriesLabel(SeriesEntry s) => switch (s.type) {
        TrackingType.reps => '${s.reps ?? 0} reps',
        TrackingType.repsAndLoad => () {
            final load = s.loadKg != null && s.loadKg! > 0
                ? ' · ${s.loadKg!.toStringAsFixed(s.loadKg! == s.loadKg!.roundToDouble() ? 0 : 1)} kg'
                : '';
            return '${s.reps ?? 0} reps$load';
          }(),
        TrackingType.duration => () {
            final sec = s.durationSec ?? 0;
            return sec >= 60
                ? '${sec ~/ 60}m ${sec % 60}s'
                : '${sec}s';
          }(),
      };
}
