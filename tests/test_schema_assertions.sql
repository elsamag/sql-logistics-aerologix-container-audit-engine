-- =============================================================================
-- Enterprise Practice: Elsamag IT Solutions
-- Author & Lead Technical Consultant: Samuel Chinwendu Agu
-- Repository: sql-logistics-aerologix-container-audit-engine
-- Path: tests/test_schema_assertions.sql
-- Add-On: ADDON_1_DATA_QUALITY_SCHEMA_ASSERTION_ANOMALY_GATE
-- Dialect: Google Cloud BigQuery Standard SQL
-- =============================================================================

-- Assertion 1: Zero NULL Check for Primary Routing Keys
WITH null_key_assertion AS (
    SELECT 
        'PRIMARY_ROUTING_KEY_NULL_CHECK' AS assertion_name,
        COUNT(*) AS failure_count
    FROM `aerologix-logistics-prod.raw_manifests.air_cargo_inbound`
    WHERE container_id IS NULL 
       OR booking_ref IS NULL
),

-- Assertion 2: Weight Variance Range Check (Zero/Negative or Extreme Outliers)
weight_variance_assertion AS (
    SELECT 
        'GROSS_WEIGHT_TOLERANCE_CHECK' AS assertion_name,
        COUNT(*) AS failure_count
    FROM `aerologix-logistics-prod.raw_manifests.ocean_freight_inbound`
    WHERE gross_weight_kg <= 0 
       OR gross_weight_kg > 65000.00
),

-- Assertion 3: ISO Container Format Regex Assertion
format_pattern_assertion AS (
    SELECT 
        'CONTAINER_ID_REGEX_CONFORMANCE' AS assertion_name,
        COUNT(*) AS failure_count
    FROM `aerologix-logistics-prod.raw_manifests.air_cargo_inbound`
    WHERE NOT REGEXP_CONTAINS(container_id, r'^CONT-[A-Z]{3}-[0-9]{5}$')
)

-- Unified Assertion Summary Engine
SELECT 
    assertion_name,
    failure_count,
    CASE 
        WHEN failure_count = 0 THEN 'ASSERTION_PASSED'
        ELSE 'ASSERTION_FAILED_QUARANTINE_TRIGGERED'
    END AS assertion_status,
    CURRENT_TIMESTAMP() AS audit_executed_at
FROM null_key_assertion

UNION ALL

SELECT 
    assertion_name,
    failure_count,
    CASE 
        WHEN failure_count = 0 THEN 'ASSERTION_PASSED'
        ELSE 'ASSERTION_FAILED_QUARANTINE_TRIGGERED'
    END AS assertion_status,
    CURRENT_TIMESTAMP() AS audit_executed_at
FROM weight_variance_assertion

UNION ALL

SELECT 
    assertion_name,
    failure_count,
    CASE 
        WHEN failure_count = 0 THEN 'ASSERTION_PASSED'
        ELSE 'ASSERTION_FAILED_QUARANTINE_TRIGGERED'
    END AS assertion_status,
    CURRENT_TIMESTAMP() AS audit_executed_at
FROM format_pattern_assertion;
