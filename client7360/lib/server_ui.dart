
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ServerTestingPage extends StatefulWidget {
  const ServerTestingPage({super.key});

  @override
  State<ServerTestingPage> createState() => _ServerTestingPageState();
}

class _ServerTestingPageState extends State<ServerTestingPage> {
  final String apiUrl = 'http://127.0.0.1:8000';

  int nombrePlacesLibres = 0;
  List<dynamic> placesLibres = [];

  bool chargement = false;
  int? placeEnCours;
  String? erreur;

  Future<void> chargerPlacesLibres() async {
    setState(() {
      chargement = true;
      erreur = null;
    });

    try {
      final response = await http.get(
        Uri.parse('$apiUrl/data/free'),
      );

      if (response.statusCode != 200) {
        throw Exception('Erreur HTTP ${response.statusCode}');
      }

      final resultat =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) return;

      setState(() {
        nombrePlacesLibres = resultat['N'] as int;
        placesLibres = resultat['data'] as List<dynamic>? ?? [];
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erreur = 'Impossible de récupérer les places libres : $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          chargement = false;
        });
      }
    }
  }

  Future<void> occuperPlace(int id) async {
    setState(() {
      placeEnCours = id;
      erreur = null;
    });

    try {
      // Paramètres temporaires pour la démonstration.
      // La tâche Jira 3 permettra de choisir le véhicule.
      final url = Uri.parse(
        '$apiUrl/data/$id/set_occupation',
      ).replace(queryParameters: {
        'set_bool': 'true',
        'occupation_time_min': '60',
        'vehicule': 'AB123CD',
      });

      final response = await http.patch(url);

      if (response.statusCode != 200) {
        String message = response.body;

        try {
          final resultat = jsonDecode(response.body);
          if (resultat is Map && resultat['detail'] != null) {
            message = resultat['detail'].toString();
          }
        } catch (_) {}

        throw Exception(message);
      }

      await chargerPlacesLibres();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('La place n° $id est maintenant occupée.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erreur = 'Impossible d\'occuper la place n° $id : $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          placeEnCours = null;
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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.local_parking,
              size: 60,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nombre de places libres',
              style: TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              '$nombrePlacesLibres',
              style: const TextStyle(
                fontSize: 50,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: chargement || placeEnCours != null
                  ? null
                  : chargerPlacesLibres,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
            if (erreur != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  erreur!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            const Divider(height: 30),
            const Text(
              'Liste des places libres',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: chargement
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : placesLibres.isEmpty
                      ? const Center(
                          child: Text('Aucune place libre'),
                        )
                      : ListView.builder(
                          itemCount: placesLibres.length,
                          itemBuilder: (context, index) {
                            final place =
                                placesLibres[index] as List<dynamic>;

                            final id = place[0] as int;
                            final type = place[3] == 'moto'
                                ? 'Moto'
                                : 'Voiture';

                            final pmr = place[5] == 1;
                            final electrique = place[6] == 1;

                            final details = [
                              type,
                              if (pmr) 'PMR',
                              if (electrique) 'Électrique',
                            ].join(' • ');

                            return Card(
                              child: ListTile(
                                leading: const Icon(
                                  Icons.local_parking,
                                  color: Colors.blue,
                                ),
                                title: Text('Place n° $id'),
                                subtitle: Text(details),
                                trailing: ElevatedButton(
                                  onPressed: chargement ||
                                          placeEnCours != null
                                      ? null
                                      : () => occuperPlace(id),
                                  child: placeEnCours == id
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Occuper'),
                                ),
                              ),
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
