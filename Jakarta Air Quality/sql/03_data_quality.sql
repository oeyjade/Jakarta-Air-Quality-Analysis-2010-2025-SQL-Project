-- ==========================================
-- 03_data_quality.sql
-- Checks coverage and completeness after cleaning
-- ==========================================
USE jakarta_aq;

-- Missing values per pollutant per year
SELECT YEAR(obs_date) AS yr, COUNT(*) AS total_rows,
       SUM(pm25 IS NULL) AS pm25_missing, SUM(pm10 IS NULL) AS pm10_missing,
       SUM(so2 IS NULL)  AS so2_missing,  SUM(co IS NULL)   AS co_missing,
       SUM(o3 IS NULL)   AS o3_missing,   SUM(no2 IS NULL)  AS no2_missing
FROM ispu_clean GROUP BY yr ORDER BY yr;

-- Usable days per station per year (excludes 'no data' and flagged rows)
SELECT station, YEAR(obs_date) AS yr, COUNT(*) AS usable_days
FROM ispu_clean
WHERE max_val IS NOT NULL AND is_reliable = 1
GROUP BY station, yr ORDER BY station, yr;

-- Suspicious values (the ISPU scale tops out around 500)
SELECT * FROM ispu_clean
WHERE max_val > 500 OR pm10 > 500 OR pm25 > 500;
