-- 1. DRIVER STATUS AUTOMATION (State Transitions)
-- Automatically marks drivers as 'busy' or 'available' based on ride status.
CREATE OR REPLACE FUNCTION update_driver_status()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IN ('accepted', 'ongoing') THEN
        UPDATE drivers SET status = 'busy' WHERE driver_id = NEW.driver_id;
    ELSIF NEW.status IN ('completed', 'cancelled') THEN
        UPDATE drivers SET status = 'available' WHERE driver_id = NEW.driver_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_driver_status_automation
AFTER UPDATE OF status ON rides
FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION update_driver_status();


-- 2. CONCURRENCY CONTROL (Prevent Double Booking)
CREATE OR REPLACE FUNCTION prevent_double_booking()
RETURNS TRIGGER AS $$
DECLARE
    v_driver_status driver_status_enum;
BEGIN
    IF NEW.status = 'accepted' THEN
        SELECT status INTO v_driver_status 
        FROM drivers WHERE driver_id = NEW.driver_id FOR UPDATE; 
        IF v_driver_status != 'available' THEN
            RAISE EXCEPTION 'State Error: Driver % is currently % and cannot accept a new ride.', NEW.driver_id, v_driver_status;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_double_booking
BEFORE UPDATE OF status ON rides
FOR EACH ROW WHEN (NEW.status = 'accepted' AND OLD.status = 'requested')
EXECUTE FUNCTION prevent_double_booking();


-- 3. DATA INTEGRITY: RATING VALIDATION (FIXED FOR EXCLUSIVE ARC)
CREATE OR REPLACE FUNCTION verify_rating_participation()
RETURNS TRIGGER AS $$
DECLARE
    v_rider_id INT;
    v_driver_id INT;
BEGIN
    SELECT rider_id, driver_id INTO v_rider_id, v_driver_id
    FROM rides WHERE ride_id = NEW.ride_id;

    -- If a rider is submitting the rating
    IF NEW.rider_id IS NOT NULL AND NEW.rider_id != v_rider_id THEN
        RAISE EXCEPTION 'Integrity Error: This rider did not participate in this ride.';
    -- If a driver is submitting the rating
    ELSIF NEW.driver_id IS NOT NULL AND NEW.driver_id != v_driver_id THEN
        RAISE EXCEPTION 'Integrity Error: This driver did not drive this ride.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_verify_rating_participation
BEFORE INSERT OR UPDATE ON ratings
FOR EACH ROW EXECUTE FUNCTION verify_rating_participation();


-- 4. NEW: AUTOMATICALLY UPDATE DRIVER RATING AVERAGE
CREATE OR REPLACE FUNCTION update_driver_rating_avg()
RETURNS TRIGGER AS $$
BEGIN
    -- Only update driver's rating when a rider submits a review
    IF NEW.rider_id IS NOT NULL THEN
        UPDATE drivers
        SET rating = (
            SELECT COALESCE(ROUND(AVG(score), 2), 5.00)
            FROM ratings
            JOIN rides ON ratings.ride_id = rides.ride_id
            WHERE rides.driver_id = (SELECT driver_id FROM rides WHERE ride_id = NEW.ride_id)
              AND ratings.rider_id IS NOT NULL
        )
        WHERE driver_id = (SELECT driver_id FROM rides WHERE ride_id = NEW.ride_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_driver_rating
AFTER INSERT OR UPDATE ON ratings
FOR EACH ROW EXECUTE FUNCTION update_driver_rating_avg();


-- 5. UTILITY: AUTO-UPDATE TIMESTAMPS
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_riders_timestamp BEFORE UPDATE ON riders FOR EACH ROW EXECUTE FUNCTION update_modified_column();
CREATE TRIGGER trg_update_drivers_timestamp BEFORE UPDATE ON drivers FOR EACH ROW EXECUTE FUNCTION update_modified_column();


-- 6. FINITE STATE MACHINE (FSM): STRICT RIDE STATUS TRANSITIONS
CREATE OR REPLACE FUNCTION enforce_valid_ride_transitions()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IN ('accepted', 'ongoing', 'completed') AND NEW.driver_id IS NULL THEN
        RAISE EXCEPTION 'Integrity Error: A ride cannot transition to % without an assigned driver.', NEW.status;
    END IF;

    IF OLD.status = NEW.status THEN RETURN NEW; END IF;

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
FOR EACH ROW EXECUTE FUNCTION enforce_valid_ride_transitions();


-- 7. AUTOMATED AUDIT TIMESTAMPS
CREATE OR REPLACE FUNCTION auto_log_ride_timestamps()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF NEW.status = 'accepted' THEN NEW.accepted_at = CURRENT_TIMESTAMP;
        ELSIF NEW.status = 'ongoing' THEN NEW.started_at = CURRENT_TIMESTAMP;
        ELSIF NEW.status = 'completed' THEN NEW.completed_at = CURRENT_TIMESTAMP;
        ELSIF NEW.status = 'cancelled' THEN NEW.cancelled_at = CURRENT_TIMESTAMP;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_log_ride_timestamps
BEFORE UPDATE OF status ON rides
FOR EACH ROW EXECUTE FUNCTION auto_log_ride_timestamps();


-- 8. EVENT SOURCING: STATUS AUDIT LOG
CREATE OR REPLACE FUNCTION log_ride_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO ride_status_history (ride_id, old_status, new_status) VALUES (NEW.ride_id, NULL, NEW.status);
    ELSIF (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status) THEN
        INSERT INTO ride_status_history (ride_id, old_status, new_status) VALUES (NEW.ride_id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_ride_status_change
AFTER INSERT OR UPDATE OF status ON rides
FOR EACH ROW EXECUTE FUNCTION log_ride_status_change();