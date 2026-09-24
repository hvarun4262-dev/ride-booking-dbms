-- 1. FOREIGN KEY INDEXES (Crucial for JOIN performance)
-- PostgreSQL does NOT automatically index foreign keys. These prevent full table scans.

CREATE INDEX idx_rides_rider_id ON rides(rider_id);
CREATE INDEX idx_rides_driver_id ON rides(driver_id);
CREATE INDEX idx_payments_ride_id ON payments(ride_id);
CREATE INDEX idx_ratings_ride_id ON ratings(ride_id);
CREATE INDEX idx_ratings_rider_id ON ratings(rider_id);
CREATE INDEX idx_ratings_driver_id ON ratings(driver_id);
CREATE INDEX idx_history_ride_id ON ride_status_history(ride_id);


-- 2. TIME-SERIES INDEXES (For Analytics and Heatmaps)
-- Optimizes queries filtering by date ranges (e.g., "last 30 days").
-- Storing requested_at in descending order since we almost always query recent data
CREATE INDEX idx_rides_requested_at ON rides(requested_at DESC);
CREATE INDEX idx_rides_completed_at ON rides(completed_at DESC);


-- 3. GEOSPATIAL / COORDINATE INDEXES
-- Composite index to speed up distance calculations bounding box queries.
CREATE INDEX idx_rides_pickup_coords ON rides(pickup_lat, pickup_lng);
CREATE INDEX idx_rides_dropoff_coords ON rides(dropoff_lat, dropoff_lng);


-- 4. PARTIAL INDEXES (The Senior Engineer Flex)
-- Low cardinality columns (like status) usually confuse the query planner. 
-- Partial indexes only store rows matching a condition, making them lightning fast.

-- Instantly find available drivers in a specific city without scanning busy/offline drivers
CREATE INDEX idx_drivers_available_city 
ON drivers(city) 
WHERE status = 'available';

-- Instantly look up active rides (ignoring the millions of completed/cancelled rides)
CREATE INDEX idx_rides_active 
ON rides(ride_id) 
WHERE status IN ('requested', 'accepted', 'ongoing');