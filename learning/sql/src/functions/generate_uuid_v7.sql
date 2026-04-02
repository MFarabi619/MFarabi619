CREATE OR REPLACE FUNCTION generate_uuid_v7()
RETURNS UUID
LANGUAGE sql
AS $$
    SELECT uuid_generate_v7();
$$;
