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