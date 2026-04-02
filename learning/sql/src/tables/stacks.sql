CREATE TABLE stacks(
    id UUID PRIMARY KEY DEFAULT generate_uuid_v7(),
    name TEXT NOT NULL,
    organization_id UUID NOT NULL REFERENCES organizations(id),
    UNIQUE (organization_id, name),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
