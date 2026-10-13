import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/profile.dart';
import 'auth_service.dart';
import 'profile_repository.dart';

/// Core Firestore API, default database; private fields never go in users/{uid}.
class FirebaseProfileRepository implements ProfileRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  static const _basicFields = [
    'name',
    'goal',
    'level',
    'daysPerWeek',
    'hasGym',
  ];
  Map<String, dynamic> _basic(Profile profile) => Map.fromEntries(
    profile.toMap().entries.where((entry) => _basicFields.contains(entry.key)),
  );
  Map<String, dynamic> _private(Profile profile) => Map.fromEntries(
    profile.toMap().entries.where((entry) => !_basicFields.contains(entry.key)),
  );

  @override
  Future<AccountProfile> loadOrCreate(AccountIdentity user) async {
    final ref = _db.collection('users').doc(user.uid);
    final health = ref.collection('private').doc('health_profile');
    final values = await Future.wait([
      ref.get(const GetOptions(source: Source.server)),
      health.get(const GetOptions(source: Source.server)),
    ]).timeout(const Duration(seconds: 20));
    var base = values[0].data();
    var private = values[1].data();
    if (base == null || private == null) {
      await _db
          .runTransaction((tx) async {
            final a = await tx.get(ref);
            final b = await tx.get(health);
            final initial = Profile(name: user.name);
            if (!a.exists) {
              tx.set(ref, {
                ..._basic(initial),
                'onboarded': false,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
            if (!b.exists) {
              tx.set(health, {
                ..._private(initial),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
            base = a.data() ?? {..._basic(initial), 'onboarded': false};
            private = b.data() ?? _private(initial);
          })
          .timeout(const Duration(seconds: 20));
    }
    final current = FirebaseAuth.instance.currentUser;
    if (current?.uid != user.uid) throw StateError('La sesión cambió.');
    final token = await current!.getIdTokenResult();
    return AccountProfile(
      Profile.fromMap({...base!, ...private!}),
      onboarded: base!['onboarded'] == true,
      trainer: token.claims?['trainer'] == true,
    );
  }

  @override
  Future<void> save(
    String uid,
    Profile profile, {
    required bool onboarded,
  }) async {
    final ref = _db.collection('users').doc(uid);
    // A transaction fails offline instead of silently queuing a profile overwrite.
    await _db
        .runTransaction((tx) async {
          final current = await tx.get(ref);
          if (!current.exists) throw StateError('Primero recupera el perfil.');
          tx.update(ref, {
            ..._basic(profile),
            'onboarded': onboarded,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          tx.set(ref.collection('private').doc('health_profile'), {
            ..._private(profile),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        })
        .timeout(const Duration(seconds: 20));
  }
}
