import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chercher_un_parking.dart';

class EcranDAccueil extends StatelessWidget {
  const EcranDAccueil({super.key});

  @override
  Widget build(BuildContext context) {
    final buttonStyle = FilledButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Bonjour !')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Qui êtes-vous ?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final buttonSize = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight / 2.2,
                  );

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox.square(
                        dimension: buttonSize,
                        child: FilledButton(
                          style: buttonStyle,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ChercherUnParking(),
                              ),
                            );
                          },
                          child: const Text(
                            'Je suis usager \n \n'
                            '(je souhaite juste regarder, voire réserver)',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      SizedBox.square(
                        dimension: buttonSize,
                        child: FilledButton(
                          style: buttonStyle,
                          onPressed: () {},
                          child: const Text(
                            'Je suis agent \n \n'
                            '(je veux contrôler)',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: buttonStyle,
                onPressed: () {},
                child: const Text('Réglages'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
