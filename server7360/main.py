from fastapi import FastAPI
from fastapi import HTTPException, Query, Depends
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from typing import Annotated
from pydantic import BaseModel
import sqlite3
from pathlib import Path
from fastapi.middleware.cors import CORSMiddleware
import os
import json
import math
from datetime import datetime, timedelta, timezone

# Dossier des bases de données : /data par défaut (conteneur), modifiable pour
# lancer le serveur directement sur le PC : DATA_DIR=./data uvicorn main:app
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
DB_PATH = DATA_DIR / "la-base.db"
USER_DB_PATH = DATA_DIR / "database-user.db"

app = FastAPI(title="Simple SQLite API")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

########## Classes et database ##########

#Utilisateur et ses véhicules
class User():
    username : str
    type : str = "user" #user ou agent ou None -> remplacer par token?
    vehicule : list | None
    def __init__(self):
        self.username = ""
        self.type = "user"
        self.vehicule = None
current_user = User()

### Petits outils communs

def utc_now() -> datetime:
    return datetime.now(timezone.utc)

def ts(dt: datetime) -> str:
    #Format des timestamps de la base : yyyy-mm-dd hh:mm:ss (UTC)
    return dt.strftime("%Y-%m-%d %H:%M:%S")

def ensure_columns(conn: sqlite3.Connection, table: str, columns: dict) -> None:
    #Ajoute les colonnes manquantes (pour les bases créées avant cette version)
    existing = {r[1] for r in conn.execute("PRAGMA table_info(" + table + ")")}
    for name, definition in columns.items():
        if name not in existing:
            conn.execute("ALTER TABLE " + table + " ADD COLUMN " + name + " " + definition)

def require_agent() -> None:
    #Vérifie l'authentification puis que l'utilisateur est un agent
    if current_user.username=="":
        raise HTTPException(status_code=400,detail="Authentifiez-vous pour avoir accès à cette fonctionnalité")
    if current_user.type != "agent":
        raise HTTPException(status_code=403, detail="Accès réservé aux agents")

### Fonction d'initilisation de la table des places de parking dans la database principale

def init_batiment_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE IF NOT EXISTS batiment_table ("\
            " batiment_lat float NOT NULL,"\
            " batiment_long float NOT NULL,"\
            " PRIMARY KEY (batiment_lat, batiment_long))"
    )
    #TODO: créer les batiments qui vous arrangent

def init_rue_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS rue_table ("\
        " rue_name char[50] NOT NULL,"\
        " rue_ville char[40] NOT NULL,"\
        " rue_lat float NOT NULL,"\
        " rue_long float NOT NULL,"\
        " PRIMARY KEY (rue_name, rue_ville))"
    )
    row = conn.execute("SELECT rue_name FROM rue_table").fetchone()
    if row is None:
        conn.executemany(
            "INSERT INTO rue_table (rue_name, rue_ville, rue_lat, rue_long) VALUES (?, ?, ?, ?)",
            [("rue du test", "Champs-Sur-Marne", 1.21, 2.35), ("rue de l'esiee", "Champs-Sur-Marne", 1.00, 2.00)]
        )
    conn.commit()
    conn.close()
    
def init_parking_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS parking_table ("\
        " parking_name char[40] PRIMARY KEY,"\
        " parking_adresse char[100] NOT NULL,"\
        " parking_lat float NOT NULL,"\
        " parking_long float NOT NULL)"
    )
    #Position sur le plan (en mètres) : sert à dessiner le parking sur la carte
    ensure_columns(conn, "parking_table", {"parking_x": "float", "parking_y": "float"})
    row = conn.execute("SELECT parking_name FROM parking_table").fetchone()
    if row is None:
        conn.executemany(
            "INSERT INTO parking_table (parking_name, parking_adresse, parking_lat, parking_long, parking_x, parking_y) "\
            "VALUES (?, ?, ?, ?, ?, ?)",
            [("Le Parking", "1 rue du test, Champs-Sur-Marne", 1.22, 2.35, 42, -22),
             ("L'autre parking", "7 rue du test, Champs-Sur-Marne", 1.02, 2.01, -45, 25)]
        )
    conn.commit()
    conn.close()
    
def init_slot_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS slot_table ("\
        " slot_id INTEGER PRIMARY KEY,"\
        " slot_adresse char[60],"\
        " slot_ville char[40],"\
        " slot_lat float NOT NULL,"\
        " slot_long float NOT NULL,"\
        " slot_type char[4] NOT NULL, "\
        " slot_pmr boolean DEFAULT false,"\
        " slot_elec boolean DEFAULT false,"\
        " parking char[20] DEFAULT NULL,"\
        " slot_tarif float NOT NULL,"\
        " slot_occupied boolean DEFAULT false,"\
        " fin_occupation timestamp NOT NULL DEFAULT '1900-01-01 00:00:00')"
    )
    #Position sur le plan (en mètres, pas en GPS) et orientation de la place
    ensure_columns(conn, "slot_table", {"slot_x": "float", "slot_y": "float", "slot_angle": "float DEFAULT 0"})
    row = conn.execute("SELECT slot_id FROM slot_table WHERE slot_id = 1").fetchone()
    if row is None:
        libre = "1900-01-01 00:00:00"
        dans_90_min = ts(utc_now() + timedelta(minutes=90))
        depuis_45_min = ts(utc_now() - timedelta(minutes=45))
        depuis_3h = ts(utc_now() - timedelta(minutes=190))
        rue = ("rue du test", "Champs-Sur-Marne")
        lot = ("1 rue du test", "Champs-Sur-Marne")
        # id, adresse, ville, lat, long, type, pmr, elec, parking, tarif, occupée, fin d'occupation, x, y
        places = [
            (1, *rue, 1.22, 2.33, "voit", False, False, None, 1.6, False, libre, -30.0, -6.0),
            (2, *rue, 1.22, 2.35, "voit", False, False, None, 1.6, False, libre, -27.3, -6.0),
            (3, *rue, 1.23, 2.37, "voit", True, True, None, 1.6, False, libre, -24.6, -6.0),
            (4, *rue, 1.46, 2.12, "voit", False, False, None, 1.6, True, libre, -30.0, 6.0),          #occupée, rien de payé
            (5, *rue, 2.22, 0.66, "voit", False, True, None, 1.6, True, dans_90_min, -27.3, 6.0),     #occupée, en règle
            (6, *rue, 1.25, 2.43, "moto", False, False, None, 0.8, True, depuis_45_min, -20.0, 6.0),  #occupée, dépassement
            (7, *rue, 1.28, 2.29, "voit", False, True, None, 1.6, False, libre, -16.0, -6.0),
            (8, *lot, 2.00, 2.30, "voit", False, False, "Le Parking", 2.0, False, libre, 20.0, 6.0),
            (9, *lot, 2.00, 2.30, "voit", False, False, "Le Parking", 2.0, True, depuis_3h, 23.0, 6.0), #occupée, dépassement
        ]
        conn.executemany(
            "INSERT INTO slot_table (slot_id, slot_adresse, slot_ville, slot_lat, slot_long, slot_type, slot_pmr, slot_elec, "\
            "parking, slot_tarif, slot_occupied, fin_occupation, slot_x, slot_y) "\
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            places
        )
    conn.commit()
    conn.close()

### Fonction d'initilisation de la table des véhicules dans la database principale

def init_vehicule_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    # current_slot : place où le véhicule est garé en ce moment (NULL sinon)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS vehicle_table ("\
                " no_plaque char[9] PRIMARY KEY,"\
                " proprietaire char[30] NOT NULL,"\
                " type_vehicule char[4] NOT NULL,"\
                " elec boolean DEFAULT false,"\
                " current_slot INTEGER DEFAULT NULL)"
    )
    ensure_columns(conn, "vehicle_table", {"current_slot": "INTEGER DEFAULT NULL"})
    row = conn.execute("SELECT no_plaque FROM vehicle_table").fetchone()
    if row is None:
        conn.executemany(
            "INSERT INTO vehicle_table (no_plaque, proprietaire, type_vehicule, elec, current_slot) VALUES (?, ?, ?, ?, ?)",
            [("AB123CD", "ab123456", "voit", False, 4),
             ("EF456GH", "cd789", "voit", True, 5),
             ("MN012OP", "cd789", "moto", False, 6),
             ("IJ789KL", "ab123456", "voit", False, 9),
             ("QR345ST", "ab123456", "voit", False, None)]
        )
    conn.commit()
    conn.close()

### Fonction d'initilisation de la table des utilisateurs dans la database des utilisateurs

def init_user_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(USER_DB_PATH)
    conn.execute("DROP TABLE IF EXISTS user_table")
    conn.execute(
            "CREATE TABLE IF NOT EXISTS user_table ("\
                " username char[30] PRIMARY KEY,"\
                " password char[100] NOT NULL,"\
                " nom char[100] NOT NULL,"\
                " prenom char[100] NOT NULL,"\
                " PMR bool DEFAULT false,"\
                " type char[5] NOT NULL)"
    )
    row = conn.execute("SELECT * FROM user_table").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO user_table (username, password, nom, prenom, type)"\
            " VALUES ('ab123456', 'Mon_mdp123', 'Dupont', 'Alice', 'user'), ('cd789', 'autre_MDP666', 'Martin', 'Bruno', 'user'),"\
            " ('OSS117', 'Lablanquette117', 'Bonisseur de La Bath', 'Hubert', 'agent')"
        )
    conn.commit()
    conn.close()

### Infractions que l'agent peut sanctionner (montants forfaitaires du Code de la route)

def init_infraction_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS offense_table ("\
        " code char[20] PRIMARY KEY,"\
        " label char[60] NOT NULL,"\
        " amount float NOT NULL,"\
        " legal char[60] NOT NULL,"\
        " majorated float DEFAULT NULL)"
    )
    row = conn.execute("SELECT code FROM offense_table").fetchone()
    if row is None:
        #Le forfait post-stationnement (FPS) est fixé par chaque commune (environ 10 à 50 €) : à adapter
        conn.executemany(
            "INSERT INTO offense_table (code, label, amount, legal, majorated) VALUES (?, ?, ?, ?, ?)",
            [("overtime", "Dépassement de la durée payée", 35, "Forfait post-stationnement (FPS)", None),
             ("unpaid", "Absence de paiement", 35, "Forfait post-stationnement (FPS)", None),
             ("nuisance", "Stationnement gênant", 35, "Contravention de 2e classe", 75),
             ("abusive", "Stationnement abusif (plus de 7 jours)", 35, "Contravention de 2e classe", 75),
             ("veryNuisance", "Stationnement très gênant", 135, "Contravention de 4e classe", 375),
             ("pmr", "Place PMR sans carte", 135, "Contravention de 4e classe (très gênant)", 375)]
        )
    conn.commit()
    conn.close()

### Contraventions dressées par les agents

def init_fine_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    #Le numéro affiché (PV-2026-00001) est fabriqué à partir de fine_no et de l'année d'émission
    conn.execute(
        "CREATE TABLE IF NOT EXISTS fine_table ("\
        " fine_no INTEGER PRIMARY KEY AUTOINCREMENT,"\
        " no_plaque char[9] NOT NULL,"\
        " type_vehicule char[4] NOT NULL,"\
        " slot_id INTEGER NOT NULL,"\
        " lieu char[100],"\
        " agent char[30] NOT NULL,"\
        " offense char[20] NOT NULL,"\
        " amount float NOT NULL,"\
        " commentaire char[300],"\
        " date_emission timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP)"
    )
    conn.commit()
    conn.close()

### Plan de la carte : routes, bâtiments et zones (en mètres, comme la position des places)

def init_plan_tables(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS plan_road_table ("\
        " road_id INTEGER PRIMARY KEY AUTOINCREMENT,"\
        " road_name char[50],"\
        " ax float NOT NULL, ay float NOT NULL,"\
        " bx float NOT NULL, by float NOT NULL,"\
        " width float NOT NULL)"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS plan_building_table ("\
        " building_id INTEGER PRIMARY KEY AUTOINCREMENT,"\
        " footprint text NOT NULL,"\
        " height float NOT NULL,"\
        " color integer DEFAULT NULL)"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS plan_zone_table ("\
        " zone_id INTEGER PRIMARY KEY AUTOINCREMENT,"\
        " kind char[5] NOT NULL,"\
        " polygon text NOT NULL)"
    )

    def rect(x0, y0, x1, y1) -> str:
        return json.dumps([{"x": x0, "y": y0}, {"x": x1, "y": y0}, {"x": x1, "y": y1}, {"x": x0, "y": y1}])

    if conn.execute("SELECT road_id FROM plan_road_table").fetchone() is None:
        conn.executemany(
            "INSERT INTO plan_road_table (road_name, ax, ay, bx, by, width) VALUES (?, ?, ?, ?, ?, ?)",
            [("Rue du test", -85, 0, 85, 0, 7),
             ("Rue de l'ESIEE", 0, -55, 0, 55, 6),
             ("Avenue du parking", 60, -55, 60, 55, 6),
             ("Rue du parc", -85, 42, 85, 42, 6)]
        )
    if conn.execute("SELECT building_id FROM plan_building_table").fetchone() is None:
        conn.executemany(
            "INSERT INTO plan_building_table (footprint, height, color) VALUES (?, ?, ?)",
            [(rect(-70, -32, -45, -12), 14, 0xFFB0BEC5), (rect(-35, -38, -10, -14), 10, 0xFFCFD8DC),
             (rect(8, -40, 28, -14), 16, 0xFFB0BEC5), (rect(68, -40, 82, -12), 12, 0xFFCFD8DC),
             (rect(-82, 10, -60, 34), 12, 0xFFCFD8DC), (rect(-30, 12, -8, 36), 9, 0xFFB0BEC5),
             (rect(8, 12, 28, 36), 14, 0xFFCFD8DC), (rect(68, 10, 82, 36), 18, 0xFFB0BEC5)]
        )
    if conn.execute("SELECT zone_id FROM plan_zone_table").fetchone() is None:
        conn.executemany(
            "INSERT INTO plan_zone_table (kind, polygon) VALUES (?, ?)",
            [("park", rect(32, 12, 54, 38)), ("water", rect(38, 20, 48, 30))]
        )
    conn.commit()
    conn.close()

class DataPayload(BaseModel):
    value: str


@app.on_event("startup")
def startup_event() -> None:
    init_slot_table(DB_PATH)
    init_vehicule_table(DB_PATH)
    init_parking_table(DB_PATH)
    init_rue_table(DB_PATH)
    init_batiment_table(DB_PATH)
    init_plan_tables(DB_PATH)
    init_infraction_table(DB_PATH)
    init_fine_table(DB_PATH)
    init_user_table(USER_DB_PATH)
    
    
@app.get("/")
def root() -> dict:
    return {"message": "Simple SQLite API is running"}


########## Infos sur les places ##########

### Toutes les places ###

@app.get("/data")
def data_sql() -> dict:
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table")
    data = row.fetchall()
    conn.close()
    if len(data)==0:
        return {"N":len(data)}
    else :
        return {"N":len(data), "data":data}

### Places d'une zone géographique ###
# Déclarées avant /data/{id} pour que "zone" ne soit pas pris pour un identifiant de place
# La zone est un rectangle sur la carte : entre deux latitudes et deux longitudes

Latitude = Annotated[float, Query(ge=-90, le=90)]
Longitude = Annotated[float, Query(ge=-180, le=180)]

def places_dans_zone(lat_min:float, lat_max:float, long_min:float, long_max:float, libres:bool) -> dict:
    if lat_min > lat_max or long_min > long_max:
        raise HTTPException(status_code=400, detail="Zone invalide : le min doit être inférieur au max")
    requete = "SELECT * FROM slot_table WHERE slot_lat BETWEEN ? AND ? AND slot_long BETWEEN ? AND ?"
    if libres:
        requete += " AND slot_occupied=false"
    conn = sqlite3.connect(DB_PATH)
    data = conn.execute(requete, (lat_min,lat_max,long_min,long_max,)).fetchall()
    conn.close()
    if len(data)==0 :
        return {"N":0}
    return {"N":len(data), "data":data}

### Toutes les places d'une zone

@app.get("/data/zone")
def get_zone(lat_min:Latitude, lat_max:Latitude, long_min:Longitude, long_max:Longitude) -> dict:
    return places_dans_zone(lat_min, lat_max, long_min, long_max, libres=False)

### Places libres d'une zone

@app.get("/data/free/zone")
def get_free_zone(lat_min:Latitude, lat_max:Latitude, long_min:Longitude, long_max:Longitude) -> dict:
    return places_dans_zone(lat_min, lat_max, long_min, long_max, libres=True)

### Places libres

@app.get("/data/free")
def get_all_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false")
    conn.close()
    if row is None : 
        return {"Aucune place libre"}
    return {len(row)," places libres : ", row}

### Places pour voiture libres

@app.get("/data/free/voiture")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit'")
    conn.close()
    if row is None : 
        return {"Aucune place libre"}
    return {len(row), "places pour voiture libres : ", row}

### Places pour voiture libres sans les places pmr ou borne électrique

@app.get("/data/free/voiture/basic")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit' AND slot_elec != true AND slot_pmr != true")
    conn.close()
    if row is None : 
        return {"Aucune place électrique libre"}
    return {len(row), "places pour voiture électrique libres : ", row}

### Places libres avec borne électrique

@app.get("/data/free/voiture/elec")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit' AND slot_elec = true")
    conn.close()
    if row is None : 
        return {"Aucune place électrique libre"}
    return {len(row), "places pour voiture électrique libres : ", row}

### Places PMR libres

@app.get("/data/free/voiture/pmr")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit' AND slot_pmr = true")
    conn.close()
    if row is None : 
        return {"Aucune place PMR libre"}
    return {len(row), "places pour voiture PMR libres : ", row}

### Places de moto libres

@app.get("/data/free/moto")
def get_moto_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false slot_type = 'moto'")
    conn.close()
    if row is None : 
        return {"Aucune place libre"}
    return {len(row), "places pour moto libres : ", row}

### Info d'une place
    
@app.get("/data/{id:int}")
def get_data(id:int) -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_id = ?", (id,)).fetchone()
    conn.close()
    if row is None : 
        raise HTTPException(status_code=404, detail="Pas de place avec cet identifiant")
    return {"data":row}



########## Modification des places ##########


### Modification de l'occupation

@app.patch("/data/{id:int}/set_occupation")
async def set_slot_occupied(id:int, set_bool : bool, occupation_time_min : int = -1, vehicule : str = "" ) -> dict :
    #Vérifie l'authentification
    if current_user.username=="":
        raise HTTPException(status_code=400,detail="Authentifiez-vous pour avoir accès à cette fonctionnalité")
    
    conn = sqlite3.connect(DB_PATH)
    #Cas utilisateur (arrive ou part)
    if current_user.type == "user":
        #Prendre la place
        if set_bool:

            #Vérifier la présence des informations
            if vehicule=="":
                raise HTTPException(status_code=400,detail="Veuillez renseigner la plaque du véhicule garé")
            elif occupation_time_min<=0:
                raise HTTPException(status_code=400,detail="Veuillez renseigner le temps d'occupation payé")
            
            else:
                #Vérifier l'appartenance du véhicule
                data = conn.execute("SELECT proprietaire FROM vehicle_table WHERE no_plaque=?",(vehicule,)).fetchall()
                if (len(data)!=0 and  current_user.username not in data[0]) or len(data)==0:
                    raise HTTPException(status_code=400,detail="Veuillez enregistrer votre véhicule avant de le garer")
                
                #Vérifier que la place n'est pas prise
                data = conn.execute("SELECT slot_occupied FROM slot_table WHERE slot_id=?",(id,)).fetchone()
                if data==1:
                    raise HTTPException(status_code=400,detail="Cette place est occupée. Si ce n'est pas le cas, veuillez contacter le support")

                #Enregistrer les informations de la place et du véhicule
                conn.execute("UPDATE slot_table SET slot_occupied=?, fin_occupation= DATETIME(CURRENT_TIMESTAMP,?) WHERE slot_id = ?;", (set_bool, "+"+str(occupation_time_min)+" minutes",id,))
                conn.execute("UPDATE vehicle_table SET current_slot=? WHERE no_plaque=?", (id,vehicule,))

        #Libérer la place
        else:
            conn.execute("UPDATE slot_table SET slot_occupied=? AND fin_occupation='1900-01-01 00:00:00' WHERE slot_id = ?;", (set_bool,id,))
            conn.execute("UPDATE vehicle_table SET current_slot=NULL WHERE no_plaque=?", (vehicule,))
        
    #Cas agent (place mal renseignée)
    elif current_user.type == "agent":
        #Signaler une place prise ou libre non-rensignée
        if set_bool and occupation_time_min!=-1:
                conn.execute("UPDATE slot_table SET slot_occupied=? AND fin_occupation=DATETIME(CURRENT_TIMESTAMP,?) WHERE slot_id = ?;", (set_bool,"+"+str(occupation_time_min)+" minutes",id,))
        else:
                conn.execute("UPDATE slot_table SET slot_occupied=? WHERE slot_id = ?;", (set_bool,id,))

    #Enregistrement des modifications
    conn.commit()
    data = conn.execute("SELECT * FROM slot_table WHERE slot_id = ?", (id,)).fetchone()
    conn.close()
    return {"data":data}



########## Infos utilisateurs ##########


### Info des véhicule d'un utilisateur

@app.get("/user/{user_id}")
def get_vehicule_data(user_id, plaque_id="") -> dict:
    #Vérifie l'authentification
    if current_user.username=="":
            raise HTTPException(status_code=400,detail="Authentifiez-vous pour avoir accès à cette fonctionnalité")
    
    if current_user.username != user_id:
        raise HTTPException(status_code=403, detail="Accès non-autorisé")
    conn = sqlite3.connect(DB_PATH)
    if plaque_id=="":
        data = conn.execute("SELECT * FROM vehicle_table WHERE proprietaire = ?", (user_id,)).fetchall()
    else :
        data = conn.execute("SELECT * FROM vehicle_table WHERE proprietaire = ? AND no_plaque = ?", (user_id,plaque_id,)).fetchall()
    conn.close()
    if len(data)==0 : 
        return {"N":0}
    return {"N":len(data), "data":data}

### Infos des places en cours ###

@app.get("/user/{user_id}/en_cours")
def get_current_parked_vehicule(user_id) -> dict:
    #Vérifie l'authentification
    if current_user.username=="":
            raise HTTPException(status_code=400,detail="Authentifiez-vous pour avoir accès à cette fonctionnalité")
        
    if user_id!=current_user.username:
        raise HTTPException(status_code=403, detail="Accès non-autorisé")
    else:
        conn = sqlite3.connect(DB_PATH)
        data = conn.execute("SELECT no_plaque,fin_occupation FROM slot_table LEFT JOIN vehicle_table ON slot_table.slot_id=vehicle_table.current_slot WHERE proprietaire=?",(user_id,)).fetchall()
        conn.close()
        print(data)
        return {"N":len(data), "data":data}



########## Infos agents ##########


#véhicule ayant dépassé le temps mais n'ayant pas indiqué être parti (parking peut être None)
@app.get("/data/see_overtime")
def get_overtime_slot(parking) -> dict:
    #Vérifie l'authentification
    if current_user.username=="":
                raise HTTPException(status_code=400,detail="Authentifiez-vous pour avoir accès à cette fonctionnalité")

    #Vérifier que l'utilisateur est un agent
    # TODO: restreindre l'accès à certaines villes/parking?
    if current_user.type == "agent":
        conn = sqlite3.connect(DB_PATH)
        data = conn.execute("SELECT slot_id FROM slot_table WHERE parking = ?", (parking,)).fetchone()
        if data is None:
            raise HTTPException(status_code=404, detail="Pas de parking à ce nom")
        data = conn.execute("SELECT slot_id FROM slot_table WHERE parking = ? AND slot_occupied = true AND fin_occupation < CURRENT_TIMESTAMP", (parking,)).fetchall()
        conn.close()
        if len(data)==0:
            return {"N":0}
        return {"N":len(data), "data":data}



########## Plan de la carte ##########


### Plan complet : places, parkings, routes, bâtiments et zones (format attendu par ParkingMapView)

LOT_WIDTH = 24.0
LOT_LENGTH = 14.0

def position_plan(x, y, lat, long, ref_lat, ref_long) -> tuple:
    #Position en mètres. Si elle n'est pas renseignée en base, on la déduit de la latitude/longitude
    if x is not None and y is not None:
        return float(x), float(y)
    return ((long - ref_long) * 111320 * math.cos(math.radians(ref_lat)), -(lat - ref_lat) * 110540)

@app.get("/parking")
def get_parking() -> dict:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    slots = conn.execute("SELECT * FROM slot_table ORDER BY slot_id").fetchall()
    lots = conn.execute("SELECT * FROM parking_table").fetchall()
    roads = conn.execute("SELECT * FROM plan_road_table").fetchall()
    buildings = conn.execute("SELECT * FROM plan_building_table").fetchall()
    zones = conn.execute("SELECT * FROM plan_zone_table").fetchall()
    conn.close()

    ref_lat = sum(r["slot_lat"] for r in slots) / len(slots) if slots else 0.0
    ref_long = sum(r["slot_long"] for r in slots) / len(slots) if slots else 0.0

    spots = []
    for r in slots:
        x, y = position_plan(r["slot_x"], r["slot_y"], r["slot_lat"], r["slot_long"], ref_lat, ref_long)
        moto = r["slot_type"] == "moto"
        spots.append({
            "id": str(r["slot_id"]),
            "x": x, "y": y,
            "width": 1.2 if moto else 2.5,
            "length": 2.4 if moto else 5.0,
            "angle": r["slot_angle"] or 0,
            "status": "occupied" if r["slot_occupied"] else "free",
        })

    for lot in lots:
        x, y = position_plan(lot["parking_x"], lot["parking_y"], lot["parking_lat"], lot["parking_long"], ref_lat, ref_long)
        places = [r for r in slots if r["parking"] == lot["parking_name"]]
        #Un parking est complet quand toutes ses places sont occupées
        complet = len(places) > 0 and all(r["slot_occupied"] for r in places)
        spots.append({
            "id": lot["parking_name"],
            "x": x, "y": y,
            "width": LOT_WIDTH, "length": LOT_LENGTH, "angle": 0,
            "status": "occupied" if complet else "free",
            "lot": True,
        })

    return {
        "spots": spots,
        "roads": [{"ax": r["ax"], "ay": r["ay"], "bx": r["bx"], "by": r["by"], "width": r["width"], "name": r["road_name"] or ""} for r in roads],
        "buildings": [{"footprint": json.loads(r["footprint"]), "height": r["height"], "color": r["color"]} for r in buildings],
        "zones": [{"kind": r["kind"], "polygon": json.loads(r["polygon"])} for r in zones],
    }



########## Espace agent ##########


### Places avec le véhicule garé dessus (réservé aux agents)

@app.get("/agent/slots")
def get_agent_slots() -> dict:
    require_agent()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT slot_table.*, vehicle_table.no_plaque AS plaque, vehicle_table.proprietaire AS proprietaire "\
        "FROM slot_table LEFT JOIN vehicle_table ON vehicle_table.current_slot = slot_table.slot_id "\
        "ORDER BY slot_table.slot_id"
    ).fetchall()
    conn.close()
    data = [{
        "id": r["slot_id"],
        "type": r["slot_type"],
        "pmr": bool(r["slot_pmr"]),
        "elec": bool(r["slot_elec"]),
        "address": r["slot_adresse"],
        "city": r["slot_ville"],
        "parking": r["parking"],
        "tariff": r["slot_tarif"],
        "occupied": bool(r["slot_occupied"]),
        "fin_occupation": r["fin_occupation"],
        "plate": r["plaque"],
        "owner": r["proprietaire"],
    } for r in rows]
    #"now" : l'heure du serveur (UTC), pour que le client juge les dépassements avec la même horloge
    return {"now": ts(utc_now()), "N": len(data), "data": data}


### Infractions proposées pour une contravention, avec leur montant

@app.get("/agent/infractions")
def get_agent_infractions() -> dict:
    require_agent()
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("SELECT code, label, amount, legal, majorated FROM offense_table").fetchall()
    conn.close()
    data = [{"code": r[0], "label": r[1], "amount": r[2], "legal": r[3], "majorated": r[4]} for r in rows]
    return {"N": len(data), "data": data}


### Contraventions

def fine_to_dict(r: sqlite3.Row) -> dict:
    return {
        "id": "PV-" + str(r["date_emission"])[:4] + "-" + str(r["fine_no"]).zfill(5),
        "plate": r["no_plaque"],
        "vehicle_type": r["type_vehicule"],
        "slot_id": r["slot_id"],
        "location": r["lieu"] or "",
        "agent": r["agent"],
        "offense": r["offense"],
        "offense_label": r["label"] or r["offense"],
        "amount": r["amount"],
        "comment": r["commentaire"],
        "issued_at": r["date_emission"],
    }

@app.get("/agent/fines")
def get_agent_fines(mine: bool = False) -> dict:
    require_agent()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    requete = "SELECT fine_table.*, offense_table.label AS label FROM fine_table "\
              "LEFT JOIN offense_table ON offense_table.code = fine_table.offense"
    if mine:
        rows = conn.execute(requete + " WHERE agent = ? ORDER BY fine_no DESC", (current_user.username,)).fetchall()
    else:
        rows = conn.execute(requete + " ORDER BY fine_no DESC").fetchall()
    conn.close()
    data = [fine_to_dict(r) for r in rows]
    return {"N": len(data), "data": data}

class FinePayload(BaseModel):
    slot_id: int
    offense: str
    plate: str | None = None      #si absent, on prend le véhicule garé sur la place
    comment: str | None = None

@app.post("/agent/fines")
def create_agent_fine(payload: FinePayload) -> dict:
    require_agent()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    slot = conn.execute("SELECT * FROM slot_table WHERE slot_id = ?", (payload.slot_id,)).fetchone()
    if slot is None:
        conn.close()
        raise HTTPException(status_code=404, detail="Pas de place avec cet identifiant")
    if not slot["slot_occupied"]:
        conn.close()
        raise HTTPException(status_code=400, detail="Aucun véhicule n'est stationné sur cette place")

    offense = conn.execute("SELECT * FROM offense_table WHERE code = ?", (payload.offense,)).fetchone()
    if offense is None:
        conn.close()
        raise HTTPException(status_code=400, detail="Infraction inconnue")

    #Infos du véhicule : celui enregistré sur la place, sinon ce que l'agent a saisi
    vehicle = conn.execute("SELECT no_plaque, type_vehicule FROM vehicle_table WHERE current_slot = ?", (payload.slot_id,)).fetchone()
    plate = (payload.plate or "").strip().upper()
    if plate == "" and vehicle is not None:
        plate = vehicle["no_plaque"]
    if plate == "":
        conn.close()
        raise HTTPException(status_code=400, detail="Veuillez renseigner la plaque du véhicule")
    vehicle_type = vehicle["type_vehicule"] if vehicle is not None else slot["slot_type"]

    #Une seule contravention par place sur 12 h
    doublon = conn.execute("SELECT fine_no FROM fine_table WHERE slot_id = ? AND date_emission > ?", (payload.slot_id, ts(utc_now() - timedelta(hours=12)))).fetchone()
    if doublon is not None:
        conn.close()
        raise HTTPException(status_code=409, detail="Une contravention a déjà été dressée pour cette place")

    lieu = ", ".join(x for x in (slot["slot_adresse"], slot["slot_ville"]) if x) or (slot["parking"] or "")
    comment = (payload.comment or "").strip() or None
    cur = conn.execute(
        "INSERT INTO fine_table (no_plaque, type_vehicule, slot_id, lieu, agent, offense, amount, commentaire, date_emission) "\
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (plate, vehicle_type, payload.slot_id, lieu, current_user.username, offense["code"], offense["amount"], comment, ts(utc_now()))
    )
    conn.commit()
    row = conn.execute(
        "SELECT fine_table.*, offense_table.label AS label FROM fine_table "\
        "LEFT JOIN offense_table ON offense_table.code = fine_table.offense WHERE fine_no = ?", (cur.lastrowid,)
    ).fetchone()
    conn.close()
    return {"data": fine_to_dict(row)}



########## Login ##########

### Login

def set_user_info(username:str):
    current_user.username = username
    conn = sqlite3.connect(USER_DB_PATH)
    data = conn.execute("SELECT type FROM user_table WHERE username = ?", (username,)).fetchone()
    current_user.type = data[0]
    conn.close()

@app.post("/token")
async def login(form_data: Annotated[OAuth2PasswordRequestForm, Depends()]):
     #TODO : conversion form -> objet user
     conn = sqlite3.connect(USER_DB_PATH)
     data = conn.execute("SELECT * FROM user_table WHERE username = ?", (form_data.username,)).fetchone()
     if data is None:
         raise HTTPException(status_code=400, detail="username ou mot de passe erroné")
     hashed_mdp = hash(data[1])
     hashed_intput = hash(form_data.password)
     if hashed_mdp != hashed_intput:
         raise HTTPException(status_code=400, detail="username ou mot de passe erroné")
     set_user_info(form_data.username)
     return {"username":data[0], "type":current_user.type}