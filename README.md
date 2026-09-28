# Jakarta Air Quality Analysis (2010–2025) | SQL Project

An analysis of 15 years of daily air quality readings from five monitoring stations in Jakarta, Indonesia. I used MySQL to import, clean, and validate the data, then answered questions about long-term trends, seasonality, station differences, and the pollutants behind unhealthy air.

**Tools:** MySQL 9, MySQL Workbench

## Data Source

- Air Pollutant Standard Index (ISPU, *Indeks Standar Pencemar Udara*) data published by Satu Data Jakarta, via the Kaggle dataset "Air Quality Index in Jakarta (2010-2021)" by senadu34 (updated to February 2025)
- Five stations: DKI1 Bundaran HI, DKI2 Kelapa Gading, DKI3 Jagakarsa, DKI4 Lubang Buaya, DKI5 Kebon Jeruk
- 25,865 rows (5 stations × 5,173 days, January 2010 to February 2025, no station-level data for 2022)
- A sixth file, `ispu_dki_all.csv`, holds one row per day for the worst station (including 2022). It has a different grain (city-day instead of station-day), so it is loaded for reference but not mixed into the analysis
- Each row holds the index for PM10, PM2.5, SO2, CO, O3 and NO2, the highest value of the day (`max`), the pollutant responsible (`critical`), and a category

The ISPU scale: 0–50 Good, 51–100 Moderate, 101–200 Unhealthy, 201–300 Very Unhealthy, above 300 Hazardous. In this project a station-day counts as "unhealthy" when the index is above 100.

## Questions

1. Is Jakarta's air quality getting better or worse?
2. Which months and seasons have the worst air?
3. Which stations are the most polluted?
4. Which pollutants drive poor air quality?
5. Did the COVID-19 restrictions in 2020 improve air quality?

## Key Findings

**1. PM2.5 dominates unhealthy air days since it was added to the index.** Since PM2.5 was included in the index (from September 2020, with PM2.5 readings in the data from 2021), it has been the critical pollutant on 84% of days in 2021–2025 and on 98% of unhealthy days. Before then, when PM2.5 was not measured, ozone (O3) was the critical pollutant on 61% of days and PM10 on 35%. Because PM2.5 was not measured earlier, the data cannot show whether it was already the main pollutant before 2020; what it does show is that fine particulate matter is the key driver of bad air days today.

**2. There is no steady improvement over 15 years.** The worst year was 2012 (average index 98.4, with 31% of station-days unhealthy), followed by 2018–2019 (about 80 and 20%). From 2021 to 2024, the average held at around 75–78, with 10–15% of days unhealthy. Because the index method changed in 2020, years before and after that point are not a like-for-like comparison. Weighting every station equally (instead of every station-day) gives the same pattern, with 2012 still the worst year (90.9).

**3. Air quality follows a strong seasonal cycle.** The index rises steadily from January (54.6) to October (86.5) and drops sharply in December (59.6). The dry season (May–October) has about 1.8 times as many unhealthy days as the wet season (17.5% vs 9.9%).

**4. COVID-19 restrictions coincided with cleaner air.** Every month from April to December 2020 was cleaner than the same month in 2019, and the average of the April–December monthly values fell by about 20% (from 86.3 to 69.4). March 2020, before the restrictions began, was actually worse than March 2019. However, January and February 2020 were also cleaner than 2019, so other factors such as weather likely contributed, and this comparison shows a correlation rather than proof that the restrictions caused the improvement.

**5. Pollution hotspots move between stations.** No station was consistently the worst: Kelapa Gading led in 2012–2013, Kebon Jeruk in 2018–2020, and Lubang Buaya in 2021 and 2023. Surprisingly, Bundaran HI in the city centre ranked last or near last in most years. The longest run of unhealthy air was 65 consecutive days at Kebon Jeruk (July–September 2018).

**6. Weekends are no cleaner than weekdays.** The average index was 74.4 on weekdays and 74.2 on weekends, so weekly traffic patterns are not visible in the daily index.

## Data Cleaning

- Loaded all five station files as text into one staging table first (with a `source_file` column), so messy values could not break the import
- Checked for duplicate station-days before loading (none found), then converted columns to proper types (dates and decimals) with a plain `INSERT`, so any duplicate or conversion error would stop the load instead of being skipped
- Standardized station names (e.g. `DKI1 (Bunderan HI)` → `DKI1 Bundaran HI`)
- Recalculated the category from the index value (`category_en`) so every row is labelled by the same rule
- **Found 2,409 "no data" days**, 2,350 of which stored a placeholder value of 0. Left as is, they would have been counted as "Good" air days, so I converted them to NULL
- **Found 323 rows (~1.4%) with misaligned columns**, where the daily maximum did not match the pollutant values (for example, a maximum of 20 on a day when one pollutant read 106). They are concentrated in September 2020 – January 2021 and January 2023, where values in the source appear shifted into the wrong columns. I flagged these rows with `is_reliable = 0` and excluded them from the analysis instead of deleting them
- 205 rows (Sep 2020 – Jan 2021) name PM2.5 as the critical pollutant but have no PM2.5 value, because PM2.5 was in the index before its readings were published. They pass the other check and are kept; the rule handles them explicitly
- After these fixes, only 25 rows had an original category that disagreed with the index value (19 of them at one station in December 2024), so the recalculated category was used throughout

After cleaning, 23,133 station-days were used for analysis.

## Limitations

- **No station-level data for 2022**, and 2025 covers only January–February (the wet season), so 2025 figures are not comparable to full years
- **Station coverage changes over time.** In 2010 only Bundaran HI reported for most of the year, and Kebon Jeruk only started in late 2012
- **The index method changed in 2020.** Under Minister of Environment and Forestry Regulation No. 14 of 2020, PM2.5 was added to the index (it appears in this data from September 2020, with PM2.5 readings from 2021). Because PM2.5 is often the highest pollutant, index values and critical-pollutant shares from late 2020 onward are not directly comparable to earlier years
- Five stations cannot represent every neighbourhood in a city of over 10 million people
- The dry-season definition (May–October) is an approximation
- The COVID comparison shows a correlation; weather and other factors also changed between 2019 and 2020
- Some extreme readings may reflect sensor issues, such as the 2012 ozone values at Kelapa Gading (up to 314), which are far above every other station and year
- The consistency check catches most misaligned rows, but shifted values that happen to look internally consistent would not be detected
- Missing and flagged days end an unhealthy streak, so streak lengths are conservative

## SQL Techniques Used

- A staging table and `LOAD DATA LOCAL INFILE` with a column list and `SET` for raw imports
- A duplicate check with `GROUP BY … HAVING`, and a unique key on `(obs_date, station)`
- Data cleaning with `CASE`, `REGEXP`, `TRIM`, and `NULLIF`
- A `STORED` generated column for the recalculated category
- Row-level consistency checks with `GREATEST` and `COALESCE`
- A view (`v_ispu`) with helper columns for year, month, season, and day type
- CTEs and conditional aggregation
- Window functions: `LAG`, `RANK`, `ROW_NUMBER`, `SUM() OVER`, and a 7-day moving average framed by calendar days (`RANGE … INTERVAL 6 DAY PRECEDING`) with a named `WINDOW`
- The "gaps and islands" pattern to find the longest streaks of unhealthy days

## Repository Structure

```
├── README.md
├── data/                        raw CSV files
└── sql/
    ├── 01_setup_and_import.sql  create database, load CSVs into staging
    ├── 02_cleaning.sql          explore, clean, verify, and flag bad rows
    ├── 03_data_quality.sql      missing values and coverage checks
    ├── 04_analysis_view.sql     analysis view with helper columns
    └── 05_analysis.sql          business questions and findings
```

## How to Run

1. In MySQL, run `SET GLOBAL local_infile = 1;` once
2. In a terminal, from the project's root folder:
   ```
   mysql --local-infile=1 -u root -p < sql/01_setup_and_import.sql
   ```
3. Run the remaining files in `sql/` in numbered order (for example, in MySQL Workbench)
