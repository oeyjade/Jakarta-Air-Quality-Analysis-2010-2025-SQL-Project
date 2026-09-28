-- ==========================================
-- 02_cleaning.sql
-- ==========================================
USE jakarta_aq;
-- ------------------------------------------
-- Part A: Explore the raw data before cleaning
-- ------------------------------------------

-- Preview rows to check that columns loaded in the right order
-- Finding: columns aligned correctly; dates in YYYY-MM-DD format;
--          pm25 is blank in early years (not yet measured)
SELECT * FROM staging_ispu LIMIT 10;

-- Check station names for spelling variations
-- Finding: 5 stations with consistent names, 5,173 rows each.
--          Names use brackets, e.g. 'DKI1 (Bunderan HI)'; standardized in Part B.
SELECT stasiun, COUNT(*) FROM staging_ispu GROUP BY stasiun;

-- Check category values for inconsistencies
-- Finding: 6 categories, no spelling variations. 2,409 rows are
--          'TIDAK ADA DATA' (no data); only 1 day is 'BERBAHAYA' (hazardous).
SELECT categori, COUNT(*) FROM staging_ispu GROUP BY categori;

-- Check which pollutants appear as critical
-- Finding: O3 is the most frequent critical pollutant (10,863 days),
--          followed by PM10 (6,398) and PM2.5 (4,998). 2,409 blanks
--          match the 'no data' rows exactly.
SELECT critical, COUNT(*) FROM staging_ispu GROUP BY critical;

-- Check the date range
-- Finding: 2010-01-01 to 2025-02-28. 5,538 days in this period minus
--          the 365 days of 2022 = 5,173 days per station,
--          confirming the station files have no data for 2022.
SELECT MIN(tanggal), MAX(tanggal) FROM staging_ispu;

-- Check for duplicate station-days before loading the clean table
-- Finding: no duplicates (0 rows returned)
SELECT tanggal, stasiun, COUNT(*) AS copies
FROM staging_ispu
GROUP BY tanggal, stasiun
HAVING COUNT(*) > 1;

-- ------------------------------------------
-- Part B: Build the clean table
-- ------------------------------------------

DROP TABLE IF EXISTS ispu_clean;
CREATE TABLE ispu_clean (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  obs_date  DATE,
  station   VARCHAR(100),
  pm25      DECIMAL(6,1),
  pm10      DECIMAL(6,1),
  so2       DECIMAL(6,1),
  co        DECIMAL(6,1),
  o3        DECIMAL(6,1),
  no2       DECIMAL(6,1),
  max_val   DECIMAL(6,1),
  critical  VARCHAR(20),
  category  VARCHAR(40),
  category_en VARCHAR(20) GENERATED ALWAYS AS (
    CASE WHEN max_val IS NULL THEN NULL
         WHEN max_val <= 50  THEN 'Good'
         WHEN max_val <= 100 THEN 'Moderate'
         WHEN max_val <= 200 THEN 'Unhealthy'
         WHEN max_val <= 300 THEN 'Very Unhealthy'
         ELSE 'Hazardous' END) STORED,
  UNIQUE KEY uq_date_station (obs_date, station),
  -- Supports the window queries, which partition by station and order by date
  KEY idx_station_date (station, obs_date)
);

-- A plain INSERT (not INSERT IGNORE): Part A found no duplicates, so any
-- duplicate or conversion error here should stop the load, not be skipped.
INSERT INTO ispu_clean
  (obs_date, station, pm25, pm10, so2, co, o3, no2, max_val, critical, category)
SELECT
  CASE
    WHEN tanggal REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN DATE(LEFT(tanggal, 10))
    WHEN tanggal REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}' THEN STR_TO_DATE(tanggal, '%d/%m/%Y')
  END,
  CASE
    WHEN stasiun LIKE '%DKI1%' THEN 'DKI1 Bundaran HI'
    WHEN stasiun LIKE '%DKI2%' THEN 'DKI2 Kelapa Gading'
    WHEN stasiun LIKE '%DKI3%' THEN 'DKI3 Jagakarsa'
    WHEN stasiun LIKE '%DKI4%' THEN 'DKI4 Lubang Buaya'
    WHEN stasiun LIKE '%DKI5%' THEN 'DKI5 Kebon Jeruk'
    ELSE TRIM(stasiun)
  END,
  -- Keep values that are whole numbers or decimals (e.g. 73 or 73.0); blanks become NULL
  CASE WHEN TRIM(pm25) REGEXP '^[0-9]+([.][0-9]+)?$' THEN TRIM(pm25) END,
  CASE WHEN TRIM(pm10) REGEXP '^[0-9]+([.][0-9]+)?$' THEN TRIM(pm10) END,
  CASE WHEN TRIM(so2)  REGEXP '^[0-9]+([.][0-9]+)?$' THEN TRIM(so2)  END,
  CASE WHEN TRIM(co)   REGEXP '^[0-9]+([.][0-9]+)?$' THEN TRIM(co)   END,
  CASE WHEN TRIM(o3)   REGEXP '^[0-9]+([.][0-9]+)?$' THEN TRIM(o3)   END,
  CASE WHEN TRIM(no2)  REGEXP '^[0-9]+([.][0-9]+)?$' THEN TRIM(no2)  END,
  CASE WHEN TRIM(max_val) REGEXP '^[0-9]+([.][0-9]+)?$' THEN TRIM(max_val) END,
  -- Removing '\r' is defensive: the current files use '\n' line endings,
  -- but a re-export from Windows would leave '\r' on the last column
  NULLIF(UPPER(TRIM(REPLACE(critical, '\r', ''))), ''),
  NULLIF(UPPER(TRIM(REPLACE(categori, '\r', ''))), '')
FROM staging_ispu;

-- ------------------------------------------
-- Part C: Verify the cleaning
-- ------------------------------------------

-- Row counts should be equal (25,865 each)
SELECT (SELECT COUNT(*) FROM staging_ispu) AS staging_rows,
       (SELECT COUNT(*) FROM ispu_clean)   AS clean_rows;

-- Should be 0 if all dates converted correctly
SELECT COUNT(*) AS bad_dates FROM ispu_clean WHERE obs_date IS NULL;

-- Should show exactly 5 stations
SELECT station, COUNT(*) FROM ispu_clean GROUP BY station;

-- Original Indonesian labels vs. labels recalculated from max_val
-- Finding: 2,350 'no data' rows had placeholder values and were
--          counted as 'Good' (fixed in Part D). 168 other rows (~0.7%)
--          have labels that disagree with max_val; category_en is
--          used for analysis because it is calculated consistently.
SELECT category, category_en, COUNT(*) FROM ispu_clean
GROUP BY category, category_en ORDER BY category;

-- ------------------------------------------
-- Part D: Fix issues found during verification
-- ------------------------------------------

-- Check what max_val contains on 'no data' days
-- Finding: 0.0 on 2,350 rows, NULL on 59
SELECT max_val, COUNT(*) FROM ispu_clean
WHERE category = 'TIDAK ADA DATA' GROUP BY max_val;

-- Safe update mode blocks UPDATEs whose WHERE is not on a key column.
-- It is switched off for Parts D and E and back on at the end of Part E.
SET SQL_SAFE_UPDATES = 0;

-- 'No data' days hold placeholder values instead of NULL, which made
-- 2,350 of them count as 'Good'. Set them to NULL so they are excluded.
UPDATE ispu_clean
SET pm25 = NULL, pm10 = NULL, so2 = NULL, co = NULL,
    o3 = NULL, no2 = NULL, max_val = NULL
WHERE category = 'TIDAK ADA DATA';

-- Re-check: every 'TIDAK ADA DATA' row should now show NULL
SELECT category, category_en, COUNT(*) FROM ispu_clean
GROUP BY category, category_en ORDER BY category;

-- ------------------------------------------
-- Part E: Flag rows with misaligned columns
-- ------------------------------------------

-- Keep the rows but flag them, so they can be excluded from analysis
-- (deleting them would hide the problem instead of documenting it)
ALTER TABLE ispu_clean ADD COLUMN is_reliable TINYINT(1) NOT NULL DEFAULT 1;

-- Consistency rule, defined once here:
--   Test 1: max_val must not be smaller than the highest pollutant value.
--           COALESCE(x,0) is needed because GREATEST returns NULL if any
--           argument is NULL (PM2.5 is blank before 2021).
--   Test 2: the pollutant named in 'critical' must hold the max_val value.
--           If that pollutant's value is not published, test 2 cannot be
--           applied, so the COALESCE makes the comparison pass explicitly
--           (see the check below) instead of relying on a NULL comparison.
UPDATE ispu_clean
SET is_reliable = 0
WHERE max_val IS NOT NULL
  AND (max_val < GREATEST(COALESCE(pm25,0), COALESCE(pm10,0), COALESCE(so2,0),
                          COALESCE(co,0),   COALESCE(o3,0),   COALESCE(no2,0))
       OR max_val <> COALESCE(CASE critical WHEN 'PM25' THEN pm25 WHEN 'PM10' THEN pm10
                                            WHEN 'SO2'  THEN so2  WHEN 'CO'   THEN co
                                            WHEN 'O3'   THEN o3   WHEN 'NO2'  THEN no2 END,
                              max_val));

SET SQL_SAFE_UPDATES = 1;

-- Should return 323
SELECT COUNT(*) AS unreliable_rows FROM ispu_clean WHERE is_reliable = 0;

-- Where the flagged rows are
-- Finding: 323 rows (~1.4% of rows with data). They are concentrated in
--          Sep 2020 - Jan 2021 (mostly DKI4 and DKI5, plus Nov 2020 at
--          DKI1-DKI3) and Jan 2023 at DKI5, where values in the source
--          files appear shifted into the wrong columns.
SELECT DATE_FORMAT(obs_date, '%Y-%m') AS yr_month, station, COUNT(*) AS bad_rows
FROM ispu_clean
WHERE is_reliable = 0
GROUP BY yr_month, station
ORDER BY yr_month, station;

-- Rows kept as reliable although the critical pollutant's value is blank
-- Finding: 205 rows, almost all Sep 2020 - Jan 2021 with critical = 'PM25'
--          (plus 1 with 'SO2'). PM2.5 was already part of the index then,
--          but its readings were not published until January 2021. These
--          rows pass test 1, so they are kept; they are the small PM2.5
--          share in the 2010-2020 period in Q12.
SELECT DATE_FORMAT(obs_date, '%Y-%m') AS yr_month, critical, COUNT(*) AS n
FROM ispu_clean
WHERE is_reliable = 1 AND max_val IS NOT NULL
  AND critical IN ('PM25','PM10','SO2','CO','O3','NO2')
  AND CASE critical WHEN 'PM25' THEN pm25 WHEN 'PM10' THEN pm10
                    WHEN 'SO2'  THEN so2  WHEN 'CO'   THEN co
                    WHEN 'O3'   THEN o3   WHEN 'NO2'  THEN no2 END IS NULL
GROUP BY yr_month, critical
ORDER BY yr_month;

-- Label mismatches that remain among reliable rows
-- Finding: only 25 mismatches remain: 19 days at DKI1 in Dec 2024
--          labelled BAIK despite values of 53-78, 4 days at exactly 200
--          (a boundary case), and 2 others. category_en is used instead.
SELECT category, category_en, COUNT(*) FROM ispu_clean
WHERE is_reliable = 1 AND max_val IS NOT NULL
GROUP BY category, category_en ORDER BY category;
