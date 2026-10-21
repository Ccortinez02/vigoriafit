import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/nutrition.dart';
import '../data/workouts.dart';
import '../models/profile.dart';
import '../services/store.dart';
import 'achievements_page.dart';
import 'settings_page.dart';
import 'week_plan_page.dart';
import 'workout_detail_page.dart';

class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final s = AppStore.instance;
        final p = s.profile;
        final workout = Workouts.todayFor(p);
        final done = s.isWorkoutDoneToday(workout.id);
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                // Encabezado
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hola, ${p.name} 👋',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink)),
                          Text(Fmt.date(DateTime.now()),
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AchievementsPage())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.military_tech_rounded,
                                size: 16, color: AppColors.brandDark),
                            const SizedBox(width: 4),
                            Text('Nv. ${s.level}',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brandDark)),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsPage())),
                      icon: Icon(Icons.settings_outlined, color: AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Accesos rápidos: plan semanal IA + logros
                Row(
                  children: [
                    Expanded(
                      child: _quickAccess(
                        context,
                        emoji: '🗓️',
                        title: 'Plan semanal',
                        subtitle: 'Armado por IA',
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const WeekPlanPage())),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _quickAccess(
                        context,
                        emoji: '🏆',
                        title: 'Logros',
                        subtitle: '${s.level} · nivel actual',
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AchievementsPage())),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Tarjeta hero: objetivo + racha
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.brand, AppColors.brandDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(p.goal.emoji,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                          Text('Tu objetivo',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 13.5)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(p.goal.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _heroStat('🔥', '${s.streak}', 'días de racha'),
                          const SizedBox(width: 12),
                          _heroStat('💪', '${s.workoutsThisWeek}', 'entrenos/sem'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Entreno de hoy
                _sectionTitle('Entreno de hoy'),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppColors.brandSoft,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(Icons.fitness_center_rounded,
                                  color: AppColors.brand),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(workout.title,
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink)),
                                  Text('${workout.minutes} min · ${workout.focus}',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: done
                              ? OutlinedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => WorkoutDetailPage(
                                              workout: workout))),
                                  icon: const Icon(Icons.check_circle_rounded,
                                      color: AppColors.success),
                                  label: const Text('¡Completado hoy!'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.success,
                                    side:
                                        const BorderSide(color: AppColors.success),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => WorkoutDetailPage(
                                              workout: workout))),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Empezar entreno'),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Agua
                _sectionTitle('Hidratación'),
                const SizedBox(height: 8),
                _waterCard(s),
                const SizedBox(height: 16),

                // Menú sugerido
                _sectionTitle('Comida sugerida hoy'),
                const SizedBox(height: 8),
                _menuPreview(p.goal),
                const SizedBox(height: 16),

                // Consejo
                _tipCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _quickAccess(BuildContext context,
      {required String emoji,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(String emoji, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                Text(label,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _waterCard(AppStore s) {
    final today   = DateTime.now();
    final totalMl = s.waters.totalMlForDay(today);
    final goalMl  = s.waterGoalMl;
    final pct     = (totalMl / goalMl).clamp(0, 1).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop_rounded, color: AppColors.water),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('$totalMl ml de $goalMl ml',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                ),
                if (totalMl >= goalMl)
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              for (final ml in [200, 250, 500])
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: OutlinedButton(
                    onPressed: () => s.waters.add(ml),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.water),
                      foregroundColor: AppColors.water,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 34),
                    ),
                    child: Text('+$ml', style: const TextStyle(fontSize: 12)),
                  ),
                )),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 9,
                backgroundColor: AppColors.line,
                color: AppColors.water,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuPreview(Goal goal) {
    final menu = Nutrition.dayMenu(goal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          children: menu.entries.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Text(e.key.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key.label,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.muted)),
                        Text(e.value.name,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink)),
                      ],
                    ),
                  ),
                  Text('${e.value.kcal} kcal',
                      style: TextStyle(fontSize: 12, color: AppColors.faint)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _tipCard() {
    final tip = Nutrition.tips[DateTime.now().day % Nutrition.tips.length];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mintSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tip,
                style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.ink,
                    height: 1.35,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink));
}
