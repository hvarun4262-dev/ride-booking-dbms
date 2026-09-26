from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Hardcoded for local testing. Use environment variables in production.
DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/ride_booking_db"

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()