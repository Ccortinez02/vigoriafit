import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/services/unit_system.dart';

void main() {
  group('UnitSystem — conversión de unidades', () {
    group('Métrico (sin conversión)', () {
      test('displayWeight no cambia kg', () {
        expect(UnitSystem.metric.displayWeight(80), closeTo(80, 0.01));
      });
      test('canonicalWeight es inversa exacta', () {
        final display = UnitSystem.metric.displayWeight(75.5);
        expect(UnitSystem.metric.canonicalWeight(display), closeTo(75.5, 0.01));
      });
      test('displayHeight no cambia cm', () {
        expect(UnitSystem.metric.displayHeight(175), closeTo(175, 0.01));
      });
      test('formatWeight usa kg', () {
        expect(UnitSystem.metric.formatWeight(70), contains('kg'));
      });
      test('formatHeight usa cm', () {
        expect(UnitSystem.metric.formatHeight(175), contains('cm'));
      });
    });

    group('Imperial', () {
      test('displayWeight convierte kg → lb', () {
        // 70 kg ≈ 154.3 lb
        expect(UnitSystem.imperial.displayWeight(70), closeTo(154.3, 0.5));
      });
      test('canonicalWeight es inversa de displayWeight', () {
        const kg = 68.0;
        final lb = UnitSystem.imperial.displayWeight(kg);
        expect(UnitSystem.imperial.canonicalWeight(lb), closeTo(kg, 0.01));
      });
      test('displayHeight convierte cm → in', () {
        // 175 cm ≈ 68.9 in
        expect(UnitSystem.imperial.displayHeight(175), closeTo(68.9, 0.5));
      });
      test('canonicalHeight es inversa de displayHeight', () {
        const cm = 180.0;
        final inches = UnitSystem.imperial.displayHeight(cm);
        expect(UnitSystem.imperial.canonicalHeight(inches), closeTo(cm, 0.1));
      });
      test('formatWeight usa lb', () {
        expect(UnitSystem.imperial.formatWeight(70), contains('lb'));
      });
      test('formatHeight usa pies y pulgadas', () {
        // 175 cm → 5'9"
        final s = UnitSystem.imperial.formatHeight(175);
        expect(s, contains("'"));
      });
    });

    group('Invariante: cambiar unidades no altera el canónico', () {
      test('convertir al display y de vuelta preserva el valor canónico', () {
        const kgOriginal = 82.5;
        for (final u in UnitSystem.values) {
          final display = u.displayWeight(kgOriginal);
          final backToKg = u.canonicalWeight(display);
          expect(backToKg, closeTo(kgOriginal, 0.01),
              reason: 'Fallo con sistema ${u.name}');
        }
      });
      test('la conversión de estatura es simétrica', () {
        const cmOriginal = 168.0;
        for (final u in UnitSystem.values) {
          final display = u.displayHeight(cmOriginal);
          final backToCm = u.canonicalHeight(display);
          expect(backToCm, closeTo(cmOriginal, 0.5),
              reason: 'Fallo con sistema ${u.name}');
        }
      });
    });
  });
}
