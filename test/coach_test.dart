import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/services/ai_adapter.dart';
import 'package:vigoriafit/services/coach_service.dart';

void main() {
  group('CoachService systemPrompt', () {
    test('#259: systemPrompt incluye defensa contra jailbreak', () {
      expect(
        CoachService.systemPromptForTest,
        contains('Solo puedo ayudarte con entrenamiento y alimentación.'),
      );
    });

    test('systemPrompt prohíbe explícitamente "diagnóstico" y "tratamiento"', () {
      // El prompt debe decirle al modelo que nunca use esas palabras
      expect(CoachService.systemPromptForTest, contains('diagnóstico'));
      expect(CoachService.systemPromptForTest, contains('tratamiento'));
      expect(CoachService.systemPromptForTest, contains('Jamás uses'));
    });

    test('systemPrompt menciona español', () {
      expect(CoachService.systemPromptForTest, contains('español'));
    });
  });

  group('CoachService con MockAdapter', () {
    test('respuesta de IA se retorna cuando adaptador tiene éxito', () async {
      final mock = MockAiAdapter(chatResponse: '¡Muy bien! Sigue adelante.');
      final svc = CoachService(mock);
      final resp = await svc.send('Hola coach');
      expect(resp.fromAi, isTrue);
      expect(resp.text, contains('Muy bien'));
      expect(resp.error, isNull);
      svc.dispose();
    });

    test('noNetwork → fallback local, fromAi=false, error=noNetwork', () async {
      final mock = MockAiAdapter(injectError: AiError.noNetwork);
      final svc = CoachService(mock);
      final resp = await svc.send('Hola');
      expect(resp.fromAi, isFalse);
      expect(resp.error, AiError.noNetwork);
      expect(resp.text, isNotEmpty);
      svc.dispose();
    });

    test('noConfig → fallback local, fromAi=false, error=noConfig', () async {
      final mock = MockAiAdapter(injectError: AiError.noConfig);
      final svc = CoachService(mock);
      final resp = await svc.send('Hola');
      expect(resp.fromAi, isFalse);
      expect(resp.error, AiError.noConfig);
      svc.dispose();
    });

    test('quota → fallback local', () async {
      final mock = MockAiAdapter(injectError: AiError.quota);
      final svc = CoachService(mock);
      final resp = await svc.send('Hola');
      expect(resp.fromAi, isFalse);
      expect(resp.error, AiError.quota);
      svc.dispose();
    });

    test('timeout → texto de error sin fallback local', () async {
      final mock = MockAiAdapter(injectError: AiError.timeout);
      final svc = CoachService(mock);
      final resp = await svc.send('Hola');
      expect(resp.fromAi, isFalse);
      expect(resp.error, AiError.timeout);
      expect(resp.text, contains('tardó demasiado'));
      svc.dispose();
    });

    test('clearHistory reinicia historial', () async {
      final mock = MockAiAdapter(chatResponse: 'Respuesta.');
      final svc = CoachService(mock);
      await svc.send('Mensaje 1');
      await svc.send('Mensaje 2');
      svc.clearHistory();
      // Verifica que no acumule errores tras limpiar
      final resp = await svc.send('Nuevo inicio');
      expect(resp.text, isNotEmpty);
      svc.dispose();
    });

    test('dispose evita que respuestas tardías actualicen el estado', () async {
      final mock = MockAiAdapter(
        delay: const Duration(milliseconds: 200),
        chatResponse: 'Respuesta tardía',
      );
      final svc = CoachService(mock);
      final future = svc.send('Pregunta');
      svc.dispose();
      final resp = await future;
      // Después de dispose, la respuesta es ignorada (texto vacío)
      expect(resp.text, isEmpty);
    });
  });

  group('CoachService.errorLabel', () {
    test('labels de errores son strings no vacíos', () {
      for (final err in AiError.values) {
        final label = CoachService.errorLabel(err);
        if (err != AiError.unknown) {
          expect(label, isNotEmpty, reason: 'label vacío para $err');
        }
      }
    });
  });
}
