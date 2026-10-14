from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel
import sqlite3
from pathlib import Path
from typing import Annotated

DB_PATH = Path("/data/la-base.db")
VEHICULE_DB_PATH = Path("/data/l-autre-database.db")
USER_DB_PATH = Path("/data/database-user.db")

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

########## Startup ##########

@app.on_event("startup")
def startup_event() -> None:
    init_slot_db()
    init_vehicule_db()
    init_user_db()

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
