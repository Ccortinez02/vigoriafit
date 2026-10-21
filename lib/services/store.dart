import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/achievements.dart';
import '../models/exercise_log.dart';
import '../models/logs.dart';
import '../models/profile.dart';
import '../models/week_plan.dart';
import 'notifications.dart';
import 'auth_service.dart';
import 'account_preferences.dart';
import 'profile_repository.dart';
import 'firebase_profile_repository.dart';
import 'sync_state.dart';
import 'unit_system.dart';
import 'food_service.dart';
import 'water_service.dart';
import 'workout_session_service.dart';

/// Perfil remoto por UID y registros locales separados por cuenta.
class AppStore extends ChangeNotifier {
  AppStore({
    required AccountAuth auth,
    required ProfileRepository profiles,
    Future<void> Function()? clearReminders,
    WorkoutSessionService? sessionService,
    FoodService? foodService,
    WaterService? waterService,
  }) : _auth = auth,
       _profiles = profiles,
       _clearReminders =
           clearReminders ??
           (() async {
             await Notifications.cancelWorkout();
             await Notifications.cancelWater();
           }),
       sessions = sessionService ?? WorkoutSessionService(),
       foods    = foodService  ?? FoodService(),
       waters   = waterService ?? WaterService();
  static final AppStore instance = AppStore(
    auth: FirebaseAccountAuth(),
    profiles: FirebaseProfileRepository(),
  );

  /// Servicio de sesiones de entrenamiento. Expuesto para que las páginas
  /// puedan suscribirse y llamar sus operaciones.
  final WorkoutSessionService sessions;

  /// Servicios de nutrición e hidratación (Sprint 5).
  final FoodService  foods;
  final WaterService waters;
  final AccountAuth _auth;
  final ProfileRepository _profiles;
  final Future<void> Function() _clearReminders;
  StreamSubscription<AccountIdentity?>? _authSubscription;
  AccountIdentity? _account;
  AccountPreferences? _accountPrefs;
  Future<void> _transition = Future.value();
  Future<void> _reminderTransition = Future.value();
  int _epoch = 0;
  // Contador por sesión que distingue entre guardados concurrentes dentro de
  // la misma sesión (mismo epoch). Cada llamada a _saveRemoteProfile incrementa
  // este contador; los guardados tardíos verifican que siguen siendo el más nuevo
  // antes de actualizar el estado en memoria y borrar _kPendingWrite.
  int _saveGeneration = 0;
  // Cola de escrituras remotas: garantiza que las transacciones Firestore se
  // envían en el mismo orden en que se originaron y que solo hay una en vuelo
  // a la vez. Cuando una edición posterior llega a la cola, la anterior —si aún
  // no terminó— no puede ya ser la "más reciente"; al obtener su turno la compara
  // con _saveGeneration y cede sin escribir al servidor.
  Future<void> _saveQueue = Future<void>.value();
  bool _sessionInitialized = false;
  String? _sessionError;
  String? get sessionError => _sessionError;
  String? get currentUid => _account?.uid;

  static const _kProfile = 'brio_profile_v1';
  static const _kOnboarded = 'brio_onboarded_v1';
  static const _kTheme = 'brio_theme_v1';
  static const _kUnits = 'brio_units_v1';
  static const _kMigrationVersion = 'brio_migration_v1';
  // Indica que hay una escritura remota pendiente para este UID.
  // Se establece antes del intento remoto y se borra al confirmar.
  // Permite recuperar el borrador local tras un reinicio sin sobreescribirlo.
  static const _kPendingWrite = 'brio_pending_write_v1';
  static const _kLogs = 'brio_daylogs_v1';
  static const _kWeights = 'brio_weights_v1';
  static const _kWorkoutReminder = 'brio_reminder_workout_v1';
  static const _kWorkoutHour = 'brio_reminder_workout_hour_v1';
  static const _kWorkoutMinute = 'brio_reminder_workout_min_v1';
  static const _kWaterReminder = 'brio_reminder_water_v1';
  static const _kWeekPlan = 'brio_weekplan_v1';
  static const _kExerciseWeights = 'brio_exercise_weights_v1';
  static const _kGroupId = 'brio_group_id_v1';
  static const _kGroupCode = 'brio_group_code_v1';
  static const _kAchievements = 'brio_achievements_v1';

  Profile _profile = Profile();
  bool _onboarded = false;
  ThemeMode _themeMode = ThemeMode.system;
  UnitSystem _units = UnitSystem.metric;
  SyncState _profileSyncState = SyncState.idle;
  final Map<String, DayLog> _logs = {};
  final List<WeightEntry> _weights = [];
  bool _workoutReminderOn = false;
  int _workoutHour = 18;
  int _workoutMinute = 0;
  bool _waterReminderOn = false;
  WeekPlan? _weekPlan;
  final Map<String, List<ExerciseWeightEntry>> _exerciseWeights = {};
  String _localUserId = '';
  bool _isTrainer = false;
  String? _groupId;
  String? _groupCode;
  bool _loaded = false;
  Set<String> _notifiedAchievements = {};

  /// Preferencias del usuario actual. Null si no hay sesión activa.
  AccountPreferences? get currentPrefs => _accountPrefs;

  Profile get profile => _profile;
  bool get onboarded => _onboarded;
  ThemeMode get themeMode => _themeMode;
  UnitSystem get units => _units;
  SyncState get profileSyncState => _profileSyncState;
  bool get loaded => _loaded;
  List<WeightEntry> get weights => List.unmodifiable(_weights);
  bool get workoutReminderOn => _workoutReminderOn;
  int get workoutHour => _workoutHour;
  int get workoutMinute => _workoutMinute;
  bool get waterReminderOn => _waterReminderOn;
  WeekPlan? get weekPlan => _weekPlan;

  // ── Rol entrenador / grupos ──────────────────────────────────────────────
  String get localUserId => _localUserId;
  bool get isTrainer => _isTrainer;
  String? get groupId => _groupId;
  String? get groupCode => _groupCode;
  bool get inGroup => _groupId != null;

  // ── Sesión / autenticación ───────────────────────────────────────────────
  bool get authed => _account != null;
  String? get currentEmail => _account?.email;

  Future<void> load() async {
    _authSubscription ??= _auth.changes.listen((user) {
      unawaited(_acceptSession(user));
    });
    await _acceptSession(_auth.current);
  }

  Future<void> _acceptSession(AccountIdentity? user, {bool force = false}) {
    if (!force && _sessionInitialized && user?.uid == _account?.uid)
      return _transition;
    _sessionInitialized = true;
    final epoch = ++_epoch;
    _saveGeneration = 0;
    _saveQueue = Future<void>.value();
    _account = user;
    _accountPrefs = null;
    _profile = Profile();
    _onboarded = false;
    _themeMode = ThemeMode.system;
    _units = UnitSystem.metric;
    _profileSyncState = SyncState.idle;
    _logs.clear();
    _weights.clear();
    _exerciseWeights.clear();
    _weekPlan = null;
    _groupId = null;
    _groupCode = null;
    _isTrainer = false;
    _localUserId = user?.uid ?? '';
    _workoutReminderOn = false;
    _waterReminderOn = false;
    _workoutHour = 18;
    _workoutMinute = 0;
    _loaded = false;
    _notifiedAchievements = {};
    _sessionError = null;
    sessions.clearForUser();
    foods.clearForUser();
    waters.clearForUser();
    notifyListeners();
    return _transition = _restoreAccount(user, epoch);
  }

  Future<void> _restoreAccount(AccountIdentity? user, int epoch) async {
    try {
      await _updateReminders(cancelOnly: true);
      if (epoch != _epoch) return;
      if (user != null) {
        final storage = await SharedPreferences.getInstance();
        if (epoch != _epoch) return;
        final p = AccountPreferences(storage, user.uid);
        _accountPrefs = p;
        _readAccountCache(p);
        await sessions.loadForUser(p);
        await foods.loadForUser(p, user.uid);
        await waters.loadForUser(p, user.uid);
        if (epoch != _epoch) return;
        await _runMigrationIfNeeded(p, user.uid);
        final hasPending = p.getBool(_kPendingWrite) ?? false;
        if (!hasPending) {
          // Sin escritura pendiente: el remoto es la fuente de verdad.
          final remote = await _profiles.loadOrCreate(user);
          if (epoch != _epoch) return;
          _profile = remote.profile;
          _onboarded = remote.onboarded;
          _isTrainer = remote.trainer;
          await p.setString(_kProfile, _profile.toJson());
          await p.setBool(_kOnboarded, remote.onboarded);
        } else {
          // Hay un borrador pendiente de confirmar: no sobreescribir con remoto.
          // El perfil ya se cargó desde caché en _readAccountCache.
          // Intentar sincronizar el pendiente.
          _profileSyncState = SyncState.pending;
          final uid2 = user.uid;
          final snap = _profile.copy();
          final ob = _onboarded;
          // Captura generación y slot de cola antes del primer await.
          // Si el usuario edita mientras el reintento está en vuelo,
          // _saveRemoteProfile incrementará _saveGeneration; este reintento
          // detectará que ya no es el más reciente y cederá sin escribir.
          final myRetryGen = _saveGeneration;
          final priorRetry = _saveQueue;
          final retrySlot = Completer<void>();
          // Error suprimido en la cola para no contaminar el Zone si no hay
          // guardado posterior que lo observe.
          _saveQueue = retrySlot.future.catchError((_) {});
          try {
            final remote = await _profiles.loadOrCreate(user);
            if (epoch != _epoch) {
              retrySlot.complete();
              return;
            }
            _isTrainer = remote.trainer;
            // Espera a cualquier guardado anterior antes de escribir.
            await priorRetry;
            if (epoch != _epoch || myRetryGen != _saveGeneration) {
              retrySlot.complete();
              return;
            }
            // Reintenta enviar el borrador al servidor.
            await _profiles.save(uid2, snap, onboarded: ob);
            retrySlot.complete();
            if (epoch != _epoch || myRetryGen != _saveGeneration) return;
            await p.remove(_kPendingWrite);
            _profileSyncState = SyncState.confirmed;
          } catch (e) {
            if (!retrySlot.isCompleted) retrySlot.completeError(e);
            if (epoch == _epoch) _profileSyncState = SyncState.failed;
          }
        }
        if (epoch == _epoch) await _updateReminders();
      }
    } catch (_) {
      if (epoch != _epoch) return;
      _sessionError =
          'No pudimos recuperar tu perfil. Revisa la conexión y vuelve a intentar.';
    } finally {
      if (epoch == _epoch) {
        _loaded = true;
        notifyListeners();
      }
    }
  }

  Future<void> retryProfile() => _acceptSession(_auth.current, force: true);

  void _readAccountCache(AccountPreferences p) {
    final pj = p.getString(_kProfile);
    if (pj != null) _profile = Profile.fromJson(pj);
    _onboarded = p.getBool(_kOnboarded) ?? false;
    _themeMode = ThemeMode.values[(p.getInt(_kTheme) ?? 0).clamp(0, 2)];
    _units = UnitSystem.values[(p.getInt(_kUnits) ?? 0).clamp(0, UnitSystem.values.length - 1)];
    _logs
      ..clear()
      ..addEntries(
        (p.getStringList(_kLogs) ?? [])
            .map(DayLog.fromJson)
            .map((l) => MapEntry(l.dateKey, l)),
      );
    _weights
      ..clear()
      ..addAll((p.getStringList(_kWeights) ?? []).map(WeightEntry.fromJson));
    _weights.sort((a, b) => a.date.compareTo(b.date));
    _workoutReminderOn = p.getBool(_kWorkoutReminder) ?? false;
    _workoutHour = p.getInt(_kWorkoutHour) ?? 18;
    _workoutMinute = p.getInt(_kWorkoutMinute) ?? 0;
    _waterReminderOn = p.getBool(_kWaterReminder) ?? false;
    final wpj = p.getString(_kWeekPlan);
    _weekPlan = wpj != null ? WeekPlan.fromJson(wpj) : null;
    final ewj = p.getString(_kExerciseWeights);
    _exerciseWeights.clear();
    if (ewj != null) {
      final decoded = jsonDecode(ewj) as Map<String, dynamic>;
      decoded.forEach((name, list) {
        _exerciseWeights[name] = (list as List)
            .map((e) => ExerciseWeightEntry.fromMap(e as Map<String, dynamic>))
            .toList();
      });
    }
    _groupId = p.getString(_kGroupId);
    _groupCode = p.getString(_kGroupCode);
    _notifiedAchievements =
        Set<String>.from(p.getStringList(_kAchievements) ?? []);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  // ── Hidratación: meta ────────────────────────────────────────────────────
  int get waterGoalMl => waters.goalMl;
  Future<void> setWaterGoalMl(int ml) => waters.setGoalMl(ml);

  // ── Rol entrenador / grupos ──────────────────────────────────────────────
  Future<void> setIsTrainer(bool value) async {
    if (value != _isTrainer) {
      throw StateError(
        'El rol de entrenador debe ser habilitado por un administrador.',
      );
    }
  }

  Future<void> setMyGroup(String groupId, String code) async {
    _groupId = groupId;
    _groupCode = code;
    notifyListeners();
    await _prefs((p) async {
      await p.setString(_kGroupId, groupId);
      await p.setString(_kGroupCode, code);
    });
  }

  Future<void> leaveGroup() async {
    _groupId = null;
    _groupCode = null;
    notifyListeners();
    await _prefs((p) async {
      await p.remove(_kGroupId);
      await p.remove(_kGroupCode);
    });
  }

  // ── Progreso por ejercicio (sobrecarga progresiva) ─────────────────────────
  /// Historial de pesos registrados para un ejercicio, más reciente primero.
  List<ExerciseWeightEntry> exerciseWeightHistory(String exerciseName) {
    final list = _exerciseWeights[exerciseName] ?? const [];
    return list.reversed.toList();
  }

  double? lastExerciseWeight(String exerciseName) {
    final list = _exerciseWeights[exerciseName];
    if (list == null || list.isEmpty) return null;
    return list.last.kg;
  }

  Future<void> logExerciseWeight(
    String exerciseName,
    double kg, {
    int? sets,
    int? reps,
  }) async {
    final list = _exerciseWeights.putIfAbsent(exerciseName, () => []);
    list.add(ExerciseWeightEntry(DateTime.now(), kg, sets: sets, reps: reps));
    if (list.length > 20) list.removeRange(0, list.length - 20);
    notifyListeners();
    await _persistExerciseWeights();
  }

  /// Corrige un registro ya guardado (por si el usuario se equivocó al
  /// tipear). Se identifica por su fecha/hora exacta, que es única por
  /// registro.
  Future<void> updateExerciseEntry(
    String exerciseName,
    DateTime date, {
    required double kg,
    int? sets,
    int? reps,
  }) async {
    final list = _exerciseWeights[exerciseName];
    if (list == null) return;
    final i = list.indexWhere((e) => e.date == date);
    if (i < 0) return;
    list[i] = ExerciseWeightEntry(date, kg, sets: sets, reps: reps);
    notifyListeners();
    await _persistExerciseWeights();
  }

  Future<void> deleteExerciseEntry(String exerciseName, DateTime date) async {
    final list = _exerciseWeights[exerciseName];
    if (list == null) return;
    list.removeWhere((e) => e.date == date);
    notifyListeners();
    await _persistExerciseWeights();
  }

  Future<void> _persistExerciseWeights() async {
    final encoded = jsonEncode(
      _exerciseWeights.map(
        (name, list) => MapEntry(name, list.map((e) => e.toMap()).toList()),
      ),
    );
    await _prefs((p) => p.setString(_kExerciseWeights, encoded));
  }

  /// Progresión automática: compara los últimos 2 registros de peso de un
  /// ejercicio y sugiere el próximo paso (sobrecarga progresiva). Devuelve
  /// null si todavía no hay suficiente historial.
  ExerciseSuggestion? suggestNextWeight(String exerciseName) {
    final history = _exerciseWeights[exerciseName]; // cronológico
    if (history == null || history.isEmpty) return null;
    if (history.length == 1) {
      return ExerciseSuggestion(
        'Registra una vez más para que te sugiera cuánto subir. 💪',
        null,
      );
    }
    final last = history.last.kg;
    final prev = history[history.length - 2].kg;
    final step = last >= 10 ? 2.5 : 1.0;
    if (last > prev) {
      return ExerciseSuggestion(
        'Subiste a ${_fmtKg(last)} kg. Mantén ese peso una vez más antes de volver a subir.',
        last,
      );
    }
    final next = last + step;
    return ExerciseSuggestion(
      'Llevas ${_fmtKg(last)} kg. Prueba con ${_fmtKg(next)} kg la próxima vez. 📈',
      next,
    );
  }

  String _fmtKg(double kg) =>
      kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toStringAsFixed(1);

  // ── Recordatorios ────────────────────────────────────────────────────────
  Future<void> _updateReminders({bool cancelOnly = false}) {
    final epoch = _epoch;
    final workout = !cancelOnly && _workoutReminderOn;
    final water = !cancelOnly && _waterReminderOn;
    final hour = _workoutHour;
    final minute = _workoutMinute;
    // Serialize platform calls: a previous account cannot schedule after logout.
    return _reminderTransition = _reminderTransition.catchError((_) {}).then((
      _,
    ) async {
      if (epoch != _epoch) return;
      await _clearReminders();
      if (epoch != _epoch) return;
      if (workout) await Notifications.scheduleWorkout(hour, minute);
      if (epoch != _epoch) return;
      if (water) await Notifications.scheduleWater();
    });
  }

  Future<void> setWorkoutReminder(bool on, {int? hour, int? minute}) async {
    final epoch = _epoch;
    _workoutReminderOn = on;
    if (hour != null) _workoutHour = hour;
    if (minute != null) _workoutMinute = minute;
    final savedHour = _workoutHour;
    final savedMinute = _workoutMinute;
    notifyListeners();
    await _prefs((p) async {
      await p.setBool(_kWorkoutReminder, on);
      await p.setInt(_kWorkoutHour, savedHour);
      await p.setInt(_kWorkoutMinute, savedMinute);
    });
    if (epoch == _epoch) await _updateReminders();
  }

  Future<void> setWaterReminder(bool on) async {
    final epoch = _epoch;
    _waterReminderOn = on;
    notifyListeners();
    await _prefs((p) => p.setBool(_kWaterReminder, on));
    if (epoch == _epoch) await _updateReminders();
  }

  // ── Plan semanal (IA) ────────────────────────────────────────────────────
  Future<void> saveWeekPlan(WeekPlan plan) async {
    _weekPlan = plan;
    notifyListeners();
    await _prefs((p) => p.setString(_kWeekPlan, plan.toJson()));
  }

  Future<String?> register(String name, String email, String password) async {
    if (name.trim().isEmpty) return 'Escribe tu nombre.';
    try {
      await _auth.register(name.trim(), email.trim(), password);
      await _acceptSession(_auth.current);
      return null;
    } catch (error) {
      return accountError(error);
    }
  }

  Future<String?> login(String email, String password) async {
    try {
      await _auth.signIn(email.trim(), password);
      await _acceptSession(_auth.current);
      return null;
    } catch (error) {
      return accountError(error);
    }
  }

  Future<String?> loginWithGoogle() async {
    try {
      await _auth.signInWithGoogle();
      await _acceptSession(_auth.current);
      return null;
    } catch (error) {
      return accountError(error);
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    await _acceptSession(null);
  }

  /// Paso 3 del Sprint 2: migración segura e idempotente.
  ///
  /// Versión actual: 1.
  /// Lógica: registra que ya se ejecutó la verificación para este UID.
  /// No migra datos de propietario incierto (claves antiguas `brio_*`):
  /// esas claves se conservan sin tocar hasta que el propietario sea
  /// verificado fuera de la app. Este mecanismo garantiza idempotencia:
  /// si se interrumpe y se reanuda, no duplica datos.
  static const int _migrationCurrentVersion = 1;

  Future<void> _runMigrationIfNeeded(AccountPreferences p, String uid) async {
    final done = p.getInt(_kMigrationVersion) ?? 0;
    if (done >= _migrationCurrentVersion) return;

    // Verificación: ¿hay claves antiguas `brio_*` sin UID asociado?
    // Por política del Sprint 2, no se asignan al usuario actual porque
    // no es posible verificar la propiedad con certeza.
    // Se marca la migración como completada sin mover datos ambiguos.
    await p.setInt(_kMigrationVersion, _migrationCurrentVersion);
  }

  Future<void> _prefs(Future<void> Function(AccountPreferences p) fn) async {
    final p = _accountPrefs;
    if (p == null || !authed) throw StateError('No hay una sesión lista.');
    await fn(p);
  }

  // ── Perfil / onboarding ──────────────────────────────────────────────────
  Future<void> completeOnboarding(Profile profile) async {
    await _saveRemoteProfile(profile, onboarded: true);
  }

  Future<void> saveProfile(Profile profile) async {
    await _saveRemoteProfile(profile, onboarded: _onboarded);
  }

  Future<void> _saveRemoteProfile(
    Profile profile, {
    required bool onboarded,
  }) async {
    final uid = currentUid;
    final epoch = _epoch;
    // Captura la generación ANTES de cualquier await, de modo que si otro
    // guardado comienza mientras éste está en vuelo, myGeneration < _saveGeneration.
    final myGeneration = ++_saveGeneration;
    final cache = _accountPrefs;
    if (uid == null || cache == null || !_loaded || _sessionError != null) {
      throw StateError('No hay una sesión lista.');
    }
    final snapshot = profile.copy();

    // Guarda localmente primero para preservar el borrador ante errores.
    await cache.setString(_kProfile, snapshot.toJson());
    await cache.setBool(_kOnboarded, onboarded);
    // Marca la escritura como pendiente ANTES del intento remoto.
    // Si la app se reinicia antes de la confirmación, _restoreAccount
    // detectará el flag y no sobreescribirá el borrador con el remoto.
    await cache.setBool(_kPendingWrite, true);

    // Verifica epoch después de los awaits de escritura local: la cuenta puede
    // haber cambiado mientras SharedPreferences escribía.
    if (epoch != _epoch) throw StateError('La sesión cambió durante el guardado.');

    // Guard rápido: si una edición más nueva ya comenzó durante las escrituras
    // locales, no hace falta ni entrar en la cola.
    if (myGeneration != _saveGeneration) return;

    _profileSyncState = SyncState.saving;
    notifyListeners();

    // Cola de escrituras por sesión: serializa las transacciones Firestore.
    // Cada guardado encola su Future y espera al anterior antes de escribir.
    // Al obtener su turno, revalida la generación: si ya hay un guardado
    // posterior en espera, cede sin enviar datos viejos al servidor.
    final priorSave = _saveQueue;
    final mySlot = Completer<void>();
    // La cola almacena el future con el error ya suprimido: si ningún guardado
    // posterior llega a esperar, el error no se propaga al Zone. El slot interno
    // (mySlot) sigue teniendo el error para que el catch a continuación lo reenvíe.
    _saveQueue = mySlot.future.catchError((_) {});

    // Espera a que el guardado anterior complete (éxito o error suprimido).
    await priorSave;

    // Revalidar tras la espera: puede que llegara una edición más nueva.
    if (epoch != _epoch) {
      mySlot.complete();
      throw StateError('La sesión cambió durante el guardado.');
    }
    if (myGeneration != _saveGeneration) {
      // Un guardado más reciente ya ocupa la cola — ceder sin escribir al servidor.
      mySlot.complete();
      return;
    }

    try {
      await _profiles.save(uid, snapshot, onboarded: onboarded);
      mySlot.complete();
    } on StateError catch (e) {
      // La sesión cambió o el perfil aún no existe en el servidor.
      mySlot.completeError(e);
      if (epoch == _epoch) {
        _profileSyncState = SyncState.failed;
        notifyListeners();
      }
      rethrow;
    } catch (e) {
      mySlot.completeError(e);
      if (epoch == _epoch) {
        final isPermission = e.toString().contains('PERMISSION_DENIED') ||
            e.toString().contains('permission-denied');
        _profileSyncState =
            isPermission ? SyncState.rejected : SyncState.failed;
        notifyListeners();
      }
      rethrow;
    }

    if (epoch != _epoch) {
      throw StateError('La sesión cambió durante el guardado.');
    }

    if (myGeneration != _saveGeneration) return;

    _profile = snapshot;
    _onboarded = onboarded;
    _profileSyncState = SyncState.confirmed;
    if (_weights.isEmpty && onboarded) {
      _weights.add(WeightEntry(DateTime.now(), snapshot.weightKg));
    }
    final weights = _weights.map((e) => e.toJson()).toList();
    await cache.setStringList(_kWeights, weights);
    // Borra el flag de escritura pendiente: el servidor confirmó.
    await cache.remove(_kPendingWrite);
    if (epoch == _epoch) notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _prefs((p) => p.setInt(_kTheme, mode.index));
  }

  Future<void> setUnits(UnitSystem system) async {
    _units = system;
    notifyListeners();
    await _prefs((p) => p.setInt(_kUnits, system.index));
  }

  /// Reinicia el estado sync del perfil a idle, por ejemplo tras un reintento.
  void clearProfileSyncState() {
    _profileSyncState = SyncState.idle;
    notifyListeners();
  }

  // ── Registros diarios ────────────────────────────────────────────────────
  DayLog logFor(DateTime d) {
    final k = dayKey(d);
    return _logs[k] ?? DayLog(k);
  }

  DayLog get today => logFor(DateTime.now());

  Future<void> _saveLog(DayLog log) async {
    _logs[log.dateKey] = log;
    notifyListeners();
    await _prefs(
      (p) =>
          p.setStringList(_kLogs, _logs.values.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> addWater([int delta = 1]) async {
    final log = today;
    log.water = (log.water + delta).clamp(0, 30);
    await _saveLog(log);
  }

  Future<void> toggleWorkoutDone(String workoutId) async {
    final log = today;
    if (log.workouts.contains(workoutId)) {
      log.workouts.remove(workoutId);
    } else {
      log.workouts.add(workoutId);
    }
    await _saveLog(log);
  }

  bool isWorkoutDoneToday(String id) => today.workouts.contains(id);

  Future<void> addFood(FoodEntry entry) async {
    final log = today;
    log.foods.add(entry);
    await _saveLog(log);
  }

  Future<void> removeFood(int index) async {
    final log = today;
    if (index >= 0 && index < log.foods.length) {
      log.foods.removeAt(index);
      await _saveLog(log);
    }
  }

  int get kcalToday => today.kcal;
  int get proteinToday => today.protein;

  // ── Peso ─────────────────────────────────────────────────────────────────
  Future<void> addWeight(double kg) async {
    final epoch = _epoch;
    final updated = _profile.copy()..weightKg = kg;
    await saveProfile(updated);
    if (epoch != _epoch) throw StateError('La sesión cambió.');
    final k = dayKey(DateTime.now());
    _weights.removeWhere((w) => dayKey(w.date) == k); // 1 registro por día
    _weights.add(WeightEntry(DateTime.now(), kg));
    _weights.sort((a, b) => a.date.compareTo(b.date));
    _profile.weightKg = kg;
    notifyListeners();
    await _prefs((p) async {
      await p.setStringList(
        _kWeights,
        _weights.map((e) => e.toJson()).toList(),
      );
    });
  }

  // ── Métricas / rachas ────────────────────────────────────────────────────
  int get waterToday => today.water;

  /// Días seguidos (terminando hoy o ayer) con al menos un entrenamiento.
  int get streak {
    int n = 0;
    var d = DateTime.now();
    // Si hoy aún no entrena, la racha puede venir desde ayer.
    if (logFor(d).workouts.isEmpty) d = d.subtract(const Duration(days: 1));
    while (logFor(d).workouts.isNotEmpty) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Entrenamientos completados en los últimos 7 días.
  int get workoutsThisWeek {
    int n = 0;
    for (int i = 0; i < 7; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
      n += logFor(d).workouts.length;
    }
    return n;
  }

  double? get startWeight => _weights.isEmpty ? null : _weights.first.kg;
  double? get lastWeight => _weights.isEmpty ? null : _weights.last.kg;

  // ── Gamificación: XP, nivel y totales acumulados ─────────────────────────
  /// Entrenamientos completados en toda la historia (no solo esta semana).
  int get totalWorkoutsDone =>
      _logs.values.fold(0, (s, l) => s + l.workouts.length);

  /// Comidas registradas (FoodRecord del Sprint 5).
  int get totalFoodsLogged => foods.records.length;

  /// Días distintos con al menos un WaterRecord (Sprint 5).
  int get totalWaterDays {
    final days =
        waters.records.map((r) => dayKey(r.recordedAt.toLocal())).toSet();
    return days.length;
  }

  /// Puntos de experiencia: entrenar vale más que registrar comida o agua.
  int get totalXp =>
      totalWorkoutsDone * 20 +
      totalFoodsLogged * 8 +
      totalWaterDays * 5 +
      _weights.length * 5;

  /// Nivel del usuario según su XP acumulada (curva suave, sube más de a poco).
  int get level => 1 + (sqrt(totalXp / 60)).floor();

  /// XP que faltan para el siguiente nivel (para la barra de progreso).
  int get xpForNextLevel => (60 * pow(level, 2)).round();
  int get xpForThisLevel => (60 * pow(level - 1, 2)).round();
  double get levelProgress {
    final span = xpForNextLevel - xpForThisLevel;
    if (span <= 0) return 1;
    return ((totalXp - xpForThisLevel) / span).clamp(0, 1).toDouble();
  }

  // ── Peso: edición y eliminación (#198) ───────────────────────────────────

  Future<void> updateWeight(String dayKeyStr, double newKg) async {
    if (!newKg.isFinite || newKg <= 0 || newKg >= 500) {
      throw ArgumentError('Peso inválido: $newKg');
    }
    final i = _weights.indexWhere((w) => dayKey(w.date) == dayKeyStr);
    if (i < 0) return;
    _weights[i] = WeightEntry(_weights[i].date, newKg);
    // Solo actualiza el perfil si era el peso más reciente.
    if (i == _weights.length - 1) {
      _profile.weightKg = newKg;
    }
    notifyListeners();
    await _prefs(
      (p) => p.setStringList(
        _kWeights,
        _weights.map((e) => e.toJson()).toList(),
      ),
    );
  }

  Future<void> deleteWeight(String dayKeyStr) async {
    _weights.removeWhere((w) => dayKey(w.date) == dayKeyStr);
    if (_weights.isNotEmpty) {
      _profile.weightKg = _weights.last.kg;
    }
    notifyListeners();
    await _prefs(
      (p) => p.setStringList(
        _kWeights,
        _weights.map((e) => e.toJson()).toList(),
      ),
    );
  }

  // ── Logros: notificación idempotente (#201–#203) ──────────────────────────

  /// Devuelve logros recién desbloqueados que aún no se notificaron.
  /// Los marca como notificados para evitar repetición en aperturas futuras.
  Future<List<Achievement>> checkNewAchievements() async {
    final newOnes = Achievements.all
        .where((a) => a.check(this) && !_notifiedAchievements.contains(a.id))
        .toList();
    if (newOnes.isEmpty) return [];
    for (final a in newOnes) {
      _notifiedAchievements.add(a.id);
    }
    await _prefs(
      (p) => p.setStringList(_kAchievements, _notifiedAchievements.toList()),
    );
    return newOnes;
  }
}
