-- 04_seed_data.sql

-- Clear existing data (useful if you ever need to re-run this script)
TRUNCATE TABLE ratings, payments, rides, drivers, riders RESTART IDENTITY CASCADE;

-- ==========================================
-- 1. SEED RIDERS
-- ==========================================
INSERT INTO riders (name, phone, email) VALUES
('Rahul Sharma', '9876543210', 'rahul@example.com'),
('Priya Patel', '9876543211', 'priya@example.com'),
('Amit Kumar', '9876543212', 'amit@example.com'),
('Sneha Reddy', '9876543213', 'sneha@example.com');

-- ==========================================
-- 2. SEED DRIVERS (Various vehicle types and statuses)
-- ==========================================
INSERT INTO drivers (name, phone, vehicle_number, vehicle_type, passenger_capacity, city, status, rating) VALUES
('Suresh Ramesh', '8876543210', 'KA-01-AB-1234', 'bike', 1, 'Bengaluru', 'available', 4.8),
('John Doe', '8876543211', 'KA-02-XY-9876', 'auto', 3, 'Bengaluru', 'available', 4.5),
('Imran Khan', '8876543212', 'KA-03-ZZ-1111', 'mini', 4, 'Bengaluru', 'busy', 4.9),
('Ravi Teja', '8876543213', 'KA-04-QQ-2222', 'suv', 6, 'Bengaluru', 'offline', 4.2);

-- ==========================================
-- 3. SEED RIDES (Showcasing all state transitions)
-- ==========================================
INSERT INTO rides (
    rider_id, driver_id, city, 
    pickup_address, dropoff_address, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, 
    requested_vehicle_type, distance_km, surge_multiplier, fare, status, 
    requested_at, accepted_at, completed_at
) VALUES
-- Ride 1: Completed Bike Ride (Rahul rode with Suresh)
(1, 1, 'Bengaluru', 'Koramangala 5th Block', 'Indiranagar Metro', 12.9352, 77.6245, 12.9784, 77.6408, 
 'bike', 5.50, 1.00, 66.00, 'completed', 
 CURRENT_TIMESTAMP - INTERVAL '2 days', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '2 minutes', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '25 minutes'),

-- Ride 2: Completed Auto Ride with Surge Pricing (Priya rode with John)
(2, 2, 'Bengaluru', 'HSR Layout', 'BTM Layout', 12.9121, 77.6446, 12.9165, 77.6101, 
 'auto', 3.20, 1.20, 75.00, 'completed', 
 CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '1 minute', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '15 minutes'),

-- Ride 3: Ongoing Mini Ride (Amit is currently riding with Imran)
(3, 3, 'Bengaluru', 'MG Road', 'Whitefield', 12.9716, 77.5946, 12.9698, 77.7499, 
 'mini', 18.50, 1.50, 450.00, 'ongoing', 
 CURRENT_TIMESTAMP - INTERVAL '15 minutes', CURRENT_TIMESTAMP - INTERVAL '12 minutes', NULL),

-- Ride 4: Requested SUV Ride (Sneha is waiting, no driver assigned yet -> driver_id is NULL)
(4, NULL, 'Bengaluru', 'Kempegowda Airport', 'Hebbal', 13.1986, 77.7066, 13.0354, 77.5988, 
 'suv', 25.00, 1.00, 650.00, 'requested', 
 CURRENT_TIMESTAMP, NULL, NULL);

-- ==========================================
-- 4. SEED PAYMENTS
-- ==========================================
INSERT INTO payments (ride_id, amount, payment_method, status) VALUES
(1, 66.00, 'UPI', 'completed'),
(2, 75.00, 'Cash', 'completed'),
(3, 450.00, 'Credit Card', 'pending'); -- Ongoing ride hasn't paid yet

-- ==========================================
-- 5. SEED RATINGS (Using the new reviewer_id integrity check)
-- ==========================================
INSERT INTO ratings (ride_id, reviewer_id, reviewer_type, score, review) VALUES
-- For Ride 1: Rider (Rahul, ID: 1) rates the driver
(1, 1, 'rider', 5, 'Great and quick bike ride!'),
-- For Ride 1: Driver (Suresh, ID: 1) rates the rider
(1, 1, 'driver', 5, 'Polite rider, was waiting at the exact location.'),

-- For Ride 2: Rider (Priya, ID: 2) rates the driver
(2, 2, 'rider', 4, 'Auto was a bit dusty but good driving.');
-- Driver John did not rate Priya.