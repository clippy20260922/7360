# 7360

## Server

Le serveur (FastAPI + SQLite) crée ses bases et les remplit avec des données de départ au premier lancement.

### Option 1 : directement sur le PC (Python 3.12 conseillé)

```bash
cd server7360
python3 -m venv .venv
source .venv/bin/activate          # Windows (PowerShell) : .venv\Scripts\Activate.ps1
pip install -r requirements.txt
DATA_DIR=./data uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

(PowerShell : `$env:DATA_DIR="./data"; uvicorn main:app --host 0.0.0.0 --port 8000 --reload`)

`DATA_DIR` est le dossier des bases de données (`/data` par défaut, pratique pour le conteneur). Pour repartir de zéro, il suffit de supprimer ce dossier. La documentation interactive de l'API est sur http://127.0.0.1:8000/docs.

### Option 2 : conteneur

```bash
podman build -t image-monserveur ./server7360
```

```bash
podman run --detach --publish 8000:8000 --volume monserveur-data:/data --name container-monserveur image-monserveur
```

Le volume `monserveur-data` garde les bases (contraventions comprises) quand le conteneur est supprimé.

### Comptes de départ

| Identifiant | Mot de passe | Type |
|---|---|---|
| `OSS117` | `Lablanquette117` | agent |
| `ab123456` | `Mon_mdp123` | usager |
| `cd789` | `autre_MDP666` | usager (véhicule électrique) |
| `ef321` | `Mdp_Chloe_321` | usager |
| `gh654` | `Mdp_Hugo_654` | usager (carte mobilité inclusion) |

Un compte `agent` ouvre l'espace agent, un compte `user` ouvre l'espace usager.


# client7360

Client Flutter du projet 7360.

## Nouveauté de cette version : plan du parking en 3D

Cette version ajoute un **composant réutilisable** qui affiche un plan de parking en vue 3D (routes, bâtiments, places, voitures) et qui permet de le manipuler et de sélectionner une place.

### Ce que ça apporte

- **Plan 3D dessiné à la main** (`CustomPainter`, sans package supplémentaire) : routes, bâtiments extrudés, places colorées selon leur état et voitures sur les places occupées.
- **Interaction au doigt / à la souris (pas encore 100% fonctionnel)** :
  - pincement : zoom (limité entre 3 et 40 px/m) ;
  - glisser : déplacement de la carte ;
  - rotation à deux doigts : rotation de la carte ;
  - tap sur une place : sélection.
- **États des places** : libre (vert), occupée (rouge), réservée (orange).
- **Carte de sélection** : au tap sur une place, un encart affiche son identifiant et son état, avec un bouton « Réserver » si elle est libre.
- **Vue réinitialisable** depuis l'extérieur via un contrôleur.

### Fichiers ajoutés

| Fichier | Rôle |
|---|---|
| `lib/parking_map_view.dart` | Le composant `ParkingMapView` et tout ce dont il dépend : modèles (`ParkingSpot`, `Road`, `Building`), caméra 3D (`MapCamera`), peinture (`ParkingPainter`), contrôleur (`ParkingMapController`) et données de démo (`ParkingDemoData`). |
| `lib/parking_map_page.dart` | Page qui affiche le composant dans un rectangle centré, avec un bouton « réinitialiser la vue » dans l'`AppBar`. |

Fichier existant modifié : `lib/main.dart` (import de la page + bouton « Plan du parking » sous les boutons GET/POST). Le reste du projet est inchangé.

### Utiliser le composant

```dart
final controller = ParkingMapController();

ParkingMapView(
  controller: controller,
  initialTilt: 0.9,                 // 0 = vue du dessus, ~1.2 = très inclinée
  spots: spots,                     // List<ParkingSpot>
  roads: ParkingDemoData.roads,     // List<Road>
  buildings: ParkingDemoData.buildings, // List<Building>
  onSpotSelected: (spot) {},        // null si on tape dans le vide
  onReserve: (spot) {},             // si absent, la place passe en "reserved" en local
);

controller.resetView(); // remet zoom, rotation, position et inclinaison par défaut
```

| Paramètre | Description |
|---|---|
| `spots` (obligatoire) | Places à afficher. |
| `roads`, `buildings` | Routes et bâtiments (vides par défaut). |
| `controller` | Permet de réinitialiser la vue depuis le parent. |
| `initialTilt` | Inclinaison de la caméra au départ (0.9 par défaut). |
| `showSelectionCard` | Affiche ou masque la carte de sélection (`true` par défaut). |
| `onSpotSelected` | Appelé à chaque sélection. |
| `onReserve` | Appelé au clic sur « Réserver ». |

Le composant prend toute la place que son parent lui donne : pour le redimensionner, il suffit de l'envelopper dans un `SizedBox`, un `FractionallySizedBox`, etc.

> Pour l'instant, la page utilise les données de démo (`ParkingDemoData`). Le plan n'est pas encore relié au serveur.

## Lancer le client

Prérequis : [Flutter installé](https://docs.flutter.dev/install/manual) (SDK Dart `^3.13.4`, voir `pubspec.yaml`) et un appareil, un émulateur ou un navigateur disponible (`flutter devices`).

```bash
cd client7360/
```

```bash
flutter pub get
```

```bash
flutter run
```

Depuis la page d'accueil, appuyez sur **« Plan du parking »** pour ouvrir la carte.

### Autres étapes d'initialisation

- **Aucune** dépendance ajoutée : `pubspec.yaml` est inchangé (seul `http` est utilisé, comme avant).
- Les dossiers de plateforme (`android/`, `ios/`, `web/`, etc.) sont déjà présents : pas besoin de `flutter create .`.
- En cas de problème d'environnement, `flutter doctor` indique ce qu'il manque.
- Le **serveur n'est pas nécessaire** pour afficher le plan. Il ne sert que pour la page GET/POST de l'accueil ; pour le lancer, voir le `README.md` à la racine du dépôt (build et run avec `podman`).

## Tests

```bash
flutter test
```

## Espace agent

Il n'y a qu'une page de connexion (`POST /token`) : un compte de type `agent` ouvre l'espace agent, un compte de type `user` ouvre l'espace usager, des identifiants inconnus affichent une erreur. L'espace agent a quatre onglets, tous alimentés par le serveur :

| Onglet | Route(s) utilisée(s) |
|---|---|
| Carte (clic sur une place : place, véhicule, conformité, bouton « Dresser une contravention ») | `GET /parking`, `GET /agent/slots` |
| Infractions (clic sur une carte : bouton « Dresser une contravention ») | `GET /agent/slots` |
| Stats | `GET /agent/slots` |
| Amendes | `GET /agent/fines`, `GET /agent/infractions`, `POST /agent/fines` |

Le client rafraîchit ses données toutes les 8 secondes.

### Lancer serveur + client

1. Démarrer le serveur (voir plus haut) et vérifier que http://127.0.0.1:8000 répond.
2. Dans un autre terminal :

```bash
cd client7360
flutter pub get
flutter run                    # puis choisir l'appareil (windows, chrome, émulateur…)
```

L'adresse du serveur est choisie automatiquement : `http://127.0.0.1:8000` (Windows, navigateur…) ou `http://10.0.2.2:8000` (émulateur Android). Pour un téléphone réel ou un autre PC :

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:8000
```

(adresse IP du PC qui fait tourner le serveur ; le pare-feu doit autoriser le port 8000).

## Espace usager

Quatre onglets, même style que l'espace agent, tous alimentés par le serveur (routes `/me/...`, réservées aux comptes `user`) :

| Onglet | Contenu | Route(s) |
|---|---|---|
| Carte | Plan interactif. Place libre : bouton « Réserver ». Place occupée ou réservée : infos de la place seulement (jamais le véhicule). Parking : places libres par catégorie (voiture, PMR, électrique, moto) et réservation d'une catégorie | `GET /parking`, `GET /me/slots`, `GET /me/parkings` |
| Réservations | En cours / à venir / historique ; « Je suis arrivé(e) », « Reprendre la route », « Annuler » ; véhicules garés sans réservation | `GET /me/reservations`, `POST /me/reservations`, `.../{id}/checkin`, `.../{id}/checkout`, `.../{id}/cancel`, `POST /me/vehicles/{plaque}/leave` |
| Amendes | Contraventions reçues sur ses véhicules, paiement (simulé) | `GET /me/fines`, `POST /me/fines/{n}/pay` |
| Profil | Nom, prénom, plaque, type de véhicule, électrique, carte mobilité inclusion, notifications | `GET` / `PUT /me/profile` |

Sur la carte, une place libre ou réservée a aussi un bouton **« Signaler comme prise »** (voir plus bas), et les signalements envoyés avec la réponse de l'agent sont listés en haut de l'onglet Réservations (`POST` / `GET /me/reports`).

Réserver : la feuille de réservation est préremplie avec le profil, on choisit le début (maintenant, dans 30 min, 1 h, 2 h ou une heure précise) et la durée, le montant (`tarif × durée`) est affiché avant de valider. Pour un parking, le serveur choisit une place libre de la catégorie demandée. Une place PMR demande la carte mobilité inclusion dans le profil, une place avec borne un véhicule électrique.

Cycle d'une réservation : *réservée* → (« Je suis arrivé(e) ») *garé* : la place devient occupée et payée jusqu'à la fin de la réservation, ce que voit l'agent → (« Reprendre la route ») *terminée*. Si l'usager dépasse l'heure de fin, le véhicule apparaît en infraction chez l'agent.

Les rappels (début de réservation, fin de stationnement, nouvelle contravention) s'affichent dans l'application, selon les réglages du profil.

## Signalements et assignation de places

1. **L'usager signale** une place qui semble libre mais où un véhicule est garé (bouton « Signaler comme prise » sur la carte). La plaque est facultative ; l'heure du signalement est enregistrée par le serveur.
2. **L'agent est prévenu** : un badge sur la cloche en haut de son écran, et un message avec un bouton « Voir ». La page *Signalements* montre la place, l'heure, le signalant et la plaque. Si la plaque est enregistrée, le propriétaire s'affiche ; sinon l'agent saisit une plaque et la recherche (`🔍`) pour retrouver la personne.
3. **Valider** : la place est assignée au véhicule **depuis l'heure du signalement**, sans paiement : elle devient occupée et le véhicule apparaît en infraction (« sans paiement depuis 14:05 »), et l'agent peut dresser la contravention (le commentaire est prérempli). **Rejeter** laisse la place libre. L'usager voit la réponse dans son onglet Réservations.
4. **Assigner directement** : sur la carte, la fiche d'une place libre a un bouton « Assigner à un véhicule » (plaque + recherche du propriétaire). La place est assignée à partir de maintenant, sans paiement.

Une plaque inconnue est acceptée : le véhicule est enregistré sans propriétaire (`proprietaire = 'inconnu'`). Un véhicule déjà garé ailleurs ne peut pas être assigné.
