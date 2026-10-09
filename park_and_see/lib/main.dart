
import 'package:flutter/material.dart';

void main() {
  runApp(const ParkAndSeeApp());
}

// =====================================================
// APPLICATION
// =====================================================

class ParkAndSeeApp extends StatelessWidget {
  const ParkAndSeeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Park & See',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// =====================================================
// MODELES
// =====================================================

class Parking {
  final String name;
  final String address;
  final int totalSpaces;
  int availableSpaces;

  Parking({
    required this.name,
    required this.address,
    required this.totalSpaces,
    required this.availableSpaces,
  });
}

class ParkingSession {
  final Parking parking;
  final String licensePlate;
  final String vehicleType;
  final DateTime startTime;

  ParkingSession({
    required this.parking,
    required this.licensePlate,
    required this.vehicleType,
    required this.startTime,
  });
}

// =====================================================
// DONNEES DE TEST
// =====================================================

final List<Parking> parkings = [
  Parking(
    name: 'Parking de la Mairie',
    address: 'Place de la Mairie',
    totalSpaces: 80,
    availableSpaces: 12,
  ),
  Parking(
    name: 'Parking de la Gare',
    address: 'Avenue de la Gare',
    totalSpaces: 60,
    availableSpaces: 5,
  ),
  Parking(
    name: 'Parking du Centre',
    address: 'Rue du Centre',
    totalSpaces: 45,
    availableSpaces: 0,
  ),
  Parking(
    name: 'Parking du Marché',
    address: 'Place du Marché',
    totalSpaces: 50,
    availableSpaces: 18,
  ),
];

// Stationnement actif de l'utilisateur.
// Les données restent en mémoire pendant l'exécution.
ParkingSession? currentSession;

// =====================================================
// PAGE D'ACCUEIL
// =====================================================

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Widget homeButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Widget page,
  }) {
    return SizedBox(
      height: 55,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => page,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Park & See'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 25),
            const Icon(
              Icons.local_parking,
              size: 90,
              color: Colors.green,
            ),
            const SizedBox(height: 20),
            const Text(
              'Bienvenue sur Park & See',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Trouvez une place et gérez votre stationnement '
              'en toute simplicité.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 35),
            homeButton(
              context: context,
              icon: Icons.search,
              label: 'Trouver une place',
              page: const ParkingSearchPage(),
            ),
            const SizedBox(height: 15),
            homeButton(
              context: context,
              icon: Icons.directions_car,
              label: 'Mon stationnement',
              page: const MyParkingPage(),
            ),
            const SizedBox(height: 15),
            homeButton(
              context: context,
              icon: Icons.admin_panel_settings,
              label: 'Espace agent',
              page: const AgentPage(),
            ),
            const SizedBox(height: 30),
            const Text(
              'Park & See — Le stationnement simplifié',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// PAGE : RECHERCHE DES PARKINGS
// =====================================================

class ParkingSearchPage extends StatefulWidget {
  const ParkingSearchPage({super.key});

  @override
  State<ParkingSearchPage> createState() =>
      _ParkingSearchPageState();
}

class _ParkingSearchPageState extends State<ParkingSearchPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trouver une place'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: parkings.length,
        itemBuilder: (context, index) {
          final parking = parkings[index];
          final isAvailable = parking.availableSpaces > 0;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.local_parking,
                        size: 38,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          parking.name,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(parking.address),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: parking.totalSpaces == 0
                        ? 0
                        : parking.availableSpaces /
                            parking.totalSpaces,
                    backgroundColor: Colors.grey.shade300,
                    color: isAvailable
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${parking.availableSpaces} places disponibles '
                    'sur ${parking.totalSpaces}',
                    style: TextStyle(
                      color: isAvailable
                          ? Colors.green.shade800
                          : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isAvailable
                          ? () async {
                              final result =
                                  await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ParkingConfirmationPage(
                                    parking: parking,
                                  ),
                                ),
                              );

                              if (result == true && mounted) {
                                setState(() {});
                              }
                            }
                          : null,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(
                        isAvailable
                            ? 'Sélectionner ce parking'
                            : 'Parking complet',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =====================================================
// PAGE : CONFIRMATION DU STATIONNEMENT
// =====================================================

class ParkingConfirmationPage extends StatefulWidget {
  final Parking parking;

  const ParkingConfirmationPage({
    super.key,
    required this.parking,
  });

  @override
  State<ParkingConfirmationPage> createState() =>
      _ParkingConfirmationPageState();
}

class _ParkingConfirmationPageState
    extends State<ParkingConfirmationPage> {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();

  String _vehicleType = 'Voiture';

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  void _confirmParking() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (currentSession != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Terminez votre stationnement actuel avant d’en commencer un autre.',
          ),
        ),
      );
      return;
    }

    if (widget.parking.availableSpaces <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ce parking est désormais complet.'),
        ),
      );
      return;
    }

    setState(() {
      widget.parking.availableSpaces--;
    });

    currentSession = ParkingSession(
      parking: widget.parking,
      licensePlate:
          _plateController.text.trim().toUpperCase(),
      vehicleType: _vehicleType,
      startTime: DateTime.now(),
    );

    Navigator.pop(context, true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MyParkingPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmer le stationnement'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.local_parking,
                size: 65,
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              Text(
                widget.parking.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.parking.address,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.parking.availableSpaces} places encore disponibles',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              TextFormField(
                controller: _plateController,
                textCapitalization:
                    TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Plaque d’immatriculation',
                  hintText: 'AB-123-CD',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.directions_car),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Veuillez saisir votre plaque.';
                  }
                  if (value.trim().length < 5) {
                    return 'La plaque semble trop courte.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _vehicleType,
                decoration: const InputDecoration(
                  labelText: 'Type de véhicule',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.commute),
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
                  DropdownMenuItem(
                    value: 'Utilitaire',
                    child: Text('Utilitaire'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _vehicleType = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _confirmParking,
                icon: const Icon(Icons.check),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Confirmer le stationnement'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================
// PAGE : MON STATIONNEMENT
// =====================================================

class MyParkingPage extends StatefulWidget {
  const MyParkingPage({super.key});

  @override
  State<MyParkingPage> createState() => _MyParkingPageState();
}

class _MyParkingPageState extends State<MyParkingPage> {
  String formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _finishParking() {
    final session = currentSession;

    if (session == null) return;

    setState(() {
      if (session.parking.availableSpaces <
          session.parking.totalSpaces) {
        session.parking.availableSpaces++;
      }
      currentSession = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stationnement terminé.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = currentSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon stationnement'),
      ),
      body: session == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.directions_car,
                      size: 75,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Aucun stationnement en cours',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Recherchez un parking et confirmez '
                      'votre stationnement pour le voir ici.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const ParkingSearchPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.search),
                      label: const Text('Chercher un parking'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 70,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Stationnement confirmé',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.parking.name,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.location_on),
                          title: const Text('Adresse'),
                          subtitle: Text(session.parking.address),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.pin),
                          title: const Text('Immatriculation'),
                          subtitle: Text(session.licensePlate),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.directions_car),
                          title: const Text('Véhicule'),
                          subtitle: Text(session.vehicleType),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.access_time),
                          title: const Text('Heure de début'),
                          subtitle: Text(
                            formatTime(session.startTime),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  onPressed: _finishParking,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Terminer le stationnement'),
                  ),
                ),
              ],
            ),
    );
  }
}

// =====================================================
// PAGE : ESPACE AGENT
// =====================================================

class AgentPage extends StatelessWidget {
  const AgentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final totalSpaces = parkings.fold<int>(
      0,
      (sum, parking) => sum + parking.totalSpaces,
    );

    final availableSpaces = parkings.fold<int>(
      0,
      (sum, parking) => sum + parking.availableSpaces,
    );

    final occupiedSpaces = totalSpaces - availableSpaces;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace agent'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Tableau de bord',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Vue d’ensemble des parkings suivis.',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Parkings',
                  value: '${parkings.length}',
                  icon: Icons.local_parking,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Places totales',
                  value: '$totalSpaces',
                  icon: Icons.grid_view,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Disponibles',
                  value: '$availableSpaces',
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Occupées',
                  value: '$occupiedSpaces',
                  icon: Icons.directions_car,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'État des parkings',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...parkings.map((parking) {
            final available = parking.availableSpaces > 0;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(
                  available ? Icons.check_circle : Icons.cancel,
                  color: available ? Colors.green : Colors.red,
                ),
                title: Text(parking.name),
                subtitle: Text(
                  '${parking.address}\n'
                  '${parking.availableSpaces} places libres '
                  'sur ${parking.totalSpaces}',
                ),
                isThreeLine: true,
                trailing: Text(
                  '${((parking.totalSpaces -
                                  parking.availableSpaces) /
                              parking.totalSpaces *
                              100)
                          .round()} %',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          const Text(
            'Les données affichées sont fictives et servent '
            'uniquement à tester l’interface.',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// CARTE DE STATISTIQUE POUR L'AGENT
// =====================================================

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              icon,
              size: 30,
              color: Colors.green,
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}