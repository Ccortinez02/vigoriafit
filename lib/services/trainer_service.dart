import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/assignment.dart';
import '../models/workout.dart';

/// Un alumno dentro de un grupo, con su adherencia calculada.
class GroupMember {
  final String userId;
  final String name;
  final DateTime joinedAt;
  DateTime? lastWorkoutAt;
  int workoutsThisWeek = 0;

  GroupMember({
    required this.userId,
    required this.name,
    required this.joinedAt,
  });
}

/// Rol entrenador: crear un grupo, que alumnos se unan con un código, asignar
/// rutinas del catálogo existente al grupo, y ver la adherencia de cada
/// alumno (entrenamientos que de verdad completaron).
///
/// Usa UID de Firebase Auth. El permiso de entrenador se valida en las reglas
/// mediante una custom claim administrada fuera de la aplicación.
class TrainerService {
  TrainerService._();

  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');

  /// Crea un grupo nuevo y devuelve (groupId, código de 6 dígitos).
  static Future<(String, String)> createGroup(String trainerName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión.');
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _newCode();
      final doc = _groups.doc();
      final invite = _db.collection('groupInvites').doc(code);
      final created = await _db.runTransaction((tx) async {
        if ((await tx.get(invite)).exists) return false;
        tx.set(doc, {
          'trainerId': user.uid,
          'trainerName': trainerName,
          'code': code,
          'createdAt': FieldValue.serverTimestamp(),
          'assignedWorkoutId': null,
          'assignedWorkoutTitle': null,
        });
        tx.set(invite, {
          'groupId': doc.id,
          'trainerId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (created) return (doc.id, code);
    }
    throw StateError('No se pudo generar un código. Inténtalo nuevamente.');
  }

  static Future<String?> joinGroup(
    String code,
    String userId,
    String userName,
  ) async {
    if (FirebaseAuth.instance.currentUser?.uid != userId)
      throw StateError('Sesión inválida.');
    final invite = await _db.collection('groupInvites').doc(code.trim()).get();
    if (!invite.exists) return null;
    final groupId = invite.data()!['groupId'] as String;
    final member = _groups.doc(groupId).collection('members').doc(userId);
    await _db.runTransaction((tx) async {
      if (!(await tx.get(member)).exists) {
        tx.set(member, {
          'name': userName,
          'joinedAt': FieldValue.serverTimestamp(),
          'inviteCode': code.trim(),
        });
      }
    });
    return groupId;
  }

  static Future<void> leaveGroup(String groupId, String uid) async {
    await _groups.doc(groupId).collection('members').doc(uid).delete();
  }

  static Future<void> assignWorkout(String groupId, Workout w) async {
    await _groups.doc(groupId).update({
      'assignedWorkoutId': w.id,
      'assignedWorkoutTitle': w.title,
      'assignedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Escucha en vivo el grupo (para que el alumno vea si le asignaron algo
  /// nuevo sin tener que salir y volver a entrar).
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchGroup(
    String groupId,
  ) => _groups.doc(groupId).snapshots();

  static Future<Map<String, dynamic>?> getGroup(String groupId) async {
    final doc = await _groups.doc(groupId).get();
    return doc.data();
  }

  /// Registra cumplimiento de un entrenamiento. Usa [sessionId] como ID del
  /// documento: la operación es idempotente (reintentos seguros, sin duplicados).
  static Future<void> logCompletion(
    String groupId,
    String sessionId,
    String userId,
    String userName,
    Workout w, {
    String? assignmentId,
  }) async {
    final docRef =
        _groups.doc(groupId).collection('completions').doc(sessionId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (snap.exists) return; // idempotente
      tx.set(docRef, {
        'sessionId': sessionId,
        'userId': userId,
        'userName': userName,
        'workoutId': w.id,
        'workoutTitle': w.title,
        'completedAt': FieldValue.serverTimestamp(),
        if (assignmentId != null) 'assignmentId': assignmentId,
      });
    });
  }

  /// Crea una asignación de rutina al grupo y devuelve el [Assignment] creado.
  static Future<Assignment> createAssignment(
    String groupId,
    Workout w, {
    required int daysPerWeek,
    required DateTime startAt,
    DateTime? endAt,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión.');
    final docRef = _groups.doc(groupId).collection('assignments').doc();
    final now = DateTime.now();
    final data = {
      'groupId': groupId,
      'trainerId': user.uid,
      'workoutId': w.id,
      'workoutTitle': w.title,
      'exercisesSnapshot': Assignment.exerciseSnapshotFrom(w.exercises),
      'startAt': startAt.toIso8601String(),
      if (endAt != null) 'endAt': endAt.toIso8601String(),
      'daysPerWeek': daysPerWeek,
      'timezone': 'America/Santiago',
      'status': 'active',
      'createdAt': now.toIso8601String(),
    };
    await docRef.set(data);
    return Assignment.fromMap({'id': docRef.id, ...data});
  }

  /// Devuelve la asignación activa del grupo, o null si no existe.
  static Future<Assignment?> getActiveAssignment(String groupId) async {
    final snap = await _groups
        .doc(groupId)
        .collection('assignments')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return Assignment.fromMap({'id': doc.id, ...doc.data()});
  }

  /// Escucha en tiempo real la asignación activa del grupo.
  static Stream<Assignment?> watchActiveAssignment(String groupId) =>
      _groups
          .doc(groupId)
          .collection('assignments')
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots()
          .map((snap) {
        if (snap.docs.isEmpty) return null;
        final doc = snap.docs.first;
        return Assignment.fromMap({'id': doc.id, ...doc.data()});
      });

  /// Elimina a un miembro del grupo.
  static Future<void> removeMember(String groupId, String uid) =>
      leaveGroup(groupId, uid);

  /// Trae los miembros del grupo con su adherencia (entrenamientos en los
  /// últimos 7 días y fecha del último).
  static Future<List<GroupMember>> membersWithAdherence(String groupId) async {
    final membersSnap = await _groups.doc(groupId).collection('members').get();
    final members = <String, GroupMember>{};
    for (final d in membersSnap.docs) {
      final data = d.data();
      final joined =
          (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      members[d.id] = GroupMember(
        userId: d.id,
        name: data['name'] ?? '—',
        joinedAt: joined,
      );
    }
    if (members.isEmpty) return [];

    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final compSnap = await _groups
        .doc(groupId)
        .collection('completions')
        .where('completedAt', isGreaterThan: Timestamp.fromDate(weekAgo))
        .get();
    for (final d in compSnap.docs) {
      final data = d.data();
      final m = members[data['userId']];
      if (m == null) continue;
      m.workoutsThisWeek++;
      final at = (data['completedAt'] as Timestamp?)?.toDate();
      if (at != null &&
          (m.lastWorkoutAt == null || at.isAfter(m.lastWorkoutAt!))) {
        m.lastWorkoutAt = at;
      }
    }
    final list = members.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  static String _newCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }
}
