-- 1. DRIVER STATUS AUTOMATION (State Transitions)
-- Automatically marks drivers as 'busy' or 'available' based on ride status.
CREATE OR REPLACE FUNCTION update_driver_status()
RETURNS TRIGGER AS $$
BEGIN
    -- When a ride is accepted or currently ongoing
    IF NEW.status IN ('accepted', 'ongoing') THEN
        UPDATE drivers SET status = 'busy' WHERE driver_id = NEW.driver_id;
    
    -- When a ride concludes or gets cancelled
    ELSIF NEW.status IN ('completed', 'cancelled') THEN
        UPDATE drivers SET status = 'available' WHERE driver_id = NEW.driver_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_driver_status_automation
AFTER UPDATE OF status ON rides
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION update_driver_status();


-- 2. CONCURRENCY CONTROL (Prevent Double Booking)
-- Prevents race conditions where two riders book the same driver simultaneously.
CREATE OR REPLACE FUNCTION prevent_double_booking()
RETURNS TRIGGER AS $$
DECLARE
    v_driver_status driver_status_enum;
BEGIN
    IF NEW.status = 'accepted' THEN
        -- The "FOR UPDATE" lock ensures no other transaction can read or modify 
        -- this driver's status until this transaction completes.
        SELECT status INTO v_driver_status 
        FROM drivers 
        WHERE driver_id = NEW.driver_id 
        FOR UPDATE; 

        IF v_driver_status = 'busy' THEN
            RAISE EXCEPTION 'Concurrency Error: Driver % is already busy with another ride.', NEW.driver_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_double_booking
BEFORE UPDATE OF status ON rides
FOR EACH ROW
WHEN (NEW.status = 'accepted' AND OLD.status = 'requested')
EXECUTE FUNCTION prevent_double_booking();


-- 3. DATA INTEGRITY: RATING VALIDATION
-- Enforces that only the actual rider or driver of a specific ride can rate it.
CREATE OR REPLACE FUNCTION verify_rating_participation()
RETURNS TRIGGER AS $$
DECLARE
    v_rider_id INT;
    v_driver_id INT;
BEGIN
    -- Fetch the actual participants of the ride
    SELECT rider_id, driver_id INTO v_rider_id, v_driver_id
    FROM rides WHERE ride_id = NEW.ride_id;

    -- Validate based on who is leaving the review
    IF NEW.reviewer_type = 'rider' AND NEW.reviewer_id != v_rider_id THEN
        RAISE EXCEPTION 'Integrity Error: Reviewer ID does not match the Rider ID for this ride.';
    ELSIF NEW.reviewer_type = 'driver' AND NEW.reviewer_id != v_driver_id THEN
        RAISE EXCEPTION 'Integrity Error: Reviewer ID does not match the Driver ID for this ride.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_verify_rating_participation
BEFORE INSERT OR UPDATE ON ratings
FOR EACH ROW
EXECUTE FUNCTION verify_rating_participation();


-- 4. UTILITY: AUTO-UPDATE TIMESTAMPS
-- Automatically bumps the 'updated_at' timestamp when a row is modified.
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_riders_timestamp 
BEFORE UPDATE ON riders FOR EACH ROW EXECUTE FUNCTION update_modified_column();

CREATE TRIGGER trg_update_drivers_timestamp 
BEFORE UPDATE ON drivers FOR EACH ROW EXECUTE FUNCTION update_modified_column();