CREATE OR REPLACE FUNCTION poll_sensor(source_url TEXT, event_type TEXT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    response http_response;
    payload JSONB;
    instances_array JSONB;
    instance JSONB;
    metric_record RECORD;
    extracted_value DOUBLE PRECISION;
    sample_time TIMESTAMPTZ := now();
    event_name TEXT := event_type || '-' || extract(epoch FROM sample_time)::BIGINT;
    inserted_count INT := 0;
BEGIN
    SELECT * INTO response FROM http_get(source_url);

    IF response.status != 200 THEN
        RAISE WARNING 'poll_sensor failed for %: HTTP %', source_url, response.status;
        RETURN 0;
    END IF;

    payload := (response.content::JSONB)->'data';

    instances_array := COALESCE(payload->'instances', payload->'sensors', payload->'probes');

    IF instances_array IS NOT NULL AND jsonb_typeof(instances_array) = 'array' THEN
        FOR instance IN SELECT * FROM jsonb_array_elements(instances_array)
        LOOP
            IF (instance->>'read_ok')::BOOLEAN = FALSE THEN
                CONTINUE;
            END IF;

            FOR metric_record IN
                SELECT metrics.id, metrics.name
                FROM metrics
                WHERE metrics.type = event_type
            LOOP
                extracted_value := (instance->>metric_record.name)::DOUBLE PRECISION;

                IF extracted_value IS NOT NULL THEN
                    INSERT INTO samples (time, event_name, source, type, metric_id, instance_index, value)
                    VALUES (
                        sample_time, event_name, source_url, event_type, metric_record.id,
                        COALESCE((instance->>'instance_index')::INT, (instance->>'index')::INT, 0),
                        extracted_value
                    )
                    ON CONFLICT DO NOTHING;

                    IF FOUND THEN
                        inserted_count := inserted_count + 1;
                    END IF;
                END IF;
            END LOOP;
        END LOOP;
    ELSE
        IF (payload->>'read_ok')::BOOLEAN = FALSE THEN
            RETURN 0;
        END IF;

        FOR metric_record IN
            SELECT metrics.id, metrics.name
            FROM metrics
            WHERE metrics.type = event_type
        LOOP
            extracted_value := (payload->>metric_record.name)::DOUBLE PRECISION;

            IF extracted_value IS NOT NULL THEN
                INSERT INTO samples (time, event_name, source, type, metric_id, instance_index, value)
                VALUES (
                    sample_time, event_name, source_url, event_type, metric_record.id, 0,
                    extracted_value
                )
                ON CONFLICT DO NOTHING;

                IF FOUND THEN
                    inserted_count := inserted_count + 1;
                END IF;
            END IF;
        END LOOP;
    END IF;

    RETURN inserted_count;
END;
$$;
