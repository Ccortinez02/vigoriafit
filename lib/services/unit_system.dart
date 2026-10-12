/// Sistema de unidades para mostrar peso y estatura al usuario.
///
/// Los datos canónicos siempre se guardan en kg y cm. La conversión ocurre
/// solo al mostrar y al interpretar la entrada del usuario. Cambiar de sistema
/// no modifica los datos almacenados.
enum UnitSystem { metric, imperial }

extension UnitSystemX on UnitSystem {
  String get label => switch (this) {
        UnitSystem.metric => 'Métrico (kg / cm)',
        UnitSystem.imperial => 'Imperial (lb / in)',
      };

  // ── Peso ──────────────────────────────────────────────────────────────────

  /// Convierte kg → unidad de display.
  double displayWeight(double kg) => switch (this) {
        UnitSystem.metric => kg,
        UnitSystem.imperial => kg * 2.20462,
      };

  /// Convierte valor de display → kg canónicos.
  double canonicalWeight(double display) => switch (this) {
        UnitSystem.metric => display,
        UnitSystem.imperial => display / 2.20462,
      };

  String get weightUnit => switch (this) {
        UnitSystem.metric => 'kg',
        UnitSystem.imperial => 'lb',
      };

  /// Peso mínimo en unidades de display.
  double get weightMin => switch (this) {
        UnitSystem.metric => 35.0,
        UnitSystem.imperial => 77.0,
      };

  /// Peso máximo en unidades de display.
  double get weightMax => switch (this) {
        UnitSystem.metric => 200.0,
        UnitSystem.imperial => 440.0,
      };

  // ── Estatura ──────────────────────────────────────────────────────────────

  /// Convierte cm → unidad de display.
  double displayHeight(double cm) => switch (this) {
        UnitSystem.metric => cm,
        UnitSystem.imperial => cm / 2.54,
      };

  /// Convierte valor de display → cm canónicos.
  double canonicalHeight(double display) => switch (this) {
        UnitSystem.metric => display,
        UnitSystem.imperial => display * 2.54,
      };

  String get heightUnit => switch (this) {
        UnitSystem.metric => 'cm',
        UnitSystem.imperial => 'in',
      };

  double get heightMin => switch (this) {
        UnitSystem.metric => 130.0,
        UnitSystem.imperial => 51.0,
      };

  double get heightMax => switch (this) {
        UnitSystem.metric => 220.0,
        UnitSystem.imperial => 87.0,
      };

  // ── Formato ───────────────────────────────────────────────────────────────

  String formatWeight(double kg) {
    final v = displayWeight(kg);
    return '${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(1)} $weightUnit';
  }

  String formatHeight(double cm) {
    final v = displayHeight(cm);
    if (this == UnitSystem.imperial) {
      final totalIn = v.round();
      final ft = totalIn ~/ 12;
      final inches = totalIn % 12;
      return "$ft'$inches\"";
    }
    return '${v.round()} $heightUnit';
  }
}
