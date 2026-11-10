# Documentation du backend 

## Objets

### Les classes

Classe User :
* username (string) : le pseudo d'utilisation (unique)
* type (string) : type d'utilisateur ("user" ou "agent") pour définir les droits
* vehicule (liste de string) : liste des véhicules enregistrés par l'utilisateur via leur plaque d'immatriculation

Les utilisateur "user" sont le type "par défaut", ils peuvent voir les informations des places et de leurs véhicule
Les utilisateur "agent" sont ceux avec des autorisations supérieures : 
* ils peuvent modifier l'occupation de n'importe quelle place
* ils peuvent obtenir des informations sur des véhicules garés (type de véhicule, temps de stationnement...)

Le backend conserve l'utilisateur enregistré dans une variable globale

### Les databases

#### slot_table
Tableau des places de parking

| Colonne | Type | Définition | Obligatoire | Caractéristiques |
|-----|------|-----|-----|-----|
| slot_id | int | Identifiant de la place | Oui | Clé primaire, auto-incrémentation |
| slot_lat | float | Latitude de la place | Oui | |
| slot_long | float | Longitude de la place | Oui | |
| slot_type | char[4] | Type de la place : voit, moto, cami | Oui | |
| slot_occupied | bool | Occupation de la place : true=occupé et false=libre | Oui | |
| slot_pmr | bool | Place PMR | Non | |
| slot_elec | bool | Place avec borne électrique | Non | |
| parking | char[20] | Parking où se situe la place | Non | |
| parking_protege | bool | Place dans un parking protégé: true=protégé et false=à ciel ouvert | Non | |
| fin_occupation | timestamp | Heure prévue de fin d'occupation de la place (pour les places libres, le timestamp est "1900-01-01 00:00:00')| Oui | Forme du time stamp : yyyy-mm-dd hh:mm:ss|

#### vehicle_table
Tableau des véhicules enregistrés

| Colonne | Type | Définition | Obligatoire | Caractéristiques |
|-----|------|-----|-----|-----|
| no_plaque | char[9] | Plaque du véhicule | Oui | Clé primaire, 9 caractères pour correspondre au maximum des plaques françaises|
| propietaire | char[30] | Identifiant du propriétaire | Oui | TODO: permettre plusieurs propriétaires|
| type_vehicule | float | Type du véhicule : "voit", "moto" ou "cami" | Oui | |
| elec | bool | Véhicule électrique | Non | |

Colonnes ajoutées pour la carte : `slot_x`, `slot_y` (position sur le plan en mètres) et `slot_angle` (orientation, 0 par défaut). Si `slot_x`/`slot_y` sont vides, le serveur les déduit de la latitude/longitude.

Colonnes de `vehicle_table` : `current_slot` (place où le véhicule est garé en ce moment, vide sinon).

#### parking_table
Parkings (grandes zones affichées en bleu sur la carte) : `parking_name` (clé primaire), `parking_adresse`, `parking_lat`, `parking_long`, `parking_x`, `parking_y` (position sur le plan en mètres). Un parking est « complet » quand toutes ses places (`slot_table.parking`) sont occupées.

#### offense_table
Infractions proposées à l'agent, avec leur montant forfaitaire.

| Colonne | Type | Définition |
|-----|------|-----|
| code | char[20] | Clé primaire : `overtime`, `unpaid`, `nuisance`, `abusive`, `veryNuisance`, `pmr` |
| label | char[60] | Libellé affiché |
| amount | float | Montant forfaitaire en euros (le FPS est fixé par la commune : à adapter) |
| legal | char[60] | Nature (FPS, contravention de 2e ou 4e classe) |
| majorated | float | Montant majoré (vide pour le FPS) |

#### fine_table
Contraventions dressées par les agents.

| Colonne | Type | Définition |
|-----|------|-----|
| fine_no | int | Clé primaire, auto-incrémentation. Le numéro affiché est `PV-<année>-<fine_no sur 5 chiffres>` |
| no_plaque | char[9] | Plaque du véhicule |
| type_vehicule | char[4] | `voit`, `moto`... |
| slot_id | int | Place concernée |
| lieu | char[100] | Adresse de la place |
| agent | char[30] | Identifiant de l'agent qui a dressé la contravention |
| offense | char[20] | Code de l'infraction (`offense_table`) |
| amount | float | Montant au moment de la contravention |
| commentaire | char[300] | Observations (facultatif) |
| date_emission | timestamp | UTC, `yyyy-mm-dd hh:mm:ss` |

#### plan_road_table, plan_building_table, plan_zone_table
Dessin de la carte, en mètres : routes (`ax, ay, bx, by, width, road_name`), bâtiments (`footprint` en JSON `[{"x":..,"y":..}]`, `height`, `color` ARGB) et zones (`kind` = `park` ou `water`, `polygon` en JSON).

#### user_table
Tableau des utilisateurs enregistrés 

| Colonne | Type | Définition | Obligatoire | Caractéristiques |
|-----|------|-----|-----|-----|
| username | char[30] | Pseudo de l'utilisateur | Oui |Clé primaire |
| password | char[100] | Mot de passe haché de l'utilisateur | Oui | |
| type | char[5] | Type d'utilisateur : "user" ou "agent" | Oui | Détermine les permissions|

## Les pages
La structure du backend. Les pages en italiques n'ont pas de réponse visible et servent à traiter des données

 |   
+- token : login de l'utilisateur (TODO: faire ça proprement et coordonner avec le front-end)   
 |   
+- data : toutes les places   
     |   
    +- id_de_place : information sur la place id_de_place   
         |   
        +- *set_occupation* : modifie l'occupation (fonctionnement selon le type d'utilisateur)   
     |   
    +- free : toutes les places libres      
         |   
        +- voiture : toutes les places libres pour voiture   
             |   
            +- basic : les places libres pour voiture non-électriques et non-PMR   
             |   
            +- elec: les places libres pour voiture électrique   
             |   
            +- PMR : les places libres pour voiture PMR   
         |   
        +- moto : toutes les places libres pour moto   
 |   
+- user   
     |   
    +- id_utilisateur : information sur les véhicules de l'utilisateur (si l'utilisateur est enregistré)   
         |   
        +- plaque : information sur un véhicule (appartenant à l'utilisateur)

### Plan et espace agent

Les routes `/agent/...` sont réservées aux utilisateurs de type `agent` (400 si non authentifié, 403 sinon). `/token` renvoie maintenant `{"username": ..., "type": ...}`.

 |   
+- parking : plan complet pour la carte (`spots`, `roads`, `buildings`, `zones`), places et parkings   
 |   
+- agent   
     |   
    +- slots : toutes les places avec le véhicule garé (plaque, propriétaire), fin d'occupation, tarif, et `now` (heure du serveur, UTC)   
     |   
    +- infractions : liste des infractions et montants (`offense_table`)   
     |   
    +- fines : GET = contraventions (`?mine=true` pour celles de l'agent connecté) ; POST = dresser une contravention   

`POST /agent/fines` reçoit `{"slot_id": 9, "offense": "overtime", "plate": "AB123CD" (facultatif), "comment": "..." (facultatif)}`. L'agent, le montant, le lieu et la date sont remplis par le serveur. Refus : place inconnue (404), aucun véhicule sur la place, infraction inconnue ou plaque manquante (400), contravention déjà dressée pour cette place depuis moins de 12 h (409).

### Parkings, réservations et espace usager

Les places d'un parking sont des lignes de `slot_table` dont la colonne `parking` est renseignée (elles ne sont pas dessinées une à une sur la carte : elles sont comptées dans le parking). La catégorie d'une place est déduite de ses colonnes : `pmr` si `slot_pmr`, sinon `moto` si `slot_type` vaut `moto`, sinon `elec` si `slot_elec`, sinon `standard`.

#### reservation_table
| Colonne | Type | Définition |
|-----|------|-----|
| reservation_id | int | Clé primaire, auto-incrémentation |
| username | char[30] | Usager qui a réservé |
| slot_id | int | Place réservée (choisie par le serveur pour un parking) |
| parking | char[20] | Nom du parking, vide pour une place de rue |
| no_plaque, type_vehicule | char | Véhicule |
| nom, prenom | char[40] | Conducteur |
| start_at, end_at | timestamp | Créneau, en UTC |
| amount | float | `slot_tarif × durée en heures` |
| status | char[10] | `booked` → `parked` → `finished`, ou `cancelled` |
| created_at, checkin_at, checkout_at | timestamp | Dates |

#### profile_table
`username` (clé primaire), `nom`, `prenom`, `no_plaque`, `type_vehicule`, `elec` (véhicule électrique), `pmr` (carte mobilité inclusion), `notif_reservations`, `notif_expiration`, `notif_fines`.

#### fine_table (colonnes ajoutées)
`paye` (0/1) et `paye_le` : contravention payée par l'usager.

#### meta_table
Carnet de notes interne (`cle`, `valeur`) : sert à n'ajouter qu'une fois les places des parkings et les véhicules de départ.

#### Routes `/me/...` (usagers uniquement : 400 si non authentifié, 403 pour un agent)

 |   
+- me   
     |   
    +- profile : GET / PUT, profil de l'usager (la plaque est enregistrée comme véhicule de l'usager)   
     |   
    +- slots : places de rue avec statut `free`/`occupied`/`reserved` et créneaux déjà réservés (jamais d'info sur le véhicule)   
     |   
    +- parkings : parkings avec places libres/total par catégorie et tarif   
     |   
    +- reservations : GET = réservations (avec `state` : `upcoming`, `active`, `parked`, `finished`, `cancelled`, `expired`) et véhicules garés ; POST = réserver   
     |   
    +- reservations/{id}/checkin, checkout, cancel : arrivée, départ, annulation   
     |   
    +- vehicles/{plaque}/leave : libérer la place d'un véhicule garé sans réservation   
     |   
    +- fines : GET = contraventions des véhicules de l'usager ; POST fines/{n}/pay = payer   

`POST /me/reservations` reçoit `{"slot_id": 1}` (place de rue) **ou** `{"parking": "Le Parking", "category": "elec"}`, plus `start` (`AAAA-MM-JJ HH:MM:SS` en UTC, vide = maintenant), `duration_minutes` (15 à 1440), `plate`, `vehicle_type`, `nom`, `prenom`. Refus : durée ou date invalide (400), type de véhicule différent de la place (400), place PMR sans carte ou place avec borne sans véhicule électrique (403), plaque d'un autre usager, créneau déjà pris, place occupée, plus de place disponible dans la catégorie (409).

Côté agent, `GET /agent/slots` renvoie aussi `reserved` (place réservée en ce moment) et les places des parkings : les véhicules en infraction dans les parkings apparaissent donc dans les infractions.

### Signalements de places prises

#### report_table
| Colonne | Type | Définition |
|-----|------|-----|
| report_id | int | Clé primaire, auto-incrémentation |
| slot_id | int | Place signalée |
| username | char[30] | Usager qui signale |
| no_plaque | char[9] | Plaque indiquée par l'usager (facultative) |
| commentaire | char[300] | Précision (facultative) |
| reported_at | timestamp | Heure du signalement, UTC (début de l'occupation sans paiement) |
| status | char[10] | `pending` → `validated` ou `dismissed` |
| handled_by, handled_at | | Agent qui a traité et quand |
| assigned_plate | char[9] | Plaque finalement assignée à la place |

`slot_table.occupied_since` (timestamp) : depuis quand la place est occupée (arrivée d'une réservation, assignation par un agent). Renvoyé par `GET /agent/slots` dans `since`.

#### Routes

 |   
+- me   
 |   |   
 |  +- reports : POST = signaler une place de rue libre ou réservée ; GET = mes signalements et leur statut   
 |   
+- agent   
     |   
    +- reports : GET = signalements (à traiter d'abord) avec le véhicule et son propriétaire s'ils sont connus   
     |   
    +- reports/{id}/validate : POST `{"plate": ...}` (facultatif si le signalement en a une) ; assigne la place au véhicule depuis `reported_at`, sans paiement   
     |   
    +- reports/{id}/dismiss : POST ; rejette le signalement   
     |   
    +- vehicles/{plaque} : GET ; `known`, propriétaire (`owner`), type, `parked_slot`   
     |   
    +- slots/{id}/assign : POST `{"plate": ...}` ; assigne une place libre à un véhicule à partir de maintenant (règle aussi un signalement en attente sur cette place)   

Refus : place inconnue (404) ; place de parking, place déjà occupée ou déjà signalée, véhicule déjà stationné, signalement déjà traité (409) ; plaque invalide ou manquante (400).
