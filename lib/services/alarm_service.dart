import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'notifications.dart';

/// Servicio de alarma y vibración persistente para descanso completado.
class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  final AudioPlayer _player = AudioPlayer();
  Timer? _vibeTimer;
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  /// Inicia el bucle de sonido y vibración continua hasta que el usuario lo pause.
  Future<void> startAlarm() async {
    if (_isPlaying) return;
    _isPlaying = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('audio/timer_alarm.wav'));
    } catch (_) {}

    // Notificación en barra de estado si la app está en segundo plano o minimizada
    Notifications.showRestFinishedNotification();

    // Vibración recurrente potente
    _vibeTimer?.cancel();
    HapticFeedback.heavyImpact();
    _vibeTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  /// Detiene el sonido y la vibración de alarma.
  Future<void> stopAlarm() async {
    _isPlaying = false;
    _vibeTimer?.cancel();
    _vibeTimer = null;
    Notifications.cancelRestNotification();
    try {
      await _player.stop();
    } catch (_) {}
  }
}

