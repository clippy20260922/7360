import 'package:flutter/material.dart';

class ChercherUnParking extends StatelessWidget {
  const ChercherUnParking({super.key});

  Widget _buildButton(String text) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {},
        child: Text(text, textAlign: TextAlign.left, ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chercher un parking'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Voir autour de moi', 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 164,
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('Cliquer ici pour ouvrir la carte'),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Liste des endroits', 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 16),
            _buildButton('Button'),
            ...List.generate(50, (k) => _buildButton('Bouton numéro ${k}'), ),
          ],
        ),
      ),
    );
  }
}
