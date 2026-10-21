import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/logs.dart';
import '../models/water_record.dart';
import 'account_preferences.dart';

/// CRUD de registros individuales de consumo de agua.
///
/// El total de un día es la suma de los registros vigentes para ese día,
/// nunca un acumulador independiente.
///
/// La meta diaria de agua se lee/escribe en [AccountPreferences] bajo la
/// clave [_kGoal] y se expone como [goalMl].
class WaterService extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _kRecords = 'water_records_v1';
  static const _kGoal    = 'water_goal_ml_v1';
  static const _defaultGoalMl = 2000;

  String? _uid;
  AccountPreferences? _prefs;
  final List<WaterRecord> _records = [];
  int _goalMl = _defaultGoalMl;

  List<WaterRecord> get records => List.unmodifiable(_records);
  int get goalMl => _goalMl;

  // ── Carga / limpieza por cuenta ───────────────────────────────────────────

  Future<void> loadForUser(AccountPreferences prefs, String uid) async {
    _prefs = prefs;
    _uid   = uid;
    _records.clear();
    _goalMl = prefs.getInt(_kGoal) ?? _defaultGoalMl;
    final raw = prefs.getStringList(_kRecords) ?? [];
    for (final s in raw) {
      try {
        final r = WaterRecord.fromJson(s);
        if (r.uid == uid) _records.add(r);
      } catch (_) {}
    }
    notifyListeners();
  }

  void clearForUser() {
    _uid     = null;
    _prefs   = null;
    _records.clear();
    _goalMl  = _defaultGoalMl;
    notifyListeners();
  }

  // ── Consultas ─────────────────────────────────────────────────────────────

  List<WaterRecord> forDay(DateTime date) {
    final k = dayKey(date);
    return _records.where((r) => dayKey(r.recordedAt.toLocal()) == k).toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  }

  /// Total de mililitros para el día indicado, derivado de los registros vigentes.
  int totalMlForDay(DateTime date) =>
      forDay(date).fold(0, (s, r) => s + r.amountMl);

  // ── Meta de agua ──────────────────────────────────────────────────────────

  Future<void> setGoalMl(int ml) async {
    if (ml <= 0) throw ArgumentError('La meta debe ser mayor que 0 ml.');
    _goalMl = ml;
    notifyListeners();
    final p = _prefs;
    if (p != null) await p.setInt(_kGoal, ml);
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<WaterRecord> add(int amountMl, {DateTime? recordedAt}) async {
    _assertSession();
    if (amountMl <= 0) throw ArgumentError('La cantidad debe ser mayor que 0 ml.');
    final now = DateTime.now();
    final r = WaterRecord(
      id:         _uuid.v4(),
      uid:        _uid!,
      amountMl:   amountMl,
      recordedAt: recordedAt ?? now,
      createdAt:  now,
      updatedAt:  now,
    );
    _records.add(r);
    notifyListeners();
    await _persist();
    _syncRecord(r);
    return r;
  }

  Future<void> update(String id, {int? amountMl, DateTime? recordedAt}) async {
    _assertSession();
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final prev = _records[idx];
    if (amountMl != null && amountMl <= 0) {
      throw ArgumentError('La cantidad debe ser mayor que 0 ml.');
    }
    final updated = prev.copyWith(
      amountMl:   amountMl,
      recordedAt: recordedAt,
      updatedAt:  DateTime.now(),
    );
    _records[idx] = updated;
    notifyListeners();
    await _persist();
    _syncRecord(updated);
  }

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

  void _syncRecord(WaterRecord r) {
    final uid = _uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('water_records')
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
        .collection('water_records')
        .doc(id)
        .delete()
        .catchError((_) {});
  }

  Map<String, dynamic> _toFirestore(WaterRecord r) => {
    ...r.toMap(),
    'recordedAt': Timestamp.fromDate(r.recordedAt),
    'createdAt':  Timestamp.fromDate(r.createdAt),
    'updatedAt':  Timestamp.fromDate(r.updatedAt),
  };

  void _assertSession() {
    if (_uid == null || _prefs == null) {
      throw StateError('WaterService: no hay sesión activa.');
    }
  }
}
