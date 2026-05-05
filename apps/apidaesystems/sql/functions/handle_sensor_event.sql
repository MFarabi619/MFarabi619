CREATE OR REPLACE FUNCTION handle_sensor_event(payload bytea)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    message JSONB;
BEGIN
    message := convert_from(payload, 'UTF-8')::JSONB;

    INSERT INTO events (name, source, type, specversion, datacontenttype, time, data)
    VALUES (
        message->>'id',
        message->>'source',
        message->>'type',
        COALESCE(message->>'specversion', '1.0'),
        COALESCE(message->>'datacontenttype', 'application/json'),
        COALESCE((message->>'time')::TIMESTAMPTZ, CURRENT_TIMESTAMP),
        message->'data'
    )
    ON CONFLICT (time, name) DO NOTHING;
END;
$$;
