import 'package:flutter/material.dart';

class ExempleDePage extends StatelessWidget {
  const ExempleDePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exemple de page'),
      ),
      body: const Center(
        child: Text('Bienvenue dans cet exemple :)'),
      ),
    );
  }
}
