import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'parking_map_view.dart';

/// Page qui affiche le plan du parking dans un rectangle centré.
class ParkingMapPage extends StatefulWidget {
  const ParkingMapPage({super.key});

  @override
  State<ParkingMapPage> createState() => _ParkingMapPageState();
}

class _ParkingMapPageState extends State<ParkingMapPage> {
  final ParkingMapController _controller = ParkingMapController();
  late final List<ParkingSpot> _spots = ParkingDemoData.spots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Plan du parking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Réinitialiser la vue',
            onPressed: _controller.resetView,
          ),
        ],
      ),
      body: Center(
        child: FractionallySizedBox(
          widthFactor: 0.9,   // 90 % de la largeur
          heightFactor: 0.8,  // 80 % de la hauteur disponible
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black26, width: 2),
            ),
            child: ParkingMapView(
              controller: _controller,
              initialTilt: 0,
              spots: _spots,
              roads: ParkingDemoData.roads,
              buildings: ParkingDemoData.buildings,
            ),
          ),
        ),
      ),
    );
  }
}
