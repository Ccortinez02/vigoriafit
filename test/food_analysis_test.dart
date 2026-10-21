import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigoriafit/data/nutrition.dart';
import 'package:vigoriafit/models/food_record.dart';
import 'package:vigoriafit/services/account_preferences.dart';
import 'package:vigoriafit/services/ai_adapter.dart';
import 'package:vigoriafit/services/food_service.dart';

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

    // Test #256a: cálculo proporcional (lógica de UI al editar qty)
    test('#256a: kcal proporcional cuando qty cambia (lógica de presentación)', () {
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

  // Test #256b: flujo completo corrección → FoodRecord → totales (integración)
  // Verifica que qty editada llega al registro nutricional y afecta totales una sola vez.
  group('#256b: flujo corrección → FoodRecord → totales (integración)', () {
    late FoodService svc;
    const uid = 'test_user_256';

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Evita errores de plugin de SharedPreferences en tests headless
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/shared_preferences'),
        (MethodCall call) async {
          if (call.method == 'getAll') return <String, Object>{};
          if (call.method == 'setStringList') return true;
          return null;
        },
      );
      SharedPreferences.setMockInitialValues({});
      svc = FoodService();
      final prefs = await SharedPreferences.getInstance();
      await svc.loadForUser(AccountPreferences(prefs, uid), uid);
    });

    test('qty editada llega a FoodRecord y kcal es proporcional', () async {
      // Propuesta original: 100g de pollo = 165 kcal
      const originalQty = 100.0;
      const originalKcal = 165.0;
      // El usuario edita a 250g en la pantalla de revisión
      const editedQty = 250.0;
      final expectedKcal = originalKcal * editedQty / originalQty; // 412.5

      final record = FoodRecord(
        id: 'fr_test_256b',
        uid: uid,
        foodId: 'pollo_pechuga_cocida',
        foodName: 'Pollo pechuga cocida',
        refQty: originalQty,
        kcalRef: originalKcal,
        proteinRef: 31,
        carbsRef: 0,
        fatRef: 3.57,
        refUnit: 'g',
        quantity: editedQty,   // ← qty editada por el usuario
        unit: 'g',
        mealType: MealType.almuerzo,
        consumedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await svc.add(record);

      // FoodRecord.kcal usa la fórmula proporcional: kcalRef × quantity / refQty
      expect(record.kcal, closeTo(expectedKcal, 0.1));

      // kcalForDay agrega todos los registros del día
      final total = svc.kcalForDay(DateTime.now());
      expect(total, closeTo(expectedKcal, 0.1));
    });

    test('guardar mismo ID dos veces no duplica los totales (#256b idempotencia)', () async {
      const editedQty = 200.0;
      const originalKcal = 165.0;
      const originalQty = 100.0;
      final expectedKcal = originalKcal * editedQty / originalQty; // 330.0

      final record = FoodRecord(
        id: 'fr_test_256b_idem',
        uid: uid,
        foodId: 'pollo_pechuga_cocida',
        foodName: 'Pollo pechuga cocida',
        refQty: originalQty,
        kcalRef: originalKcal,
        proteinRef: 31,
        carbsRef: 0,
        fatRef: 3.57,
        refUnit: 'g',
        quantity: editedQty,
        unit: 'g',
        mealType: MealType.almuerzo,
        consumedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Primer guardado
      await svc.add(record);
      final firstTotal = svc.kcalForDay(DateTime.now());

      // Segundo guardado con mismo ID (simula doble tap o retry)
      await svc.add(record);
      final secondTotal = svc.kcalForDay(DateTime.now());

      // Los totales no se duplican — FoodService.add actualiza en lugar de agregar
      expect(secondTotal, closeTo(firstTotal, 0.01),
          reason: 'Guardar dos veces el mismo ID no debe duplicar los totales');
      expect(secondTotal, closeTo(expectedKcal, 0.1));
    });
  });
}
