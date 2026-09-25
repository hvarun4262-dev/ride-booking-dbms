from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.exc import DatabaseError


# 1. DATABASE SETUP
DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/ride_booking_db"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

app = FastAPI(title="Ride Booking API")


# 2. PYDANTIC SCHEMAS (Input Validation)
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
    score: int
    review: str | None = None

# 3. API ENDPOINTS


@app.post("/rides", status_code=201)
def request_ride(ride: RideRequest, db: Session = Depends(get_db)):
    """Rider requests a new ride."""
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

@app.put("/rides/{ride_id}/accept")
def accept_ride(ride_id: int, req: AcceptRideRequest, db: Session = Depends(get_db)):
    """Driver accepts a ride. DB handles concurrency locking and state validation."""
    try:
        query = text("""
            UPDATE rides 
            SET status = 'accepted', driver_id = :driver_id 
            WHERE ride_id = :ride_id 
            RETURNING ride_id;
        """)
        result = db.execute(query, {"driver_id": req.driver_id, "ride_id": ride_id})
        
        if not result.fetchone():
            raise HTTPException(status_code=404, detail="Ride not found.")
            
        db.commit()
        return {"message": f"Ride {ride_id} accepted successfully by Driver {req.driver_id}."}
    except DatabaseError as e:
        db.rollback()
        # If the DB FSM or double-booking trigger fails, it throws a 400 here automatically!
        raise HTTPException(status_code=400, detail=str(e.orig))

@app.put("/rides/{ride_id}/complete")
def complete_ride(ride_id: int, db: Session = Depends(get_db)):
    """Driver completes the ride. DB auto-updates the history and driver status."""
    try:
        query = text("""
            UPDATE rides SET status = 'completed' 
            WHERE ride_id = :ride_id RETURNING ride_id;
        """)
        result = db.execute(query, {"ride_id": ride_id})
        
        if not result.fetchone():
            raise HTTPException(status_code=404, detail="Ride not found.")
            
        db.commit()
        return {"message": f"Ride {ride_id} completed."}
    except DatabaseError as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e.orig))

@app.post("/rides/{ride_id}/ratings", status_code=201)
def rate_ride(ride_id: int, req: RatingRequest, db: Session = Depends(get_db)):
    """Submit a rating. DB enforces the Exclusive Arc and checks participation."""
    try:
        query = text("""
            INSERT INTO ratings (ride_id, rider_id, driver_id, score, review)
            VALUES (:ride_id, :rider_id, :driver_id, :score, :review)
            RETURNING rating_id;
        """)
        result = db.execute(query, {
            "ride_id": ride_id,
            "rider_id": req.rider_id,
            "driver_id": req.driver_id,
            "score": req.score,
            "review": req.review
        })
        db.commit()
        return {"message": "Rating submitted successfully.", "rating_id": result.scalar()}
    except DatabaseError as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e.orig))