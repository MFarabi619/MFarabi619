CREATE OR REPLACE FUNCTION poll_cloudevents(source_url TEXT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    response http_response;
    cloud_events JSONB;
    cloud_event JSONB;
    inserted_count INT := 0;
BEGIN
    SELECT * INTO response FROM http_get(source_url);

    IF response.status != 200 THEN
        RAISE WARNING 'poll_cloudevents failed for %: HTTP %', source_url, response.status;
        RETURN 0;
    END IF;

    cloud_events := response.content::JSONB;

    FOR cloud_event IN SELECT * FROM jsonb_array_elements(cloud_events)
    LOOP
        INSERT INTO events (name, source, type, specversion, datacontenttype, time, data)
        VALUES (
            cloud_event->>'id',
            cloud_event->>'source',
            cloud_event->>'type',
            cloud_event->>'specversion',
            cloud_event->>'datacontenttype',
            (cloud_event->>'time')::TIMESTAMPTZ,
            cloud_event->'data'
        )
        ON CONFLICT (time, name) DO NOTHING;

        IF FOUND THEN
            inserted_count := inserted_count + 1;
        END IF;
    END LOOP;

    RETURN inserted_count;
END;
$$;
