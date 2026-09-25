from fastapi import FastAPI
from app.routes import rides, analytics

app = FastAPI(title="Ride Booking API - DBMS Mini Project")

# Register the modular routers
app.include_router(rides.router)
app.include_router(analytics.router)

@app.get("/health")
def health_check():
    return {"status": "healthy"}