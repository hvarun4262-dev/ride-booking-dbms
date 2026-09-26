from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session
from app.db import get_db

router = APIRouter(prefix="/analytics", tags=["Analytics"])

@router.get("/surge-heatmap")
def get_surge_heatmap(db: Session = Depends(get_db)):
    query = text("""
        SELECT 
            EXTRACT(HOUR FROM requested_at) AS hour_of_day,
            COUNT(ride_id) AS total_requests,
            ROUND(AVG(surge_multiplier), 2) AS avg_surge,
            ROUND(100.0 * COUNT(ride_id) FILTER (WHERE status = 'cancelled') / NULLIF(COUNT(ride_id), 0), 2) AS cancellation_rate
        FROM rides
        GROUP BY hour_of_day
        ORDER BY total_requests DESC;
    """)
    result = db.execute(query).mappings().all()
    return {"heatmap": result}