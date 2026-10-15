import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Ein erkanntes Lebensmittel auf dem Foto — geschätzt, nicht gemessen.
class PhotoItem {
  const PhotoItem({
    required this.name,
    required this.grams,
    required this.kcal,
    this.protein,
    this.carbs,
    this.fat,
  });

  final String name;
  final double grams;
  final double kcal;
  final double? protein;
  final double? carbs;
  final double? fat;
}

class PhotoEstimate {
  const PhotoEstimate({required this.items, this.hinweis = ''});

  final List<PhotoItem> items;

  /// Kurze Anmerkung zur Unsicherheit, etwa „Soße kaum zu erkennen".
  final String hinweis;
}

class PhotoEstimateException implements Exception {
  PhotoEstimateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Modelle zur Auswahl. Teurer heißt hier: genauere Schätzung.
const kClaudeModels = <(String, String)>[
  ('claude-opus-5-5', 'Opus 5.5 — beste Schätzung, ca. 1 Cent je Foto'),
  ('claude-sonnet-5-5', 'Sonnet 5.5 — etwas günstiger'),
  ('claude-haiku-5-5', 'Haiku 5.5 — am günstigsten, eher grob'),
];
const kDefaultClaudeModel = 'claude-opus-5-5';

/// Schlüssel und Modell. Der Schlüssel liegt im geschützten Speicher des Geräts — nie in
/// der App selbst (die APK ist öffentlich) und nie in der Nextcloud.
class ClaudeSettings {
  ClaudeSettings({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _keyName = 'claude_api_key';
  static const _modelKey = 'claude_model';

  Future<String?> apiKey() async {
    final k = await _storage.read(key: _keyName);
    return (k == null || k.trim().isEmpty) ? null : k.trim();
  }

  Future<void> setApiKey(String? key) async {
    if (key == null || key.trim().isEmpty) {
      await _storage.delete(key: _keyName);
    } else {
      await _storage.write(key: _keyName, value: key.trim());
    }
  }

  Future<String> model() async =>
      (await SharedPreferences.getInstance()).getString(_modelKey) ?? kDefaultClaudeModel;

  Future<void> setModel(String m) async =>
      (await SharedPreferences.getInstance()).setString(_modelKey, m);
}

const _prompt = '''
Auf dem Foto ist eine Mahlzeit. Schätze jede erkennbare Komponente einzeln: Name auf
Deutsch, Menge in Gramm und die Nährwerte für genau diese Menge (kcal, Eiweiß,
Kohlenhydrate, Fett in Gramm). Rechne sichtbare Soßen, Öl und Beilagen mit.
Ist eine Menge schwer zu erkennen, nimm eine übliche Portion. Ist kein Essen zu sehen,
gib eine leere Liste zurück. Im Hinweis höchstens ein Satz dazu, was unsicher ist.''';

/// Antwortformat: Die Schnittstelle garantiert damit gültiges JSON in genau dieser Form.
const Map<String, Object> _schema = {
  'type': 'object',
  'properties': {
    'items': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'grams': {'type': 'number'},
          'kcal': {'type': 'number'},
          'protein_g': {'type': 'number'},
          'carbs_g': {'type': 'number'},
          'fat_g': {'type': 'number'},
        },
        'required': ['name', 'grams', 'kcal', 'protein_g', 'carbs_g', 'fat_g'],
        'additionalProperties': false,
      },
    },
    'hinweis': {'type': 'string'},
  },
  'required': ['items', 'hinweis'],
  'additionalProperties': false,
};

/// Die Anfrage an die Claude-Schnittstelle. Öffentlich, damit sich ihre Form ohne Netz
/// prüfen lässt.
Map<String, Object> buildEstimateRequest({
  required String model,
  required String base64Image,
  String mediaType = 'image/jpeg',
}) =>
    {
      'model': model,
      'max_tokens': 16000,
      // Haiku hat keinen Ersatz bei Ablehnungen; für die anderen springt bei einer
      // Ablehnung automatisch das empfohlene Ersatzmodell ein.
      if (model != 'claude-haiku-5-5') 'fallbacks': 'default',
      'output_config': {
        // Ein Foto schätzen braucht kein langes Nachdenken — mittel hält es günstig.
        'effort': 'medium',
        'format': {'type': 'json_schema', 'schema': _schema},
      },
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Image},
            },
            {'type': 'text', 'text': _prompt.trim()},
          ],
        },
      ],
    };

/// Liest die Antwort. Erst den Abbruchgrund prüfen, dann den Inhalt — eine Ablehnung
/// kommt mit Status 200.
PhotoEstimate parseEstimateResponse(Map<String, dynamic> j) {
  if (j['stop_reason'] == 'refusal') {
    throw PhotoEstimateException('Claude hat das Foto nicht ausgewertet.');
  }
  if (j['stop_reason'] == 'max_tokens') {
    throw PhotoEstimateException('Die Antwort wurde abgeschnitten — bitte noch einmal.');
  }
  final text = (j['content'] as List? ?? const [])
      .whereType<Map>()
      .where((b) => b['type'] == 'text')
      .map((b) => b['text'] as String)
      .firstOrNull;
  if (text == null) throw PhotoEstimateException('Keine Antwort erhalten.');
  final daten = jsonDecode(text) as Map<String, dynamic>;
  double? zahl(Object? v) => v is num ? v.toDouble() : null;
  return PhotoEstimate(
    hinweis: (daten['hinweis'] as String?)?.trim() ?? '',
    items: [
      for (final i in (daten['items'] as List? ?? const []))
        if (i is Map && i['name'] is String && zahl(i['kcal']) != null)
          PhotoItem(
            name: (i['name'] as String).trim(),
            grams: zahl(i['grams']) ?? 0,
            kcal: zahl(i['kcal'])!,
            protein: zahl(i['protein_g']),
            carbs: zahl(i['carbs_g']),
            fat: zahl(i['fat_g']),
          ),
    ],
  );
}

/// Schickt ein Foto an Claude und bekommt eine Schätzung zurück.
class ClaudePhotoClient {
  ClaudePhotoClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<PhotoEstimate> estimate({
    required String apiKey,
    required String model,
    required Uint8List jpeg,
  }) async {
    final http.Response r;
    try {
      r = await _client
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              if (model != 'claude-haiku-5-5')
                'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode(buildEstimateRequest(model: model, base64Image: base64Encode(jpeg))),
          )
          .timeout(const Duration(minutes: 2));
    } catch (e) {
      throw PhotoEstimateException('Claude nicht erreichbar: $e');
    }
    switch (r.statusCode) {
      case 200:
        return parseEstimateResponse(
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>,
        );
      case 401:
        throw PhotoEstimateException(
          'Der API-Schlüssel wird nicht angenommen — bitte in den Einstellungen prüfen.',
        );
      case 402 || 403:
        throw PhotoEstimateException(
          'Kein Guthaben oder kein Zugriff — bitte in der Anthropic Console nachsehen.',
        );
      case 429 || 529:
        throw PhotoEstimateException('Claude ist gerade ausgelastet — bitte gleich noch einmal.');
      default:
        throw PhotoEstimateException('Unerwartete Antwort von Claude (${r.statusCode}).');
    }
  }
}
