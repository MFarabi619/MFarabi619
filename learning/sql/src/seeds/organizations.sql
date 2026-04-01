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
('Texas Instruments')
ON CONFLICT (name) DO NOTHING;

UPDATE organizations
SET domain = 'apidae-systems.microvisor.systems'
WHERE name = 'Apidae Systems';
