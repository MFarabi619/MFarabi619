CREATE OR REPLACE FUNCTION extract_samples_from_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    instances_array JSONB;
    instance JSONB;
    metric_record RECORD;
    extracted_value DOUBLE PRECISION;
    array_index INT;
BEGIN
    instances_array := COALESCE(NEW.data->'instances', NEW.data->'sensors');

    IF instances_array IS NOT NULL AND jsonb_typeof(instances_array) = 'array' THEN
        FOR instance IN SELECT * FROM jsonb_array_elements(instances_array)
        LOOP
            IF (instance->>'read_ok')::BOOLEAN = FALSE THEN
                CONTINUE;
            END IF;

            FOR metric_record IN
                SELECT metrics.id, metrics.name
                FROM metrics
                WHERE metrics.type = NEW.type
            LOOP
                extracted_value := (instance->>metric_record.name)::DOUBLE PRECISION;

                IF extracted_value IS NOT NULL THEN
                    INSERT INTO samples (time, event_name, source, type, metric_id, instance_index, value)
                    VALUES (
                        NEW.time, NEW.name, NEW.source, NEW.type, metric_record.id,
                        COALESCE((instance->>'instance_index')::INT, (instance->>'index')::INT, 0),
                        extracted_value
                    )
                    ON CONFLICT DO NOTHING;
                END IF;
            END LOOP;
        END LOOP;
    ELSE
        IF (NEW.data->>'read_ok')::BOOLEAN = FALSE THEN
            RETURN NEW;
        END IF;

        FOR metric_record IN
            SELECT metrics.id, metrics.name
            FROM metrics
            WHERE metrics.type = NEW.type
        LOOP
            IF jsonb_typeof(NEW.data -> metric_record.name) = 'array' THEN
                FOR array_index IN 0..jsonb_array_length(NEW.data -> metric_record.name) - 1
                LOOP
                    extracted_value := (NEW.data -> metric_record.name ->> array_index)::DOUBLE PRECISION;

                    IF extracted_value IS NOT NULL THEN
                        INSERT INTO samples (time, event_name, source, type, metric_id, instance_index, value)
                        VALUES (NEW.time, NEW.name, NEW.source, NEW.type, metric_record.id, array_index, extracted_value)
                        ON CONFLICT DO NOTHING;
                    END IF;
                END LOOP;
            ELSE
                extracted_value := (NEW.data->>metric_record.name)::DOUBLE PRECISION;

                IF extracted_value IS NOT NULL THEN
                    INSERT INTO samples (time, event_name, source, type, metric_id, instance_index, value)
                    VALUES (NEW.time, NEW.name, NEW.source, NEW.type, metric_record.id, 0, extracted_value)
                    ON CONFLICT DO NOTHING;
                END IF;
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;
