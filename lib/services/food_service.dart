import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/food_record.dart';
import '../models/logs.dart';
import 'account_preferences.dart';

/// CRUD de registros de comida, con persistencia local (SharedPreferences)
/// y sincronización a Firestore users/{uid}/food_records/{id}.
///
/// La fuente de verdad local es la lista completa serializada. Los totales
/// se derivan siempre de los registros vigentes, nunca de acumuladores.
class FoodService extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _kRecords = 'food_records_v1';

  String? _uid;
  AccountPreferences? _prefs;
  final List<FoodRecord> _records = [];

  List<FoodRecord> get records => List.unmodifiable(_records);

  // ── Carga / limpieza por cuenta ───────────────────────────────────────────

  Future<void> loadForUser(AccountPreferences prefs, String uid) async {
    _prefs = prefs;
    _uid   = uid;
    _records.clear();
    final raw = prefs.getStringList(_kRecords) ?? [];
    for (final s in raw) {
      try {
        final r = FoodRecord.fromJson(s);
        if (r.uid == uid) _records.add(r);
      } catch (_) {}
    }
    notifyListeners();
  }

  void clearForUser() {
    _uid    = null;
    _prefs  = null;
    _records.clear();
    notifyListeners();
  }

  // ── Consultas ─────────────────────────────────────────────────────────────

  List<FoodRecord> forDay(DateTime date) {
    final k = dayKey(date);
    return _records.where((r) => dayKey(r.consumedAt.toLocal()) == k).toList()
      ..sort((a, b) => a.consumedAt.compareTo(b.consumedAt));
  }

  double kcalForDay(DateTime date)    => forDay(date).fold(0, (s, r) => s + r.kcal);
  double proteinForDay(DateTime date) => forDay(date).fold(0, (s, r) => s + r.proteinG);
  double carbsForDay(DateTime date)   => forDay(date).fold(0, (s, r) => s + r.carbsG);
  double fatForDay(DateTime date)     => forDay(date).fold(0, (s, r) => s + r.fatG);

  // ── CRUD ──────────────────────────────────────────────────────────────────

  /// Añade un registro. El [id] se genera en cliente; reintentos con el mismo
  /// ID actualizan en vez de duplicar.
  Future<FoodRecord> add(FoodRecord r) async {
    _assertSession();
    final record = r.id.isEmpty
        ? FoodRecord(
            id:         _uuid.v4(),
            uid:        _uid!,
            foodId:     r.foodId,
            foodName:   r.foodName,
            refQty:     r.refQty,
            refUnit:    r.refUnit,
            kcalRef:    r.kcalRef,
            proteinRef: r.proteinRef,
            carbsRef:   r.carbsRef,
            fatRef:     r.fatRef,
            quantity:   r.quantity,
            unit:       r.unit,
            mealType:   r.mealType,
            consumedAt: r.consumedAt,
            createdAt:  r.createdAt,
            updatedAt:  r.updatedAt,
          )
        : r;
    final idx = _records.indexWhere((x) => x.id == record.id);
    if (idx >= 0) {
      _records[idx] = record;
    } else {
      _records.add(record);
    }
    notifyListeners();
    await _persist();
    _syncRecord(record);
    return record;
  }

  /// Actualiza un registro existente (conserva su ID y createdAt).
  Future<void> update(FoodRecord updated) async {
    _assertSession();
    final idx = _records.indexWhere((r) => r.id == updated.id);
    if (idx < 0) return;
    _records[idx] = updated;
    notifyListeners();
    await _persist();
    _syncRecord(updated);
  }

  /// Elimina un registro. La operación se persiste localmente de inmediato;
  /// si la sync remota falla, el registro ya no reaparecerá al reabrir.
  Future<void> delete(String id) async {
    _assertSession();
    _records.removeWhere((r) => r.id == id);
    notifyListeners();
    await _persist();
    _deleteRemote(id);
  }

  // ── Persistencia local ────────────────────────────────────────────────────

  Future<void> _persist() async {
    final p = _prefs;
    if (p == null) return;
    await p.setStringList(_kRecords, _records.map((r) => r.toJson()).toList());
  }

  // ── Sync remota (best-effort, silenciosa) ─────────────────────────────────

  void _syncRecord(FoodRecord r) {
    final uid = _uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('food_records')
        .doc(r.id)
        .set(_toFirestore(r))
        .catchError((_) {});
  }

  void _deleteRemote(String id) {
    final uid = _uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('food_records')
        .doc(id)
        .delete()
        .catchError((_) {});
  }

  Map<String, dynamic> _toFirestore(FoodRecord r) => {
    ...r.toMap(),
    'consumedAt': Timestamp.fromDate(r.consumedAt),
    'createdAt':  Timestamp.fromDate(r.createdAt),
    'updatedAt':  Timestamp.fromDate(r.updatedAt),
  };

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _assertSession() {
    if (_uid == null || _prefs == null) {
      throw StateError('FoodService: no hay sesión activa.');
    }
  }
}
