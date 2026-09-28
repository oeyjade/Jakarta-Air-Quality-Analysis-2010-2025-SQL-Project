-- ==========================================
-- 05_analysis.sql
-- Business questions answered with the v_ispu view.
-- Note: 2010 covers mostly one station (others start late 2010 / late 2012)
--       and 2025 covers only January-February, so both are partial years.
-- ==========================================
USE jakarta_aq;

-- Q1: Is Jakarta's air getting better or worse?
-- Finding: no steady improvement. Worst year was 2012 (avg 98.4, 31.2% of
--          station-days unhealthy); 2018-2019 were also bad (~80, ~20%);
--          2020 dipped to 67.6 / 7.4%; 2021-2024 settled around 75-78.
SELECT yr, ROUND(AVG(max_val),1) AS avg_ispu,
       ROUND(100*AVG(is_unhealthy),1) AS pct_unhealthy_days
FROM v_ispu GROUP BY yr ORDER BY yr;

-- Q1b: Same trend with every station weighted equally
-- Q1 averages all station-days, so years where fewer stations reported
-- (2010 is mostly DKI1; DKI5 starts late 2012) are weighted toward those
-- stations. Averaging each station first, then the stations, removes that.
-- Finding: the pattern holds. 2012 is still the worst year (90.9 vs 98.4
--          in Q1, since DKI2's extreme 2012 readings count for less);
--          2010 rises from 59.4 to 63.3; other years change by under 1.
WITH station_year AS (
  SELECT yr, station, AVG(max_val) AS station_avg
  FROM v_ispu GROUP BY yr, station)
SELECT yr, COUNT(*) AS stations, ROUND(AVG(station_avg),1) AS avg_of_stations
FROM station_year GROUP BY yr ORDER BY yr;

-- Q2: Year-over-year change
-- LAG returns the previous row, not the previous calendar year. 2022 is
-- missing, so the change is only shown when the previous row is yr - 1
-- (2023 is left blank instead of being compared with 2021).
-- Finding: biggest drops were 2013 (-18.5) and 2020 (-13.2);
--          biggest jumps were 2012 (+23.1), 2011 (+15.9, though 2010 is
--          mostly one station) and 2018 (+12.8).
--          2025 covers only January-February, so its change is not comparable.
WITH yearly AS (SELECT yr, AVG(max_val) AS avg_ispu FROM v_ispu GROUP BY yr),
with_prev AS (
  SELECT yr, avg_ispu,
         LAG(yr)       OVER (ORDER BY yr) AS prev_yr,
         LAG(avg_ispu) OVER (ORDER BY yr) AS prev_avg
  FROM yearly)
SELECT yr, ROUND(avg_ispu,1) AS avg_ispu,
       CASE WHEN prev_yr = yr - 1 THEN ROUND(avg_ispu - prev_avg,1) END AS change_vs_prev_year
FROM with_prev ORDER BY yr;

-- Q3: Which months are worst?
-- Finding: air worsens steadily from January (54.6) to October (86.5),
--          then improves sharply in December (59.6). July-November each
--          have ~18-21% unhealthy days vs ~3% in January.
SELECT mth, ROUND(AVG(max_val),1) AS avg_ispu,
       ROUND(100*AVG(is_unhealthy),1) AS pct_unhealthy_days
FROM v_ispu GROUP BY mth ORDER BY mth;

-- Q4: Dry vs wet season
-- Finding: dry season averages 82.4 vs 66.4 in the wet season, with
--          17.5% vs 9.9% unhealthy days (about 1.8x as many).
SELECT season, ROUND(AVG(max_val),1) AS avg_ispu,
       ROUND(100*AVG(is_unhealthy),1) AS pct_unhealthy_days
FROM v_ispu GROUP BY season;

-- Q5: Station ranking by year
-- Finding: no station is consistently the worst. DKI2 Kelapa Gading led
--          in 2012-2013 (147.1 in 2012), DKI5 Kebon Jeruk in 2018-2020,
--          DKI4 Lubang Buaya in 2021 and 2023. DKI1 Bundaran HI (city
--          centre) ranked last or near last in most years.
SELECT yr, station, ROUND(AVG(max_val),1) AS avg_ispu,
       RANK() OVER (PARTITION BY yr ORDER BY AVG(max_val) DESC) AS rank_in_year
FROM v_ispu GROUP BY yr, station ORDER BY yr, rank_in_year;

-- Q6: Which pollutant is most often the critical one?
-- Finding: overall, O3 (46.9%), PM10 (27.5%) and PM2.5 (21.3%).
--          Misleading on its own, since PM2.5 was only measured from late
--          2020 (see Q12).
SELECT critical, COUNT(*) AS days,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct
FROM v_ispu WHERE critical IS NOT NULL
GROUP BY critical ORDER BY days DESC;

-- Q7: Weekday vs weekend (CO and NO2 come largely from traffic)
-- Finding: virtually no difference (74.4 vs 74.2), so weekly traffic
--          patterns are not visible in the daily index.
SELECT day_type, ROUND(AVG(max_val),1) AS avg_ispu,
       ROUND(AVG(co),1) AS avg_co, ROUND(AVG(no2),1) AS avg_no2
FROM v_ispu GROUP BY day_type;

-- Q8: COVID restrictions (PSBB began April 2020): 2019 vs 2020 by month
-- Finding: March 2020 was worse than March 2019 (75.7 vs 68.6), but
--          every month from April to December 2020 was cleaner than 2019;
--          the average of the April-December monthly values fell from
--          86.3 to 69.4 (about -20%).
--          January-February 2020 were also cleaner, so weather and other
--          factors likely contributed (correlation, not proof).
SELECT mth,
       ROUND(AVG(CASE WHEN yr = 2019 THEN max_val END),1) AS avg_2019,
       ROUND(AVG(CASE WHEN yr = 2020 THEN max_val END),1) AS avg_2020
FROM v_ispu WHERE yr IN (2019, 2020)
GROUP BY mth ORDER BY mth;

-- Q9: The 10 worst days on record
-- Finding: 9 of the 10 worst readings were ozone at DKI2 Kelapa Gading in
--          2012, including the only 'Hazardous' day (314 on 2012-11-04).
--          The exception is PM2.5 at DKI4 Lubang Buaya (287, 2023-09-28).
SELECT obs_date, station, max_val, critical, category_en
FROM v_ispu ORDER BY max_val DESC LIMIT 10;

-- Q10: 7-day rolling average per station (smooths daily noise to show trends)
-- RANGE with INTERVAL uses calendar days, so missing or flagged days do not
-- stretch the window further back (ROWS would count the last 7 rows).
-- days_in_window shows how many readings each average is based on.
SELECT station, obs_date, max_val,
       ROUND(AVG(max_val) OVER w, 1) AS rolling_7d,
       COUNT(max_val) OVER w        AS days_in_window
FROM v_ispu
WINDOW w AS (PARTITION BY station ORDER BY obs_date
             RANGE BETWEEN INTERVAL 6 DAY PRECEDING AND CURRENT ROW);

-- Q11: Longest streaks of consecutive unhealthy days ("gaps and islands")
-- Missing and flagged days are not in v_ispu, so they end a streak;
-- streak lengths are therefore conservative (never overstated).
-- Finding: the longest was 65 days at DKI5 Kebon Jeruk
--          (14 July - 16 September 2018). Next were DKI2 Kelapa Gading with
--          33 days (Dec 2012 - Jan 2013) and DKI4 Lubang Buaya with 32 days
--          (Oct - Nov 2023).
WITH unhealthy AS (
  SELECT station, obs_date,
         DATE_SUB(obs_date, INTERVAL ROW_NUMBER() OVER
           (PARTITION BY station ORDER BY obs_date) DAY) AS grp
  FROM v_ispu WHERE is_unhealthy = 1)
SELECT station, MIN(obs_date) AS streak_start, MAX(obs_date) AS streak_end,
       COUNT(*) AS streak_days
FROM unhealthy GROUP BY station, grp
ORDER BY streak_days DESC LIMIT 10;

-- Q12: Which pollutant drives bad air since PM2.5 was added to the index?
-- Finding: since 2021, PM2.5 is critical on 83.5% of days and on 98.3% of
--          unhealthy days. In 2010-2020, before PM2.5 was measured, O3 was
--          critical on 60.9% of days and PM10 on 34.5%. Because PM2.5 was not
--          measured earlier, this does not prove the main pollutant changed.
-- The small PM2.5 share in 2010-2020 comes from Sep-Dec 2020, when PM2.5
-- was already part of the index (see the 205-row check in 02_cleaning.sql).
WITH periods AS (
  SELECT CASE WHEN yr < 2021 THEN '2010-2020' ELSE '2021-2025' END AS period,
         critical
  FROM v_ispu)
SELECT period, critical, COUNT(*) AS days,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (PARTITION BY period),1) AS pct
FROM periods
GROUP BY period, critical
ORDER BY period, days DESC;

SELECT critical, COUNT(*) AS unhealthy_days,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct
FROM v_ispu
WHERE is_unhealthy = 1 AND yr >= 2021
GROUP BY critical ORDER BY unhealthy_days DESC;
