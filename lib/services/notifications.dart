import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Recordatorios de VigoriaFit: entrenar y tomar agua, todos los días a horas fijas.
///
/// Usa notificaciones locales (no requiere servidor). La zona horaria se fija
/// a Chile continental, ya que la app está pensada para estudiantes chilenos.
class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  // IDs fijos por tipo de recordatorio (permiten cancelar/reprogramar cada uno).
  static const _idWorkout = 100;
  static const _idWater1 = 201;
  static const _idWater2 = 202;
  static const _idWater3 = 203;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('America/Santiago'));
    } catch (_) {
      // Si la zona no está disponible, seguimos con la del sistema.
    }
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _plugin.initialize(initSettings);
    _ready = true;
  }

  /// Pide permiso de notificaciones (Android 13+). Devuelve true si se otorgó.
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  static Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'brio_reminders',
          'Recordatorios de VigoriaFit',
          channelDescription: 'Avisos para entrenar y tomar agua',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // se repite cada día
    );
  }

  /// Programa el recordatorio diario de entrenar a la hora indicada.
  static Future<void> scheduleWorkout(int hour, int minute) => _scheduleDaily(
        id: _idWorkout,
        hour: hour,
        minute: minute,
        title: '💪 Hora de entrenar',
        body: 'Tu rutina de hoy te espera. ¡Unos minutos y listo!',
      );

  static Future<void> cancelWorkout() => _plugin.cancel(_idWorkout);

  /// Programa 3 recordatorios de agua repartidos en el día (mañana, tarde, noche).
  static Future<void> scheduleWater() async {
    await _scheduleDaily(
        id: _idWater1,
        hour: 11,
        minute: 0,
        title: '💧 Toma agua',
        body: 'Un vaso de agua ahora te ayuda a rendir mejor.');
    await _scheduleDaily(
        id: _idWater2,
        hour: 15,
        minute: 30,
        title: '💧 Toma agua',
        body: '¿Cómo vas con tu meta de agua hoy?');
    await _scheduleDaily(
        id: _idWater3,
        hour: 19,
        minute: 0,
        title: '💧 Toma agua',
        body: 'Última pasada del día: hidrátate.');
  }

  static Future<void> cancelWater() async {
    await _plugin.cancel(_idWater1);
    await _plugin.cancel(_idWater2);
    await _plugin.cancel(_idWater3);
  }
}
