// Test de la page de paiement (SCRUM-13) avec un faux serveur.
// Lancer : flutter test test/paiement_page_test.dart
import 'dart:convert';

import 'package:client7360/paiement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object corps, [int statut = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(corps)), statut,
        headers: {'content-type': 'application/json'});

void main() {
  testWidgets('connexion, choix du véhicule et de la durée, paiement',
      (tester) async {
    final requetes = <String>[];
    final serveur = MockClient((req) async {
      requetes.add('${req.method} ${req.url.path}?${req.url.query}');
      final duree = int.tryParse(req.url.queryParameters['duree'] ?? '') ?? 0;
      switch ('${req.method} ${req.url.path}') {
        case 'GET /data/1/prix':
          return _json({'place': 1, 'type': 'voit', 'duree': duree, 'tarif_horaire': 1.6,
              'prix': (1.6 * duree / 60 * 100).round() / 100});
        case 'POST /token':
          return req.bodyFields['password'] == 'Mon_mdp123'
              ? _json({'username': 'ab123456', 'type': 'user'})
              : _json({'detail': 'username ou mot de passe erroné'}, 400);
        case 'GET /user/ab123456':
          return _json({'N': 3, 'data': [
            ['AB123CD', 'ab123456', 'voit', false, 4],
            ['MN012OP', 'ab123456', 'moto', false, null],
            ['QR345ST', 'ab123456', 'voit', false, null],
          ]});
        case 'POST /data/1/payer':
          return _json({'paiement': 1, 'place': 1, 'plaque': req.url.queryParameters['plaque'],
              'duree': duree, 'prix': 0.8, 'fin_occupation': '2026-11-06 10:30:00',
              'prolongation': false});
      }
      return _json({'detail': 'inconnu'}, 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: PaiementPage(idPlace: 1)));
      await tester.pumpAndSettle();

      // Le prix est demandé dès l'ouverture
      expect(find.text('Tarif : 1,60 € / h'), findsOneWidget);
      expect(find.text('Prix pour 1 h : 1,60 €'), findsOneWidget);

      // Mauvais mot de passe
      await tester.enterText(find.widgetWithText(TextField, 'Identifiant'), 'ab123456');
      await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'faux');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();
      expect(find.text('Identifiant ou mot de passe incorrect'), findsOneWidget);

      // Bon mot de passe : on voit ses véhicules
      await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'Mon_mdp123');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();
      expect(find.text('Connecté : ab123456'), findsOneWidget);

      // Seules les voitures sont proposées pour une place voiture
      await tester.tap(find.text('AB123CD'));
      await tester.pumpAndSettle();
      expect(find.text('MN012OP'), findsNothing);
      await tester.tap(find.text('QR345ST').last);
      await tester.pumpAndSettle();

      // 30 min : le prix est redemandé au serveur
      await tester.tap(find.text('1 h'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min').last);
      await tester.pumpAndSettle();
      expect(find.text('Payer 0,80 €'), findsOneWidget);

      await tester.ensureVisible(find.text('Payer 0,80 €'));
      await tester.tap(find.text('Payer 0,80 €'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Paiement accepté (0,80 €) : place 1 payée'), findsOneWidget);

      // Après le paiement, le bouton est désactivé
      final bouton = tester.widget<ButtonStyleButton>(
          find.ancestor(of: find.text('Payer 0,80 €'), matching: find.bySubtype<ButtonStyleButton>()));
      expect(bouton.onPressed, isNull);
    }, () => serveur);

    expect(requetes, contains('POST /data/1/payer?plaque=QR345ST&duree=30'));
  });
}
