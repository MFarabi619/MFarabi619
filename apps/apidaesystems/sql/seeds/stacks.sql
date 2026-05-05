INSERT INTO stacks (name, organization_id)
SELECT
    stack_data.stack_name,
    organization.id
FROM (
    VALUES
        ('dev', 'Apidae Systems'),
        ('dev', 'Microvisor Systems')
) AS stack_data(stack_name, organization_name)
JOIN organizations AS organization
    ON organization.name = stack_data.organization_name
ON CONFLICT (organization_id, name) DO NOTHING;
