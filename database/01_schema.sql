-- MASS DATA GENERATION (100 Riders, 50 Drivers, 1000 Rides)
-- PostgreSQL procedural generation for load testing.


-- Clear existing data safely
TRUNCATE TABLE ratings, payments, rides, drivers, riders RESTART IDENTITY CASCADE;


-- 1. Generate 100 Riders
INSERT INTO riders (name, phone, email)
SELECT 
    'Rider ' || id, 
    '900000' || LPAD(id::text, 4, '0'), 
    'rider' || id || '@example.com'
FROM generate_series(1, 100) AS id;


-- 2. Generate 50 Drivers with diverse vehicles

INSERT INTO drivers (name, phone, vehicle_number, vehicle_type, passenger_capacity, city)
SELECT 
    'Driver ' || id, 
    '800000' || LPAD(id::text, 4, '0'), 
    'KA-01-AB-' || LPAD(id::text, 4, '0'),
    CAST((ARRAY['bike', 'auto', 'mini', 'sedan', 'suv'])[ (id % 5) + 1 ] AS vehicle_type_enum),
    (ARRAY[1, 3, 4, 4, 6])[ (id % 5) + 1 ],
    CAST((ARRAY['Bengaluru', 'Mysuru', 'Hubli'])[ (id % 3) + 1 ] AS VARCHAR)
FROM generate_series(1, 50) AS id;


-- 3. Generate 1,000 Rides (Distributed over last 30 days)
INSERT INTO rides (
    rider_id, driver_id, city, pickup_address, dropoff_address, 
    pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, 
    requested_vehicle_type, distance_km, surge_multiplier, fare, status, 
    requested_at
)
SELECT 
    (random() * 99 + 1)::INT, -- random rider_id (1 to 100)
    (random() * 49 + 1)::INT, -- random driver_id (1 to 50)
    'Bengaluru', 
    'Random Point A', 'Random Point B', 
    12.9000 + (random() * 0.1), 77.5000 + (random() * 0.1), 
    12.9000 + (random() * 0.1), 77.5000 + (random() * 0.1), 
    CAST((ARRAY['bike', 'auto', 'mini', 'sedan', 'suv'])[ (id % 5) + 1 ] AS vehicle_type_enum),
    ROUND((random() * 18 + 2)::numeric, 2), -- Distance: 2km to 20km
    CASE WHEN random() > 0.8 THEN 1.50 ELSE 1.00 END, -- 20% surge probability
    ROUND((random() * 400 + 50)::numeric, 2), -- Fare: ₹50 to ₹450
    'completed'::ride_status_enum,
    CURRENT_TIMESTAMP - (random() * interval '30 days') -- Requested anytime in last 30 days
FROM generate_series(1, 1000) AS id;

-- Logically update the accepted and completed timestamps based on distance
UPDATE rides 
SET 
    accepted_at = requested_at + (random() * interval '3 minutes'),
    completed_at = requested_at + (random() * interval '3 minutes') + (distance_km * interval '3 minutes');


-- 4. Generate 1,000 Payments for those rides
INSERT INTO payments (ride_id, amount, payment_method, status, processed_at)
SELECT 
    ride_id, 
    fare, 
    CAST((ARRAY['UPI', 'Credit Card', 'Cash'])[ (ride_id % 3) + 1 ] AS VARCHAR), 
    'completed'::payment_status_enum,
    completed_at + interval '1 minute'
FROM rides;

-- 5. Generate Ratings (~70% of riders leave a rating)
INSERT INTO ratings (ride_id, reviewer_id, reviewer_type, score, review, created_at)
SELECT 
    ride_id,
    rider_id,
    'rider'::reviewer_type_enum,
    (random() * 2 + 3)::INT, -- Scores between 3 and 5
    'Great ride!',
    completed_at + interval '1 hour'
FROM rides
WHERE random() > 0.3;