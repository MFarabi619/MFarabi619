CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT generate_uuid_v7(),
    name TEXT NOT NULL UNIQUE,
    slug TEXT GENERATED ALWAYS AS (
        lower(trim(both '-' FROM regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g')))
    ) STORED UNIQUE,
    domain TEXT UNIQUE,
    symbol_asset_id UUID REFERENCES assets(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
