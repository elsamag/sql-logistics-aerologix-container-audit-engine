-- =============================================================================
-- Enterprise Practice: Elsamag IT Solutions
-- Author & Lead Technical Consultant: Samuel Chinwendu Agu
-- Target Repository: sql-logistics-aerologix-container-audit-engine
-- Asset Path: /src/03_data_quality_anomaly_gate.sql
-- Technical Specification: BigQuery Standard SQL / ANSI SQL
-- Add-On Architecture: ADDON_1_DATA_QUALITY_SCHEMA_ASSERTION_ANOMALY_GATE
-- Objective: Pre-execution assertion layer enforcing container format syntax,
--            non-null booking references, gross weight boundary constraints,
--            and automated quarantine routing for downstream ETL protection.
-- =============================================================================

WITH raw_stream_staging AS (
    -- Ingest and normalize combined modal freight feeds
    SELECT 
        TRIM(container_id) AS container_id,
        TRIM(booking_ref) AS booking_ref,
        UPPER(TRIM(transport_mode)) AS transport_mode,
        UPPER(TRIM(origin_hub)) AS origin_hub,
        UPPER(TRIM(dest_hub)) AS dest_hub,
        gross_weight_kg,
        manifest_timestamp
    FROM `aerologix-logistics-prod.staging.unified_freight_manifests`
    WHERE DATE(manifest_timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
),

schema_assertion_engine AS (
    -- Evaluate row-level data quality assertions and isolate failure modes
    SELECT 
        container_id,
        booking_ref,
        transport_mode,
        origin_hub,
        dest_hub,
        gross_weight_kg,
        manifest_timestamp,
        -- Assertion 1: ISO 6346 Container Format Standard Check (CONT-XXX-XXXXX)
        CASE 
            WHEN container_id IS NULL OR LENGTH(container_id) = 0 THEN 'FAIL_NULL_CONTAINER_ID'
            WHEN NOT REGEXP_CONTAINS(container_id, r'^CONT-(AIR|OCN)-[0-9]{5}$') THEN 'FAIL_INVALID_CONTAINER_SYNTAX'
            ELSE 'PASS'
        END AS assert_container_id_format,

        -- Assertion 2: Booking Reference Presence & Length Check
        CASE 
            WHEN booking_ref IS NULL OR LENGTH(booking_ref) = 0 THEN 'FAIL_NULL_BOOKING_REF'
            WHEN NOT REGEXP_CONTAINS(booking_ref, r'^BK-[0-9]{6}-[A-Z]$') THEN 'FAIL_INVALID_BOOKING_SYNTAX'
            ELSE 'PASS'
        END AS assert_booking_ref_integrity,

        -- Assertion 3: Modal Physical Weight Bounds (Air < 5,000kg | Ocean < 35,000kg)
        CASE 
            WHEN gross_weight_kg IS NULL OR gross_weight_kg <= 0 THEN 'FAIL_INVALID_WEIGHT_VALUE'
            WHEN transport_mode = 'AIR_FREIGHT' AND gross_weight_kg > 5000.00 THEN 'FAIL_AIR_OVERWEIGHT_THRESHOLD'
            WHEN transport_mode = 'OCEAN_FREIGHT' AND gross_weight_kg > 35000.00 THEN 'FAIL_OCEAN_OVERWEIGHT_THRESHOLD'
            ELSE 'PASS'
        END AS assert_weight_boundary,

        -- Assertion 4: Hub Route Parity Check (Origin != Destination)
        CASE 
            WHEN origin_hub IS NULL OR dest_hub IS NULL THEN 'FAIL_NULL_HUB_ROUTE'
            WHEN origin_hub = dest_hub THEN 'FAIL_IDENTICAL_ORIGIN_DESTINATION'
            ELSE 'PASS'
        END AS assert_route_logic
    FROM raw_stream_staging
),

audited_quarantine_pipeline AS (
    -- Route validated records vs quarantined anomaly rows
    SELECT 
        container_id,
        booking_ref,
        transport_mode,
        origin_hub,
        dest_hub,
        gross_weight_kg,
        manifest_timestamp,
        assert_container_id_format,
        assert_booking_ref_integrity,
        assert_weight_boundary,
        assert_route_logic,
        CASE 
            WHEN assert_container_id_format = 'PASS'
             AND assert_booking_ref_integrity = 'PASS'
             AND assert_weight_boundary = 'PASS'
             AND assert_route_logic = 'PASS'
            THEN 'CLEAN_PROD_INGEST'
            ELSE 'QUARANTINE_ANOMALY_FLAGGED'
        END AS assertion_gate_status,
        ARRAY_TO_STRING(
            ARRAY(
                SELECT err FROM UNNEST([
                    IF(assert_container_id_format != 'PASS', assert_container_id_format, NULL),
                    IF(assert_booking_ref_integrity != 'PASS', assert_booking_ref_integrity, NULL),
                    IF(assert_weight_boundary != 'PASS', assert_weight_boundary, NULL),
                    IF(assert_route_logic != 'PASS', assert_route_logic, NULL)
                ]) AS err WHERE err IS NOT NULL
            ), 
            ' | '
        ) AS failed_assertion_reasons
    FROM schema_assertion_engine
)

-- Production Output Stream: Pass-Through or Flagged Review
SELECT 
    container_id,
    booking_ref,
    transport_mode,
    origin_hub,
    dest_hub,
    gross_weight_kg,
    manifest_timestamp,
    assertion_gate_status,
    failed_assertion_reasons
FROM audited_quarantine_pipeline
ORDER BY 
    CASE WHEN assertion_gate_status = 'QUARANTINE_ANOMALY_FLAGGED' THEN 0 ELSE 1 END,
    manifest_timestamp DESC;
