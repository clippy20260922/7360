from fastapi import FastAPI
from pydantic import BaseModel
import sqlite3
from pathlib import Path

DB_PATH = Path("/data/la-base.db")

app = FastAPI(title="Simple SQLite API")


def init_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS app_data (
            slot_id int AUTO_INCREMENT PRIMARY KEY,
            slot_lat float NOT NULL,
            slot_long float NOT NULL,
            slot_type char[4] NOT NULL, //"voit", "moto", "velo"
            slot_occupied boolean DEFAULT false,
            slot_pmr boolean,
            slot_elec boolean,
            parking_protege boolean
        )
        """
    )
    row = conn.execute("SELECT value FROM app_data WHERE id = 1").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO app_data (slot_lat, slot_long, slot_type, slot_pmr, slot_elec,parking_protege) " \
            "VALUES (1.22, 2.33, 'voit', false, false, false) (1.22, 2.35, 'voit', false, false, false)"
            "(1.23, 2.37, 'voit', false, true, true) (1.46, 2.12, 'voit', true, false, false)"
            "(2.22, 0.66, 'voit', true, false, true) (1.25, 2.43, 'moto', false, false, false)"
            "(1.28, 2.29, 'voit', false, false, true)"
        )
    conn.commit()
    conn.close()


class DataPayload(BaseModel):
    value: str


@app.on_event("startup")
def startup_event() -> None:
    init_db()

@app.get("/")
def root() -> dict:
    return {"message": "Simple SQLite API is running"}

    
@app.get("/data/{id}")
def get_data(id) -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM app_data WHERE slot_id = ?", (id,))
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

@app.get("/data/free/voiture")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit'")
    conn.close()
    if row is None : 
        return {"Aucune place libre"}
    return {len(row), "places pour voiture libres : ", row}

@app.get("/data/free/voiture/basic")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit' AND slot_elec != true AND slot_pmr != true")
    conn.close()
    if row is None : 
        return {"Aucune place électrique libre"}
    return {len(row), "places pour voiture électrique libres : ", row}

### Places libres spécifiques

@app.get("/data/free/voiture/elec")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit' AND slot_elec = true")
    conn.close()
    if row is None : 
        return {"Aucune place électrique libre"}
    return {len(row), "places pour voiture électrique libres : ", row}

@app.get("/data/free/voiture/pmr")
def get_voit_free() -> dict : 
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT * FROM slot_table WHERE slot_occupied = false AND slot_type = 'voit' AND slot_pmr = true")
    conn.close()
    if row is None : 
        return {"Aucune place PMR libre"}
    return {len(row), "places pour voiture PMR libres : ", row}

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
