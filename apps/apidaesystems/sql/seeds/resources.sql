WITH target_organization AS (
    SELECT
        organizations.id AS organization_id,
        organizations.name AS organization_name,
        organizations.slug AS organization_slug,
        organizations.domain AS organization_domain
    FROM organizations
    WHERE organizations.name = 'Apidae Systems'
),
target_stack AS (
    SELECT stacks.id AS stack_id
    FROM stacks
    JOIN target_organization
        ON target_organization.organization_id = stacks.organization_id
    WHERE stacks.name = 'dev'
),
organization_resources AS (
    SELECT
        target_organization.organization_slug AS resource_name,
        'microvisor:index:Organization'::text AS resource_type,
        format(
            'urn:pulumi:dev::arctic-rover::microvisor:index:Organization::%s',
            target_organization.organization_slug
        ) AS resource_urn
    FROM target_organization
),
domain_resources AS (
    SELECT
        coalesce(
            target_organization.organization_domain,
            format('%s.microvisor.systems', target_organization.organization_slug)
        ) AS resource_name,
        'microvisor:index:Domain'::text AS resource_type,
        format(
            'urn:pulumi:dev::arctic-rover::microvisor:index:Domain::%s',
            coalesce(
                target_organization.organization_domain,
                format('%s.microvisor.systems', target_organization.organization_slug)
            )
        ) AS resource_urn
    FROM target_organization
),
static_resources AS (
    SELECT *
    FROM (
        VALUES
            ('arctic-rover', 'microvisor:index:Location', 'urn:pulumi:dev::arctic-rover::microvisor:index:Location::arctic-rover'),
            ('toronto-transit-commission-subway', 'microvisor:index:Location', 'urn:pulumi:dev::arctic-rover::microvisor:index:Location::toronto-transit-commission-subway'),
            ('arctic-rover-fleet', 'microvisor:index:Fleet', 'urn:pulumi:dev::arctic-rover::microvisor:index:Fleet::arctic-rover-fleet'),
            ('toronto-transit-commission-subway-fleet', 'microvisor:index:Fleet', 'urn:pulumi:dev::arctic-rover::microvisor:index:Fleet::toronto-transit-commission-subway-fleet')
    ) AS static_resource(resource_name, resource_type, resource_urn)
),
arctic_node_resources AS (
    SELECT
        'arctic-rover.01'::text AS resource_name,
        'microvisor:index:Node'::text AS resource_type,
        'urn:pulumi:dev::arctic-rover::microvisor:index:Node::arctic-rover.01'::text AS resource_urn
),
toronto_node_resources AS (
    SELECT
        format('toronto-transit-commission-subway.%s', lpad(node_numbers.node_number::text, 2, '0')) AS resource_name,
        'microvisor:index:Node'::text AS resource_type,
        format(
            'urn:pulumi:dev::arctic-rover::microvisor:index:Node::toronto-transit-commission-subway.%s',
            lpad(node_numbers.node_number::text, 2, '0')
        ) AS resource_urn
    FROM generate_series(1, 20) AS node_numbers(node_number)
),
all_node_resources AS (
    SELECT * FROM arctic_node_resources
    UNION ALL
    SELECT * FROM toronto_node_resources
),
sim_card_resources AS (
    SELECT
        format('%s-sim-card', all_node_resources.resource_name) AS resource_name,
        'microvisor:index:SimCard'::text AS resource_type,
        format(
            'urn:pulumi:dev::arctic-rover::microvisor:index:SimCard::%s-sim-card',
            all_node_resources.resource_name
        ) AS resource_urn
    FROM all_node_resources
),
all_resources AS (
    SELECT * FROM organization_resources
    UNION ALL
    SELECT * FROM domain_resources
    UNION ALL
    SELECT * FROM static_resources
    UNION ALL
    SELECT * FROM all_node_resources
    UNION ALL
    SELECT * FROM sim_card_resources
)
INSERT INTO resources (name, stack_id, urn, type, package, module)
SELECT
    all_resources.resource_name,
    target_stack.stack_id,
    all_resources.resource_urn,
    all_resources.resource_type,
    'microvisor'::text AS package,
    'index'::text AS module
FROM all_resources
CROSS JOIN target_stack
ON CONFLICT (urn) DO NOTHING;
