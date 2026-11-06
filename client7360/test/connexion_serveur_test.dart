// Adresse du serveur, jeton de connexion, place enregistrée puis libérée sur le serveur.
import 'dart:convert';

import 'package:client7360/paiement_page.dart';
import 'package:client7360/parking_map_page.dart';
import 'package:client7360/reprendre_la_route_page.dart';
import 'package:client7360/reservations_locales.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object corps, [int code = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(corps)), code,
    headers: {'content-type': 'application/json'});

void main() {
  group('adresse du serveur', () {
    String choisir({String envoyee = '', String? enregistree, bool web = false, bool android = false, String? page}) =>
        ParkingService.choisirAdresse(
            envoyee: envoyee, enregistree: enregistree, web: web, android: android,
            page: page == null ? null : Uri.parse(page));

    test('--dart-define=API_URL passe avant tout', () {
      expect(choisir(envoyee: 'http://10.1.2.3:8000/', enregistree: 'http://x:1', web: true, page: 'http://y:8360/'),
          'http://10.1.2.3:8000');
    });
    test("l'adresse des Réglages passe avant celle de la page", () {
      expect(choisir(enregistree: ' http://192.168.1.20:8000 ', web: true, page: 'http://y:8360/'),
          'http://192.168.1.20:8000');
      expect(choisir(enregistree: '  ', android: true), 'http://10.0.2.2:8000');
    });
    test('sur le web : la machine qui sert la page, port 8000', () {
      expect(choisir(web: true, page: 'http://100.111.128.15:8360/#/'), 'http://100.111.128.15:8000');
      expect(choisir(web: true, page: 'http://127.0.0.1:8360/'), 'http://127.0.0.1:8000');
    });
    test('émulateur Android, sinon 127.0.0.1', () {
      expect(choisir(android: true), 'http://10.0.2.2:8000');
      expect(choisir(), 'http://127.0.0.1:8000');
    });
  });

  group('place payée puis libérée', () {
    late List<http.Request> requetes;
    late Map<String, http.Response Function(http.Request)> serveur;
    final client = MockClient((r) async {
      requetes.add(r);
      final cle = '${r.method} ${r.url.path}';
      return serveur[cle]?.call(r) ?? json({'detail': 'inconnu : $cle'}, 404);
    });

    setUp(() {
      requetes = [];
      ParkingService.baseUrl = 'http://serveur:8000';
      ParkingService.jeton = null;
      ParkingService.usager = null;
      ReservationsLocales.liberer('QR345ST');
      ReservationsLocales.liberer('AB123CD');
    });

    testWidgets('payer garde le jeton et note la place pour le départ', (tester) async {
      serveur = {
        'GET /data/7/prix': (r) => json({'place': 7, 'type': 'voit', 'duree': 60, 'tarif_horaire': 1.6, 'prix': 1.6}),
        'GET /data/8/prix': (r) => json({'place': 8, 'type': 'voit', 'duree': 60, 'tarif_horaire': 2.0, 'prix': 2.0}),
        'POST /token': (r) => json({'username': 'ab123456', 'type': 'user', 'access_token': 'J1', 'token_type': 'bearer'}),
        'GET /user/ab123456': (r) => r.headers['Authorization'] == 'Bearer J1'
            ? json({'N': 2, 'data': [['QR345ST', 'ab123456', 'voit', 0, null], ['MOTO1', 'ab123456', 'moto', 0, null]]})
            : json({'detail': 'Authentifiez-vous pour avoir accès à cette fonctionnalité'}, 400),
        'POST /data/7/payer': (r) => r.headers['Authorization'] == 'Bearer J1'
            ? json({'paiement': 1, 'place': 7, 'plaque': 'QR345ST', 'duree': 60, 'prix': 1.6,
                'fin_occupation': '2026-11-17 14:00:00', 'prolongation': false})
            : json({'detail': 'Connectez-vous pour payer'}, 401),
      };
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: PaiementPage(idPlace: 7)));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Identifiant'), 'ab123456');
        await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'secret');
        await tester.tap(find.text('Se connecter'));
        await tester.pumpAndSettle();
        expect(find.text('Connecté : ab123456'), findsOneWidget);
        expect(ParkingService.jeton, 'J1');

        await tester.tap(find.text('Payer 1,60 €'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Paiement accepté'), findsOneWidget);
        expect(ReservationsLocales.rechercher('QR345ST'), '7');
        expect(ReservationsLocales.estSurLeServeur('QR345ST'), isTrue);

        // Une autre place : la session est reprise, pas besoin de se reconnecter
        await tester.pumpWidget(const MaterialApp(home: PaiementPage(idPlace: 8)));
        await tester.pumpAndSettle();
        expect(find.text('Connecté : ab123456'), findsOneWidget);
      }, () => client);
      expect(requetes.where((r) => r.url.path == '/token').length, 1);
    });

    Future<void> partir(WidgetTester tester, String plaque) async {
      await tester.pumpWidget(const MaterialApp(home: ReprendreLaRoutePage()));
      await tester.enterText(find.byType(TextField), plaque.toLowerCase());
      await tester.tap(find.text('Rechercher ma réservation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer mon départ'));
      await tester.pumpAndSettle();
    }

    testWidgets('le départ libère la place sur le serveur, avec le jeton', (tester) async {
      ParkingService.jeton = 'J1';
      ReservationsLocales.reserverSurLeServeur('AB123CD', '4');
      serveur = {'PATCH /data/4/set_occupation': (r) => json({'data': [4]})};
      await http.runWithClient(() => partir(tester, 'AB123CD'), () => client);

      final patch = requetes.single;
      expect(patch.url.queryParameters, {'set_bool': 'false', 'vehicule': 'AB123CD'});
      expect(patch.headers['Authorization'], 'Bearer J1');
      expect(find.text('Départ confirmé pour la place n°4'), findsOneWidget);
      expect(ReservationsLocales.rechercher('AB123CD'), isNull);
    });

    testWidgets('refus du serveur : le message est affiché et la réservation gardée', (tester) async {
      ParkingService.jeton = 'J1';
      ReservationsLocales.reserverSurLeServeur('AB123CD', '4');
      serveur = {
        'PATCH /data/4/set_occupation': (r) => json({'detail': "Ce véhicule n'est pas garé sur cette place"}, 400),
      };
      await http.runWithClient(() => partir(tester, 'AB123CD'), () => client);

      expect(find.text("Départ non enregistré : Ce véhicule n'est pas garé sur cette place"), findsOneWidget);
      expect(ReservationsLocales.rechercher('AB123CD'), '4');
    });

    testWidgets('serveur redémarré (jeton oublié) : reconnexion puis départ', (tester) async {
      var jetonValide = 'J1';
      serveur = {
        'POST /token': (r) => json({'username': 'ab123456', 'type': 'user', 'access_token': jetonValide, 'token_type': 'bearer'}),
        'PATCH /data/4/set_occupation': (r) => r.headers['Authorization'] == 'Bearer $jetonValide'
            ? json({'data': [4]})
            : json({'detail': 'Authentifiez-vous pour avoir accès à cette fonctionnalité'}, 400),
      };
      await http.runWithClient(() async {
        await ParkingService.connecter('ab123456', 'secret');
        ReservationsLocales.reserverSurLeServeur('AB123CD', '4');
        jetonValide = 'J2'; // le serveur a redémarré
        await partir(tester, 'AB123CD');
      }, () => client);

      expect([for (final r in requetes) r.url.path],
          ['/token', '/data/4/set_occupation', '/token', '/data/4/set_occupation']);
      expect(requetes.last.headers['Authorization'], 'Bearer J2');
      expect(find.text('Départ confirmé pour la place n°4'), findsOneWidget);
    });

    testWidgets('réservation de démonstration : rien n\'est envoyé au serveur', (tester) async {
      ReservationsLocales.reserver('AB123CD', 'A12');
      serveur = {};
      await http.runWithClient(() => partir(tester, 'AB123CD'), () => client);
      expect(requetes, isEmpty);
      expect(find.text('Départ confirmé pour la place n°A12'), findsOneWidget);
    });
  });
}
