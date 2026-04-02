CREATE TABLE ipv4_addresses (
    id UUID PRIMARY KEY DEFAULT generate_uuid_v7(),
    resource_id UUID NOT NULL REFERENCES resources(id),
    address_ipv4 ip4 NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (resource_id),
    UNIQUE (address_ipv4)
);
