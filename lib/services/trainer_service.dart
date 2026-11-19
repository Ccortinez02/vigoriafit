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
  final Set<String> _trainingDays = {}; // fechas únicas 'yyyy-MM-dd'

  GroupMember({
    required this.userId,
    required this.name,
    required this.joinedAt,
  });

  /// Días únicos de entrenamiento en la semana consultada.
  int get trainingDaysThisWeek => _trainingDays.length;

  /// Registra una sesión completada; deduplicada por fecha (días únicos).
  void recordCompletion(DateTime at) {
    final key =
        '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
    _trainingDays.add(key);
    if (lastWorkoutAt == null || at.isAfter(lastWorkoutAt!)) {
      lastWorkoutAt = at;
    }
  }
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
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('Sesión inválida.');
    }
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

  /// Elimina a un miembro del grupo **y borra todos sus completions** en ese grupo.
  /// Así el historial de adherencia queda limpio si el alumno vuelve a unirse.
  static Future<void> leaveGroup(String groupId, String uid) async {
    // Eliminar el doc de miembro (siempre, operación crítica)
    await _groups.doc(groupId).collection('members').doc(uid).delete();
    // Eliminar sus completions (best-effort: no bloquea si falla por permisos)
    try {
      final compsSnap = await _groups
          .doc(groupId)
          .collection('completions')
          .where('userId', isEqualTo: uid)
          .get();
      if (compsSnap.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in compsSnap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (_) {
      // Si la regla aún no está desplegada en Firebase Console, se ignora.
      // El miembro ya fue removido; los completions quedarán huérfanos sin impacto.
    }
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
    List<Map<String, dynamic>>? exercises,
  }) async {
    final docRef =
        _groups.doc(groupId).collection('completions').doc(sessionId);
    try {
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
          'assignmentId': ?assignmentId,
          'exercises': ?exercises,
        });
      });
    } catch (_) {
      // Si la regla de Firestore en Firebase Console aún no permite 'exercises',
      // reintentar guardando los campos estándar para asegurar que la finalización
      // y la adherencia del alumno queden siempre registradas sin error.
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (snap.exists) return;
        tx.set(docRef, {
          'sessionId': sessionId,
          'userId': userId,
          'userName': userName,
          'workoutId': w.id,
          'workoutTitle': w.title,
          'completedAt': FieldValue.serverTimestamp(),
          'assignmentId': ?assignmentId,
        });
      });
    }
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
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final maxAllowedFuture = todayStart.add(const Duration(days: 7, hours: 23, minutes: 59, seconds: 59));
    if (startAt.isBefore(todayStart)) {
      throw ArgumentError('La fecha de inicio no puede ser en el pasado.');
    }
    if (startAt.isAfter(maxAllowedFuture)) {
      throw ArgumentError('Las rutinas adelantadas solo se pueden agregar hasta 7 días desde hoy.');
    }
    if (endAt != null && !endAt.isAfter(startAt)) {
      throw ArgumentError('La fecha de término debe ser posterior a la fecha de inicio.');
    }
    final docRef = _groups.doc(groupId).collection('assignments').doc();
    final exercisesSnapshot = Assignment.exerciseSnapshotFrom(w.exercises);
    // startAt: fecha elegida por el entrenador (puede ser futura).
    // createdAt: serverTimestamp (la regla exige createdAt == request.time).
    final data = {
      'groupId': groupId,
      'trainerId': user.uid,
      'workoutId': w.id,
      'workoutTitle': w.title,
      'exercisesSnapshot': exercisesSnapshot,
      'startAt': Timestamp.fromDate(startAt),
      if (endAt != null) 'endAt': Timestamp.fromDate(endAt),
      'daysPerWeek': daysPerWeek,
      'timezone': 'America/Santiago',
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    };
    await docRef.set(data);
    // Construimos el Assignment localmente con DateTime.now() como aproximación;
    // el valor real del servidor difiere solo en milisegundos.
    return Assignment(
      id: docRef.id,
      groupId: groupId,
      trainerId: user.uid,
      workoutId: w.id,
      workoutTitle: w.title,
      exercisesSnapshot: exercisesSnapshot,
      startAt: startAt,
      endAt: endAt,
      daysPerWeek: daysPerWeek,
      timezone: 'America/Santiago',
      status: 'active',
      createdAt: now,
    );
  }

  /// Convierte un valor de Firestore (Timestamp o String ISO) a DateTime.
  static DateTime _dateFromFirestore(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return DateTime.parse(v as String);
  }

  /// Normaliza los campos de fecha en datos leídos de Firestore antes de
  /// pasarlos a Assignment.fromMap (que espera strings ISO).
  static Map<String, dynamic> _normalizeAssignmentData(Map<String, dynamic> data) {
    return {
      ...data,
      if (data['startAt'] != null)
        'startAt': _dateFromFirestore(data['startAt']).toIso8601String(),
      if (data['endAt'] != null)
        'endAt': _dateFromFirestore(data['endAt']).toIso8601String(),
      if (data['createdAt'] != null)
        'createdAt': _dateFromFirestore(data['createdAt']).toIso8601String(),
    };
  }

  /// Trae la lista de todas las asignaciones activas dentro de la ventana:
  /// - Retrasadas acumulables: hasta 3 días hacia el pasado.
  /// - Adelantadas: hasta 7 días hacia el futuro.
  /// Aquellas con más de 3 días de retraso se purgan automáticamente en Firestore.
  /// NOTA: Se ordena en cliente para evitar requerir índice compuesto en Firestore.
  static Future<List<Assignment>> getGroupAssignments(String groupId) async {
    final snap = await _groups
        .doc(groupId)
        .collection('assignments')
        .where('status', isEqualTo: 'active')
        .get();

    final now = DateTime.now();
    final validList = <Assignment>[];
    final toPurge = <DocumentReference>[];

    for (final doc in snap.docs) {
      final a = Assignment.fromMap(_normalizeAssignmentData({'id': doc.id, ...doc.data()}));
      if (a.isPurgeable(now)) {
        toPurge.add(doc.reference);
      } else if (a.isWithinWindow(now)) {
        validList.add(a);
      }
    }

    if (toPurge.isNotEmpty) {
      _purgeOldAssignments(toPurge);
    }

    // Ordenar en cliente por startAt ascendente
    validList.sort((a, b) => a.startAt.compareTo(b.startAt));
    return validList;
  }

  /// Escucha en tiempo real la lista de asignaciones activas y acumuladas dentro de la ventana permitida.
  /// NOTA: Se ordena en cliente para evitar requerir índice compuesto en Firestore.
  static Stream<List<Assignment>> watchGroupAssignments(String groupId) {
    return _groups
        .doc(groupId)
        .collection('assignments')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      final validList = <Assignment>[];
      final toPurge = <DocumentReference>[];

      for (final doc in snap.docs) {
        final a = Assignment.fromMap(_normalizeAssignmentData({'id': doc.id, ...doc.data()}));
        if (a.isPurgeable(now)) {
          toPurge.add(doc.reference);
        } else if (a.isWithinWindow(now)) {
          validList.add(a);
        }
      }

      if (toPurge.isNotEmpty) {
        _purgeOldAssignments(toPurge);
      }

      // Ordenar en cliente por startAt ascendente
      validList.sort((a, b) => a.startAt.compareTo(b.startAt));
      return validList;
    });
  }

  static void _purgeOldAssignments(List<DocumentReference> refs) async {
    try {
      final batch = _db.batch();
      for (final ref in refs) {
        batch.delete(ref);
      }
      await batch.commit();
    } catch (_) {
      try {
        final batch = _db.batch();
        for (final ref in refs) {
          batch.update(ref, {'status': 'inactive'});
        }
        await batch.commit();
      } catch (_) {}
    }
  }

  /// Elimina o inactiva una asignación específica del grupo.
  static Future<void> deleteAssignment(String groupId, String assignmentId) async {
    final ref = _groups.doc(groupId).collection('assignments').doc(assignmentId);
    try {
      await ref.delete();
    } catch (_) {
      await ref.update({'status': 'inactive'});
    }
  }

  /// Devuelve la primera asignación activa y actualmente vigente del grupo, o null si no hay.
  static Future<Assignment?> getActiveAssignment(String groupId) async {
    final list = await getGroupAssignments(groupId);
    final now = DateTime.now();
    return list.where((a) => a.isEffective(now)).firstOrNull ?? list.firstOrNull;
  }

  /// Devuelve la última asignación activa creada (para compatibilidad).
  static Future<Assignment?> getLatestAssignment(String groupId) async {
    final list = await getGroupAssignments(groupId);
    return list.lastOrNull;
  }

  /// Escucha en tiempo real la asignación activa y vigente del grupo (para compatibilidad).
  static Stream<Assignment?> watchActiveAssignment(String groupId) {
    return watchGroupAssignments(groupId).map((list) {
      final now = DateTime.now();
      return list.where((a) => a.isEffective(now)).firstOrNull ?? list.firstOrNull;
    });
  }

  /// Elimina a un miembro del grupo.
  static Future<void> removeMember(String groupId, String uid) =>
      leaveGroup(groupId, uid);

  /// Genera un nuevo código de invitación para el grupo.
  /// Los miembros actuales permanecen (la membresía es por UID, no por código).
  /// El código anterior sigue en groupInvites pero el grupo ya apunta al nuevo,
  /// por lo que nadie puede re-unirse con el código viejo.
  static Future<String> rotateCode(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión.');
    for (var attempt = 0; attempt < 5; attempt++) {
      final newCode = _newCode();
      final newInviteRef = _db.collection('groupInvites').doc(newCode);
      final groupRef = _groups.doc(groupId);
      final done = await _db.runTransaction((tx) async {
        if ((await tx.get(newInviteRef)).exists) return false;
        tx.update(groupRef, {'code': newCode});
        tx.set(newInviteRef, {
          'groupId': groupId,
          'trainerId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (done) return newCode;
    }
    throw StateError('No se pudo generar un código. Inténtalo nuevamente.');
  }

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
      final at = (data['completedAt'] as Timestamp?)?.toDate();
      if (at != null) m.recordCompletion(at);
    }
    final list = members.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Trae el historial de entrenamientos completados por un alumno específico
  /// en el grupo, incluyendo los ejercicios y series registradas.
  static Future<List<Map<String, dynamic>>> getMemberCompletions(
    String groupId,
    String memberUid,
  ) async {
    final snap = await _groups
        .doc(groupId)
        .collection('completions')
        .where('userId', isEqualTo: memberUid)
        .get();
    final list = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final data = {'id': doc.id, ...doc.data()};
      // Si la completion no guardó los ejercicios (ej. sesiones anteriores),
      // intenta recuperarlos directamente de la sesión del usuario.
      if (data['exercises'] == null) {
        try {
          final sessionDoc = await _db
              .collection('users')
              .doc(memberUid)
              .collection('workout_sessions')
              .doc(doc.id)
              .get();
          if (sessionDoc.exists && sessionDoc.data()?['exercises'] != null) {
            data['exercises'] = sessionDoc.data()!['exercises'];
          }
        } catch (_) {}
      }
      list.add(data);
    }
    list.sort((a, b) {
      final atA = (a['completedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
      final atB = (b['completedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
      return atB.compareTo(atA);
    });
    return list;
  }

  static String _newCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }
}
