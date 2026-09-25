from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel, Field, model_validator
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
    score: int = Field(..., ge=1, le=5) # Validates score is between 1 and 5
    review: str | None = None

    @model_validator(mode='after')
    def check_exclusive_arc(self):
        # ^ (XOR) ensures exactly one is True. If both are given, or neither is given, it fails.
        if bool(self.rider_id) == bool(self.driver_id):
            raise ValueError('Must provide exactly one of rider_id or driver_id')
        return self

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
    try:
        query = text("""
            UPDATE rides 
            SET status = 'accepted', driver_id = :driver_id 
            WHERE ride_id = :ride_id AND status = 'requested' 
            RETURNING ride_id;
        """)
        result = db.execute(query, {"driver_id": req.driver_id, "ride_id": ride_id})
        
        # If the ride doesn't exist OR isn't in 'requested' state, it modifies 0 rows
        if not result.fetchone():
            raise HTTPException(
                status_code=400, 
                detail="Ride not found or is no longer available."
            )
            
        db.commit()
        return {"message": f"Ride {ride_id} accepted successfully."}
    except DatabaseError as e:
        db.rollback()
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