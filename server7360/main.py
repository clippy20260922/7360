from fastapi import FastAPI
from pydantic import BaseModel
import sqlite3
from pathlib import Path

DB_PATH = Path("/data/la-base.db")
VEHICULE_DB_PATH = Path("/data/l-autre-database.db")

app = FastAPI(title="Simple SQLite API")


def init_slot_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS slot_table ("\
        " slot_id int AUTO_INCREMENT PRIMARY KEY, ("\
        " slot_lat float NOT NULL,("\
        " slot_long float NOT NULL,("\
        " slot_type char[4] NOT NULL, ("\
        " slot_occupied boolean DEFAULT false,("\
        " slot_pmr boolean,("\
        " slot_elec boolean,("\
        " parking_protege boolean)"
    )
    row = conn.execute("SELECT slot_id FROM slot_table WHERE id = 1").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO slot_table (slot_lat, slot_long, slot_type, slot_pmr, slot_elec,parking_protege) " \
            "VALUES (1.22, 2.33, 'voit', false, false, false) (1.22, 2.35, 'voit', false, false, false)"
            "(1.23, 2.37, 'voit', false, true, true) (1.46, 2.12, 'voit', true, false, false)"
            "(2.22, 0.66, 'voit', true, false, true) (1.25, 2.43, 'moto', false, false, false)"
            "(1.28, 2.29, 'voit', false, false, true)"
        )
    conn.commit()
    conn.close()

def init_vehicule_db() -> None:
    VEHICULE_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS user_table ("\
                " no_plaque char[9] PRIMARY KEY, ("\
                " proprietaire char[10] NOT NULL,"\
                " type_vehicule float NOT NULL,("\
                " elec boolean)"
    )
    row = conn.execute("SELECT no_place FROM user_table").fetchone()
    if row is None:
        conn.execute (
            "INSERT INTO user_table (no_plaque, type_vehicule, elec)"\
            "VALUES ('AB123CD','voit', false)"
        )
    conn.commit()
    conn.close()

class DataPayload(BaseModel):
    value: str


@app.on_event("startup")
def startup_event() -> None:
    init_slot_db()
    init_vehicule_db()

@app.get("/")
def root() -> dict:
    return {"message": "Simple SQLite API is running"}

### Info d'une place
    
@app.get("/data/{id}")
def get_data(id) -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_id = ?", (id,))
    conn.close()
    if row is None : 
        return {"Pas de place avec cet identifiant : ", id}
    return {"Place ", id, " : ", row[0]}

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



### Modification de l'occupation

@app.post("/data/{id}/set_occupied")
def set_slot_occupied() -> dict:
    conn = sqlite3.connect(DB_PATH)
    conn.execute ("UPDATE slot_table SET slot_occupied = true WHERE slot_id = ?", (id,))
    conn.commit()
    conn.close()
    return {"Place ", id, " marqué comme occupée"}

@app.post("/data/{id}/set_free")
def set_slot_occupied() -> dict:
    conn = sqlite3.connect(DB_PATH)
    conn.execute ("UPDATE slot_table SET slot_occupied = false WHERE slot_id = ?", (id,))
    conn.commit()
    conn.close()
    return {"Place ", id, " marqué comme libre"}



### Info des véhicule d'un utilisateur

@app.post("/user/{user_id}")
def get_vehicule_data(user_id):
    conn = sqlite3.connect(VEHICULE_DB_PATH)
    row = conn.execute("SELECT * FROM user_table WHERE proprietaire = ?", (user_id,))
    conn.close()
    if row is None : 
        return {"Aucune véhicule pour cet utilisateur"}
    return {len(row), "véhicules pour cet utilisateur : ", row}

### Info d'un véhicule d'un utilisateur

@app.post("/user/{user_id}/{plaque_id}")
def get_vehicule_data(user_id, plaque_id):
    conn = sqlite3.connect(VEHICULE_DB_PATH)
    row = conn.execute("SELECT * FROM user_table WHERE proprietaire = ? AND no_plaque = ?", (user_id,plaque_id,))
    conn.close()
    if row is None : 
        return {"Vous n'avez pas enregistré ce véhicule"}
    return {"Info de votre véhicule : ", row}
