
CREATE TABLE device_metrics(
 time TIMESTAMP WITH TIME ZONE NOT NULL,
 device_id INT NOT NULL,
 temperature FLOAT NOT NULL,
 humidity FLOAT NOT NULL
);

SELECT create_hypertable('device_metrics', 'time');

CREATE TABLE environmental_data (
time TIMESTAMP WITH TIME ZONE NOT NULL,
sensor_id INT NOT NULL,
temperature DECIMAL NOT NULL,
humidity DECIMAL NOT NULL
);

SELECT create_hypertable('environmental_data', 'time');

INSERT INTO environmental_data (time, sensor_id, temperature, humidity) VALUES
('2024-03-15 10:00:00+00', 1, 25.3, 30.2),
('2024-03-15 10:05:00+00', 1, 25.4, 30.3),
('2024-03-15 10:10:00+00', 2, 20.5, 45.2);

SELECT sensor_id, AVG(temperature) AS avg_temperature, AVG(humidity) AS avg_humidity
FROM environmental_data
GROUP BY sensor_id;

CREATE TABLE web_metrics (
time TIMESTAMP WITH TIME ZONE NOT NULL,
endpoint TEXT NOT NULL,
response_time_ms INT NOT NULL,
status_code INT NOT NULL
);

SELECT create_hypertable('web_metrics', 'time');

INSERT INTO web_metrics (time, endpoint, response_time_ms, status_code) VALUES
('2024-03-15 09:00:00+00', '/api/data', 150, 200),
('2024-03-15 09:01:00+00', '/api/data', 145, 200),
('2024-03-15 09:02:00+00', '/api/user', 160, 404);

SELECT endpoint, AVG(response_time_ms) AS avg_response_time
FROM web_metrics
GROUP BY endpoint;

-- list databases
\l
-- list relations
\d
-- list tables
\dt+
\dt
