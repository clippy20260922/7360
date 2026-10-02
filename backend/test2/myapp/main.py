from fastapi import FastAPI
from sqlmodel import Field, SessionDep, SQLModel, create_engine, select

app = FastAPI()

class Place(SQLModel, table=True):
    id : int = Field(primary_key=True)
    type_vehicule : int = Field(index=True)
    occupe : bool = Field(index=True)
    lat : float = Field(index=False)
    long : float = Field(index=False)
    parking : str | None = Field(index=True)
    place_pmr : bool = Field(index=True)
    place_elec : bool = Field(index=True)

@app.get("/")
def main():
    return {"message": "Hello World"}

#récup les infos d'une place
@app.get("/Place/{place_id}") 
def get_place(place_id: int, session: SessionDep) -> Place:
    place = session.get(Place, place_id)
    if not place:
        print("Pas de place pour cet ID")
    return place

#avoir la liste des places libres
@app.get("/Place/libres/")
def get_free_place(session: SessionDep) -> list(Place) #remplacer la sortie plus tard
    statement = select(Place).where(Place.occupe == False)
    results = session.exec(statement)
    for place in results :
        print("Place ", place.id, " aux coordonnées lat=", place.lat, "; long=", place.long)

#avoir la liste des places pmr libres
@app.get("/Place/libres/")
def get_free_place(session: SessionDep) -> list(Place) # remplacer la sortie plus tard
    statement = select(Place).where(Place.occupe == False).where(Place.place_pmr == True) 
    results = session.exec(statement)
    if place.size() == 0  :
         print("Pas de place PMR libre")
    else :
        print("Nombre de place PMR libre = ", place.size())
        for place in results :
            print("Place ", place.id, " aux coordonnées lat=", place.lat, "; long=", place.long)

#modifie l'occupation d'une place en "occupée"
@app.patch("Place/{place_id}")
def maj_place_occupe(place_id : int, place : Place, session : SessionDep) -> Place :
    place_a_traiter = session.get(Place, place_id) # récup la place avec id place_id
    if not place:
            print("Pas de place pour cet ID")
    place_a_traiter.occupe = True
    session.add(place_a_traiter)
    session.commit()
    session.refresh()
    return place_a_traiter
    #place_a_traiter.sqlmodel_update() #comment updater bien

#modifie l'occupation d'une place en "libre"
@app.patch("Place/{place_id}")
def maj_place_occupe(place_id : int, place : Place, session : SessionDep) -> Place :
    place_a_traiter = session.get(Place, place_id) # récup la place avec id place_id
    if not place:
            print("Pas de place pour cet ID")
    place_a_traiter.occupe = False
    session.add(place_a_traiter)
    session.commit()
    session.refresh()
    return place_a_traiter
    #place_a_traiter.sqlmodel_update() #comment updater bien
