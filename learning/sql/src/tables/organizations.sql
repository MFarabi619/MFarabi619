CREATE TABLE organizations (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    slug TEXT GENERATED ALWAYS AS (
        lower(trim(both '-' FROM regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g')))
    ) STORED UNIQUE,
    domain TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
