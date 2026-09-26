from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import text
from sqlalchemy.orm import Session
from sqlalchemy.exc import DatabaseError
from app.db import get_db

router = APIRouter(prefix="/rides", tags=["Transactional"])

class RideRequest(BaseModel):
    rider_id: int
    pickup_address: str
    dropoff_address: str
    pickup_lat: float
    pickup_lng: float
    dropoff_lat: float
    dropoff_lng: float
    requested_vehicle_type: str
    distance_km: float
    fare: float

class AcceptRideRequest(BaseModel):
    driver_id: int

class RatingRequest(BaseModel):
    rider_id: int | None = None
    driver_id: int | None = None
    score: int = Field(..., ge=1, le=5)
    review: str | None = None

    @model_validator(mode='after')
    def check_exclusive_arc(self):
        if bool(self.rider_id) == bool(self.driver_id):
            raise ValueError('Must provide exactly one of rider_id or driver_id')
        return self

@router.post("/", status_code=201)
def request_ride(ride: RideRequest, db: Session = Depends(get_db)):
    try:
        query = text("""
            INSERT INTO rides (
                rider_id, city, pickup_address, dropoff_address, 
                pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, 
                requested_vehicle_type, distance_km, fare
            ) VALUES (
                :rider_id, 'Bengaluru', :pickup_address, :dropoff_address, 
                :pickup_lat, :pickup_lng, :dropoff_lat, :dropoff_lng, 
                :requested_vehicle_type, :distance_km, :fare
            ) RETURNING ride_id;
        """)
        result = db.execute(query, ride.model_dump())
        db.commit()
        return {"message": "Ride requested successfully", "ride_id": result.scalar()}
    except DatabaseError as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e.orig))

@router.put("/{ride_id}/accept")
def accept_ride(ride_id: int, req: AcceptRideRequest, db: Session = Depends(get_db)):
    try:
        query = text("""
            UPDATE rides 
            SET status = 'accepted', driver_id = :driver_id 
            WHERE ride_id = :ride_id AND status = 'requested'
            RETURNING ride_id;
        """)
        result = db.execute(query, {"driver_id": req.driver_id, "ride_id": ride_id})
        if not result.fetchone():
            raise HTTPException(status_code=400, detail="Ride not found or unavailable.")
        db.commit()
        return {"message": f"Ride {ride_id} accepted."}
    except DatabaseError as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e.orig))

@router.put("/{ride_id}/complete")
def complete_ride(ride_id: int, db: Session = Depends(get_db)):
    try:
        query = text("UPDATE rides SET status = 'completed' WHERE ride_id = :ride_id RETURNING ride_id;")
        result = db.execute(query, {"ride_id": ride_id})
        if not result.fetchone():
            raise HTTPException(status_code=404, detail="Ride not found.")
        db.commit()
        return {"message": f"Ride {ride_id} completed."}
    except DatabaseError as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e.orig))

@router.post("/{ride_id}/ratings", status_code=201)
def rate_ride(ride_id: int, req: RatingRequest, db: Session = Depends(get_db)):
    try:
        query = text("""
            INSERT INTO ratings (ride_id, rider_id, driver_id, score, review)
            VALUES (:ride_id, :rider_id, :driver_id, :score, :review)
            RETURNING rating_id;
        """)
        result = db.execute(query, {"ride_id": ride_id, **req.model_dump()})
        db.commit()
        return {"message": "Rating submitted.", "rating_id": result.scalar()}
    except DatabaseError as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e.orig))