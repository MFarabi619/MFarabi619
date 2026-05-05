WITH icon_assets AS (
    SELECT *
    FROM (
        VALUES
            ('openbsd.png'),
            ('qemu.svg'),
            ('tailscale.svg'),
            ('apple.svg'),
            ('nats.svg')
    ) AS icon_asset(filename)
),
prepared_assets AS (
    SELECT
        icon_assets.filename,
        pg_read_binary_file(format('%s/assets/icons/%s', :'devenv_root', icon_assets.filename)) AS image_data
    FROM icon_assets
)
INSERT INTO assets (filename, content_type, image_data)
SELECT
    prepared_assets.filename,
    byteamagic_mime(prepared_assets.image_data),
    prepared_assets.image_data
FROM prepared_assets
ON CONFLICT (filename)
DO UPDATE
SET content_type = EXCLUDED.content_type,
    image_data = EXCLUDED.image_data;
