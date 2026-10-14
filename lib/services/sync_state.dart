/// Estado de una operación de guardado remoto.
///
/// Los valores representan el ciclo de vida completo: desde sin cambios
/// hasta confirmación o rechazo. La interfaz muestra mensajes distintos
/// para cada estado sin exponer terminología técnica al usuario.
enum SyncState {
  /// Sin cambios pendientes; el estado remoto es el vigente.
  idle,

  /// Operación en curso hacia el servidor.
  saving,

  /// Guardado localmente pero todavía no confirmado por el servidor.
  /// Ocurre cuando hay una operación reciente sin respuesta definitiva,
  /// o cuando el SDK de Firestore encola la escritura sin conexión.
  pending,

  /// El servidor confirmó la escritura exitosamente.
  confirmed,

  /// El servidor no respondió o devolvió un error recuperable.
  /// El usuario puede reintentar.
  failed,

  /// Rechazado por reglas de validación o permisos.
  /// No tiene sentido reintentar sin corregir los datos o la sesión.
  rejected,
}

extension SyncStateX on SyncState {
  /// Mensaje breve que la interfaz puede mostrar al usuario.
  String get label => switch (this) {
        SyncState.idle => '',
        SyncState.saving => 'Guardando…',
        SyncState.pending =>
          'Guardado en este dispositivo. Pendiente de sincronizar.',
        SyncState.confirmed => 'Cambios guardados.',
        SyncState.failed => 'No se pudo sincronizar. Reintentar.',
        SyncState.rejected =>
          'Los datos no son válidos. Revisa los campos e inténtalo de nuevo.',
      };

  bool get isInProgress => this == SyncState.saving;
  bool get needsAttention =>
      this == SyncState.failed || this == SyncState.rejected;
}
