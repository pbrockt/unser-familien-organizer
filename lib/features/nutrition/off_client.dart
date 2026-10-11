import 'dart:convert';

import 'package:http/http.dart' as http;

import 'nutrition_models.dart';

class OffException implements Exception {
  OffException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Zugriff auf Open Food Facts — die freie Lebensmittel-Datenbank (ODbL).
///
/// Bewusst nur zwei Anfragen: ein Produkt per Barcode und eine Textsuche. Die komplette
/// Datenbank wäre mehrere Gigabyte groß; gebraucht wird nur, was man wirklich isst, und
/// das landet ohnehin im eigenen Puffer.
class OffClient {
  OffClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Open Food Facts verlangt eine erkennbare App-Kennung; anonyme Anfragen werden
  /// gedrosselt oder gesperrt.
  static const userAgent =
      'UnserFamilienOrganizer/1.0 (https://github.com/pbrockt/unser-familien-organizer)';

  static const _felder =
      'code,product_name,product_name_de,brands,nutriments,serving_quantity';

  Map<String, String> get _headers => {'User-Agent': userAgent};

  /// Ein Produkt per Barcode. `null`, wenn Open Food Facts es nicht kennt.
  Future<Food?> byBarcode(String code) async {
    final uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/${Uri.encodeComponent(code)}.json'
      '?fields=$_felder',
    );
    final r = await _get(uri);
    if (r.statusCode == 404) return null;
    _pruefe(r);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (j['status'] != 1 || j['product'] is! Map<String, dynamic>) return null;
    return foodFromOff(j['product'] as Map<String, dynamic>, code: code);
  }

  /// Textsuche, beschränkt auf Produkte, die in Deutschland verkauft werden.
  Future<List<Food>> search(String text) async {
    final q = '$text countries_tags:"en:germany"';
    final uri = Uri.parse('https://search.openfoodfacts.org/search').replace(
      queryParameters: {
        'q': q,
        'langs': 'de',
        'page_size': '25',
        'fields': _felder,
      },
    );
    final r = await _get(uri);
    _pruefe(r);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final out = <Food>[];
    for (final h in (j['hits'] as List? ?? const [])) {
      if (h is! Map<String, dynamic>) continue;
      final f = foodFromOff(h);
      if (f != null) out.add(f);
    }
    return out;
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw OffException('Open Food Facts nicht erreichbar: $e');
    }
  }

  void _pruefe(http.Response r) {
    if (r.statusCode == 429 || r.statusCode == 503) {
      throw OffException('Open Food Facts ist gerade ausgelastet — bitte gleich noch einmal.');
    }
    if (r.statusCode != 200) {
      throw OffException('Unerwartete Antwort von Open Food Facts (${r.statusCode}).');
    }
  }
}

/// Wandelt ein Produkt aus Open Food Facts in ein [Food]. `null`, wenn Name oder
/// Brennwert fehlen — ohne die ist ein Eintrag wertlos.
///
/// Öffentlich, damit sich die Umrechnung an gespeicherten Antworten prüfen lässt.
Food? foodFromOff(Map<String, dynamic> p, {String? code, DateTime? now}) {
  final barcode = (p['code'] as String?) ?? code;
  final name = ((p['product_name_de'] as String?)?.trim().isNotEmpty ?? false)
      ? (p['product_name_de'] as String).trim()
      : (p['product_name'] as String?)?.trim();
  if (name == null || name.isEmpty) return null;

  final n = (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? const {};
  double? zahl(String k) {
    final v = n[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  // kcal fehlen bei manchen Produkten; dann aus Kilojoule umrechnen.
  final kcal = zahl('energy-kcal_100g') ??
      (zahl('energy-kj_100g') ?? zahl('energy_100g')).let((kj) => kj / 4.184);
  if (kcal == null) return null;

  // Die Produkt-Schnittstelle liefert die Marken als Text, die Suche als Liste.
  final marken = p['brands'];
  final marke = switch (marken) {
    final String s => s.split(',').first.trim(),
    final List<dynamic> l when l.isNotEmpty => l.first.toString().trim(),
    _ => null,
  };

  final portion = p['serving_quantity'];
  return Food(
    id: barcode ?? 'off:$name',
    name: name,
    brand: (marke == null || marke.isEmpty) ? null : marke,
    barcode: barcode,
    kcal100: kcal,
    protein100: zahl('proteins_100g'),
    carbs100: zahl('carbohydrates_100g'),
    fat100: zahl('fat_100g'),
    sugar100: zahl('sugars_100g'),
    portionG: portion is num && portion > 0
        ? portion.toDouble()
        : (portion is String ? double.tryParse(portion) : null),
    source: 'off',
    updated: now ?? DateTime.now(),
  );
}

extension _Let<T extends Object> on T? {
  R? let<R>(R Function(T) f) {
    final v = this;
    return v == null ? null : f(v);
  }
}
