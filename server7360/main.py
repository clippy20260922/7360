from fastapi import FastAPI
from fastapi import HTTPException, Query, Depends
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from typing import Annotated
from pydantic import BaseModel
import sqlite3
from pathlib import Path

DB_PATH = Path("/data/la-base.db")
USER_DB_PATH = Path("/data/database-user.db")

app = FastAPI(title="Simple SQLite API")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

app = FastAPI(title="Simple SQLite API")

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

### Fonction d'initilisation de la table des places de parking dans la database principale

def init_slot_db(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS slot_table ("\
        " slot_id INTEGER PRIMARY KEY,"\
        " slot_lat float NOT NULL,"\
        " slot_long float NOT NULL,"\
        " slot_type char[4] NOT NULL, "\
        " slot_occupied boolean DEFAULT false,"\
        " slot_pmr boolean,"\
        " slot_elec boolean,"\
        " parking char[20] DEFAULT NULL,"\
        " parking_protege boolean,"\
        " fin_occupation timestamp NOT NULL DEFAULT '1900-01-01 00:00:00')"
    )
    row = conn.execute("SELECT slot_id FROM slot_table WHERE slot_id = 1").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO slot_table (slot_id, slot_lat, slot_long, slot_type, slot_occupied, slot_pmr, slot_elec) "\
            "VALUES (1, 1.22, 2.33, 'voit', false, false, false), (2, 1.22, 2.35, 'voit', false, false, false),"\
            "(3, 1.23, 2.37, 'voit', false, true, true), (4, 1.46, 2.12, 'voit', true, false, false),"\
            "(5, 2.22, 0.66, 'voit', true, false, true), (6, 1.25, 2.43, 'moto', false, false, false),"\
            "(7, 1.28, 2.29, 'voit', false, false, true)"
        )
        conn.execute(
            "INSERT INTO slot_table (slot_id, slot_lat, slot_long, slot_type, slot_occupied, slot_pmr, slot_elec, parking, fin_occupation) "\
            "VALUES (8, 2.00, 2.30, 'voit', false, false, false, 'Le Parking', '1900-01-01 00:00:00'), (9, 2.00, 2.3, 'voit', true, false, false, 'Le Parking', '2026-10-20 00:00:00')"
        )
    conn.commit()
    conn.close()

### Fonction d'initilisation de la table des véhicules dans la database principale

def init_vehicule_db(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("DROP TABLE IF EXISTS vehicle_table")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS user_table ("\
                " no_plaque char[9] PRIMARY KEY,"\
                " proprietaire char[10] NOT NULL,"\
                " type_vehicule float NOT NULL,"\
                " elec boolean)"
    )
    row = conn.execute("SELECT no_plaque FROM user_table").fetchone()
    if row is None:
        conn.execute (
            "INSERT INTO user_table (no_plaque, proprietaire, type_vehicule, elec)"\
            "VALUES ('AB123CD', 'ab123456','voit', false)"
        )
    conn.commit()
    conn.close()

### Fonction d'initilisation de la table des utilisateurs dans la database des utilisateurs

def init_user_db(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(USER_DB_PATH)
    conn.execute("DROP TABLE IF EXISTS user_table")
    conn.execute(
            "CREATE TABLE IF NOT EXISTS user_table ("\
                " username char[30] PRIMARY KEY,"\
                " password char[100] NOT NULL,"\
                " type char[5] NOT NULL)"
    )
    row = conn.execute("SELECT * FROM user_table").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO user_table (username, password, type)"\
            " VALUES ('ab123456', 'Mon_mdp123', 'user'), ('cd789', 'autre_MDP666', 'user'),"\
            " ('OSS117', 'Lablanquette117', 'agent')"
        )
    conn.commit()
    conn.close()

class DataPayload(BaseModel):
    value: str


@app.on_event("startup")
def startup_event() -> None:
    init_slot_db(DB_PATH)
    init_vehicule_db(DB_PATH)
    init_user_db(USER_DB_PATH)
    
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
    
@app.get("/data/{id}")
def get_data(id) -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_id = ?", (id,))
    conn.close()
    if row is None : 
        return {"Pas de place avec cet identifiant : ", id}
    return {"Place ", id, " : ", row[0]}



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
     return {"username":data[0]}