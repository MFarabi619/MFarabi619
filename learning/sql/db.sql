CREATE TABLE IF NOT EXISTS greeting(
    one TEXT,
    two TEXT
);

DELETE FROM greeting;

INSERT INTO greeting VALUES ('Hello', 'world!');
INSERT INTO greeting VALUES ('Hello', 'world again!');

SELECT * FROM greeting;
