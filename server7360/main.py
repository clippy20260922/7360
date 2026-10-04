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
            id INTEGER PRIMARY KEY CHECK (id = 1),
            value TEXT NOT NULL
        )
        """
    )
    row = conn.execute("SELECT value FROM app_data WHERE id = 1").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO app_data (id, value) VALUES (1, 'hello from sqlite')"
        )
    conn.commit()
    conn.close()


class DataPayload(BaseModel):
    value: str


@app.on_event("startup")
def startup_event() -> None:
    init_db()


@app.get("/data")
def get_data() -> dict:
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT value FROM app_data WHERE id = 1").fetchone()
    conn.close()
    if row is None:
        return {"value": ""}
    return {"value": row[0]}


@app.post("/data")
def set_data(payload: DataPayload) -> dict:
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "UPDATE app_data SET value = ? WHERE id = 1",
        (payload.value,),
    )
    conn.commit()
    conn.close()
    return {"value": payload.value}


@app.get("/")
def root() -> dict:
    return {"message": "Simple SQLite API is running"}
