
import 'package:flutter/material.dart';

class InformationsVehiculePage extends StatefulWidget {
  const InformationsVehiculePage({
    super.key,
    required this.placeId,
    required this.typePlace,
  });

  final String placeId;
  final String typePlace;

  @override
  State<InformationsVehiculePage> createState() =>
      _InformationsVehiculePageState();
}

class _InformationsVehiculePageState
    extends State<InformationsVehiculePage> {
  final _formKey = GlobalKey<FormState>();
  final _plaqueController = TextEditingController();

  String _typeVehicule = 'Voiture';

  @override
  void initState() {
    super.initState();

    if (widget.typePlace == 'Moto') {
      _typeVehicule = 'Moto';
    }
  }

  @override
  void dispose() {
    _plaqueController.dispose();
    super.dispose();
  }

  void _valider() {
    if (!_formKey.currentState!.validate()) return;

    // Pour l'instant, on renvoie les informations
    // à la page précédente, sans appeler le backend.
    Navigator.pop(context, {
      'placeId': widget.placeId,
      'typeVehicule': _typeVehicule,
      'plaque': _plaqueController.text.trim().toUpperCase(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informations du véhicule'),
        backgroundColor:
            Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Place sélectionnée : ${widget.placeId}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),

              Text('Type de place : ${widget.typePlace}'),

              const SizedBox(height: 24),

              const Text(
                'Type de véhicule',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _typeVehicule,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Choisir un véhicule',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Voiture',
                    child: Text('Voiture'),
                  ),
                  DropdownMenuItem(
                    value: 'Moto',
                    child: Text('Moto'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _typeVehicule = value);
                  }
                },
                validator: (value) {
                  if (value == null) {
                    return 'Veuillez choisir un type de véhicule';
                  }
                  if (value != widget.typePlace) {
                    return 'Ce véhicule ne correspond pas au type de place';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              const Text(
                "Plaque d'immatriculation",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _plaqueController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Immatriculation',
                  hintText: 'AA-123-AA',
                  prefixIcon: Icon(Icons.directions_car),
                ),
                validator: (value) {
                  final plaque = value?.trim() ?? '';

                  if (plaque.isEmpty) {
                    return "Veuillez saisir une plaque d'immatriculation";
                  }

                  if (plaque.length < 4) {
                    return 'Plaque trop courte';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 32),

              FilledButton.icon(
                onPressed: _valider,
                icon: const Icon(Icons.check),
                label: const Text('Confirmer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
