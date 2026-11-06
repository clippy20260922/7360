// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client7360/main.dart';

void main() {
  // Le test d'exemple du modèle Flutter cherchait un compteur qui n'existe plus :
  // on vérifie à la place que l'appli démarre sur l'écran d'accueil.
  testWidgets("l'appli démarre sur l'écran d'accueil", (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Qui êtes-vous ?'), findsOneWidget);
    expect(find.textContaining('Je suis usager'), findsOneWidget);
    expect(find.textContaining('Je suis agent'), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(3)); // usager, agent, réglages
  });
}
