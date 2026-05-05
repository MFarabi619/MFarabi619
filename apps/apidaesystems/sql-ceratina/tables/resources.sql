CREATE TABLE resources(
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    name TEXT NOT NULL,
    stack_id UUID NOT NULL REFERENCES stacks(id),
    urn TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL,
    package TEXT NOT NULL,
    module TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX resources_stack_id_idx ON resources (stack_id);
CREATE INDEX resources_type_idx ON resources (type);
