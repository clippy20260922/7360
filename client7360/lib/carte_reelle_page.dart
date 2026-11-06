import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'paiement_page.dart';
import 'parking_map_page.dart' show ParkingService;

/// Une place du serveur, telle que renvoyée par GET /data/carte.
class PlaceCarte {
  const PlaceCarte({
    required this.id,
    required this.position,
    required this.type,
    this.pmr = false,
    this.elec = false,
    this.adresse,
    this.ville,
    this.parking,
    this.tarif,
    this.occupee = false,
  });

  final int id;
  final LatLng position;
  final String type; // voit, moto, cami
  final bool pmr, elec, occupee;
  final String? adresse, ville, parking;
  final double? tarif;

  /// null si la place n'a pas de coordonnées GPS valides.
  static PlaceCarte? depuisJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final long = (j['long'] as num?)?.toDouble();
    if (lat == null || long == null || lat.abs() > 90 || long.abs() > 180) {
      return null;
    }
    return PlaceCarte(
      id: (j['id'] as num).toInt(),
      position: LatLng(lat, long),
      type: (j['type'] as String?) ?? 'voit',
      pmr: j['pmr'] == true,
      elec: j['elec'] == true,
      adresse: j['adresse'] as String?,
      ville: j['ville'] as String?,
      parking: j['parking'] as String?,
      tarif: (j['tarif'] as num?)?.toDouble(),
      occupee: j['occupee'] == true,
    );
  }

  String get typeLisible => switch (type) {
        'moto' => 'Moto',
        'cami' => 'Camion',
        _ => 'Voiture',
      };
}

/// Vraie carte OpenStreetMap (SCRUM-52) avec les places du serveur.
/// Vert = libre, rouge = occupée. Toucher une place affiche sa fiche,
/// d'où l'on peut la payer.
class CarteReellePage extends StatefulWidget {
  const CarteReellePage({super.key});

  /// ESIEE Paris (Noisy-le-Grand / Champs-sur-Marne) : centre de départ
  static const LatLng esiee = LatLng(48.8390, 2.5853);

  @override
  State<CarteReellePage> createState() => _CarteReellePageState();
}

class _CarteReellePageState extends State<CarteReellePage> {
  final MapController _carte = MapController();

  List<PlaceCarte> _places = [];
  bool _chargement = true;
  String? _erreur;
  double _zoom = 15; // la taille des marqueurs suit le zoom

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final reponse = await http
          .get(Uri.parse('${ParkingService.baseUrl}/data/carte'))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (reponse.statusCode != 200) {
        setState(() => _erreur = 'Erreur serveur (${reponse.statusCode})');
        return;
      }
      final data = jsonDecode(utf8.decode(reponse.bodyBytes)) as Map<String, dynamic>;
      final places = [
        for (final p in (data['data'] as List<dynamic>? ?? []))
          if (p is Map<String, dynamic>) PlaceCarte.depuisJson(p),
      ].whereType<PlaceCarte>().toList();
      setState(() => _places = places);
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Serveur injoignable');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _voirToutesLesPlaces() {
    // On cadre les places autour du campus (à moins de 30 km de l'ESIEE) :
    // les places de démo ont des coordonnées fictives, loin de tout.
    const distance = Distance();
    final proches = _places
        .where((p) => distance.as(LengthUnit.Kilometer, p.position, CarteReellePage.esiee) < 30)
        .toList();
    final cadre = proches.isEmpty ? _places : proches;
    if (cadre.isEmpty) return;
    if (cadre.length == 1) {
      _carte.move(cadre.first.position, 17);
      return;
    }
    _carte.fitCamera(CameraFit.coordinates(
      coordinates: [for (final p in cadre) p.position],
      padding: const EdgeInsets.all(48),
      maxZoom: 18,
    ));
  }

  void _ouvrirFiche(PlaceCarte place) {
    showModalBottomSheet<void>(
      context: context,
      builder: (contexteFiche) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Place n°${place.id}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (place.adresse != null || place.ville != null)
                Text([place.adresse, place.ville].whereType<String>().join(', ')),
              if (place.parking != null) Text('Parking : ${place.parking}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(place.occupee ? Icons.block : Icons.check_circle,
                        color: place.occupee ? Colors.red : Colors.green),
                    label: Text(place.occupee ? 'Occupée' : 'Libre'),
                  ),
                  Chip(label: Text(place.typeLisible)),
                  if (place.pmr) const Chip(avatar: Icon(Icons.accessible), label: Text('PMR')),
                  if (place.elec) const Chip(avatar: Icon(Icons.bolt), label: Text('Électrique')),
                  if (place.tarif != null)
                    Chip(label: Text('${place.tarif!.toStringAsFixed(2).replaceAll('.', ',')} € / h')),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.euro),
                  label: const Text('Payer cette place'),
                  onPressed: () {
                    Navigator.pop(contexteFiche);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PaiementPage(idPlace: place.id)),
                    ).then((_) => _charger()); // la place a pu passer occupée
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _marqueur(PlaceCarte place) {
    final couleur = place.occupee ? Colors.red.shade600 : Colors.green.shade600;
    // Les places sont à 2,5 m les unes des autres : de loin, de simples points
    final taille = _zoom >= 18.5
        ? 30.0
        : _zoom >= 17.5
            ? 20.0
            : _zoom >= 16.5
                ? 12.0
                : 7.0;
    final pastille = Container(
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: taille >= 20 ? 2 : 1),
        boxShadow: taille >= 20 ? const [BoxShadow(blurRadius: 3, color: Colors.black38)] : null,
      ),
      child: taille >= 20
          ? Icon(place.type == 'moto' ? Icons.two_wheeler : Icons.local_parking,
              color: Colors.white, size: taille * 0.6)
          : null,
    );
    return Marker(
      point: place.position,
      width: taille,
      height: taille,
      child: GestureDetector(
        onTap: () => _ouvrirFiche(place),
        child: taille >= 20 ? Tooltip(message: 'Place n°${place.id}', child: pastille) : pastille,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libres = _places.where((p) => !p.occupee).length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Carte des places'),
        actions: [
          IconButton(
            icon: const Icon(Icons.school),
            tooltip: "Recentrer sur l'ESIEE",
            onPressed: () => _carte.move(CarteReellePage.esiee, 15),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out_map),
            tooltip: 'Voir toutes les places',
            onPressed: _places.isEmpty ? null : _voirToutesLesPlaces,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _chargement ? null : _charger,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _carte,
            options: MapOptions(
              initialCenter: CarteReellePage.esiee,
              initialZoom: 15,
              minZoom: 3,
              maxZoom: 20,
              onPositionChanged: (camera, _) {
                if ((camera.zoom - _zoom).abs() >= 0.25) setState(() => _zoom = camera.zoom);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.client7360',
              ),
              MarkerLayer(markers: [for (final p in _places) _marqueur(p)]),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
          ),
          // Bandeau d'état en haut de la carte
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Center(
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(20),
                color: _erreur != null ? Colors.red.shade50 : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: _chargement
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_erreur ??
                          '${_places.length} place(s) sur la carte, dont $libres libre(s)'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
