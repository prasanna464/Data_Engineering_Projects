
-- ============================================================
-- GOLD LAYER: AIRLINE FLIGHT OPERATIONS
-- Source: Silver Clean and Rejected Tables
-- ============================================================


-- 1. MONTHLY FLIGHT SUMMARY

CREATE OR REFRESH MATERIALIZED VIEW gold_monthly_flights
COMMENT 'Gold layer: Monthly airline flight operational and revenue KPIs'
AS

SELECT
    CAST(DATE_TRUNC('MONTH', flight_date) AS DATE) AS month_start,
    YEAR(flight_date) AS flight_year,
    MONTH(flight_date) AS flight_month,

    COUNT(*) AS total_flights,
    SUM(passengers) AS total_passengers,
    SUM(ticket_revenue) AS total_revenue,
    SUM(fuel_cost) AS total_fuel_cost,

    AVG(avg_fare) AS average_fare,
    AVG(delay_minutes) AS average_delay_minutes,

    SUM(CASE WHEN delay_category = 'On Time' THEN 1 ELSE 0 END)
        AS on_time_flights,

    SUM(CASE WHEN delay_category = 'Minor Delay' THEN 1 ELSE 0 END)
        AS minor_delay_flights,

    SUM(CASE WHEN delay_category = 'Major Delay' THEN 1 ELSE 0 END)
        AS major_delay_flights,

    ROUND(
        100.0 * SUM(CASE WHEN delay_category = 'On Time' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        2
    ) AS on_time_percentage

FROM airline_flight_operations.default.silver_flights_clean

GROUP BY
    CAST(DATE_TRUNC('MONTH', flight_date) AS DATE),
    YEAR(flight_date),
    MONTH(flight_date);


-- ============================================================
-- 2. AIRLINE PERFORMANCE SUMMARY
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW gold_airline_summary
COMMENT 'Gold layer: Airline-wise operational performance KPIs'
AS

SELECT
    airline,

    COUNT(*) AS total_flights,
    COUNT(DISTINCT flight_id) AS unique_flights,

    SUM(passengers) AS total_passengers,
    SUM(seat_capacity) AS total_seat_capacity,

    SUM(ticket_revenue) AS total_revenue,
    SUM(fuel_cost) AS total_fuel_cost,

    AVG(avg_fare) AS average_fare,
    AVG(delay_minutes) AS average_delay_minutes,

    SUM(CASE WHEN delay_category = 'On Time' THEN 1 ELSE 0 END)
        AS on_time_flights,

    SUM(CASE WHEN delay_category = 'Minor Delay' THEN 1 ELSE 0 END)
        AS minor_delay_flights,

    SUM(CASE WHEN delay_category = 'Major Delay' THEN 1 ELSE 0 END)
        AS major_delay_flights,

    ROUND(
        100.0 * SUM(CASE WHEN delay_category = 'On Time' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        2
    ) AS on_time_percentage,

    ROUND(
        100.0 * SUM(passengers)
        / NULLIF(SUM(seat_capacity), 0),
        2
    ) AS seat_occupancy_percentage

FROM airline_flight_operations.default.silver_flights_clean

GROUP BY airline;


-- ============================================================
-- 3. ROUTE PERFORMANCE SUMMARY
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW gold_route_summary
COMMENT 'Gold layer: Origin and destination route performance analysis'
AS

SELECT
    origin_city,
    destination_city,
    origin_region,

    COUNT(*) AS total_flights,
    SUM(passengers) AS total_passengers,

    SUM(ticket_revenue) AS total_revenue,
    SUM(fuel_cost) AS total_fuel_cost,

    AVG(distance_km) AS average_distance_km,
    AVG(delay_minutes) AS average_delay_minutes,

    SUM(CASE WHEN delay_category = 'On Time' THEN 1 ELSE 0 END)
        AS on_time_flights,

    SUM(CASE WHEN delay_category IN ('Minor Delay', 'Major Delay')
        THEN 1 ELSE 0 END) AS delayed_flights,

    ROUND(
        100.0 * SUM(CASE WHEN delay_category = 'On Time' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        2
    ) AS on_time_percentage

FROM airline_flight_operations.default.silver_flights_clean

GROUP BY
    origin_city,
    destination_city,
    origin_region;


-- ============================================================
-- 4. FLIGHT DELAY SUMMARY
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW gold_delay_summary
COMMENT 'Gold layer: Flight delay category and reason analysis'
AS

SELECT
    delay_category,
    delay_reason,

    COUNT(*) AS total_flights,

    AVG(delay_minutes) AS average_delay_minutes,
    MAX(delay_minutes) AS maximum_delay_minutes,
    MIN(delay_minutes) AS minimum_delay_minutes,

    SUM(passengers) AS total_passengers,

    SUM(ticket_revenue) AS total_revenue,

    SUM(CASE
        WHEN delay_minutes > 15 THEN 1
        ELSE 0
    END) AS delayed_flights

FROM airline_flight_operations.default.silver_flights_clean

GROUP BY
    delay_category,
    delay_reason;


-- ============================================================
-- 5. DATA QUALITY SUMMARY
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW gold_data_quality
COMMENT 'Gold layer: Bronze to Silver reconciliation and data quality metrics'
AS

WITH bronze_metrics AS (

    SELECT
        COUNT(*) AS bronze_total_rows,

        COUNT(DISTINCT flight_id) AS bronze_unique_flights,

        COUNT(*) - COUNT(DISTINCT flight_id)
            AS bronze_duplicate_rows,

        SUM(CASE WHEN airline IS NULL OR TRIM(airline) = ''
            THEN 1 ELSE 0 END) AS missing_airline,

        SUM(CASE WHEN aircraft_id IS NULL OR TRIM(aircraft_id) = ''
            THEN 1 ELSE 0 END) AS missing_aircraft_id,

        SUM(CASE WHEN delay_minutes IS NULL
            THEN 1 ELSE 0 END) AS missing_delay_minutes,

        SUM(
            CASE
               WHEN delay_reason IS NULL
                    OR TRIM(delay_reason) = ''
                    OR LOWER(TRIM(delay_reason)) IN ('none', 'null')
               THEN 1
               ELSE 0
            END
        ) AS missing_delay_reason,

        SUM(CASE WHEN ticket_revenue IS NULL
            THEN 1 ELSE 0 END) AS missing_ticket_revenue,

        SUM(CASE WHEN _rescued_data IS NOT NULL
            THEN 1 ELSE 0 END) AS rescued_data_rows

    FROM airline_flight_operations.default.bronze_airline_flights

),

silver_clean_metrics AS (

    SELECT COUNT(*) AS clean_total_rows
    FROM airline_flight_operations.default.silver_flights_clean

),

silver_rejected_metrics AS (

    SELECT
        COUNT(*) AS rejected_total_rows,

        SUM(CASE
            WHEN reject_reason LIKE '%Overbooked passengers%'
            THEN 1 ELSE 0
        END) AS overbooked_records,

        SUM(CASE
            WHEN reject_reason LIKE '%Negative passengers%'
            THEN 1 ELSE 0
        END) AS negative_passenger_records,

        SUM(CASE
            WHEN reject_reason LIKE '%Negative average fare%'
            THEN 1 ELSE 0
        END) AS negative_fare_records

    FROM airline_flight_operations.default.silver_flights_rejected

),

overlap_metrics AS (

    SELECT COUNT(*) AS overlapping_records

    FROM airline_flight_operations.default.silver_flights_clean c

    INNER JOIN airline_flight_operations.default.silver_flights_rejected r

        ON c.flight_id = r.flight_id

)

SELECT
    b.bronze_total_rows,
    b.bronze_unique_flights,
    b.bronze_duplicate_rows,

    c.clean_total_rows,
    r.rejected_total_rows,

    o.overlapping_records,

    b.bronze_total_rows
        - c.clean_total_rows
        - r.rejected_total_rows
        - b.bronze_duplicate_rows
        AS reconciliation_difference,

    b.missing_airline,
    b.missing_aircraft_id,
    b.missing_delay_minutes,
    b.missing_delay_reason,
    b.missing_ticket_revenue,
    b.rescued_data_rows,

    r.overbooked_records,
    r.negative_passenger_records,
    r.negative_fare_records,

    CASE
        WHEN
            b.bronze_total_rows =
                c.clean_total_rows
                + r.rejected_total_rows
                + b.bronze_duplicate_rows

            AND o.overlapping_records = 0

        THEN 'PASS'
        ELSE 'CHECK REQUIRED'
    END AS reconciliation_status

FROM bronze_metrics b

CROSS JOIN silver_clean_metrics c

CROSS JOIN silver_rejected_metrics r

CROSS JOIN overlap_metrics o;
