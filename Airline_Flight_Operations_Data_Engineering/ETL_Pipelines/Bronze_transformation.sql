
-- =====================================================
-- PROJECT : AIRLINE FLIGHT OPERATIONS ANALYTICS
-- LAYER   : BRONZE
-- TABLE   : bronze_airline_flights
-- PURPOSE : Raw data ingestion using Auto Loader
-- =====================================================

CREATE OR REFRESH STREAMING TABLE bronze_airline_flights
COMMENT 'Bronze layer: Raw airline flight data ingested from CSV using Auto Loader'

AS

SELECT
    *,
    _metadata.file_name AS source_file,
    current_timestamp() AS loaded_at

FROM STREAM read_files(
    '/Volumes/airline_flight_operations/default/airline_schema/',
    format => 'csv',
    header => true
);
