INSERT INTO modules (title, sku, wiki, organization_id)
SELECT
    data.title,
    data.sku,
    data.wiki,
    organization.id
FROM (
    VALUES
        ('SHT31 Temperature & Humidity Sensor', 'SEN0385', 'https://wiki.dfrobot.com/SHT31_Temperature_Humidity_Sensor_SKU_SEN0385', 'DFRobot'),
        ('RS485 Photoelectric Solar Radiation Sensor', 'SEN0640', 'https://wiki.dfrobot.com/SKU_SEN0640_RS485_Photoelectric_Solar_Radiation_Sensor', 'DFRobot'),
        ('RS485 Wind Direction Transmitter V2', 'SEN0482', 'https://wiki.dfrobot.com/SKU_SEN0482_RS485_Wind_Direction_Transmitter_V2', 'DFRobot'),
        ('RS485 Wind Speed Transmitter', 'SEN0483', 'https://wiki.dfrobot.com/RS485_Wind_Speed_Transmitter_SKU_SEN0483', 'DFRobot'),
        ('INA228 I2C Power Monitor', 'INA228', 'https://learn.adafruit.com/adafruit-ina228-i2c-power-monitor', 'Adafruit')
) AS data(title, sku, wiki, organization_name)
JOIN organizations AS organization
    ON organization.name = data.organization_name;
