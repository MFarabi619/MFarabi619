INSERT INTO organizations (name)
VALUES
('Apidae Systems'),
('Microvisor Systems'),
('Adafruit'),
('Arduino'),
('Bosch'),
('Bell Labs'),
('Sun Microsystems'),
('FreeBSD Foundation'),
('Linux Foundation'),
('Cloud Native Computing Foundation'),
('STMicroelectronics'),
('Xerox PARC'),
('Open Source Robotics Foundation'),
('Canonical'),
('Red Hat'),
('Collabora'),
('System76'),
('Framework'),
('SiFive'),
('Raspberry Pi Foundation'),
('Espressif'),
('NXP'),
('DFRobot'),
('Texas Instruments'),
('OpenBSD'),
('QEMU'),
('Tailscale'),
('Apple'),
('NATS')
ON CONFLICT (name) DO NOTHING;

UPDATE organizations
SET domain = 'apidae-systems.microvisor.systems'
WHERE name = 'Apidae Systems';

UPDATE organizations AS organization
SET symbol_asset_id = asset.id
FROM (
    VALUES
        ('OpenBSD', 'openbsd.png'),
        ('QEMU', 'qemu.svg'),
        ('Tailscale', 'tailscale.svg'),
        ('Apple', 'apple.svg'),
        ('NATS', 'nats.svg')
) AS organization_symbol(organization_name, filename)
JOIN assets AS asset
    ON asset.filename = organization_symbol.filename
WHERE organization.name = organization_symbol.organization_name;
