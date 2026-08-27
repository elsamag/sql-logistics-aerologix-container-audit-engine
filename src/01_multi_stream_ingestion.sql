-- =============================================================================
-- Enterprise Practice: Elsamag IT Solutions
-- Author & Lead Technical Consultant: Samuel Chinwendu Agu
-- Repository Target: https://github.com/Elsamag/sql-logistics-aerologix-container-audit-engine
-- File: src/01_multi_stream_ingestion.sql
-- Technical Objective: Ingest and unify multi-modal logistics streams (Air and Ocean)
--                      into a standardized staging layer using zero-sort UNION ALL.
-- Dialect: Google Cloud BigQuery Standard SQL
-- =============================================================================

CREATE OR REPLACE VIEW `aerologix-logistics-prod.staging.v_unified_shipment_stream` AS
-- Stream 1: High-Priority Air Cargo Inbound Feeds
SELECT 
    TRIM(container_id) AS container_id,
    TRIM(booking_ref) AS booking_ref,
    'AIR_FREIGHT' AS transport_mode,
    UPPER(TRIM(origin_hub)) AS origin_hub,
    UPPER(TRIM(dest_hub)) AS dest_hub,
    CAST(gross_weight_kg AS NUMERIC) AS gross_weight_kg,
    TIMESTAMP(manifest_timestamp) AS manifest_timestamp,
    DATE(manifest_timestamp) AS manifest_date
FROM `aerologix-logistics-prod.raw_manifests.air_cargo_inbound`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
                        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND container_id IS NOT NULL

UNION ALL

-- Stream 2: High-Volume Ocean Cargo Inbound Feeds
SELECT 
    TRIM(container_id) AS container_id,
    TRIM(booking_ref) AS booking_ref,
    'OCEAN_FREIGHT' AS transport_mode,
    UPPER(TRIM(origin_hub)) AS origin_hub,
    UPPER(TRIM(dest_hub)) AS dest_hub,
    CAST(gross_weight_kg AS NUMERIC) AS gross_weight_kg,
    TIMESTAMP(manifest_timestamp) AS manifest_timestamp,
    DATE(manifest_timestamp) AS manifest_date
FROM `aerologix-logistics-prod.raw_manifests.ocean_freight_inbound`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
                        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND container_id IS NOT NULL;
