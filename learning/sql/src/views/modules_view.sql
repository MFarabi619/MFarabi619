CREATE VIEW modules_view AS
SELECT
    module.id,
    module.title,
    module.sku,
    brand.name AS vendor,
    module.wiki
FROM modules AS module
JOIN brands AS brand
    ON brand.id = module.vendor_id;
