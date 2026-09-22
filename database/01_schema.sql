-- 1. ENUMERATED TYPES
CREATE TYPE driver_status_enum AS ENUM ('available', 'busy', 'offline');
CREATE TYPE ride_status_enum AS ENUM ('requested', 'accepted', 'ongoing', 'completed', 'cancelled');
CREATE TYPE payment_status_enum AS ENUM ('pending', 'completed', 'failed');
CREATE TYPE vehicle_type_enum AS ENUM ('bike', 'auto', 'mini', 'sedan', 'suv');


-- 2. CORE ENTITIES
CREATE TABLE riders (
    rider_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE drivers (
    driver_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) UNIQUE NOT NULL,
    vehicle_number VARCHAR(20) UNIQUE NOT NULL,
    vehicle_type vehicle_type_enum NOT NULL,
    passenger_capacity INT NOT NULL CHECK (passenger_capacity > 0 AND passenger_capacity <= 8),
    city VARCHAR(50) NOT NULL,
    status driver_status_enum NOT NULL DEFAULT 'offline',
    rating DECIMAL(3, 2) NOT NULL DEFAULT 5.00 CHECK (rating >= 1.00 AND rating <= 5.00),
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- 3. TRANSACTIONAL ENTITIES
CREATE TABLE rides (
    ride_id SERIAL PRIMARY KEY,
    rider_id INT NOT NULL REFERENCES riders(rider_id) ON DELETE CASCADE,
    
    -- driver_id MUST remain nullable because a ride is requested before a driver is assigned.
    driver_id INT REFERENCES drivers(driver_id) ON DELETE SET NULL, 
    
    city VARCHAR(50) NOT NULL,
    pickup_address TEXT NOT NULL,
    dropoff_address TEXT NOT NULL,
    
    -- GEOSPATIAL VALIDATION: Prevents mathematically impossible coordinates
    pickup_lat DECIMAL(9, 6) NOT NULL CHECK (pickup_lat BETWEEN -90 AND 90),
    pickup_lng DECIMAL(9, 6) NOT NULL CHECK (pickup_lng BETWEEN -180 AND 180),
    dropoff_lat DECIMAL(9, 6) NOT NULL CHECK (dropoff_lat BETWEEN -90 AND 90),
    dropoff_lng DECIMAL(9, 6) NOT NULL CHECK (dropoff_lng BETWEEN -180 AND 180),
    
    requested_vehicle_type vehicle_type_enum NOT NULL,
    distance_km DECIMAL(5, 2) NOT NULL CHECK (distance_km > 0),
    surge_multiplier DECIMAL(3, 2) NOT NULL DEFAULT 1.00 CHECK (surge_multiplier >= 1.00),
    fare DECIMAL(10, 2) NOT NULL CHECK (fare >= 0),
    
    status ride_status_enum NOT NULL DEFAULT 'requested',
    
    requested_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    accepted_at TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    cancelled_at TIMESTAMP
);

CREATE TABLE ride_status_history (
    history_id SERIAL PRIMARY KEY,
    ride_id INT NOT NULL REFERENCES rides(ride_id) ON DELETE CASCADE,
    old_status ride_status_enum, -- Nullable: First entry has no old status
    new_status ride_status_enum NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    ride_id INT NOT NULL UNIQUE REFERENCES rides(ride_id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL CHECK (amount >= 0),
    payment_method VARCHAR(50), -- Nullable: Unknown until the user actually pays
    status payment_status_enum NOT NULL DEFAULT 'pending',
    processed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE ratings (
    rating_id SERIAL PRIMARY KEY,
    ride_id INT NOT NULL REFERENCES rides(ride_id) ON DELETE CASCADE,
    
    -- EXCLUSIVE ARC: Both must be nullable at the schema level...
    rider_id INT REFERENCES riders(rider_id) ON DELETE CASCADE,
    driver_id INT REFERENCES drivers(driver_id) ON DELETE CASCADE,
    
    score INT NOT NULL CHECK (score >= 1 AND score <= 5),
    review TEXT, -- Nullable: Optional text review
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ...but the CHECK constraint enforces that exactly ONE is strictly NOT NULL per row
    CHECK (
        (rider_id IS NOT NULL AND driver_id IS NULL) OR 
        (rider_id IS NULL AND driver_id IS NOT NULL)
    ),
    
    UNIQUE (ride_id, rider_id),
    UNIQUE (ride_id, driver_id)
);