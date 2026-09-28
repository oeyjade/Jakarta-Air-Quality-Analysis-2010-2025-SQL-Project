-- ==========================================
-- 04_analysis_view.sql
-- One view with helper columns, so analysis queries stay short.
-- Excludes 'no data' days and rows flagged as unreliable in 02_cleaning.sql.
-- Assumption: Jakarta's dry season is approximated as May-October.
-- Columns are listed explicitly: MySQL fixes a view's column list when the
-- view is created, so SELECT * would not pick up columns added later.
-- ==========================================
USE jakarta_aq;

CREATE OR REPLACE VIEW v_ispu AS
SELECT id, obs_date, station,
       pm25, pm10, so2, co, o3, no2,
       max_val, critical, category, category_en,
       YEAR(obs_date)  AS yr,
       MONTH(obs_date) AS mth,
       CASE WHEN MONTH(obs_date) BETWEEN 5 AND 10 THEN 'Dry' ELSE 'Wet' END AS season,
       CASE WHEN DAYOFWEEK(obs_date) IN (1,7) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       (max_val > 100) AS is_unhealthy
FROM ispu_clean
WHERE max_val IS NOT NULL
  AND is_reliable = 1;

-- Should return 23,133
SELECT COUNT(*) FROM v_ispu;
