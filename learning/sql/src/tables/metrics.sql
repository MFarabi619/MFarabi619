CREATE TABLE metrics (
    id UUID PRIMARY KEY DEFAULT generate_uuid_v7(),
    type TEXT NOT NULL,
    name TEXT NOT NULL,
    unit TEXT NOT NULL,
    UNIQUE (type, name)
);
