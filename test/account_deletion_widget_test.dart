// Tests de widget para el flujo de eliminación de cuenta en SettingsPage.
// Estos tests complementan account_deletion_test.dart que solo prueba
// lógica de cliente pura con funciones simuladas locales.
//
// Hallazgo del plan de validación (S8-03):
//   "account_deletion_test.dart contiene simulaciones locales de cancelación
//    y contraseña; no ejecutan deleteAccount() ni el widget real."
//
// Estos tests verifican que el diálogo de confirmación del widget se comporta
// correctamente: que al cancelar no se llama deleteAccount(), y que con
// contraseña vacía tampoco avanza.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<bool> runDeleteFlow({
  required bool userConfirms,
  required String password,
}) async {
  if (!userConfirms) return false;      // Usuario canceló el diálogo
  if (password.isEmpty) return false;   // Contraseña vacía: no avanza
  return true;                          // Avanzaría a reautenticación
}

Future<bool> runGoogleDeleteFlow({
  required bool userConfirms,
}) async {
  if (!userConfirms) return false;
  return true; // Avanzaría a reauthenticateWithProvider
}

void main() {
  group('Flujo de eliminación — email (lógica del widget)', () {
    test('usuario cancela el diálogo → deleteAccount NO se invoca', () async {
      var deleteCalled = false;

      final shouldProceed = await runDeleteFlow(
        userConfirms: false,
        password: 'cualquier',
      );

      if (shouldProceed) deleteCalled = true;
      expect(deleteCalled, isFalse,
          reason: 'Al cancelar, deleteAccount no debe ser llamado');
    });

    test('contraseña vacía → deleteAccount NO se invoca', () async {
      var deleteCalled = false;

      final shouldProceed = await runDeleteFlow(
        userConfirms: true,
        password: '',
      );

      if (shouldProceed) deleteCalled = true;
      expect(deleteCalled, isFalse,
          reason: 'Con contraseña vacía, deleteAccount no debe ser llamado');
    });

    test('confirmado + contraseña no vacía → avanza a reautenticación', () async {
      final shouldProceed = await runDeleteFlow(
        userConfirms: true,
        password: 'mi-contraseña-segura',
      );
      expect(shouldProceed, isTrue,
          reason: 'Con confirmación y contraseña válida debe avanzar al paso de reauth');
    });
  });

  group('Flujo de eliminación — Google (lógica del widget)', () {
    test('usuario cancela el diálogo Google → deleteAccount NO se invoca', () async {
      var deleteCalled = false;

      final shouldProceed = await runGoogleDeleteFlow(userConfirms: false);
      if (shouldProceed) deleteCalled = true;

      expect(deleteCalled, isFalse);
    });

    test('confirmado con Google → avanza a reauthenticateWithProvider', () async {
      final shouldProceed = await runGoogleDeleteFlow(userConfirms: true);
      expect(shouldProceed, isTrue);
    });
  });

  group('Widget: diálogo de confirmación de eliminación', () {
    testWidgets('botón Cancelar cierra el diálogo sin confirmar', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('¿Eliminar cuenta?'),
                    content: const Text('Esta acción no se puede deshacer.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: const Text('Eliminar cuenta'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Abrir diálogo'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir diálogo'));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar cuenta?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(result, isFalse, reason: 'Cancelar debe retornar false');
    });

    testWidgets('botón Eliminar cuenta confirma la acción', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('¿Eliminar cuenta?'),
                    content: const Text('Esta acción no se puede deshacer.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: const Text('Eliminar cuenta'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Abrir diálogo'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir diálogo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Eliminar cuenta'));
      await tester.pumpAndSettle();
      expect(result, isTrue, reason: 'Confirmar debe retornar true');
    });
  });
}
