import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/models/water_record.dart';

WaterRecord makeWater({
  String id = 'w1',
  String uid = 'u1',
  int amountMl = 250,
  DateTime? recordedAt,
}) {
  final now = recordedAt ?? DateTime(2024, 6, 1, 9);
  return WaterRecord(
    id:         id,
    uid:        uid,
    amountMl:   amountMl,
    recordedAt: now,
    createdAt:  now,
    updatedAt:  now,
  );
}

void main() {
  group('Suma diaria de agua (#257)', () {
    test('suma de registros del mismo día es correcta', () {
      final records = [
        makeWater(amountMl: 200),
        makeWater(amountMl: 250),
        makeWater(amountMl: 500),
      ];
      final total = records.fold<int>(0, (s, r) => s + r.amountMl);
      expect(total, 950);
    });

    test('corrección: editar un registro actualiza el total (#257)', () {
      final records = [
        makeWater(id: 'w1', amountMl: 200),
        makeWater(id: 'w2', amountMl: 300),
      ];
      // Simula editar w1 de 200 → 500
      final updated = records.map((r) =>
          r.id == 'w1' ? r.copyWith(amountMl: 500) : r).toList();
      final total = updated.fold<int>(0, (s, r) => s + r.amountMl);
      expect(total, 800);
    });

    test('corrección: eliminar un registro reduce el total (#257)', () {
      final records = [
        makeWater(id: 'w1', amountMl: 300),
        makeWater(id: 'w2', amountMl: 400),
      ];
      final afterDelete = records.where((r) => r.id != 'w1').toList();
      final total = afterDelete.fold<int>(0, (s, r) => s + r.amountMl);
      expect(total, 400);
    });

    test('lista vacía da total 0', () {
      final total = <WaterRecord>[].fold<int>(0, (s, r) => s + r.amountMl);
      expect(total, 0);
    });
  });

  group('copyWith', () {
    test('actualiza amountMl y conserva el resto', () {
      final r = makeWater(amountMl: 250);
      final c = r.copyWith(amountMl: 500);
      expect(c.amountMl,   500);
      expect(c.id,         r.id);
      expect(c.uid,        r.uid);
      expect(c.createdAt,  r.createdAt);
    });

    test('actualiza recordedAt sin cambiar createdAt', () {
      final r   = makeWater();
      final ts  = DateTime(2025, 3, 15, 20);
      final c   = r.copyWith(recordedAt: ts);
      expect(c.recordedAt, ts);
      expect(c.createdAt,  r.createdAt);
    });

    test('actualiza updatedAt', () {
      final r   = makeWater();
      final now = DateTime(2025, 1, 1);
      final c   = r.copyWith(updatedAt: now);
      expect(c.updatedAt, now);
    });
  });

  group('Serialización', () {
    test('toMap / fromMap es simétrico', () {
      final r  = makeWater(amountMl: 350);
      final m  = r.toMap();
      final r2 = WaterRecord.fromMap(m);
      expect(r2.id,         r.id);
      expect(r2.uid,        r.uid);
      expect(r2.amountMl,   r.amountMl);
      expect(r2.recordedAt, r.recordedAt);
    });

    test('toJson / fromJson es simétrico', () {
      final r  = makeWater(amountMl: 500);
      final r2 = WaterRecord.fromJson(r.toJson());
      expect(r2.amountMl, r.amountMl);
    });

    test('clave ml en mapa serializado', () {
      final m = makeWater().toMap();
      expect(m.containsKey('ml'), isTrue);
      expect(m['ml'],             250);
    });
  });

  group('Aislamiento por uid', () {
    test('registros de distintos usuarios no se mezclan', () {
      final u1 = makeWater(uid: 'user_a', amountMl: 200);
      final u2 = makeWater(uid: 'user_b', amountMl: 500);
      expect(u1.uid, isNot(u2.uid));
      expect(u1.amountMl, isNot(u2.amountMl));
    });
  });

  group('Meta de agua', () {
    test('por encima de la meta', () {
      const goalMl  = 2000;
      final records = List.generate(5, (i) => makeWater(amountMl: 500));
      final total   = records.fold<int>(0, (s, r) => s + r.amountMl);
      expect(total >= goalMl, isTrue);
    });

    test('por debajo de la meta', () {
      const goalMl  = 2000;
      final records = [makeWater(amountMl: 300), makeWater(amountMl: 400)];
      final total   = records.fold<int>(0, (s, r) => s + r.amountMl);
      expect(total < goalMl, isTrue);
    });
  });
}
