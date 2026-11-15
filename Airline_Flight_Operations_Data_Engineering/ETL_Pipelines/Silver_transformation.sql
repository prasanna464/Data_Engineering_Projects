
-- ============================================================
-- SILVER LAYER: AIRLINE FLIGHT OPERATIONS
-- Source: Bronze Airline Flights
-- ============================================================


-- 1. CLEAN FLIGHTS
-- Deduplicate, standardize and clean valid records.

CREATE OR REFRESH MATERIALIZED VIEW silver_flights_clean
COMMENT 'Silver layer: Deduplicated and cleaned airline flight records'
AS

WITH ranked_flights AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY flight_id
            ORDER BY loaded_at DESC, source_file ASC
        ) AS row_num

    FROM airline_flight_operations.default.bronze_airline_flights

),

deduplicated AS (

    SELECT *
    FROM ranked_flights
    WHERE row_num = 1

),

cleaned AS (

    SELECT
        flight_id,
        TRIM(flight_number) AS flight_number,
        COALESCE(NULLIF(INITCAP(TRIM(airline)), ''), 'Unknown') AS airline,
        NULLIF(TRIM(aircraft_id), '') AS aircraft_id,
        COALESCE(NULLIF(INITCAP(TRIM(aircraft_type)), ''), 'Unknown') AS aircraft_type,
        flight_date,
        COALESCE(NULLIF(INITCAP(TRIM(day_of_week)), ''), 'Unknown') AS day_of_week,
        COALESCE(NULLIF(INITCAP(TRIM(origin_city)), ''), 'Unknown') AS origin_city,
        COALESCE(NULLIF(INITCAP(TRIM(destination_city)), ''), 'Unknown') AS destination_city,
        COALESCE(NULLIF(INITCAP(TRIM(origin_region)), ''), 'Unknown') AS origin_region,
        distance_km,
        scheduled_departure,
        actual_departure,

        COALESCE(
            delay_minutes,
            TIMESTAMPDIFF(
                MINUTE,
                scheduled_departure,
                actual_departure
            )
        ) AS delay_minutes,

        CASE
           WHEN delay_reason IS NULL
                OR TRIM(delay_reason) = ''
                OR LOWER(TRIM(delay_reason)) IN ('none', 'null')
           THEN 'Unknown'
           ELSE INITCAP(TRIM(delay_reason))
        END AS delay_reason,
        seat_capacity,
        passengers,
        avg_fare,

        COALESCE(
            ticket_revenue,
            passengers * avg_fare
        ) AS ticket_revenue,

        fuel_cost,
        _rescued_data,
        source_file,
        loaded_at

    FROM deduplicated

),

classified AS (

    SELECT
        *,
        CASE
            WHEN delay_minutes IS NULL THEN 'Unknown'
            WHEN delay_minutes <= 15 THEN 'On Time'
            WHEN delay_minutes <= 60 THEN 'Minor Delay'
            ELSE 'Major Delay'
        END AS delay_category

    FROM cleaned

)

SELECT *
FROM classified
WHERE
    (seat_capacity IS NULL OR passengers <= seat_capacity)
    AND (passengers IS NULL OR passengers >= 0)
    AND (avg_fare IS NULL OR avg_fare >= 0);


-- ============================================================
-- 2. REJECTED FLIGHTS
-- Keep records that violate the specified business rules.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW silver_flights_rejected
COMMENT 'Silver layer: Airline flight records rejected by business rules'
AS

WITH ranked_flights AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY flight_id
            ORDER BY loaded_at DESC, source_file ASC
        ) AS row_num

    FROM airline_flight_operations.default.bronze_airline_flights

),

deduplicated AS (

    SELECT *
    FROM ranked_flights
    WHERE row_num = 1

),

cleaned AS (

    SELECT
        flight_id,
        TRIM(flight_number) AS flight_number,
        COALESCE(NULLIF(INITCAP(TRIM(airline)), ''), 'Unknown') AS airline,
        NULLIF(TRIM(aircraft_id), '') AS aircraft_id,
        COALESCE(NULLIF(INITCAP(TRIM(aircraft_type)), ''), 'Unknown') AS aircraft_type,
        flight_date,
        COALESCE(NULLIF(INITCAP(TRIM(day_of_week)), ''), 'Unknown') AS day_of_week,
        COALESCE(NULLIF(INITCAP(TRIM(origin_city)), ''), 'Unknown') AS origin_city,
        COALESCE(NULLIF(INITCAP(TRIM(destination_city)), ''), 'Unknown') AS destination_city,
        COALESCE(NULLIF(INITCAP(TRIM(origin_region)), ''), 'Unknown') AS origin_region,
        distance_km,
        scheduled_departure,
        actual_departure,

        COALESCE(
            delay_minutes,
            TIMESTAMPDIFF(MINUTE, scheduled_departure, actual_departure)
        ) AS delay_minutes,

        CASE
           WHEN delay_reason IS NULL
                OR TRIM(delay_reason) = ''
                OR LOWER(TRIM(delay_reason)) IN ('none', 'null')
           THEN 'Unknown'
           ELSE INITCAP(TRIM(delay_reason))
        END AS delay_reason,
        seat_capacity,
        passengers,
        avg_fare,

        COALESCE(
            ticket_revenue,
            passengers * avg_fare
        ) AS ticket_revenue,

        fuel_cost,
        _rescued_data,
        source_file,
        loaded_at

    FROM deduplicated

),

classified AS (

    SELECT
        *,
        CASE
            WHEN delay_minutes IS NULL THEN 'Unknown'
            WHEN delay_minutes <= 15 THEN 'On Time'
            WHEN delay_minutes <= 60 THEN 'Minor Delay'
            ELSE 'Major Delay'
        END AS delay_category

    FROM cleaned

)

SELECT
    *,
    CONCAT_WS(
        ', ',
        CASE
            WHEN passengers > seat_capacity THEN 'Overbooked passengers'
        END,
        CASE
            WHEN passengers < 0 THEN 'Negative passengers'
        END,
        CASE
            WHEN avg_fare < 0 THEN 'Negative average fare'
        END
    ) AS reject_reason

FROM classified

WHERE
    passengers > seat_capacity
    OR passengers < 0
    OR avg_fare < 0;
