import 'package:flutter/material.dart';

class ExempleDePage extends StatelessWidget {
  // const ExempleDePage({super.key});
  const ExempleDePage({super.key, required this.un_exemple_de_variable});

  final String un_exemple_de_variable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exemple de page'),
      ),
      body: Center(
        child: Column(
          children: [
            Text('Bienvenue dans cet exemple :)'),
            SizedBox(height: 32),
            Text(this.un_exemple_de_variable),
          ]
        )
      ),
    );
  }
}
