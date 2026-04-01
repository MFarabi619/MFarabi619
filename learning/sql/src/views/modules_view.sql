CREATE VIEW modules_view AS
SELECT
    module.id,
    module.title,
    module.sku,
    organization.name AS vendor,
    module.wiki
FROM modules AS module
JOIN organizations AS organization
    ON organization.id = module.organization_id;
