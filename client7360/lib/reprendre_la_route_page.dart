import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'parking_map_page.dart' show ParkingService;
import 'reservations_locales.dart';

class ReprendreLaRoutePage extends StatefulWidget {
  const ReprendreLaRoutePage({super.key});

  @override
  State<ReprendreLaRoutePage> createState() =>
      _ReprendreLaRoutePageState();
}

class _ReprendreLaRoutePageState extends State<ReprendreLaRoutePage> {
  final TextEditingController _plaqueController = TextEditingController();

  @override
  void dispose() {
    _plaqueController.dispose();
    super.dispose();
  }

  /// PATCH /data/{id}/set_occupation : la place redevient libre sur le serveur.
  /// Renvoie null si c'est fait, sinon le message d'erreur.
  Future<String?> _libererSurLeServeur(String plaque, String placeId) async {
    final url = Uri.parse('${ParkingService.baseUrl}/data/$placeId/set_occupation')
        .replace(queryParameters: {'set_bool': 'false', 'vehicule': plaque});
    try {
      final res = await ParkingService.envoyer(
          (entetes) => http.patch(url, headers: entetes));
      if (res.statusCode == 200) return null;
      try {
        final detail = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['detail'];
        if (detail is String) return detail;
      } catch (_) {}
      return 'erreur ${res.statusCode}';
    } catch (_) {
      return 'serveur injoignable';
    }
  }

  void _rechercherReservation() {
    final plaque = _plaqueController.text.trim().toUpperCase();

    if (plaque.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Veuillez saisir votre plaque d\'immatriculation'),
        ),
        );
        return;
    }

    final placeId = ReservationsLocales.rechercher(plaque);

    if (placeId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Aucune réservation trouvée pour cette plaque'),
        ),
        );
        return;
    }

    showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
        title: const Text('Réservation trouvée'),
        content: Text(
            'Plaque : $plaque\n'
            'Place n°$placeId\n\n'
            'Souhaitez-vous confirmer votre départ ?',
        ),
        actions: [
            TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
            ),
            FilledButton(
            onPressed: () async {
                Navigator.pop(dialogContext);

                // Place payée sur le serveur : on la libère d'abord là-bas
                if (ReservationsLocales.estSurLeServeur(plaque)) {
                  final erreur = await _libererSurLeServeur(plaque, placeId);
                  if (!mounted) return;
                  if (erreur != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Départ non enregistré : $erreur')),
                    );
                    return;
                  }
                }

                ReservationsLocales.liberer(plaque);
                ReservationsLocales.marquerPlaceLiberee(placeId);

                ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                    'Départ confirmé pour la place n°$placeId',
                    ),
                ),
                );
            },
            child: const Text('Confirmer mon départ'),
            ),
        ],
        ),
    );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reprendre la route'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.directions_car, size: 72),
            const SizedBox(height: 24),
            const Text(
              'Retrouver ma place',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Saisissez la plaque d\'immatriculation utilisée '
              'lors de votre réservation.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _plaqueController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Plaque d\'immatriculation',
                hintText: 'AA-123-AA',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.confirmation_number),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _rechercherReservation,
              icon: const Icon(Icons.search),
              label: const Text('Rechercher ma réservation'),
            ),
          ],
        ),
      ),
    );
  }
}