import 'dart:convert';
import 'dart:typed_data';

import 'package:family_planner/features/nutrition/nutrition_models.dart';
import 'package:family_planner/features/nutrition/photo_estimate.dart';
import 'package:family_planner/features/nutrition/photo_estimate_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Eine Antwort, wie sie die Schnittstelle mit Denkblock und Text schickt.
Map<String, dynamic> _antwort(Object inhalt, {String stop = 'end_turn'}) => {
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'model': 'claude-opus-5-5',
      'stop_reason': stop,
      'content': [
        {'type': 'thinking', 'thinking': ''},
        {'type': 'text', 'text': jsonEncode(inhalt)},
      ],
    };

const _teller = {
  'items': [
    {'name': 'Spaghetti', 'grams': 250, 'kcal': 395, 'protein_g': 14, 'carbs_g': 78, 'fat_g': 2.5},
    {'name': 'Bolognese', 'grams': 150, 'kcal': 210, 'protein_g': 13, 'carbs_g': 8, 'fat_g': 14},
  ],
  'hinweis': 'Menge der Soße schwer zu erkennen.',
};

void main() {
  group('Anfrage', () {
    test('Bild, Aufgabe und festes Antwortformat', () {
      final r = buildEstimateRequest(model: 'claude-opus-5-5', base64Image: 'QUJD');
      expect(r['model'], 'claude-opus-5-5');
      expect(r['fallbacks'], 'default');
      final out = r['output_config'] as Map;
      expect(out['effort'], 'medium');
      expect((out['format'] as Map)['type'], 'json_schema');
      final inhalt = ((r['messages'] as List).single as Map)['content'] as List;
      expect((inhalt.first as Map)['type'], 'image');
      expect(((inhalt.first as Map)['source'] as Map)['data'], 'QUJD');
      expect((inhalt.last as Map)['text'], contains('Gramm'));
      // Kein Denkbudget und keine ausgeschaltete Denkphase — beides lehnt Opus 5.5 ab.
      expect(r.containsKey('thinking'), isFalse);
    });

    test('Haiku ohne Ersatzmodell', () {
      final r = buildEstimateRequest(model: 'claude-haiku-5-5', base64Image: 'QUJD');
      expect(r.containsKey('fallbacks'), isFalse);
    });
  });

  group('Antwort', () {
    test('Komponenten mit Nährwerten', () {
      final e = parseEstimateResponse(_antwort(_teller));
      expect(e.items, hasLength(2));
      expect(e.items.first.name, 'Spaghetti');
      expect(e.items.first.grams, 250);
      expect(e.items.first.kcal, 395);
      expect(e.items.last.fat, 14);
      expect(e.hinweis, contains('Soße'));
    });

    test('eine Ablehnung wird gemeldet, nicht als leerer Teller gelesen', () {
      expect(
        () => parseEstimateResponse(_antwort(const {}, stop: 'refusal')),
        throwsA(isA<PhotoEstimateException>()),
      );
    });

    test('kein Essen auf dem Foto: leere Liste', () {
      final e = parseEstimateResponse(_antwort(const {'items': [], 'hinweis': ''}));
      expect(e.items, isEmpty);
    });
  });

  group('Verbindung', () {
    test('schickt Schlüssel, Version und Fallback-Kennung', () async {
      late http.Request gefragt;
      final c = ClaudePhotoClient(client: MockClient((r) async {
        gefragt = r;
        return http.Response.bytes(utf8.encode(jsonEncode(_antwort(_teller))), 200);
      }));
      final e = await c.estimate(
        apiKey: 'sk-test',
        model: 'claude-opus-5-5',
        jpeg: Uint8List.fromList([1, 2, 3]),
      );
      expect(e.items, hasLength(2));
      expect(gefragt.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(gefragt.headers['x-api-key'], 'sk-test');
      expect(gefragt.headers['anthropic-version'], '2023-06-01');
      expect(gefragt.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      final body = jsonDecode(gefragt.body) as Map;
      final bild = (((body['messages'] as List).single as Map)['content'] as List).first as Map;
      expect((bild['source'] as Map)['data'], base64Encode([1, 2, 3]));
    });

    test('falscher Schlüssel und Überlastung mit verständlicher Meldung', () async {
      Future<String> fehler(int status) async {
        final c = ClaudePhotoClient(client: MockClient((_) async => http.Response('{}', status)));
        try {
          await c.estimate(apiKey: 'x', model: 'claude-opus-5-5', jpeg: Uint8List(1));
          return '';
        } on PhotoEstimateException catch (e) {
          return e.message;
        }
      }

      expect(await fehler(401), contains('Schlüssel'));
      expect(await fehler(529), contains('ausgelastet'));
      expect(await fehler(429), contains('ausgelastet'));
    });
  });

  testWidgets('Prüfliste: abwählen und Menge ändern', (tester) async {
    List<MealEntry>? ergebnis;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                ergebnis = await showModalBottomSheet<List<MealEntry>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => PhotoReviewSheet(
                    estimate: parseEstimateResponse(_antwort(_teller)),
                    meal: Meal.abend,
                  ),
                );
              },
              child: const Text('öffnen'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('605 kcal eintragen'), findsOneWidget);

    // Bolognese abwählen.
    await tester.tap(find.text('Bolognese'));
    await tester.pumpAndSettle();
    expect(find.text('395 kcal eintragen'), findsOneWidget);

    // Spaghetti auf 125 g halbieren.
    await tester.tap(find.byTooltip('Menge ändern').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '125');
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('198 kcal eintragen'), findsOneWidget);

    await tester.tap(find.text('198 kcal eintragen'));
    await tester.pumpAndSettle();
    expect(ergebnis, hasLength(1));
    expect(ergebnis!.single.name, '📷 Spaghetti');
    expect(ergebnis!.single.grams, 125);
    expect(ergebnis!.single.protein, 7);
    expect(ergebnis!.single.meal, Meal.abend);
  });
}
