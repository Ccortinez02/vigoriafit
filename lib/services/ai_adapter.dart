import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../core/secrets.dart';
import '../data/food_catalog.dart';

/// Tipos de error del servicio de IA.
enum AiError { noConfig, noNetwork, timeout, quota, blocked, invalidResponse, unknown }

class AiException implements Exception {
  final AiError kind;
  final String? detail;
  const AiException(this.kind, [this.detail]);

  @override
  String toString() => 'AiException(${kind.name}${detail != null ? ": $detail" : ""})';
}

/// Propuesta de alimento devuelta por el análisis de imagen.
class FoodProposal {
  final String suggestedName;
  final String? catalogId;
  final double estimatedQty;
  final String estimatedUnit;
  final double? kcalEstimated;
  final double? proteinEstimated;
  final double? carbsEstimated;
  final double? fatEstimated;
  final bool fromCatalog;
  final String? note;

  const FoodProposal({
    required this.suggestedName,
    this.catalogId,
    required this.estimatedQty,
    required this.estimatedUnit,
    this.kcalEstimated,
    this.proteinEstimated,
    this.carbsEstimated,
    this.fatEstimated,
    this.fromCatalog = false,
    this.note,
  });

  FoodProposal copyWith({
    String? suggestedName,
    double? estimatedQty,
    String? estimatedUnit,
    double? kcalEstimated,
    double? proteinEstimated,
    double? carbsEstimated,
    double? fatEstimated,
    String? note,
  }) => FoodProposal(
    suggestedName:    suggestedName    ?? this.suggestedName,
    catalogId:        catalogId,
    estimatedQty:     estimatedQty     ?? this.estimatedQty,
    estimatedUnit:    estimatedUnit    ?? this.estimatedUnit,
    kcalEstimated:    kcalEstimated    ?? this.kcalEstimated,
    proteinEstimated: proteinEstimated ?? this.proteinEstimated,
    carbsEstimated:   carbsEstimated   ?? this.carbsEstimated,
    fatEstimated:     fatEstimated     ?? this.fatEstimated,
    fromCatalog:      fromCatalog,
    note:             note             ?? this.note,
  );
}

class FoodAnalysisResult {
  final String requestId;
  final List<FoodProposal> proposals;
  final String? rawResponse;
  final bool isPartial;

  const FoodAnalysisResult({
    required this.requestId,
    required this.proposals,
    this.rawResponse,
    this.isPartial = false,
  });
}

typedef ChatMessage = ({String role, String text});

abstract class AiAdapter {
  Future<String> chat(
    String systemPrompt,
    List<ChatMessage> history,
    String userMessage, {
    String? requestId,
    Duration timeout,
  });

  Future<FoodAnalysisResult> analyzeFood(
    Uint8List imageBytes, {
    String? requestId,
    Duration timeout,
  });

  bool get isConfigured;
}

// ── Esquema de respuesta estructurada para análisis de comida ─────────────────

/// Esquema JSON que el modelo debe respetar al analizar imágenes de comida.
/// Con responseSchema el modelo está restringido a este formato — no puede
/// incluir texto libre fuera del JSON ni campos adicionales.
final _foodResponseSchema = Schema.object(
  properties: {
    'items': Schema.array(
      items: Schema.object(
        properties: {
          'name':    Schema.string(description: 'Nombre corto del alimento en español'),
          'qty':     Schema.number(description: 'Cantidad estimada, positiva'),
          'unit':    Schema.enumString(
                       enumValues: ['g', 'ml', 'unidad'],
                       description: 'Unidad de medida',
                     ),
          // Los nutrientes son opcionales: omitir si no hay estimación confiable.
          'kcal':    Schema.number(description: 'Calorías estimadas'),
          'protein': Schema.number(description: 'Proteína en gramos'),
          'carbs':   Schema.number(description: 'Carbohidratos en gramos'),
          'fat':     Schema.number(description: 'Grasa en gramos'),
        },
        // name/qty/unit son requeridos; nutrientes son opcionales.
        optionalProperties: ['kcal', 'protein', 'carbs', 'fat'],
      ),
      description: 'Lista de alimentos identificados, vacía si no hay comida',
    ),
  },
  // items es el único campo requerido del objeto raíz.
);

// ── Adaptador real (Firebase AI Logic) ───────────────────────────────────────

class GeminiAdapter implements AiAdapter {
  /// Firebase AI Logic siempre está configurado cuando Firebase está inicializado.
  /// No requiere API key en el cliente: la autenticación la gestiona Firebase Auth.
  @override
  bool get isConfigured => true;

  GenerativeModel _chatModel(String systemPrompt) =>
      FirebaseAI.googleAI().generativeModel(
        model: kGeminiModel,
        systemInstruction: Content.system(systemPrompt),
        generationConfig: GenerationConfig(maxOutputTokens: 500, temperature: 0.7),
      );

  /// Modelo de visión con salida estructurada (responseSchema).
  /// El modelo devuelve directamente JSON válido según [_foodResponseSchema];
  /// no puede incluir texto libre fuera del JSON.
  GenerativeModel _visionModel() =>
      FirebaseAI.googleAI().generativeModel(
        model: kGeminiModel,
        generationConfig: GenerationConfig(
          temperature: 0.2,
          responseMimeType: 'application/json',
          responseSchema: _foodResponseSchema,
        ),
      );

  @override
  Future<String> chat(
    String systemPrompt,
    List<ChatMessage> history,
    String userMessage, {
    String? requestId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final model = _chatModel(systemPrompt);
      final geminiHistory = history.map((m) =>
        m.role == 'user'
          ? Content('user', [TextPart(m.text)])
          : Content.model([TextPart(m.text)]),
      ).toList();
      final chat = model.startChat(history: geminiHistory);
      final res = await chat.sendMessage(Content.text(userMessage)).timeout(timeout);
      if (res.promptFeedback?.blockReason != null) {
        throw const AiException(AiError.blocked);
      }
      final text = res.text?.trim();
      if (text == null || text.isEmpty) throw const AiException(AiError.invalidResponse);
      return text;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw const AiException(AiError.timeout);
    } on SocketException {
      throw const AiException(AiError.noNetwork);
    } on InvalidApiKey catch (e) {
      throw AiException(AiError.noConfig, e.toString());
    } on FirebaseAIException catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('quota') || msg.contains('resource_exhausted') || msg.contains('429')) {
        throw AiException(AiError.quota, e.toString());
      }
      if (msg.contains('404') || msg.contains('not found') || msg.contains('not supported')) {
        throw AiException(AiError.noConfig, 'Modelo $kGeminiModel no disponible: ${e.toString()}');
      }
      if (msg.contains('api_not_enabled') || msg.contains('service') || msg.contains('403')
          || msg.contains('app check') || msg.contains('permission')) {
        throw AiException(AiError.noConfig, e.toString());
      }
      throw AiException(AiError.unknown, e.toString());
    } catch (e) {
      throw AiException(AiError.unknown, e.toString());
    }
  }

  @override
  Future<FoodAnalysisResult> analyzeFood(
    Uint8List imageBytes, {
    String? requestId,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    // Prompt simplificado: el modelo está restringido al esquema JSON por responseSchema.
    const prompt =
        'Eres un nutricionista chileno. Analiza esta foto de comida.\n'
        'Identifica hasta 5 alimentos visibles con sus cantidades estimadas.\n'
        'qty debe ser positivo. Omite un campo de nutriente si no puedes estimarlo.\n'
        'Si la imagen no contiene comida, devuelve items vacío.';
    try {
      final model = _visionModel();
      final res = await model.generateContent([
        Content.multi([TextPart(prompt), InlineDataPart('image/jpeg', imageBytes)]),
      ]).timeout(timeout);
      if (res.promptFeedback?.blockReason != null) {
        throw const AiException(AiError.blocked);
      }
      final raw = res.text?.trim() ?? '';
      return _parseAnalysis(raw, requestId ?? 'gemini');
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw const AiException(AiError.timeout);
    } on SocketException {
      throw const AiException(AiError.noNetwork);
    } on InvalidApiKey catch (e) {
      throw AiException(AiError.noConfig, e.toString());
    } on FirebaseAIException catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('quota') || msg.contains('resource_exhausted') || msg.contains('429')) {
        throw AiException(AiError.quota, e.toString());
      }
      // Modelo no disponible: 404, model_not_found, model not supported.
      if (msg.contains('404') || msg.contains('not found') || msg.contains('not supported')) {
        throw AiException(AiError.noConfig, 'Modelo $kGeminiModel no disponible: ${e.toString()}');
      }
      if (msg.contains('api_not_enabled') || msg.contains('service') || msg.contains('403')
          || msg.contains('app check') || msg.contains('permission')) {
        throw AiException(AiError.noConfig, e.toString());
      }
      throw AiException(AiError.unknown, e.toString());
    } catch (e) {
      throw AiException(AiError.unknown, e.toString());
    }
  }
}

// ── Adaptador simulado (tests) ────────────────────────────────────────────────

class MockAiAdapter implements AiAdapter {
  AiError? injectError;
  String chatResponse;
  FoodAnalysisResult? foodResponse;
  Duration delay;

  MockAiAdapter({
    this.injectError,
    this.chatResponse = 'Respuesta simulada del coach.',
    this.foodResponse,
    this.delay = Duration.zero,
  });

  @override
  bool get isConfigured => injectError != AiError.noConfig;

  @override
  Future<String> chat(
    String systemPrompt,
    List<ChatMessage> history,
    String userMessage, {
    String? requestId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (injectError != null) throw AiException(injectError!);
    return chatResponse;
  }

  @override
  Future<FoodAnalysisResult> analyzeFood(
    Uint8List imageBytes, {
    String? requestId,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (injectError != null) throw AiException(injectError!);
    return foodResponse ??
        FoodAnalysisResult(
          requestId: requestId ?? 'mock',
          proposals: [
            const FoodProposal(
              suggestedName: 'Comida simulada',
              estimatedQty: 100,
              estimatedUnit: 'g',
              kcalEstimated: 200,
              proteinEstimated: 15,
              carbsEstimated: 20,
              fatEstimated: 5,
            ),
          ],
        );
  }
}

// ── Parseador de respuesta de análisis de imagen ──────────────────────────────

/// Expuesto para pruebas unitarias.
// ignore: non_constant_identifier_names
FoodAnalysisResult parseAnalysisForTest(String raw, String requestId) =>
    _parseAnalysis(raw, requestId);

FoodAnalysisResult _parseAnalysis(String raw, String requestId) {
  if (raw.isEmpty) throw const AiException(AiError.invalidResponse, 'empty response');

  final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
  if (match == null) throw const AiException(AiError.invalidResponse, 'no JSON found');

  Map<String, dynamic> json;
  try {
    json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
  } catch (_) {
    throw const AiException(AiError.invalidResponse, 'JSON parse failed');
  }

  final items = json['items'];
  if (items == null || items is! List) {
    throw const AiException(AiError.invalidResponse, 'missing items array');
  }
  if (items.length > 5) {
    throw const AiException(AiError.invalidResponse, 'too many items (max 5)');
  }

  final proposals = <FoodProposal>[];
  for (final item in items) {
    if (item is! Map<String, dynamic>) {
      throw const AiException(AiError.invalidResponse, 'item not an object');
    }
    final name = item['name'];
    if (name == null || name is! String) {
      throw const AiException(AiError.invalidResponse, 'missing name');
    }
    final qtyRaw = item['qty'];
    if (qtyRaw == null || qtyRaw is! num) {
      throw const AiException(AiError.invalidResponse, 'invalid qty type');
    }
    final qty = qtyRaw.toDouble();
    if (qty <= 0) {
      throw const AiException(AiError.invalidResponse, 'qty must be > 0');
    }
    final unit = (item['unit'] ?? 'g').toString();

    double? safeNum(String key) {
      final v = item[key];
      if (v == null) return null;
      if (v is! num) throw const AiException(AiError.invalidResponse, 'invalid numeric field');
      final d = v.toDouble();
      if (d < 0) throw const AiException(AiError.invalidResponse, 'negative nutrient value');
      return d;
    }

    final kcal    = safeNum('kcal');
    final protein = safeNum('protein');
    final carbs   = safeNum('carbs');
    final fat     = safeNum('fat');

    final catalogMatch = _matchCatalog(name);
    proposals.add(FoodProposal(
      suggestedName:    name,
      catalogId:        catalogMatch?.id,
      estimatedQty:     qty,
      estimatedUnit:    unit,
      kcalEstimated:    kcal,
      proteinEstimated: protein,
      carbsEstimated:   carbs,
      fatEstimated:     fat,
      fromCatalog:      catalogMatch != null,
    ));
  }

  return FoodAnalysisResult(
    requestId:   requestId,
    proposals:   proposals,
    rawResponse: raw,
    isPartial:   false,
  );
}

FoodCatalogItem? _matchCatalog(String name) {
  final lower = name.toLowerCase();
  final words = lower.split(RegExp(r'\s+'));
  for (final item in FoodCatalog.all) {
    final itemName = item.name.toLowerCase();
    final itemWords = itemName.split(RegExp(r'\s+'));
    for (final w in words) {
      if (w.length >= 4 && itemWords.any((iw) => iw.contains(w) || w.contains(iw))) {
        return item;
      }
    }
    // also check by id keywords
    final idParts = item.id.split('_');
    for (final w in words) {
      if (w.length >= 4 && idParts.any((p) => p.contains(w) || w.contains(p))) {
        return item;
      }
    }
  }
  return null;
}
