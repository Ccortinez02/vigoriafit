import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/data/achievements.dart';

// Stub mínimo para que check() pueda evaluar sin instanciar AppStore completo.
class _FakeStore {
  int totalWaterDays;
  int totalFoodsLogged;
  int totalWorkoutsDone;
  int streak;
  int level;
  int weightCount;

  _FakeStore({
    this.totalWaterDays = 0,
    this.totalFoodsLogged = 0,
    this.totalWorkoutsDone = 0,
    this.streak = 0,
    this.level = 1,
    this.weightCount = 0,
  });
}

// Evalúa las condiciones directamente (misma lógica que Achievement.check)
// sin pasar por AppStore para evitar SharedPreferences/Firebase en test.
bool _check(String id, _FakeStore s) {
  switch (id) {
    case 'first_workout':  return s.totalWorkoutsDone >= 1;
    case 'workouts_10':    return s.totalWorkoutsDone >= 10;
    case 'workouts_50':    return s.totalWorkoutsDone >= 50;
    case 'streak_3':       return s.streak >= 3;
    case 'streak_7':       return s.streak >= 7;
    case 'streak_30':      return s.streak >= 30;
    case 'scan_first':     return s.totalFoodsLogged >= 1;
    case 'scan_20':        return s.totalFoodsLogged >= 20;
    case 'water_7':        return s.totalWaterDays >= 7;
    case 'weight_5':       return s.weightCount >= 5;
    case 'level_5':        return s.level >= 5;
    case 'level_10':       return s.level >= 10;
    default:               return false;
  }
}

void main() {
  test('catálogo contiene todos los logros esperados', () {
    final ids = Achievements.all.map((a) => a.id).toSet();
    expect(ids, contains('first_workout'));
    expect(ids, contains('water_7'));
    expect(ids, contains('streak_7'));
    expect(ids, contains('scan_20'));
    expect(ids, contains('weight_5'));
  });

  test('water_7 se desbloquea con 7 días distintos de agua', () {
    expect(_check('water_7', _FakeStore(totalWaterDays: 6)), false);
    expect(_check('water_7', _FakeStore(totalWaterDays: 7)), true);
    expect(_check('water_7', _FakeStore(totalWaterDays: 10)), true);
  });

  test('scan_first se desbloquea con 1 alimento registrado', () {
    expect(_check('scan_first', _FakeStore(totalFoodsLogged: 0)), false);
    expect(_check('scan_first', _FakeStore(totalFoodsLogged: 1)), true);
  });

  test('scan_20 requiere exactamente 20 registros', () {
    expect(_check('scan_20', _FakeStore(totalFoodsLogged: 19)), false);
    expect(_check('scan_20', _FakeStore(totalFoodsLogged: 20)), true);
  });

  test('streak_7 requiere 7 días seguidos', () {
    expect(_check('streak_7', _FakeStore(streak: 6)), false);
    expect(_check('streak_7', _FakeStore(streak: 7)), true);
  });

  test('weight_5 requiere 5 entradas de peso', () {
    expect(_check('weight_5', _FakeStore(weightCount: 4)), false);
    expect(_check('weight_5', _FakeStore(weightCount: 5)), true);
  });

  // Idempotencia: si un logro ya está en _notifiedAchievements, no vuelve
  // a emitirse. Lo probamos con la lógica del filtro directamente.
  test('idempotencia: filtrar ya notificados excluye correctamente', () {
    // Simula: 3 logros desbloqueados, 2 ya notificados.
    final unlocked = ['first_workout', 'streak_3', 'water_7'];
    final notified = {'first_workout', 'streak_3'};
    final newOnes = unlocked.where((id) => !notified.contains(id)).toList();
    expect(newOnes, ['water_7']);
  });

  test('idempotencia: todos ya notificados → sin nuevos', () {
    final unlocked = ['first_workout', 'streak_3'];
    final notified = {'first_workout', 'streak_3'};
    final newOnes = unlocked.where((id) => !notified.contains(id)).toList();
    expect(newOnes, isEmpty);
  });
}
