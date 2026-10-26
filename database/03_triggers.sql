
-- 1. Driver availability follows ride status.
CREATE OR REPLACE FUNCTION update_driver_status()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IN ('accepted', 'ongoing') THEN
        UPDATE drivers
        SET status = 'busy'
        WHERE driver_id = NEW.driver_id;
    ELSIF NEW.status IN ('completed', 'cancelled') THEN
        UPDATE drivers
        SET status = 'available'
        WHERE driver_id = OLD.driver_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_driver_status_automation ON rides;

CREATE TRIGGER trg_driver_status_automation
AFTER UPDATE OF status ON rides
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION update_driver_status();


-- 2. Lock driver row to prevent one driver accepting two rides.
CREATE OR REPLACE FUNCTION prevent_double_booking()
RETURNS TRIGGER AS $$
DECLARE
    v_driver_status driver_status_enum;
BEGIN
    IF NEW.status = 'accepted'
       AND OLD.status = 'requested' THEN

        SELECT status
        INTO v_driver_status
        FROM drivers
        WHERE driver_id = NEW.driver_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Driver % does not exist.', NEW.driver_id;
        END IF;

        IF v_driver_status <> 'available' THEN
            RAISE EXCEPTION
                'Driver % is %, so cannot accept a ride.',
                NEW.driver_id, v_driver_status;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_double_booking ON rides;

CREATE TRIGGER trg_prevent_double_booking
BEFORE UPDATE OF status ON rides
FOR EACH ROW
WHEN (NEW.status = 'accepted' AND OLD.status = 'requested')
EXECUTE FUNCTION prevent_double_booking();


-- 3. Validate rating participant and ride completion.
CREATE OR REPLACE FUNCTION verify_rating_participation()
RETURNS TRIGGER AS $$
DECLARE
    v_rider_id INT;
    v_driver_id INT;
    v_status ride_status_enum;
BEGIN
    SELECT rider_id, driver_id, status
    INTO v_rider_id, v_driver_id, v_status
    FROM rides
    WHERE ride_id = NEW.ride_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ride % does not exist.', NEW.ride_id;
    END IF;

    IF v_status <> 'completed' THEN
        RAISE EXCEPTION 'Only completed rides can be rated.';
    END IF;

    IF NEW.rider_id IS NOT NULL
       AND NEW.rider_id <> v_rider_id THEN
        RAISE EXCEPTION 'Rider did not participate in this ride.';
    END IF;

    IF NEW.driver_id IS NOT NULL
       AND NEW.driver_id <> v_driver_id THEN
        RAISE EXCEPTION 'Driver did not participate in this ride.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_verify_rating_participation ON ratings;

CREATE TRIGGER trg_verify_rating_participation
BEFORE INSERT OR UPDATE ON ratings
FOR EACH ROW
EXECUTE FUNCTION verify_rating_participation();


-- 4. Recalculate driver average when a rider rates a driver.
CREATE OR REPLACE FUNCTION update_driver_rating_avg()
RETURNS TRIGGER AS $$
DECLARE
    v_ride_driver_id INT;
BEGIN
    SELECT driver_id
    INTO v_ride_driver_id
    FROM rides
    WHERE ride_id = NEW.ride_id;

    IF NEW.rider_id IS NOT NULL AND v_ride_driver_id IS NOT NULL THEN
        UPDATE drivers
        SET rating = (
            SELECT ROUND(AVG(r.score), 2)
            FROM ratings r
            JOIN rides ri ON ri.ride_id = r.ride_id
            WHERE ri.driver_id = v_ride_driver_id
              AND r.rider_id IS NOT NULL
        )
        WHERE driver_id = v_ride_driver_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_driver_rating ON ratings;

CREATE TRIGGER trigger_update_driver_rating
AFTER INSERT OR UPDATE ON ratings
FOR EACH ROW
EXECUTE FUNCTION update_driver_rating_avg();


-- 5. Updated-at timestamps.
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_riders_timestamp ON riders;
CREATE TRIGGER trg_update_riders_timestamp
BEFORE UPDATE ON riders
FOR EACH ROW
EXECUTE FUNCTION update_modified_column();

DROP TRIGGER IF EXISTS trg_update_drivers_timestamp ON drivers;
CREATE TRIGGER trg_update_drivers_timestamp
BEFORE UPDATE ON drivers
FOR EACH ROW
EXECUTE FUNCTION update_modified_column();


-- 6. Enforce ride FSM.
CREATE OR REPLACE FUNCTION enforce_valid_ride_transitions()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IN ('accepted', 'ongoing', 'completed')
       AND NEW.driver_id IS NULL THEN
        RAISE EXCEPTION
            'Ride cannot transition to % without an assigned driver.',
            NEW.status;
    END IF;

    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    IF OLD.status = 'requested'
       AND NEW.status NOT IN ('accepted', 'cancelled') THEN
        RAISE EXCEPTION 'Invalid transition: requested -> %', NEW.status;
    ELSIF OLD.status = 'accepted'
       AND NEW.status NOT IN ('ongoing', 'cancelled') THEN
        RAISE EXCEPTION 'Invalid transition: accepted -> %', NEW.status;
    ELSIF OLD.status = 'ongoing'
       AND NEW.status NOT IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Invalid transition: ongoing -> %', NEW.status;
    ELSIF OLD.status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Ride is already in terminal state %', OLD.status;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enforce_ride_transitions ON rides;

CREATE TRIGGER trg_enforce_ride_transitions
BEFORE UPDATE OF status ON rides
FOR EACH ROW
EXECUTE FUNCTION enforce_valid_ride_transitions();


-- 7. Set lifecycle timestamps.
CREATE OR REPLACE FUNCTION auto_log_ride_timestamps()
RETURNS TRIGGER AS $$
BEGIN
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

DROP TRIGGER IF EXISTS trg_auto_log_ride_timestamps ON rides;

CREATE TRIGGER trg_auto_log_ride_timestamps
BEFORE UPDATE OF status ON rides
FOR EACH ROW
EXECUTE FUNCTION auto_log_ride_timestamps();


-- 8. Audit status history.
CREATE OR REPLACE FUNCTION log_ride_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO ride_status_history (ride_id, old_status, new_status)
        VALUES (NEW.ride_id, NULL, NEW.status);
    ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO ride_status_history (ride_id, old_status, new_status)
        VALUES (NEW.ride_id, OLD.status, NEW.status);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_ride_status_change ON rides;

CREATE TRIGGER trg_log_ride_status_change
AFTER INSERT OR UPDATE OF status ON rides
FOR EACH ROW
EXECUTE FUNCTION log_ride_status_change();
