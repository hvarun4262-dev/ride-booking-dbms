from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel
from app.db import get_db

router = APIRouter(prefix="/rides", tags=["Rides"])

# --- Pydantic Schemas ---
class RideRequestSchema(BaseModel):
    rider_id: int
    city: str
    pickup_address: str
    dropoff_address: str
    pickup_lat: float
    pickup_lng: float
    dropoff_lat: float
    dropoff_lng: float
    requested_vehicle_type: str # 'bike', 'auto', 'mini', 'sedan', 'suv'

class DriverActionSchema(BaseModel):
    driver_id: int

class PaymentSchema(BaseModel):
    amount: float

# --- Endpoints ---

@router.post("/request")
def request_ride(payload: RideRequestSchema, db: Session = Depends(get_db)):
    """Creates a ride, computes fare server-side, and matches nearest driver."""
    
    # 1. Server-side distance calculation (rough approximation for fare)
    distance_km = ((payload.pickup_lat - payload.dropoff_lat)**2 + (payload.pickup_lng - payload.dropoff_lng)**2)**0.5 * 111.32
    distance_km = max(0.1, round(distance_km, 2)) # Ensure it passes the > 0 DB constraint
    
    # 2. Server-side Fare & Surge Logic
    BASE_FARE = 50.0
    PER_KM_RATE = 15.0
    
    # Check demand for surge (active rides vs available drivers in that city)
    active_rides = db.execute(text("SELECT COUNT(*) FROM rides WHERE status IN ('requested', 'accepted', 'ongoing')")).scalar()
    available_drivers = db.execute(text("SELECT COUNT(*) FROM drivers WHERE status = 'available' AND city = :city"), {"city": payload.city}).scalar()
    
    surge_multiplier = 1.5 if (available_drivers > 0 and active_rides / available_drivers > 1.2) else 1.0
    calculated_fare = round((BASE_FARE + (distance_km * PER_KM_RATE)) * surge_multiplier, 2)

    # 3. Find Nearest Available Driver (Filters by city and vehicle_type)
    nearest_driver_query = text("""
        SELECT driver_id FROM drivers 
        WHERE status = 'available' 
          AND city = :city 
          AND vehicle_type = :v_type
        ORDER BY (
            6371 * acos(
                cos(radians(:pickup_lat)) * cos(radians(current_lat)) * 
                cos(radians(current_lng) - radians(:pickup_lng)) + 
                sin(radians(:pickup_lat)) * sin(radians(current_lat))
            )
        ) ASC LIMIT 1;
    """)
    driver = db.execute(nearest_driver_query, {
        "city": payload.city,
        "v_type": payload.requested_vehicle_type,
        "pickup_lat": payload.pickup_lat, 
        "pickup_lng": payload.pickup_lng
    }).fetchone()
    
    driver_id = driver[0] if driver else None

    # 4. Insert the requested ride (Includes all NOT NULL fields from schema)
    insert_query = text("""
        INSERT INTO rides (
            rider_id, driver_id, city, pickup_address, dropoff_address, 
            pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, 
            requested_vehicle_type, distance_km, surge_multiplier, fare, status
        )
        VALUES (
            :rider_id, :driver_id, :city, :p_address, :d_address,
            :p_lat, :p_lng, :d_lat, :d_lng, 
            :v_type, :dist, :surge, :fare, 'requested'
        )
        RETURNING ride_id;
    """)
    
    result = db.execute(insert_query, {
        "rider_id": payload.rider_id,
        "driver_id": driver_id,
        "city": payload.city,
        "p_address": payload.pickup_address,
        "d_address": payload.dropoff_address,
        "p_lat": payload.pickup_lat,
        "p_lng": payload.pickup_lng,
        "d_lat": payload.dropoff_lat,
        "d_lng": payload.dropoff_lng,
        "v_type": payload.requested_vehicle_type,
        "dist": distance_km,
        "surge": surge_multiplier,
        "fare": calculated_fare
    })
    ride_id = result.scalar()
    db.commit()

    return {
        "message": "Ride requested successfully",
        "ride_id": ride_id,
        "matched_driver": driver_id,
        "fare_estimate": calculated_fare,
        "surge_multiplier": surge_multiplier
    }

@router.post("/{ride_id}/accept")
def accept_ride(ride_id: int, payload: DriverActionSchema, db: Session = Depends(get_db)):
    """Driver accepts the ride, using FOR UPDATE lock to prevent double-booking."""
    try:
        # Lock the specific ride row
        lock_query = text("SELECT ride_id, status FROM rides WHERE ride_id = :ride_id FOR UPDATE NOWAIT")
        ride = db.execute(lock_query, {"ride_id": ride_id}).fetchone()
        
        if not ride:
            raise HTTPException(status_code=404, detail="Ride not found")
        if ride[1] != 'requested':
            raise HTTPException(status_code=400, detail="Ride is no longer available")
            
        update_query = text("""
            UPDATE rides SET status = 'accepted', driver_id = :driver_id 
            WHERE ride_id = :ride_id
        """)
        db.execute(update_query, {"driver_id": payload.driver_id, "ride_id": ride_id})
        
        db.commit()
        return {"message": "Ride accepted"}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=409, detail="Could not acquire lock or accept ride. It may have been taken.")

@router.post("/{ride_id}/cancel")
def cancel_ride(ride_id: int, db: Session = Depends(get_db)):
    """Cancels a ride and frees up the driver."""
    query = text("""
        UPDATE rides 
        SET status = 'cancelled' 
        WHERE ride_id = :ride_id AND status IN ('requested', 'accepted')
        RETURNING driver_id;
    """)
    result = db.execute(query, {"ride_id": ride_id}).fetchone()
    
    if not result:
        raise HTTPException(status_code=400, detail="Cannot cancel this ride")
        
    db.commit()
    return {"message": "Ride cancelled", "driver_freed": result[0]}

@router.post("/{ride_id}/pay")
def pay_ride(ride_id: int, payload: PaymentSchema, db: Session = Depends(get_db)):
    """Processes payment and finalizes the ride state."""
    insert_payment = text("""
        INSERT INTO payments (ride_id, amount, status) 
        VALUES (:ride_id, :amount, 'completed')
    """)
    try:
        db.execute(insert_payment, {"ride_id": ride_id, "amount": payload.amount})
        
        # Update ride to completed
        update_ride = text("UPDATE rides SET status = 'completed' WHERE ride_id = :ride_id")
        db.execute(update_ride, {"ride_id": ride_id})
        
        db.commit()
        return {"message": "Payment processed successfully"}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e))