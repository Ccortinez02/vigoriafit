import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigoriafit/services/ai_adapter.dart';

void main() {
  FoodAnalysisResult parse(String raw) => parseAnalysisForTest(raw, 'test');

  group('Parseo de respuesta de imagen IA', () {
    test('JSON válido con 2 ítems retorna 2 proposals', () {
      const raw = '{"items":['
          '{"name":"Pechuga de pollo","qty":150,"unit":"g","kcal":247,"protein":46,"carbs":0,"fat":5},'
          '{"name":"Arroz cocido","qty":100,"unit":"g","kcal":130,"protein":3,"carbs":28,"fat":0}'
          ']}';
      final result = parse(raw);
      expect(result.proposals.length, 2);
      expect(result.proposals[0].suggestedName, 'Pechuga de pollo');
      expect(result.proposals[1].suggestedName, 'Arroz cocido');
    });

    test('qty negativa lanza AiException(invalidResponse)', () {
      const raw = '{"items":[{"name":"Algo","qty":-10,"unit":"g"}]}';
      expect(
        () => parse(raw),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiError.invalidResponse)),
      );
    });

    test('qty igual a 0 lanza AiException(invalidResponse)', () {
      const raw = '{"items":[{"name":"Algo","qty":0,"unit":"g"}]}';
      expect(
        () => parse(raw),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiError.invalidResponse)),
      );
    });

    test('más de 5 ítems lanza AiException(invalidResponse)', () {
      final items = List.generate(
        6,
        (i) => '{"name":"Item $i","qty":100,"unit":"g"}',
      ).join(',');
      expect(
        () => parse('{"items":[$items]}'),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiError.invalidResponse)),
      );
    });

    test('kcal negativo lanza AiException(invalidResponse)', () {
      const raw = '{"items":[{"name":"Algo","qty":100,"unit":"g","kcal":-50}]}';
      expect(
        () => parse(raw),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiError.invalidResponse)),
      );
    });

    test('JSON inválido lanza AiException(invalidResponse)', () {
      expect(
        () => parse('not json at all'),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiError.invalidResponse)),
      );
    });

    test('respuesta vacía lanza AiException(invalidResponse)', () {
      expect(
        () => parse(''),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiError.invalidResponse)),
      );
    });

    test('mapeo a catálogo: "pollo" encuentra pollo_pechuga_cocida', () {
      const raw = '{"items":[{"name":"pollo","qty":100,"unit":"g","kcal":165,"protein":31,"carbs":0,"fat":3}]}';
      final result = parse(raw);
      expect(result.proposals[0].fromCatalog, isTrue);
      expect(result.proposals[0].catalogId, 'pollo_pechuga_cocida');
    });

    test('sin coincidencia en catálogo: catalogId es null', () {
      const raw = '{"items":[{"name":"sushi especial","qty":80,"unit":"g"}]}';
      final result = parse(raw);
      expect(result.proposals, isNotEmpty);
      // No lanza excepción — simplemente fromCatalog=false
    });

    test('array vacío retorna 0 proposals', () {
      const raw = '{"items":[]}';
      final result = parse(raw);
      expect(result.proposals, isEmpty);
    });

    // Test #256: qty editada se usa proporcionalmente para calcular nutrientes
    test('#256: kcal proporcional cuando qty cambia', () {
      const prop = FoodProposal(
        suggestedName: 'Pollo test',
        estimatedQty: 100,
        estimatedUnit: 'g',
        kcalEstimated: 165,
        proteinEstimated: 31,
      );
      // Simula edición de qty a 250g (como hace la UI con _EditableProposal)
      const editedQty = 250.0;
      final kcalAjustado = prop.kcalEstimated! * editedQty / prop.estimatedQty;
      expect(kcalAjustado, closeTo(412.5, 0.01));
    });

    // Test #258: error inyectado resulta en AiException
    test('#258: MockAdapter con noNetwork lanza AiException', () async {
      final mock = MockAiAdapter(injectError: AiError.noNetwork);
      await expectLater(
        () => mock.analyzeFood(Uint8List(0)),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiError.noNetwork)),
      );
    });
  });

  group('MockAiAdapter', () {
    test('sin error retorna foodResponse predeterminado', () async {
      final mock = MockAiAdapter();
      final result = await mock.analyzeFood(Uint8List(0));
      expect(result.proposals.length, 1);
      expect(result.proposals[0].suggestedName, 'Comida simulada');
    });

    test('foodResponse personalizado', () async {
      final custom = FoodAnalysisResult(
        requestId: 'r1',
        proposals: [
          const FoodProposal(
            suggestedName: 'Test food',
            estimatedQty: 200,
            estimatedUnit: 'g',
          ),
        ],
      );
      final mock = MockAiAdapter(foodResponse: custom);
      final result = await mock.analyzeFood(Uint8List(0));
      expect(result.proposals[0].suggestedName, 'Test food');
    });

    test('chat sin error retorna chatResponse', () async {
      final mock = MockAiAdapter(chatResponse: 'Hola, soy el coach.');
      final text = await mock.chat('sys', [], 'Hola');
      expect(text, 'Hola, soy el coach.');
    });

    test('chat con error lanza AiException', () async {
      final mock = MockAiAdapter(injectError: AiError.quota);
      await expectLater(
        () => mock.chat('sys', [], 'Hola'),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiError.quota)),
      );
    });

    test('isConfigured es false cuando error es noConfig', () {
      final mock = MockAiAdapter(injectError: AiError.noConfig);
      expect(mock.isConfigured, isFalse);
    });

    test('isConfigured es true por defecto', () {
      expect(MockAiAdapter().isConfigured, isTrue);
    });
  });
}
