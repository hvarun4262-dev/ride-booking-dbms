-- ENUMERATED TYPES (State & Categorization)

CREATE TYPE driver_status_enum AS ENUM ('available', 'busy', 'offline');
CREATE TYPE ride_status_enum AS ENUM ('requested', 'accepted', 'ongoing', 'completed', 'cancelled');
CREATE TYPE payment_status_enum AS ENUM ('pending', 'completed', 'failed');
CREATE TYPE reviewer_type_enum AS ENUM ('rider', 'driver');
CREATE TYPE vehicle_type_enum AS ENUM ('bike', 'auto', 'mini', 'sedan', 'suv');


-- Riders Table
CREATE TABLE riders (
    rider_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Drivers Table (Updated with Vehicle Info)
CREATE TABLE drivers (
    driver_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) UNIQUE NOT NULL,
    vehicle_number VARCHAR(20) UNIQUE NOT NULL,
    vehicle_type vehicle_type_enum NOT NULL,
    passenger_capacity INT NOT NULL CHECK (passenger_capacity > 0 AND passenger_capacity <= 8),
    city VARCHAR(50) NOT NULL,
    status driver_status_enum DEFAULT 'offline',
    rating DECIMAL(3, 2) DEFAULT 5.00 CHECK (rating >= 1.00 AND rating <= 5.00),
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- Rides Table (The Core Engine)
CREATE TABLE rides (
    ride_id SERIAL PRIMARY KEY,
    rider_id INT NOT NULL REFERENCES riders(rider_id) ON DELETE CASCADE,
    driver_id INT REFERENCES drivers(driver_id) ON DELETE SET NULL,
    city VARCHAR(50) NOT NULL,
    
    -- Geospatial & Address Data
    pickup_address TEXT NOT NULL,
    dropoff_address TEXT NOT NULL,
    pickup_lat DECIMAL(9, 6) NOT NULL,
    pickup_lng DECIMAL(9, 6) NOT NULL,
    dropoff_lat DECIMAL(9, 6) NOT NULL,
    dropoff_lng DECIMAL(9, 6) NOT NULL,
    
    -- Ride Preferences & Metrics
    requested_vehicle_type vehicle_type_enum NOT NULL,
    distance_km DECIMAL(5, 2) NOT NULL CHECK (distance_km > 0),
    surge_multiplier DECIMAL(3, 2) DEFAULT 1.00 CHECK (surge_multiplier >= 1.00),
    fare DECIMAL(10, 2) NOT NULL CHECK (fare >= 0),
    
    -- Status & Timestamps
    status ride_status_enum DEFAULT 'requested',
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    accepted_at TIMESTAMP,
    completed_at TIMESTAMP
);

-- Payments Table
CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    ride_id INT NOT NULL UNIQUE REFERENCES rides(ride_id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL CHECK (amount >= 0),
    payment_method VARCHAR(50),
    status payment_status_enum DEFAULT 'pending',
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Ratings Table (Updated for data integrity)
CREATE TABLE ratings (
    rating_id SERIAL PRIMARY KEY,
    ride_id INT NOT NULL REFERENCES rides(ride_id) ON DELETE CASCADE,
    reviewer_id INT NOT NULL, -- NEW: Tracks exactly who gave the rating
    reviewer_type reviewer_type_enum NOT NULL,
    score INT NOT NULL CHECK (score >= 1 AND score <= 5),
    review TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Ensure the specific reviewer can only rate this specific ride once
    UNIQUE (ride_id, reviewer_type, reviewer_id)
);