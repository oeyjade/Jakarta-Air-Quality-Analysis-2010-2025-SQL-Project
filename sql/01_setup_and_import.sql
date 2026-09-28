-- ==========================================
-- 01_setup_and_import.sql
-- ==========================================
-- How to run: open Terminal in the project's root folder and run
--   mysql --local-infile=1 -u root -p < sql/01_setup_and_import.sql
-- The CSV paths are relative to the project's root folder.
-- Run SET GLOBAL local_infile = 1; once beforehand if loading is disabled.

CREATE DATABASE IF NOT EXISTS jakarta_aq;
USE jakarta_aq;

-- ==========================================
-- 1. One staging table for all five station files
-- ==========================================
-- Every column is text so messy values cannot break the import.
-- source_file records which CSV each row came from.
DROP TABLE IF EXISTS staging_ispu;
CREATE TABLE staging_ispu (
  source_file VARCHAR(30),
  tanggal VARCHAR(30), stasiun VARCHAR(100),
  pm25 VARCHAR(20), pm10 VARCHAR(20), so2 VARCHAR(20),
  co VARCHAR(20), o3 VARCHAR(20), no2 VARCHAR(20),
  max_val VARCHAR(20), critical VARCHAR(30), categori VARCHAR(40)
);

-- ==========================================
-- 2. Load the five station files into it
-- ==========================================
-- The column list maps the 11 CSV columns by position; SET fills source_file.
LOAD DATA LOCAL INFILE 'data/ispu_dki1.csv' INTO TABLE staging_ispu
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS
(tanggal, stasiun, pm25, pm10, so2, co, o3, no2, max_val, critical, categori)
SET source_file = 'ispu_dki1.csv';

LOAD DATA LOCAL INFILE 'data/ispu_dki2.csv' INTO TABLE staging_ispu
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS
(tanggal, stasiun, pm25, pm10, so2, co, o3, no2, max_val, critical, categori)
SET source_file = 'ispu_dki2.csv';

LOAD DATA LOCAL INFILE 'data/ispu_dki3.csv' INTO TABLE staging_ispu
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS
(tanggal, stasiun, pm25, pm10, so2, co, o3, no2, max_val, critical, categori)
SET source_file = 'ispu_dki3.csv';

LOAD DATA LOCAL INFILE 'data/ispu_dki4.csv' INTO TABLE staging_ispu
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS
(tanggal, stasiun, pm25, pm10, so2, co, o3, no2, max_val, critical, categori)
SET source_file = 'ispu_dki4.csv';

LOAD DATA LOCAL INFILE 'data/ispu_dki5.csv' INTO TABLE staging_ispu
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS
(tanggal, stasiun, pm25, pm10, so2, co, o3, no2, max_val, critical, categori)
SET source_file = 'ispu_dki5.csv';

-- ==========================================
-- 3. Check row counts for each file
-- ==========================================
-- Expected: 5,173 rows per file, 25,865 in total
SELECT source_file, COUNT(*) AS n FROM staging_ispu GROUP BY source_file
UNION ALL
SELECT 'total', COUNT(*) FROM staging_ispu;

SELECT * FROM staging_ispu LIMIT 5;

-- ==========================================
-- 4. The city-wide file (loaded for reference only)
-- ==========================================
-- ispu_dki_all.csv has a different grain: one row per day holding the
-- worst station's reading (city-day, not station-day). It includes 2022,
-- which the station files do not. It is not mixed into the station-level
-- analysis, because that would double-count days and distort station
-- comparisons.
DROP TABLE IF EXISTS staging_ispu_dki_all;
CREATE TABLE staging_ispu_dki_all LIKE staging_ispu;

LOAD DATA LOCAL INFILE 'data/ispu_dki_all.csv' INTO TABLE staging_ispu_dki_all
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS
(tanggal, stasiun, pm25, pm10, so2, co, o3, no2, max_val, critical, categori)
SET source_file = 'ispu_dki_all.csv';

-- Finding: 5,538 rows, one per day from 2010-01-01 to 2025-02-28,
--          including all 365 days of 2022.
SELECT LEFT(tanggal, 4) AS yr, COUNT(*) AS days
FROM staging_ispu_dki_all GROUP BY yr ORDER BY yr;
