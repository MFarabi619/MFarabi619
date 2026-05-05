WITH node_addresses AS (
    SELECT
        'arctic-rover.01'::text AS resource_name,
        '192.168.1.100'::ip4 AS address_ipv4

    UNION ALL

    SELECT
        format('toronto-transit-commission-subway.%s', lpad(node_numbers.node_number::text, 2, '0')) AS resource_name,
        format('10.42.0.%s', 10 + node_numbers.node_number)::ip4 AS address_ipv4
    FROM generate_series(1, 20) AS node_numbers(node_number)
)
INSERT INTO ipv4_addresses (resource_id, address_ipv4)
SELECT
    resources.id,
    node_addresses.address_ipv4
FROM node_addresses
JOIN resources
    ON resources.name = node_addresses.resource_name
   AND resources.type = 'microvisor:index:Node'
ON CONFLICT (resource_id)
DO UPDATE
SET address_ipv4 = EXCLUDED.address_ipv4,
    modified_at = CURRENT_TIMESTAMP;
