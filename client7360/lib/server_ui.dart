
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ServerTestingPage extends StatefulWidget {
  const ServerTestingPage({super.key});

  @override
  State<ServerTestingPage> createState() => _ServerTestingPageState();
}

class _ServerTestingPageState extends State<ServerTestingPage> {
  int? nombrePlacesLibres;
  bool chargement = false;
  String? erreur;

  Future<void> chargerPlacesLibres() async {
    setState(() {
      chargement = true;
      erreur = null;
    });

    try {
      final url = Uri.parse('http://127.0.0.1:8000/data/free');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Erreur HTTP : ${response.statusCode}');
      }

      final Map<String, dynamic> resultat =
          jsonDecode(response.body) as Map<String, dynamic>;

      final int nombre = resultat['N'] as int;

      if (!mounted) return;

      setState(() {
        nombrePlacesLibres = nombre;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erreur = 'Impossible de récupérer les places libres. '
            'Vérifie que le backend est démarré.';
      });
    } finally {
      if (mounted) {
        setState(() {
          chargement = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    chargerPlacesLibres();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Places disponibles'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_parking,
                size: 70,
                color: Colors.blue,
              ),
              const SizedBox(height: 20),
              const Text(
                'Nombre de places libres',
                style: TextStyle(fontSize: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              if (chargement)
                const CircularProgressIndicator()
              else if (erreur != null)
                Text(
                  erreur!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                )
              else
                Text(
                  '${nombrePlacesLibres ?? 0}',
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                  ),
                ),

              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: chargement ? null : chargerPlacesLibres,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
