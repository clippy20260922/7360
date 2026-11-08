from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi import HTTPException, Query, Depends
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from typing import Annotated, AsyncIterator
from pydantic import BaseModel
import sqlite3
from pathlib import Path
from fastapi.middleware.cors import CORSMiddleware
import os
import json
import math
import re
from datetime import datetime, timedelta, timezone

# Dossier des bases de données : /data par défaut (conteneur), modifiable pour
# lancer le serveur directement sur le PC : DATA_DIR=./data uvicorn main:app
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
DB_PATH = DATA_DIR / "la-base.db"
USER_DB_PATH = DATA_DIR / "database-user.db"

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    startup_event()
    yield


app = FastAPI(title="Simple SQLite API", lifespan=lifespan)

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

def require_user() -> None:
    #Vérifie l'authentification puis que l'utilisateur est un usager
    if current_user.username=="":
        raise HTTPException(status_code=400,detail="Authentifiez-vous pour avoir accès à cette fonctionnalité")
    if current_user.type != "user":
        raise HTTPException(status_code=403, detail="Accès réservé aux usagers")

def open_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def norm_plate(plate) -> str:
    #« ab-123-cd » → « AB123CD » : une seule écriture en base
    return re.sub(r"[^A-Z0-9]", "", (plate or "").upper())

def parse_ts(value: str) -> datetime:
    try:
        v = value.strip().replace("T", " ").replace("Z", "").split(".")[0]
        return datetime.strptime(v[:19], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except Exception:
        raise HTTPException(status_code=400, detail="Date invalide (format attendu : AAAA-MM-JJ HH:MM:SS, en UTC)")

CATEGORY_LABELS = {"standard": "Voiture", "pmr": "PMR", "elec": "Électrique", "moto": "Moto"}

def slot_category(pmr, slot_type, elec) -> str:
    #Une place PMR est comptée PMR même si elle a une borne
    if pmr:
        return "pmr"
    if slot_type == "moto":
        return "moto"
    if elec:
        return "elec"
    return "standard"

def reserved_slot_ids(conn: sqlite3.Connection) -> set:
    #Places dont une réservation est en cours de validité et dont le véhicule n'est pas encore arrivé
    now = ts(utc_now())
    rows = conn.execute(
        "SELECT slot_id FROM reservation_table WHERE status = 'booked' AND start_at <= ? AND end_at > ?", (now, now)
    ).fetchall()
    return {r[0] for r in rows}


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
            [
                ("rue du test", "Champs-Sur-Marne", 1.21, 2.35),
                ("rue de l'esiee", "Champs-Sur-Marne", 1.00, 2.00),
            ],
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
            " ('OSS117', 'Lablanquette117', 'Bonisseur de La Bath', 'Hubert', 'agent'),"\
            " ('ef321', 'Mdp_Chloe_321', 'Leroy', 'Chloé', 'user'), ('gh654', 'Mdp_Hugo_654', 'Garcia', 'Hugo', 'user')"
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
    #Contravention réglée par l'usager (0/1) et date du paiement
    ensure_columns(conn, "fine_table", {"paye": "boolean DEFAULT 0", "paye_le": "timestamp"})
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

### Contenu des parkings : places par catégorie (standard, PMR, électrique, moto)

PARKINGS_PLACES = {
    "Le Parking": [("standard", 7), ("pmr", 2), ("elec", 3)],
    "L'autre parking": [("standard", 6), ("moto", 2), ("elec", 2)],
    "Parking Sud": [("standard", 4), ("pmr", 2), ("moto", 2)],
}
TARIF_CATEGORIE = {"standard": 2.0, "pmr": 2.0, "elec": 2.6, "moto": 1.0}

def init_meta_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    #Petit carnet de notes : sert à ne remplir qu'une seule fois les données de départ ajoutées après coup
    conn.execute("CREATE TABLE IF NOT EXISTS meta_table (cle char[40] PRIMARY KEY, valeur char[40])")
    conn.commit()
    conn.close()

def init_parking_slots(DB_PATH: Path) -> None:
    #Ajoute les places des parkings (et quelques véhicules garés) sans toucher aux données existantes
    conn = sqlite3.connect(DB_PATH)
    if conn.execute("SELECT valeur FROM meta_table WHERE cle = 'parking_slots_v1'").fetchone() is not None:
        conn.close()
        return
    conn.execute(
        "INSERT OR IGNORE INTO parking_table (parking_name, parking_adresse, parking_lat, parking_long, parking_x, parking_y) "\
        "VALUES ('Parking Sud', '12 rue du parc, Champs-Sur-Marne', 1.10, 2.20, 42, 55)"
    )
    ids = {}
    for name, categories in PARKINGS_PLACES.items():
        info = conn.execute("SELECT parking_adresse, parking_lat, parking_long FROM parking_table WHERE parking_name = ?", (name,)).fetchone()
        if info is None:
            continue
        for category, count in categories:
            ids[(name, category)] = []
            for _ in range(count):
                cur = conn.execute(
                    "INSERT INTO slot_table (slot_adresse, slot_ville, slot_lat, slot_long, slot_type, slot_pmr, slot_elec, parking, slot_tarif) "\
                    "VALUES (?, 'Champs-Sur-Marne', ?, ?, ?, ?, ?, ?, ?)",
                    (info[0], info[1], info[2], "moto" if category == "moto" else "voit",
                     category == "pmr", category == "elec", name, TARIF_CATEGORIE[category])
                )
                ids[(name, category)].append(cur.lastrowid)

    #Utilisateurs de départ ajoutés : leurs véhicules (libres ou garés dans les parkings)
    vehicules = [
        ("UV678WX", "cd789", "voit", True, None), ("DE890FG", "ef321", "voit", False, None), ("HI123JK", "gh654", "voit", False, None),
    ]
    #(parking, catégorie, plaque, propriétaire, type, borne, minutes avant la fin ; 0 = rien de payé)
    garees = [
        ("Le Parking", "standard", "KL234MN", "ef321", "voit", False, 120),
        ("Le Parking", "standard", "PQ456RS", "gh654", "voit", False, 0),
        ("Le Parking", "elec", "TV789UW", "ef321", "voit", True, 45),
        ("L'autre parking", "standard", "XY012ZA", "gh654", "voit", False, -20),
        ("L'autre parking", "moto", "BC345DE", "ef321", "moto", False, 60),
        ("Parking Sud", "pmr", "FG678HI", "gh654", "voit", False, 30),
        ("Parking Sud", "standard", "JK901LM", "cd789", "voit", False, 180),
    ]
    conn.executemany("INSERT OR IGNORE INTO vehicle_table (no_plaque, proprietaire, type_vehicule, elec) VALUES (?, ?, ?, ?)", [v[:4] for v in vehicules])
    used = {}
    for parking, category, plaque, proprio, type_vehicule, elec, minutes in garees:
        rang = used.get((parking, category), 0)
        used[(parking, category)] = rang + 1
        if (parking, category) not in ids or rang >= len(ids[(parking, category)]):
            continue
        slot_id = ids[(parking, category)][rang]
        fin = ts(utc_now() + timedelta(minutes=minutes)) if minutes != 0 else "1900-01-01 00:00:00"
        conn.execute("UPDATE slot_table SET slot_occupied = 1, fin_occupation = ? WHERE slot_id = ?", (fin, slot_id))
        conn.execute("INSERT OR IGNORE INTO vehicle_table (no_plaque, proprietaire, type_vehicule, elec) VALUES (?, ?, ?, ?)", (plaque, proprio, type_vehicule, elec))
        conn.execute("UPDATE vehicle_table SET current_slot = ? WHERE no_plaque = ?", (slot_id, plaque))
    #Les places 8 et 9 (déjà en base) font partie de « Le Parking » : elles sont dessinées dans le parking, plus dans la rue
    conn.execute("INSERT OR REPLACE INTO meta_table (cle, valeur) VALUES ('parking_slots_v1', '1')")
    conn.commit()
    conn.close()

### Réservations des usagers

def init_reservation_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    #status : booked (réservée) → parked (véhicule arrivé) → finished (parti) ; ou cancelled
    conn.execute(
        "CREATE TABLE IF NOT EXISTS reservation_table ("\
        " reservation_id INTEGER PRIMARY KEY AUTOINCREMENT,"\
        " username char[30] NOT NULL,"\
        " slot_id INTEGER NOT NULL,"\
        " parking char[20] DEFAULT NULL,"\
        " no_plaque char[9] NOT NULL,"\
        " type_vehicule char[4] NOT NULL,"\
        " nom char[40],"\
        " prenom char[40],"\
        " start_at timestamp NOT NULL,"\
        " end_at timestamp NOT NULL,"\
        " amount float NOT NULL,"\
        " status char[10] NOT NULL DEFAULT 'booked',"\
        " created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,"\
        " checkin_at timestamp DEFAULT NULL,"\
        " checkout_at timestamp DEFAULT NULL)"
    )
    conn.commit()
    conn.close()

### Profil des usagers (nom, prénom, véhicule, notifications)

def init_profile_table(DB_PATH: Path) -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS profile_table ("\
        " username char[30] PRIMARY KEY,"\
        " nom char[40],"\
        " prenom char[40],"\
        " no_plaque char[9],"\
        " type_vehicule char[4] NOT NULL DEFAULT 'voit',"\
        " elec boolean DEFAULT false,"\
        " pmr boolean DEFAULT false,"\
        " notif_reservations boolean DEFAULT true,"\
        " notif_expiration boolean DEFAULT true,"\
        " notif_fines boolean DEFAULT true)"
    )
    row = conn.execute("SELECT username FROM profile_table").fetchone()
    if row is None:
        conn.executemany(
            "INSERT INTO profile_table (username, nom, prenom, no_plaque, type_vehicule, elec, pmr) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [("ab123456", "Dupont", "Alice", "QR345ST", "voit", False, False),
             ("cd789", "Martin", "Bruno", "UV678WX", "voit", True, False),
             ("ef321", "Leroy", "Chloé", "DE890FG", "voit", False, False),
             ("gh654", "Garcia", "Hugo", "HI123JK", "voit", False, True)]
        )
    conn.commit()
    conn.close()

class DataPayload(BaseModel):
    value: str


def startup_event() -> None:
    init_meta_table(DB_PATH)
    init_slot_table(DB_PATH)
    init_vehicule_table(DB_PATH)
    init_parking_table(DB_PATH)
    init_rue_table(DB_PATH)
    init_batiment_table(DB_PATH)
    init_plan_tables(DB_PATH)
    init_infraction_table(DB_PATH)
    init_fine_table(DB_PATH)
    init_reservation_table(DB_PATH)
    init_profile_table(DB_PATH)
    init_parking_slots(DB_PATH)
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
    reserved = reserved_slot_ids(conn)
    roads = conn.execute("SELECT * FROM plan_road_table").fetchall()
    buildings = conn.execute("SELECT * FROM plan_building_table").fetchall()
    zones = conn.execute("SELECT * FROM plan_zone_table").fetchall()
    conn.close()

    ref_lat = sum(r["slot_lat"] for r in slots) / len(slots) if slots else 0.0
    ref_long = sum(r["slot_long"] for r in slots) / len(slots) if slots else 0.0

    spots = []
    for r in slots:
        #Les places d'un parking ne sont pas dessinées une à une : elles sont comptées dans le parking
        if r["parking"] is not None:
            continue
        x, y = position_plan(r["slot_x"], r["slot_y"], r["slot_lat"], r["slot_long"], ref_lat, ref_long)
        moto = r["slot_type"] == "moto"
        spots.append({
            "id": str(r["slot_id"]),
            "x": x, "y": y,
            "width": 1.2 if moto else 2.5,
            "length": 2.4 if moto else 5.0,
            "angle": r["slot_angle"] or 0,
            "status": "occupied" if r["slot_occupied"] else ("reserved" if r["slot_id"] in reserved else "free"),
        })

    for lot in lots:
        x, y = position_plan(lot["parking_x"], lot["parking_y"], lot["parking_lat"], lot["parking_long"], ref_lat, ref_long)
        places = [r for r in slots if r["parking"] == lot["parking_name"]]
        #Un parking est complet quand il n'a plus aucune place libre (ni occupée, ni réservée en ce moment)
        complet = len(places) > 0 and all(r["slot_occupied"] or r["slot_id"] in reserved for r in places)
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
    reserved = reserved_slot_ids(conn)
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
        "reserved": (not r["slot_occupied"]) and r["slot_id"] in reserved,
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
        "no": r["fine_no"],
        "paid": bool(r["paye"]),
        "paid_at": r["paye_le"],
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
    plate = norm_plate(payload.plate)
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



########## Espace usager ##########
#Toutes les routes /me/... sont réservées aux usagers (type "user")


### Profil : nom, prénom, véhicule et notifications

def load_profile(conn: sqlite3.Connection, username: str) -> dict:
    row = conn.execute("SELECT * FROM profile_table WHERE username = ?", (username,)).fetchone()
    if row is None:
        #Pas encore de profil : on part du nom et du prénom du compte
        nom, prenom = "", ""
        uconn = sqlite3.connect(USER_DB_PATH)
        compte = uconn.execute("SELECT nom, prenom FROM user_table WHERE username = ?", (username,)).fetchone()
        uconn.close()
        if compte is not None:
            nom, prenom = compte[0] or "", compte[1] or ""
        return {"username": username, "nom": nom, "prenom": prenom, "plate": "", "vehicle_type": "voit",
                "elec": False, "pmr": False,
                "notifications": {"reservations": True, "expiration": True, "fines": True}}
    return {"username": username, "nom": row["nom"] or "", "prenom": row["prenom"] or "",
            "plate": row["no_plaque"] or "", "vehicle_type": row["type_vehicule"] or "voit",
            "elec": bool(row["elec"]), "pmr": bool(row["pmr"]),
            "notifications": {"reservations": bool(row["notif_reservations"]),
                              "expiration": bool(row["notif_expiration"]),
                              "fines": bool(row["notif_fines"])}}

@app.get("/me/profile")
def get_my_profile() -> dict:
    require_user()
    conn = open_db()
    data = load_profile(conn, current_user.username)
    conn.close()
    return {"data": data}

class ProfilePayload(BaseModel):
    nom: str = ""
    prenom: str = ""
    plate: str = ""
    vehicle_type: str = "voit"
    elec: bool = False
    pmr: bool = False
    notif_reservations: bool = True
    notif_expiration: bool = True
    notif_fines: bool = True

@app.put("/me/profile")
def update_my_profile(payload: ProfilePayload) -> dict:
    require_user()
    if payload.vehicle_type not in ("voit", "moto"):
        raise HTTPException(status_code=400, detail="Type de véhicule inconnu")
    plate = norm_plate(payload.plate)
    if plate != "" and not re.fullmatch(r"[A-Z0-9]{4,9}", plate):
        raise HTTPException(status_code=400, detail="Plaque d'immatriculation invalide")
    conn = open_db()
    if plate != "":
        #Le véhicule est enregistré au nom de l'usager (sauf s'il appartient déjà à quelqu'un d'autre)
        vehicule = conn.execute("SELECT proprietaire FROM vehicle_table WHERE no_plaque = ?", (plate,)).fetchone()
        if vehicule is not None and vehicule["proprietaire"] != current_user.username:
            conn.close()
            raise HTTPException(status_code=409, detail="Cette plaque est enregistrée au nom d'un autre usager")
        conn.execute(
            "INSERT INTO vehicle_table (no_plaque, proprietaire, type_vehicule, elec) VALUES (?, ?, ?, ?) "\
            "ON CONFLICT(no_plaque) DO UPDATE SET type_vehicule = excluded.type_vehicule, elec = excluded.elec",
            (plate, current_user.username, payload.vehicle_type, payload.elec)
        )
    conn.execute(
        "INSERT INTO profile_table (username, nom, prenom, no_plaque, type_vehicule, elec, pmr, notif_reservations, notif_expiration, notif_fines) "\
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "\
        "ON CONFLICT(username) DO UPDATE SET nom = excluded.nom, prenom = excluded.prenom, no_plaque = excluded.no_plaque, "\
        "type_vehicule = excluded.type_vehicule, elec = excluded.elec, pmr = excluded.pmr, "\
        "notif_reservations = excluded.notif_reservations, notif_expiration = excluded.notif_expiration, notif_fines = excluded.notif_fines",
        (current_user.username, payload.nom.strip(), payload.prenom.strip(), plate, payload.vehicle_type, payload.elec, payload.pmr,
         payload.notif_reservations, payload.notif_expiration, payload.notif_fines)
    )
    conn.commit()
    data = load_profile(conn, current_user.username)
    conn.close()
    return {"data": data}


### Parkings et places de rue (sans aucune info sur les véhicules garés)

@app.get("/me/parkings")
def get_my_parkings() -> dict:
    require_user()
    conn = open_db()
    reserved = reserved_slot_ids(conn)
    parkings = conn.execute("SELECT * FROM parking_table ORDER BY parking_name").fetchall()
    slots = conn.execute("SELECT * FROM slot_table WHERE parking IS NOT NULL ORDER BY slot_id").fetchall()
    conn.close()
    data = []
    for parking in parkings:
        categories = {}
        for r in slots:
            if r["parking"] != parking["parking_name"]:
                continue
            code = slot_category(r["slot_pmr"], r["slot_type"], r["slot_elec"])
            cat = categories.setdefault(code, {"code": code, "label": CATEGORY_LABELS[code], "total": 0, "free": 0, "tariff": r["slot_tarif"]})
            cat["total"] += 1
            if not r["slot_occupied"] and r["slot_id"] not in reserved:
                cat["free"] += 1
        liste = sorted(categories.values(), key=lambda c: list(CATEGORY_LABELS).index(c["code"]))
        data.append({"name": parking["parking_name"], "address": parking["parking_adresse"],
                     "total": sum(c["total"] for c in liste), "free": sum(c["free"] for c in liste), "categories": liste})
    return {"now": ts(utc_now()), "N": len(data), "data": data}

@app.get("/me/slots")
def get_my_slots() -> dict:
    require_user()
    conn = open_db()
    now = ts(utc_now())
    reserved = reserved_slot_ids(conn)
    rows = conn.execute("SELECT * FROM slot_table WHERE parking IS NULL ORDER BY slot_id").fetchall()
    bookings = conn.execute(
        "SELECT slot_id, start_at, end_at FROM reservation_table WHERE status IN ('booked', 'parked') AND end_at > ? ORDER BY start_at", (now,)
    ).fetchall()
    conn.close()
    data = []
    for r in rows:
        status = "occupied" if r["slot_occupied"] else ("reserved" if r["slot_id"] in reserved else "free")
        data.append({
            "id": r["slot_id"], "type": r["slot_type"], "pmr": bool(r["slot_pmr"]), "elec": bool(r["slot_elec"]),
            "category": slot_category(r["slot_pmr"], r["slot_type"], r["slot_elec"]),
            "address": r["slot_adresse"], "city": r["slot_ville"], "tariff": r["slot_tarif"], "status": status,
            #Créneaux déjà pris (sans dire par qui)
            "booked": [{"start": b["start_at"], "end": b["end_at"]} for b in bookings if b["slot_id"] == r["slot_id"]],
        })
    return {"now": now, "N": len(data), "data": data}


### Réservations

RESERVATION_SELECT = (
    "SELECT reservation_table.*, slot_table.slot_adresse AS adresse, slot_table.slot_ville AS ville, "\
    "slot_table.slot_pmr AS spmr, slot_table.slot_elec AS selec, slot_table.slot_type AS stype, slot_table.slot_tarif AS tarif "\
    "FROM reservation_table JOIN slot_table ON slot_table.slot_id = reservation_table.slot_id "
)

def reservation_to_dict(r: sqlite3.Row, now: str) -> dict:
    status = r["status"]
    if status == "booked":
        #Réservation non honorée : la date de fin est passée sans que le véhicule soit arrivé
        state = "expired" if r["end_at"] <= now else ("active" if r["start_at"] <= now else "upcoming")
    else:
        state = status
    return {
        "id": r["reservation_id"], "slot_id": r["slot_id"], "parking": r["parking"],
        "category": slot_category(r["spmr"], r["stype"], r["selec"]),
        "location": r["parking"] or ", ".join(x for x in (r["adresse"], r["ville"]) if x),
        "plate": r["no_plaque"], "vehicle_type": r["type_vehicule"], "nom": r["nom"], "prenom": r["prenom"],
        "start": r["start_at"], "end": r["end_at"], "amount": r["amount"], "tariff": r["tarif"],
        "status": status, "state": state,
        "checkin_at": r["checkin_at"], "checkout_at": r["checkout_at"],
    }

def get_my_reservation(conn: sqlite3.Connection, reservation_id: int) -> sqlite3.Row:
    row = conn.execute(RESERVATION_SELECT + "WHERE reservation_id = ? AND username = ?", (reservation_id, current_user.username)).fetchone()
    if row is None:
        conn.close()
        raise HTTPException(status_code=404, detail="Pas de réservation avec cet identifiant")
    return row

@app.get("/me/reservations")
def get_my_reservations() -> dict:
    require_user()
    conn = open_db()
    now = ts(utc_now())
    rows = conn.execute(RESERVATION_SELECT + "WHERE username = ? ORDER BY start_at DESC, reservation_id DESC", (current_user.username,)).fetchall()
    #Véhicules de l'usager actuellement garés (avec ou sans réservation) : pour pouvoir « reprendre la route »
    garees = conn.execute(
        "SELECT vehicle_table.no_plaque AS plaque, vehicle_table.type_vehicule AS vtype, slot_table.slot_id AS slot_id, "\
        "slot_table.parking AS parking, slot_table.slot_adresse AS adresse, slot_table.slot_ville AS ville, slot_table.fin_occupation AS fin "\
        "FROM vehicle_table JOIN slot_table ON slot_table.slot_id = vehicle_table.current_slot WHERE vehicle_table.proprietaire = ?",
        (current_user.username,)
    ).fetchall()
    conn.close()
    return {
        "now": now,
        "data": [reservation_to_dict(r, now) for r in rows],
        "parked": [{"plate": g["plaque"], "vehicle_type": g["vtype"], "slot_id": g["slot_id"], "parking": g["parking"],
                    "location": g["parking"] or ", ".join(x for x in (g["adresse"], g["ville"]) if x),
                    "fin_occupation": g["fin"]} for g in garees],
    }

class ReservationPayload(BaseModel):
    slot_id: int | None = None       #une place de rue précise...
    parking: str | None = None       #...ou une catégorie de place dans un parking (le serveur choisit la place)
    category: str | None = None
    start: str | None = None         #AAAA-MM-JJ HH:MM:SS en UTC ; vide = maintenant
    duration_minutes: int
    plate: str
    vehicle_type: str = "voit"
    nom: str
    prenom: str

def slot_unavailable_reason(conn: sqlite3.Connection, slot: sqlite3.Row, start: datetime, end: datetime, now: datetime) -> str | None:
    #Renvoie la raison pour laquelle la place ne peut pas être réservée sur ce créneau (None = disponible)
    conflit = conn.execute(
        "SELECT reservation_id FROM reservation_table WHERE slot_id = ? AND status IN ('booked', 'parked') AND start_at < ? AND end_at > ?",
        (slot["slot_id"], ts(end), ts(start))
    ).fetchone()
    if conflit is not None:
        return "Cette place est déjà réservée sur ce créneau"
    if slot["slot_occupied"]:
        libre_a = slot["fin_occupation"]
        if start <= now + timedelta(minutes=1) or libre_a <= "1900-01-02" or libre_a > ts(start):
            return "Cette place est occupée"
    return None

@app.post("/me/reservations")
def create_my_reservation(payload: ReservationPayload) -> dict:
    require_user()
    if not (15 <= payload.duration_minutes <= 1440):
        raise HTTPException(status_code=400, detail="La durée doit être comprise entre 15 minutes et 24 heures")
    if payload.vehicle_type not in ("voit", "moto"):
        raise HTTPException(status_code=400, detail="Type de véhicule inconnu")
    nom, prenom = payload.nom.strip(), payload.prenom.strip()
    if nom == "" or prenom == "":
        raise HTTPException(status_code=400, detail="Renseignez votre nom et votre prénom (onglet Profil)")
    plate = norm_plate(payload.plate)
    if not re.fullmatch(r"[A-Z0-9]{4,9}", plate):
        raise HTTPException(status_code=400, detail="Plaque d'immatriculation invalide")

    now = utc_now()
    start = parse_ts(payload.start) if payload.start else now
    if start < now - timedelta(minutes=2):
        raise HTTPException(status_code=400, detail="Le début de la réservation doit être dans le futur")
    if start > now + timedelta(days=7):
        raise HTTPException(status_code=400, detail="On ne peut pas réserver plus de 7 jours à l'avance")
    start = max(start, now)
    end = start + timedelta(minutes=payload.duration_minutes)

    conn = open_db()
    profile = load_profile(conn, current_user.username)

    #Le véhicule doit être le sien et ne pas déjà avoir une réservation (ou une place) sur ce créneau
    vehicule = conn.execute("SELECT proprietaire, current_slot FROM vehicle_table WHERE no_plaque = ?", (plate,)).fetchone()
    if vehicule is not None and vehicule["proprietaire"] != current_user.username:
        conn.close()
        raise HTTPException(status_code=409, detail="Cette plaque est enregistrée au nom d'un autre usager")
    if vehicule is not None and vehicule["current_slot"] is not None and start <= now + timedelta(minutes=1):
        conn.close()
        raise HTTPException(status_code=409, detail="Ce véhicule est déjà stationné : libérez sa place avant de réserver")
    doublon = conn.execute(
        "SELECT reservation_id FROM reservation_table WHERE no_plaque = ? AND status IN ('booked', 'parked') AND start_at < ? AND end_at > ?",
        (plate, ts(end), ts(start))
    ).fetchone()
    if doublon is not None:
        conn.close()
        raise HTTPException(status_code=409, detail="Ce véhicule a déjà une réservation sur ce créneau")

    #Places candidates : une place précise, ou toutes celles de la catégorie demandée dans le parking
    if payload.slot_id is not None:
        candidates = conn.execute("SELECT * FROM slot_table WHERE slot_id = ?", (payload.slot_id,)).fetchall()
        if len(candidates) == 0:
            conn.close()
            raise HTTPException(status_code=404, detail="Pas de place avec cet identifiant")
        if candidates[0]["parking"] is not None:
            conn.close()
            raise HTTPException(status_code=400, detail="Cette place fait partie d'un parking : réservez une catégorie de place dans ce parking")
    elif payload.parking and payload.category:
        if payload.category not in CATEGORY_LABELS:
            conn.close()
            raise HTTPException(status_code=400, detail="Catégorie de place inconnue")
        rows = conn.execute("SELECT * FROM slot_table WHERE parking = ? ORDER BY slot_id", (payload.parking,)).fetchall()
        candidates = [r for r in rows if slot_category(r["slot_pmr"], r["slot_type"], r["slot_elec"]) == payload.category]
        if len(candidates) == 0:
            conn.close()
            raise HTTPException(status_code=404, detail="Ce parking n'a pas de place de cette catégorie")
    else:
        conn.close()
        raise HTTPException(status_code=400, detail="Indiquez une place ou un parking et une catégorie")

    first = candidates[0]
    if first["slot_type"] != payload.vehicle_type:
        conn.close()
        raise HTTPException(status_code=400, detail="Ce véhicule ne correspond pas au type de place")
    if first["slot_pmr"] and not profile["pmr"]:
        conn.close()
        raise HTTPException(status_code=403, detail="Place réservée aux titulaires d'une carte mobilité inclusion (à indiquer dans votre profil)")
    if first["slot_elec"] and not profile["elec"]:
        conn.close()
        raise HTTPException(status_code=403, detail="Place équipée d'une borne de recharge : indiquez dans votre profil que votre véhicule est électrique")

    choisie, raison = None, "Aucune place disponible"
    for slot in candidates:
        raison = slot_unavailable_reason(conn, slot, start, end, now)
        if raison is None:
            choisie = slot
            break
    if choisie is None:
        conn.close()
        if payload.parking:
            raise HTTPException(status_code=409, detail="Plus aucune place " + CATEGORY_LABELS[payload.category] + " disponible dans ce parking sur ce créneau")
        raise HTTPException(status_code=409, detail=raison)

    montant = round(float(choisie["slot_tarif"]) * payload.duration_minutes / 60, 2)
    cur = conn.execute(
        "INSERT INTO reservation_table (username, slot_id, parking, no_plaque, type_vehicule, nom, prenom, start_at, end_at, amount, status) "\
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'booked')",
        (current_user.username, choisie["slot_id"], choisie["parking"], plate, payload.vehicle_type, nom, prenom, ts(start), ts(end), montant)
    )
    conn.commit()
    row = conn.execute(RESERVATION_SELECT + "WHERE reservation_id = ?", (cur.lastrowid,)).fetchone()
    data = reservation_to_dict(row, ts(now))
    conn.close()
    return {"data": data}

def free_vehicle_slot(conn: sqlite3.Connection, plate: str) -> None:
    #Le véhicule quitte sa place : la place est libérée et la réservation éventuelle est terminée
    garee = conn.execute("SELECT current_slot FROM vehicle_table WHERE no_plaque = ?", (plate,)).fetchone()
    if garee is None or garee["current_slot"] is None:
        return
    conn.execute("UPDATE slot_table SET slot_occupied = 0, fin_occupation = '1900-01-01 00:00:00' WHERE slot_id = ?", (garee["current_slot"],))
    conn.execute("UPDATE vehicle_table SET current_slot = NULL WHERE no_plaque = ?", (plate,))
    conn.execute(
        "UPDATE reservation_table SET status = 'finished', checkout_at = ? WHERE no_plaque = ? AND slot_id = ? AND status = 'parked'",
        (ts(utc_now()), plate, garee["current_slot"])
    )

@app.post("/me/reservations/{reservation_id}/checkin")
def checkin_my_reservation(reservation_id: int) -> dict:
    #Le véhicule arrive : la place devient occupée, payée jusqu'à la fin de la réservation
    require_user()
    conn = open_db()
    r = get_my_reservation(conn, reservation_id)
    now = utc_now()
    if r["status"] != "booked":
        conn.close()
        raise HTTPException(status_code=409, detail="Cette réservation n'est plus à l'état « réservée »")
    if now < parse_ts(r["start_at"]) - timedelta(minutes=10):
        conn.close()
        raise HTTPException(status_code=400, detail="Trop tôt : vous pouvez vous garer 10 minutes avant le début de la réservation")
    if now >= parse_ts(r["end_at"]):
        conn.close()
        raise HTTPException(status_code=400, detail="Cette réservation est terminée")
    slot = conn.execute("SELECT * FROM slot_table WHERE slot_id = ?", (r["slot_id"],)).fetchone()
    if slot["slot_occupied"]:
        conn.close()
        raise HTTPException(status_code=409, detail="La place est encore occupée par un autre véhicule")
    vehicule = conn.execute("SELECT proprietaire, current_slot FROM vehicle_table WHERE no_plaque = ?", (r["no_plaque"],)).fetchone()
    if vehicule is not None and vehicule["proprietaire"] != current_user.username:
        conn.close()
        raise HTTPException(status_code=409, detail="Cette plaque est enregistrée au nom d'un autre usager")
    if vehicule is not None and vehicule["current_slot"] is not None:
        conn.close()
        raise HTTPException(status_code=409, detail="Ce véhicule est déjà stationné sur une autre place")
    conn.execute(
        "INSERT INTO vehicle_table (no_plaque, proprietaire, type_vehicule, elec) VALUES (?, ?, ?, ?) "\
        "ON CONFLICT(no_plaque) DO NOTHING",
        (r["no_plaque"], current_user.username, r["type_vehicule"], bool(slot["slot_elec"]))
    )
    conn.execute("UPDATE vehicle_table SET current_slot = ? WHERE no_plaque = ?", (r["slot_id"], r["no_plaque"]))
    conn.execute("UPDATE slot_table SET slot_occupied = 1, fin_occupation = ? WHERE slot_id = ?", (r["end_at"], r["slot_id"]))
    conn.execute("UPDATE reservation_table SET status = 'parked', checkin_at = ? WHERE reservation_id = ?", (ts(now), reservation_id))
    conn.commit()
    row = conn.execute(RESERVATION_SELECT + "WHERE reservation_id = ?", (reservation_id,)).fetchone()
    data = reservation_to_dict(row, ts(now))
    conn.close()
    return {"data": data}

@app.post("/me/reservations/{reservation_id}/checkout")
def checkout_my_reservation(reservation_id: int) -> dict:
    require_user()
    conn = open_db()
    r = get_my_reservation(conn, reservation_id)
    if r["status"] != "parked":
        conn.close()
        raise HTTPException(status_code=409, detail="Ce véhicule n'est pas stationné sur cette réservation")
    free_vehicle_slot(conn, r["no_plaque"])
    conn.commit()
    row = conn.execute(RESERVATION_SELECT + "WHERE reservation_id = ?", (reservation_id,)).fetchone()
    data = reservation_to_dict(row, ts(utc_now()))
    conn.close()
    return {"data": data}

@app.post("/me/reservations/{reservation_id}/cancel")
def cancel_my_reservation(reservation_id: int) -> dict:
    require_user()
    conn = open_db()
    r = get_my_reservation(conn, reservation_id)
    if r["status"] != "booked":
        conn.close()
        raise HTTPException(status_code=409, detail="Seule une réservation non commencée peut être annulée")
    conn.execute("UPDATE reservation_table SET status = 'cancelled' WHERE reservation_id = ?", (reservation_id,))
    conn.commit()
    row = conn.execute(RESERVATION_SELECT + "WHERE reservation_id = ?", (reservation_id,)).fetchone()
    data = reservation_to_dict(row, ts(utc_now()))
    conn.close()
    return {"data": data}

@app.post("/me/vehicles/{plate}/leave")
def leave_my_vehicle(plate: str) -> dict:
    #Reprendre la route avec un véhicule garé sans réservation
    require_user()
    plate = norm_plate(plate)
    conn = open_db()
    vehicule = conn.execute("SELECT proprietaire, current_slot FROM vehicle_table WHERE no_plaque = ?", (plate,)).fetchone()
    if vehicule is None or vehicule["proprietaire"] != current_user.username:
        conn.close()
        raise HTTPException(status_code=404, detail="Pas de véhicule avec cette plaque")
    if vehicule["current_slot"] is None:
        conn.close()
        raise HTTPException(status_code=409, detail="Ce véhicule n'est pas stationné")
    free_vehicle_slot(conn, plate)
    conn.commit()
    conn.close()
    return {"data": {"plate": plate}}


### Contraventions reçues (véhicules de l'usager) et paiement

def my_plates(conn: sqlite3.Connection) -> list:
    plaques = {r[0] for r in conn.execute("SELECT no_plaque FROM vehicle_table WHERE proprietaire = ?", (current_user.username,))}
    profil = conn.execute("SELECT no_plaque FROM profile_table WHERE username = ?", (current_user.username,)).fetchone()
    if profil is not None and profil[0]:
        plaques.add(profil[0])
    return sorted(plaques)

@app.get("/me/fines")
def get_my_fines() -> dict:
    require_user()
    conn = open_db()
    plaques = my_plates(conn)
    rows = []
    if plaques:
        marques = ",".join("?" * len(plaques))
        rows = conn.execute(
            "SELECT fine_table.*, offense_table.label AS label FROM fine_table "\
            "LEFT JOIN offense_table ON offense_table.code = fine_table.offense "\
            "WHERE no_plaque IN (" + marques + ") ORDER BY fine_no DESC", plaques
        ).fetchall()
    conn.close()
    data = [fine_to_dict(r) for r in rows]
    return {"N": len(data), "data": data}

@app.post("/me/fines/{fine_no}/pay")
def pay_my_fine(fine_no: int) -> dict:
    #Le paiement est simulé : la contravention est simplement marquée comme payée
    require_user()
    conn = open_db()
    plaques = my_plates(conn)
    row = conn.execute(
        "SELECT fine_table.*, offense_table.label AS label FROM fine_table "\
        "LEFT JOIN offense_table ON offense_table.code = fine_table.offense WHERE fine_no = ?", (fine_no,)
    ).fetchone()
    if row is None or row["no_plaque"] not in plaques:
        conn.close()
        raise HTTPException(status_code=404, detail="Pas de contravention avec cet identifiant")
    if row["paye"]:
        conn.close()
        raise HTTPException(status_code=409, detail="Cette contravention est déjà payée")
    conn.execute("UPDATE fine_table SET paye = 1, paye_le = ? WHERE fine_no = ?", (ts(utc_now()), fine_no))
    conn.commit()
    row = conn.execute(
        "SELECT fine_table.*, offense_table.label AS label FROM fine_table "\
        "LEFT JOIN offense_table ON offense_table.code = fine_table.offense WHERE fine_no = ?", (fine_no,)
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