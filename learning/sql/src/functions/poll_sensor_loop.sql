CREATE OR REPLACE FUNCTION poll_sensor_loop(
    source_url TEXT,
    event_type TEXT,
    interval_seconds DOUBLE PRECISION,
    duration_seconds INT DEFAULT 58
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    total_inserted INT := 0;
    iteration INT := 0;
    max_iterations INT := floor(duration_seconds / interval_seconds)::INT;
    batch_count INT;
BEGIN
    WHILE iteration < max_iterations LOOP
        batch_count := poll_sensor(source_url, event_type);
        total_inserted := total_inserted + batch_count;
        iteration := iteration + 1;

        IF iteration < max_iterations THEN
            PERFORM pg_sleep(interval_seconds);
        END IF;
    END LOOP;

    RETURN total_inserted;
END;
$$;
