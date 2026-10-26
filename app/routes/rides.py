
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.db import get_db


router = APIRouter(prefix="/rides", tags=["Rides"])


# -------------------- REQUEST SCHEMAS --------------------

VehicleType = Literal["bike", "auto", "mini", "sedan", "suv"]


class RideRequestSchema(BaseModel):
    rider_id: int = Field(gt=0)
    city: str = Field(min_length=1, max_length=50)
    pickup_address: str = Field(min_length=1)
    dropoff_address: str = Field(min_length=1)
    pickup_lat: float = Field(ge=-90, le=90)
    pickup_lng: float = Field(ge=-180, le=180)
    dropoff_lat: float = Field(ge=-90, le=90)
    dropoff_lng: float = Field(ge=-180, le=180)
    requested_vehicle_type: VehicleType


class DriverActionSchema(BaseModel):
    driver_id: int = Field(gt=0)


class PaymentSchema(BaseModel):
    amount: float = Field(ge=0)


# -------------------- REQUEST A RIDE --------------------

@router.post("/request", status_code=201)
def request_ride(
    payload: RideRequestSchema,
    db: Session = Depends(get_db),
):
    """Calculate the fare, match an available driver, and create a ride."""

    try:
        # Approximate distance in kilometres.
        lat_diff = payload.pickup_lat - payload.dropoff_lat
        lng_diff = payload.pickup_lng - payload.dropoff_lng

        distance_km = round(
            ((lat_diff ** 2 + lng_diff ** 2) ** 0.5) * 111.32,
            2,
        )
        distance_km = max(0.1, distance_km)

        # Fare calculation.
        base_fare = 50.0
        per_km_rate = 15.0

        active_rides = db.execute(
            text("""
                SELECT COUNT(*)
                FROM rides
                WHERE city = :city
                  AND status IN (
                      'requested', 'accepted', 'ongoing'
                  )
            """),
            {"city": payload.city},
        ).scalar_one()

        available_drivers = db.execute(
            text("""
                SELECT COUNT(*)
                FROM drivers
                WHERE status = 'available'
                  AND city = :city
            """),
            {"city": payload.city},
        ).scalar_one()

        surge_multiplier = (
            1.5
            if available_drivers > 0
            and active_rides / available_drivers > 1.2
            else 1.0
        )

        calculated_fare = round(
            (base_fare + distance_km * per_km_rate)
            * surge_multiplier,
            2,
        )

        # Find the nearest available driver with the requested vehicle.
        driver = db.execute(
            text("""
                SELECT driver_id
                FROM drivers
                WHERE status = 'available'
                  AND city = :city
                  AND vehicle_type = CAST(
                      :v_type AS vehicle_type_enum
                  )
                  AND current_lat IS NOT NULL
                  AND current_lng IS NOT NULL
                ORDER BY (
                    6371 * acos(
                        LEAST(1.0, GREATEST(-1.0,
                            cos(radians(:pickup_lat))
                            * cos(radians(current_lat))
                            * cos(
                                radians(current_lng)
                                - radians(:pickup_lng)
                            )
                            + sin(radians(:pickup_lat))
                            * sin(radians(current_lat))
                        ))
                    )
                ) ASC
                LIMIT 1
                FOR UPDATE SKIP LOCKED
            """),
            {
                "city": payload.city,
                "v_type": payload.requested_vehicle_type,
                "pickup_lat": payload.pickup_lat,
                "pickup_lng": payload.pickup_lng,
            },
        ).fetchone()

        driver_id = driver[0] if driver else None

        # Create the ride.
        result = db.execute(
            text("""
                INSERT INTO rides (
                    rider_id,
                    driver_id,
                    city,
                    pickup_address,
                    dropoff_address,
                    pickup_lat,
                    pickup_lng,
                    dropoff_lat,
                    dropoff_lng,
                    requested_vehicle_type,
                    distance_km,
                    surge_multiplier,
                    fare,
                    status
                )
                VALUES (
                    :rider_id,
                    :driver_id,
                    :city,
                    :p_address,
                    :d_address,
                    :p_lat,
                    :p_lng,
                    :d_lat,
                    :d_lng,
                    CAST(:v_type AS vehicle_type_enum),
                    :dist,
                    :surge,
                    :fare,
                    CAST('requested' AS ride_status_enum)
                )
                RETURNING ride_id
            """),
            {
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
                "fare": calculated_fare,
            },
        )

        ride_id = result.scalar_one()
        db.commit()

        return {
            "message": "Ride requested successfully",
            "ride_id": ride_id,
            "matched_driver": driver_id,
            "distance_km": distance_km,
            "fare_estimate": calculated_fare,
            "surge_multiplier": surge_multiplier,
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=400,
            detail="Invalid rider or ride data. Check the supplied IDs.",
        )
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Database error while requesting the ride.",
        )


# -------------------- ACCEPT A RIDE --------------------

@router.post("/{ride_id}/accept")
def accept_ride(
    ride_id: int,
    payload: DriverActionSchema,
    db: Session = Depends(get_db),
):
    """Accept a requested ride using a row lock."""

    try:
        ride = db.execute(
            text("""
                SELECT ride_id, status, driver_id, city,
                       requested_vehicle_type
                FROM rides
                WHERE ride_id = :ride_id
                FOR UPDATE
            """),
            {"ride_id": ride_id},
        ).fetchone()

        if not ride:
            raise HTTPException(
                status_code=404,
                detail="Ride not found.",
            )

        if ride[1] != "requested":
            raise HTTPException(
                status_code=400,
                detail="Ride is no longer available.",
            )

        # If a driver was matched, only that driver may accept.
        if ride[2] is not None and ride[2] != payload.driver_id:
            raise HTTPException(
                status_code=403,
                detail="This ride is assigned to another driver.",
            )

        # Lock and verify the selected driver.
        driver = db.execute(
            text("""
                SELECT driver_id
                FROM drivers
                WHERE driver_id = :driver_id
                  AND status = 'available'
                  AND city = :city
                  AND vehicle_type = :vehicle_type
                FOR UPDATE
            """),
            {
                "driver_id": payload.driver_id,
                "city": ride[3],
                "vehicle_type": ride[4],
            },
        ).fetchone()

        if not driver:
            raise HTTPException(
                status_code=400,
                detail="Driver not found, unavailable, or incompatible.",
            )

        db.execute(
            text("""
                UPDATE rides
                SET status = CAST('accepted' AS ride_status_enum),
                    driver_id = :driver_id,
                    accepted_at = CURRENT_TIMESTAMP
                WHERE ride_id = :ride_id
            """),
            {
                "driver_id": payload.driver_id,
                "ride_id": ride_id,
            },
        )

        db.commit()

        return {
            "message": "Ride accepted successfully",
            "ride_id": ride_id,
            "driver_id": payload.driver_id,
            "status": "accepted",
        }

    except HTTPException:
        db.rollback()
        raise
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Ride acceptance conflicts with a database constraint.",
        )
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Could not accept the ride due to a database conflict.",
        )


# -------------------- START A RIDE --------------------

@router.post("/{ride_id}/start")
def start_ride(
    ride_id: int,
    payload: DriverActionSchema,
    db: Session = Depends(get_db),
):
    """Start an accepted ride assigned to the specified driver."""

    try:
        ride = db.execute(
            text("""
                SELECT status, driver_id
                FROM rides
                WHERE ride_id = :ride_id
                FOR UPDATE
            """),
            {"ride_id": ride_id},
        ).fetchone()

        if not ride:
            raise HTTPException(
                status_code=404,
                detail="Ride not found.",
            )

        if ride[0] != "accepted":
            raise HTTPException(
                status_code=400,
                detail="Only accepted rides can be started.",
            )

        if ride[1] != payload.driver_id:
            raise HTTPException(
                status_code=403,
                detail="Only the assigned driver can start this ride.",
            )

        db.execute(
            text("""
                UPDATE rides
                SET status = CAST('ongoing' AS ride_status_enum),
                    started_at = CURRENT_TIMESTAMP
                WHERE ride_id = :ride_id
            """),
            {"ride_id": ride_id},
        )

        db.commit()

        return {
            "message": "Ride started successfully",
            "ride_id": ride_id,
            "status": "ongoing",
        }

    except HTTPException:
        db.rollback()
        raise
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Database error while starting the ride.",
        )


# -------------------- CANCEL A RIDE --------------------

@router.post("/{ride_id}/cancel")
def cancel_ride(
    ride_id: int,
    db: Session = Depends(get_db),
):
    """Cancel a requested or accepted ride."""

    try:
        result = db.execute(
            text("""
                UPDATE rides
                SET status = CAST('cancelled' AS ride_status_enum),
                    cancelled_at = CURRENT_TIMESTAMP
                WHERE ride_id = :ride_id
                  AND status IN ('requested', 'accepted')
                RETURNING driver_id
            """),
            {"ride_id": ride_id},
        ).fetchone()

        if not result:
            exists = db.execute(
                text("""
                    SELECT 1 FROM rides WHERE ride_id = :ride_id
                """),
                {"ride_id": ride_id},
            ).fetchone()

            db.rollback()

            if not exists:
                raise HTTPException(
                    status_code=404,
                    detail="Ride not found.",
                )

            raise HTTPException(
                status_code=400,
                detail="Only requested or accepted rides can be cancelled.",
            )

        db.commit()

        return {
            "message": "Ride cancelled successfully",
            "ride_id": ride_id,
            "driver_freed": result[0],
            "status": "cancelled",
        }

    except HTTPException:
        raise
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Database error while cancelling the ride.",
        )


# -------------------- PROCESS PAYMENT --------------------

@router.post("/{ride_id}/pay")
def pay_ride(
    ride_id: int,
    payload: PaymentSchema,
    db: Session = Depends(get_db),
):
    """Validate the fare, record payment, and complete the ride."""

    try:
        ride = db.execute(
            text("""
                SELECT status, fare
                FROM rides
                WHERE ride_id = :ride_id
                FOR UPDATE
            """),
            {"ride_id": ride_id},
        ).fetchone()

        if not ride:
            raise HTTPException(
                status_code=404,
                detail="Ride not found.",
            )

        if ride[0] != "ongoing":
            raise HTTPException(
                status_code=400,
                detail="Only ongoing rides can be paid for.",
            )

        expected_fare = float(ride[1])

        if round(payload.amount, 2) != round(expected_fare, 2):
            raise HTTPException(
                status_code=400,
                detail=f"Payment amount must equal the ride fare ({expected_fare:.2f}).",
            )

        db.execute(
            text("""
                INSERT INTO payments (ride_id, amount, status)
                VALUES (
                    :ride_id,
                    :amount,
                    CAST('completed' AS payment_status_enum)
                )
            """),
            {
                "ride_id": ride_id,
                "amount": expected_fare,
            },
        )

        db.execute(
            text("""
                UPDATE rides
                SET status = CAST('completed' AS ride_status_enum),
                    completed_at = CURRENT_TIMESTAMP
                WHERE ride_id = :ride_id
            """),
            {"ride_id": ride_id},
        )

        db.commit()

        return {
            "message": "Payment processed successfully",
            "ride_id": ride_id,
            "amount": expected_fare,
            "payment_status": "completed",
            "ride_status": "completed",
        }

    except HTTPException:
        db.rollback()
        raise
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Payment already exists or violates a database constraint.",
        )
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Database error while processing payment.",
        )
