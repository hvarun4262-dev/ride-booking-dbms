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

        -- STRICT WHITELIST: If the driver is anything other than 'available', reject it.
        IF v_driver_status != 'available' THEN
            RAISE EXCEPTION 'State Error: Driver % is currently % and cannot accept a new ride.', NEW.driver_id, v_driver_status;
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

    -- If a rider is rating, verify they took this ride
    IF NEW.rider_id IS NOT NULL AND NEW.rider_id != v_rider_id THEN
        RAISE EXCEPTION 'Integrity Error: This rider did not participate in this ride.';
    
    -- If a driver is rating, verify they drove this ride
    ELSIF NEW.driver_id IS NOT NULL AND NEW.driver_id != v_driver_id THEN
        RAISE EXCEPTION 'Integrity Error: This driver did not drive this ride.';
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



-- 5. FINITE STATE MACHINE (FSM): STRICT RIDE STATUS TRANSITIONS
-- Enforces that rides follow a valid logical flow and prevents skipping states.
CREATE OR REPLACE FUNCTION enforce_valid_ride_transitions()
RETURNS TRIGGER AS $$
BEGIN
    -- NEW: Prevent moving forward without an assigned driver
    IF NEW.status IN ('accepted', 'ongoing', 'completed') AND NEW.driver_id IS NULL THEN
        RAISE EXCEPTION 'Integrity Error: A ride cannot transition to % without an assigned driver.', NEW.status;
    END IF;

    -- If the status isn't changing, allow the update to proceed
    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    -- Define allowed transitions mapping
    IF OLD.status = 'requested' AND NEW.status NOT IN ('accepted', 'cancelled') THEN
        RAISE EXCEPTION 'FSM Error: Cannot move from requested directly to %.', NEW.status;
        
    ELSIF OLD.status = 'accepted' AND NEW.status NOT IN ('ongoing', 'cancelled') THEN
        RAISE EXCEPTION 'FSM Error: Cannot move from accepted directly to %.', NEW.status;
        
    ELSIF OLD.status = 'ongoing' AND NEW.status NOT IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'FSM Error: Cannot move from ongoing directly to %.', NEW.status;
        
    ELSIF OLD.status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'FSM Error: Ride is in a terminal state (%), cannot change status.', OLD.status;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_enforce_ride_transitions
BEFORE UPDATE OF status ON rides
FOR EACH ROW
EXECUTE FUNCTION enforce_valid_ride_transitions();


-- 6. AUTOMATED AUDIT TIMESTAMPS
-- Automatically records the exact time a ride enters a specific state.
CREATE OR REPLACE FUNCTION auto_log_ride_timestamps()
RETURNS TRIGGER AS $$
BEGIN
    -- Only update timestamps if the status is actually changing
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF NEW.status = 'accepted' THEN
            NEW.accepted_at = CURRENT_TIMESTAMP;
        ELSIF NEW.status = 'ongoing' THEN
            NEW.started_at = CURRENT_TIMESTAMP;
        ELSIF NEW.status = 'completed' THEN
            NEW.completed_at = CURRENT_TIMESTAMP;
        ELSIF NEW.status = 'cancelled' THEN
            NEW.cancelled_at = CURRENT_TIMESTAMP;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_log_ride_timestamps
BEFORE UPDATE OF status ON rides
FOR EACH ROW
EXECUTE FUNCTION auto_log_ride_timestamps();


-- 7. EVENT SOURCING: STATUS AUDIT LOG
-- Automatically appends a record to the history table whenever a ride changes state.
CREATE OR REPLACE FUNCTION log_ride_status_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Handle the initial creation of the ride
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO ride_status_history (ride_id, old_status, new_status)
        VALUES (NEW.ride_id, NULL, NEW.status);
        
    -- Handle subsequent status updates
    ELSIF (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status) THEN
        INSERT INTO ride_status_history (ride_id, old_status, new_status)
        VALUES (NEW.ride_id, OLD.status, NEW.status);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger fires AFTER the change to guarantee the main transaction succeeded
CREATE TRIGGER trg_log_ride_status_change
AFTER INSERT OR UPDATE OF status ON rides
FOR EACH ROW
EXECUTE FUNCTION log_ride_status_change();

-- Updated Rating Trigger snippet
CREATE OR REPLACE FUNCTION verify_rating_participation()
RETURNS TRIGGER AS $$
DECLARE
    v_rider_id INT;
    v_driver_id INT;
    v_status ride_status_enum; -- NEW: variable to hold the status
BEGIN
    -- Fetch the participants AND the status of the ride
    SELECT rider_id, driver_id, status 
    INTO v_rider_id, v_driver_id, v_status
    FROM rides WHERE ride_id = NEW.ride_id;

    -- NEW: Enforce completion rule
    IF v_status != 'completed' THEN
        RAISE EXCEPTION 'Business Rule Error: Ratings can only be submitted for completed rides.';
    END IF;

    -- Check rider participation
    IF NEW.rider_id IS NOT NULL AND NEW.rider_id != v_rider_id THEN
        RAISE EXCEPTION 'Integrity Error: This rider did not participate in this ride.';
    
    -- Check driver participation
    ELSIF NEW.driver_id IS NOT NULL AND NEW.driver_id != v_driver_id THEN
        RAISE EXCEPTION 'Integrity Error: This driver did not drive this ride.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;