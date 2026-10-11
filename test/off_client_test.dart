import 'dart:convert';
import 'dart:io';

import 'package:family_planner/features/nutrition/off_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Gegen echte Antworten von Open Food Facts (gespeichert am 11.10.2026).
void main() {
  final produkt = File('test/fixtures/off_product.json').readAsStringSync();
  final suche = File('test/fixtures/off_search.json').readAsStringSync();

  test('Produkt per Barcode', () async {
    late Uri gefragt;
    late Map<String, String> kopf;
    final c = OffClient(client: MockClient((r) async {
      gefragt = r.url;
      kopf = r.headers;
      return http.Response.bytes(utf8.encode(produkt), 200);
    }));
    final f = (await c.byBarcode('4009249001102'))!;
    expect(gefragt.path, '/api/v2/product/4009249001102.json');
    expect(kopf['User-Agent'], contains('UnserFamilienOrganizer'));
    expect(f.id, '4009249001102');
    expect(f.name, 'Kraft Klotz');
    expect(f.brand, 'Lieken Urkorn');
    expect(f.kcal100, 214);
    expect(f.protein100, 5.5);
    expect(f.carbs100, 41);
    expect(f.fat100, 1.3);
    expect(f.portionG, 100);
  });

  test('unbekannter Barcode ergibt null', () async {
    final c = OffClient(client: MockClient((_) async => http.Response(
          '{"status":0,"status_verbose":"product not found"}',
          404,
        )));
    expect(await c.byBarcode('123'), isNull);
  });

  test('Suche: auf Deutschland beschränkt, Marke aus der Liste, kcal aus kJ', () async {
    late Uri gefragt;
    final c = OffClient(client: MockClient((r) async {
      gefragt = r.url;
      return http.Response.bytes(utf8.encode(suche), 200);
    }));
    final liste = await c.search('haferflocken');
    expect(gefragt.queryParameters['q'], contains('countries_tags:"en:germany"'));
    expect(liste, isNotEmpty);
    final rinatura = liste.firstWhere((f) => f.id == '4013200254742');
    expect(rinatura.brand, 'Bio Rinatura Haferflocken');
    // Nur 1565 kJ angegeben: 1565 / 4,184 = 374 kcal.
    expect(rinatura.kcal100, closeTo(374, 0.5));
    expect(liste.firstWhere((f) => f.id == '4306188047162').brand, 'Jeden Tag');
  });

  test('überlastet gibt eine verständliche Meldung', () async {
    final c = OffClient(client: MockClient((_) async => http.Response('', 503)));
    expect(
      () => c.search('apfel'),
      throwsA(isA<OffException>().having((e) => e.message, 'message', contains('ausgelastet'))),
    );
  });

  test('ohne Name oder Brennwert kein Lebensmittel', () {
    expect(foodFromOff({'code': '1', 'nutriments': {'energy-kcal_100g': 10}}), isNull);
    expect(foodFromOff({'code': '1', 'product_name': 'X', 'nutriments': {}}), isNull);
  });
}
