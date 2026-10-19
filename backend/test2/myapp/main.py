from fastapi import FastAPI, Depends, HTTPException, Query
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel
import sqlite3
from pathlib import Path
from typing import Annotated
from datetime import datetime, timedelta

DB_PATH = Path("/data/la-base.db")
VEHICULE_DB_PATH = Path("/data/l-autre-database.db")
USER_DB_PATH = Path("/data/database-user.db")
PAIEMENT_DB_PATH = Path("/data/database-paiement.db")

app = FastAPI(title="Simple SQLite API")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

########## Classes et database ##########

class User():
    username : str
    type : str = "user" #user ou agent ou None
    vehicule : list | None
    def __init__(self):
        self.username = ""
        self.type = "user"
        self.vehicule = None
current_user = User()

def init_slot_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("DROP TABLE IF EXISTS slot_table")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS slot_table ("\
        " slot_id int AUTO_INCREMENT PRIMARY KEY,"\
        " slot_lat float NOT NULL,"\
        " slot_long float NOT NULL,"\
        " slot_type char[4] NOT NULL, "\
        " slot_occupied boolean DEFAULT false,"\
        " slot_pmr boolean,"\
        " slot_elec boolean,"\
        " parking char[20],"\
        " parking_protege boolean,"\
        " fin_occupation timestamp NOT NULL DEFAULT '1900-01-01 00:00:00')"
    )
    row = conn.execute("SELECT * FROM slot_table").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO slot_table (slot_id, slot_lat, slot_long, slot_type, slot_occupied, slot_pmr, slot_elec) "\
            "VALUES (1, 1.22, 2.33, 'voit', false, false, false), (2, 1.22, 2.35, 'voit', false, false, false),"\
            "(3, 1.23, 2.37, 'voit', false, true, true), (4, 1.46, 2.12, 'voit', true, false, false),"\
            "(5, 2.22, 0.66, 'voit', true, false, true), (6, 1.25, 2.43, 'moto', false, false, false),"\
            "(7, 1.28, 2.29, 'voit', false, false, true)"
        )
    conn.commit()
    conn.close()

def init_vehicule_db() -> None:
    VEHICULE_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(VEHICULE_DB_PATH)
    conn.execute("DROP TABLE IF EXISTS vehicle_table")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS vehicle_table ("\
                " no_plaque char[9] PRIMARY KEY,"\
                " proprietaire char[30] NOT NULL,"\
                " type_vehicule float NOT NULL,"\
                " elec boolean)"
    )
    row = conn.execute("SELECT * FROM vehicle_table").fetchone()
    if row is None:
        conn.execute (
            "INSERT INTO vehicle_table (no_plaque, proprietaire, type_vehicule, elec)"\
            "VALUES ('AB123CD', 'ab123456','voit', false)"
        )
    conn.commit()
    conn.close()

def init_user_db() -> None:
    USER_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
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

def init_paiement_db() -> None:
    #pas de DROP : on garde l'historique des paiements entre deux démarrages
    PAIEMENT_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(PAIEMENT_DB_PATH)
    conn.execute(
            "CREATE TABLE IF NOT EXISTS paiement_table ("\
                " paiement_id integer PRIMARY KEY AUTOINCREMENT,"\
                " username char[30] NOT NULL,"\
                " slot_id int NOT NULL,"\
                " no_plaque char[9] NOT NULL,"\
                " montant float NOT NULL,"\
                " date_paiement timestamp NOT NULL,"\
                " fin_occupation timestamp NOT NULL)"
    )
    conn.commit()
    conn.close()

########## Startup ##########

@app.on_event("startup")
def startup_event() -> None:
    init_slot_db()
    init_vehicule_db()
    init_user_db()
    init_paiement_db()

@app.get("/")
def root() -> dict:
    
    return {"message": "Simple SQLite API is running"}


########## Infos sur les places ##########


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
    

### Info d'une place
    
@app.get("/data/{id:int}")
def get_data(id) -> None : 
    conn = sqlite3.connect(DB_PATH)
    data = conn.execute("SELECT * FROM slot_table WHERE slot_id = ?", (id,)).fetchone()
    conn.close()
    if data is None : 
        return {"Pas de place avec cet identifiant : ", id}
        #return {"N":0}
    return {"Place": id, "lat":data[1], "long":data[2], "type de place":data[3], "occupé":data[4], "PMR":data[5], "Borne électrique":data[6], "parking protégé":data[7]}
    #return {"N":1,"place":data}

### Places libres

@app.get("/data/free")
def get_all_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    data = conn.execute("SELECT * FROM slot_table WHERE slot_occupied=false").fetchall()
    conn.close()
    if len(data)==0 : 
        return {"N":0}
    return {"N":len(data), "data":data}

### Places pour voiture libres

@app.get("/data/free/voiture")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    data = conn.execute("SELECT * FROM slot_table WHERE slot_occupied=false AND slot_type='voit'").fetchall()
    conn.close()
    if len(data)==0 : 
        return {"Aucune place libre"}
    return {"N":len(data), "data":data}

### Places pour voiture libres sans les places pmr ou borne électrique

@app.get("/data/free/voiture/basic")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    data = conn.execute("SELECT * FROM slot_table WHERE slot_occupied=false AND slot_type='voit' AND slot_elec!=true AND slot_pmr!=true").fetchall()
    conn.close()
    if len(data)==0 : 
        return {"Aucune place électrique libre"}
    return {"N":len(data), "data":data}

### Places libres avec borne électrique

@app.get("/data/free/voiture/elec")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    data = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit' AND slot_elec = true").fetchall()
    conn.close()
    if len(data)==0 : 
        return {"Aucune place électrique libre"}
    return {"N":len(data), "data":data}

### Places PMR libres

@app.get("/data/free/voiture/pmr")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    data = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit' AND slot_pmr = true").fetchall()
    conn.close()
    if len(data)==0 : 
        return {"Aucune place PMR libre"}
    return {"N":len(data), "data":data}

### Places de moto libres

@app.get("/data/free/moto")
def get_moto_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    data = conn.execute("SELECT * FROM slot_table WHERE slot_occupied=false and slot_type='moto'").fetchall()
    conn.close()
    if len(data)==0 : 
        return {"Aucune place libre"}
    return {"N":len(data), "data":data}


########## Modification des places ##########

def valid_timestamp(timestamp:str):
    #verif du format du string en tant que timestamp
    valid = len(timestamp)==19
    valid = valid and int(timestamp[0:4])>2000
    valid = valid and timestamp[4]=='-'
    valid = valid and int(timestamp[5:7])>0 and int(timestamp[5:7])<13
    valid = valid and timestamp[7]=='-'
    valid = valid and int(timestamp[8:10])>0 and int(timestamp[8:10])<32
    valid = valid and timestamp[10]==' '
    valid = valid and int(timestamp[12:13])>=0 and int(timestamp[12:13])<13
    valid = valid and timestamp[13]==':'
    valid = valid and int(timestamp[14:16])>=0 and int(timestamp[14:16])<61
    valid = valid and timestamp[16]==':'
    valid = valid and int(timestamp[17:])>=0 and int(timestamp[17:])<61
    return valid

### Modification de l'occupation
@app.patch("/data/{id:int}/set_occupation")
async def set_slot_occupied(id:int, set_bool : bool, endtime : str = "1900-01-01 00:00:00" ) -> dict :
    if not valid_timestamp(endtime):
        raise HTTPException(status_code=400,detail="Timestamp invalide")
    conn = sqlite3.connect(DB_PATH)
    #Cas utilisateur (arrive ou part)
    if current_user.type == "user":
        if set_bool:
            conn.execute ("UPDATE slot_table SET slot_occupied=? AND fin_occupation='1900-01-01 00:00:00' WHERE slot_id = ?;", (set_bool,id,))
        else:
            conn.execute ("UPDATE slot_table SET slot_occupied=? AND fin_occupation=? WHERE slot_id = ?;", (set_bool,endtime,id,))
    #cas agent (place mal renseignée)
    elif current_user.type == "agent":
        if endtime!="1900-01-01 00:00:00":
            conn.execute ("UPDATE slot_table SET slot_occupied=? AND fin_occupation=? WHERE slot_id = ?;", (set_bool,endtime,id,))
        else :
            conn.execute ("UPDATE slot_table SET slot_occupied=? WHERE slot_id = ?;", (set_bool,id,))
    conn.commit()
    data = conn.execute("SELECT * FROM slot_table WHERE slot_id = ?", (id,)).fetchone()
    conn.close()
    return {"data":data}


########## Infos utilisateurs ##########


### Info des véhicule d'un utilisateur
# TODO restreindre à l'utilisateur actif
@app.get("/user/{user_id}")
def get_vehicule_data(user_id) -> dict:
    if current_user.username != user_id:
        raise HTTPException(status_code=403, detail="Accès non-autorisé")
    conn = sqlite3.connect(VEHICULE_DB_PATH)
    data = conn.execute("SELECT * FROM vehicle_table WHERE proprietaire = ?", (user_id,)).fetchall()
    conn.close()
    if len(data)==0 : 
        return {"N":0}
    return {"N":len(data), "data":data}

### Info d'un véhicule d'un utilisateur

@app.get("/user/{user_id}/{plaque_id}")
def get_vehicule_data(user_id, plaque_id) -> dict:
    conn = sqlite3.connect(VEHICULE_DB_PATH)
    data = conn.execute("SELECT * FROM vehicle_table WHERE proprietaire = ? AND no_plaque = ?", (user_id,plaque_id,)).fetchall()
    conn.close()
    if len(data)==0 : 
        return {"N":0}
    return {"N":1,"data":data}


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


########## Paiement ##########

# Prix d'une heure de stationnement selon le type de place (en euros)
TARIF_HORAIRE = {"voit": 2.0, "moto": 1.0, "cami": 4.0}
# Durée maximale qu'on peut payer d'un coup (en minutes)
DUREE_MAX = 24 * 60

def calcul_prix(slot_type:str, duree:int) -> float:
    #prix au prorata des minutes, arrondi au centime
    if slot_type not in TARIF_HORAIRE:
        raise HTTPException(status_code=400, detail="Pas de tarif pour ce type de place")
    return round(TARIF_HORAIRE[slot_type] * duree / 60, 2)

### Prix d'une place pour une durée (en minutes), avant de payer

@app.get("/data/{id:int}/prix")
def get_prix(id:int, duree:Annotated[int, Query(gt=0, le=DUREE_MAX)]) -> dict:
    conn = sqlite3.connect(DB_PATH)
    data = conn.execute("SELECT slot_type FROM slot_table WHERE slot_id = ?", (id,)).fetchone()
    conn.close()
    if data is None :
        raise HTTPException(status_code=404, detail="Pas de place avec cet identifiant")
    return {"place":id, "duree":duree, "prix":calcul_prix(data[0], duree)}

### Payer une place : elle passe occupée jusqu'à la fin de la durée payée

@app.post("/data/{id:int}/payer")
def payer_place(id:int, plaque:str, duree:Annotated[int, Query(gt=0, le=DUREE_MAX)]) -> dict:
    # TODO : utiliser le token de l'utilisateur quand le login sera fini (current_user est partagé par tout le monde)
    if current_user.username == "":
        raise HTTPException(status_code=401, detail="Connexion nécessaire pour payer")

    conn = sqlite3.connect(DB_PATH)
    place = conn.execute("SELECT slot_type, slot_occupied FROM slot_table WHERE slot_id = ?", (id,)).fetchone()
    conn.close()
    if place is None :
        raise HTTPException(status_code=404, detail="Pas de place avec cet identifiant")

    #le véhicule doit appartenir à l'utilisateur connecté et correspondre au type de place
    conn = sqlite3.connect(VEHICULE_DB_PATH)
    vehicule = conn.execute("SELECT type_vehicule FROM vehicle_table WHERE no_plaque = ? AND proprietaire = ?", (plaque,current_user.username,)).fetchone()
    conn.close()
    if vehicule is None :
        raise HTTPException(status_code=403, detail="Ce véhicule n'est pas enregistré à votre nom")
    if vehicule[0] != place[0]:
        raise HTTPException(status_code=400, detail="Ce véhicule ne correspond pas au type de place")
    if place[1]:
        raise HTTPException(status_code=409, detail="Place déjà occupée")

    prix = calcul_prix(place[0], duree)
    maintenant = datetime.now()
    date_paiement = maintenant.strftime("%Y-%m-%d %H:%M:%S")
    fin = (maintenant + timedelta(minutes=duree)).strftime("%Y-%m-%d %H:%M:%S")

    #le "AND slot_occupied=false" évite que deux personnes paient la même place en même temps
    conn = sqlite3.connect(DB_PATH)
    cur = conn.execute("UPDATE slot_table SET slot_occupied=true, fin_occupation=? WHERE slot_id = ? AND slot_occupied=false;", (fin,id,))
    nb_modifiees = cur.rowcount
    conn.commit()
    conn.close()
    if nb_modifiees == 0:
        raise HTTPException(status_code=409, detail="Place déjà occupée")

    conn = sqlite3.connect(PAIEMENT_DB_PATH)
    cur = conn.execute(
        "INSERT INTO paiement_table (username, slot_id, no_plaque, montant, date_paiement, fin_occupation)"\
        " VALUES (?, ?, ?, ?, ?, ?)", (current_user.username,id,plaque,prix,date_paiement,fin,)
    )
    conn.commit()
    paiement_id = cur.lastrowid
    conn.close()
    return {"paiement":paiement_id, "place":id, "plaque":plaque, "prix":prix, "fin_occupation":fin}
