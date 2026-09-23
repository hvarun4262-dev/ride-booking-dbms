-- 1. DRIVER LEADERBOARD (Window Functions)
-- Ranks drivers within their specific city based on their average rating and total rides.
-- Highlights: RANK() OVER (PARTITION BY), COALESCE, CTEs
WITH driver_stats AS (
    SELECT 
        d.driver_id,
        d.name,
        d.city,
        COUNT(r.ride_id) AS total_rides,
        COALESCE(AVG(rt.score), 0) AS avg_rating
    FROM drivers d
    LEFT JOIN rides r ON d.driver_id = r.driver_id AND r.status = 'completed'
    LEFT JOIN ratings rt ON r.ride_id = rt.ride_id AND rt.rider_id IS NOT NULL -- Only ratings given by riders
    GROUP BY d.driver_id, d.name, d.city
)
SELECT 
    driver_id,
    name,
    city,
    total_rides,
    ROUND(avg_rating, 2) AS avg_rating,
    RANK() OVER (PARTITION BY city ORDER BY avg_rating DESC, total_rides DESC) AS city_rank
FROM driver_stats
WHERE total_rides > 0
ORDER BY city, city_rank;


-- 2. OPERATIONAL BOTTLENECKS: WAIT TIME ANALYSIS
-- Calculates exactly how long riders wait for a driver to accept and arrive.
-- Highlights: EXTRACT(EPOCH FROM interval) to convert timestamps to minutes.
SELECT 
    city,
    COUNT(ride_id) AS total_requests,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_rides,
    
    -- Time from 'requested' to 'accepted' (Wait for matching)
    ROUND(AVG(EXTRACT(EPOCH FROM (accepted_at - requested_at))/60)::numeric, 2) AS avg_match_time_mins,
    
    -- Time from 'accepted' to 'started' (Driver driving to pickup location)
    ROUND(AVG(EXTRACT(EPOCH FROM (started_at - accepted_at))/60)::numeric, 2) AS avg_arrival_time_mins
FROM rides
WHERE requested_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY city
ORDER BY total_requests DESC;


-- 3. DRIVER WEEKLY EARNINGS PAYROLL
-- Calculates driver payouts assuming the platform takes a 20% commission.
-- Highlights: DATE_TRUNC for time-series grouping, multi-table joins.
SELECT 
    d.driver_id,
    d.name,
    DATE_TRUNC('week', r.completed_at) AS week_start,
    COUNT(r.ride_id) AS rides_completed,
    SUM(r.distance_km) AS total_distance_km,
    SUM(p.amount) AS gross_booking_value,
    ROUND(SUM(p.amount) * 0.80, 2) AS net_driver_earnings -- Platform keeps 20%
FROM drivers d
JOIN rides r ON d.driver_id = r.driver_id
JOIN payments p ON r.ride_id = p.ride_id
WHERE r.status = 'completed' AND p.status = 'completed'
GROUP BY d.driver_id, d.name, week_start
ORDER BY week_start DESC, net_driver_earnings DESC;


-- 4. SURGE PRICING HEATMAP
-- Analyzes which hour of the day has the highest demand and cancellation rates.
-- Highlights: FILTER (WHERE...) clause, which is faster than standard CASE WHEN.
SELECT 
    EXTRACT(HOUR FROM requested_at) AS hour_of_day,
    COUNT(ride_id) AS total_requests,
    ROUND(AVG(surge_multiplier), 2) AS avg_surge_multiplier,
    COUNT(ride_id) FILTER (WHERE status = 'completed') AS completed_rides,
    COUNT(ride_id) FILTER (WHERE status = 'cancelled') AS cancelled_rides
FROM rides
GROUP BY hour_of_day
ORDER BY total_requests DESC;


-- 5. TRUST & SAFETY: HIGH-RISK RIDERS
-- Identifies riders with high cancellation rates or terrible ratings from drivers.
-- Highlights: Utilizes the "Exclusive Arc" rating schema design.
WITH driver_reviews_of_riders AS (
    SELECT 
        r.rider_id,
        AVG(rt.score) AS avg_rating_from_drivers
    FROM rides r
    JOIN ratings rt ON r.ride_id = rt.ride_id
    WHERE rt.driver_id IS NOT NULL -- The rating was strictly submitted by a driver
    GROUP BY r.rider_id
)
SELECT 
    r.rider_id,
    r.name,
    ROUND(drv.avg_rating_from_drivers, 2) AS avg_driver_rating,
    COUNT(rd.ride_id) FILTER (WHERE rd.status = 'cancelled') AS lifetime_cancellations
FROM riders r
JOIN driver_reviews_of_riders drv ON r.rider_id = drv.rider_id
JOIN rides rd ON r.rider_id = rd.rider_id
GROUP BY r.rider_id, r.name, drv.avg_rating_from_drivers
HAVING AVG(drv.avg_rating_from_drivers) < 3.5 OR COUNT(rd.ride_id) FILTER (WHERE rd.status = 'cancelled') >= 3
ORDER BY avg_driver_rating ASC, lifetime_cancellations DESC;