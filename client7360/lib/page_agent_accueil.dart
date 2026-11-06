import 'dart:math' as math;

import 'package:flutter/material.dart';

class PageAgentAccueil extends StatelessWidget {
  const PageAgentAccueil({super.key});

  @override
  Widget build(BuildContext context) {
    final buttonStyle = FilledButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Page Agent'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,  
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Que faire ?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final buttonSize = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight / 3.4,
                  );

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox.square(
                        dimension: buttonSize,
                        child: FilledButton(
                          style: buttonStyle,
                          onPressed: () {},
                          child: const Text(
                            'Parcourir les parkings',
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
                            'Consulter l\'historique'
                            'd\'un véhicule ou d\'un usager',
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
                            'Voir les tâches à réaliser',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
