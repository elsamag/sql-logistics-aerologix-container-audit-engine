-- =============================================================================
-- Enterprise Practice: Elsamag IT Solutions
-- Author & Lead Technical Consultant: Samuel Chinwendu Agu
-- Repository Target: https://github.com/Elsamag/sql-logistics-aerologix-container-audit-engine
-- File: src/02_left_join_discrepancy_filter.sql
-- Technical Objective: Isolate un-cleared, missing, or customs-held container records
--                      across unified Air and Ocean freight streams via LEFT JOIN
--                      missing-relation filtering and risk-tier categorization.
-- Dialect: Google Cloud BigQuery Standard SQL
-- =============================================================================

WITH unified_shipment_stream AS (
    -- Stream 1: Inbound Air Cargo Feeds
    SELECT 
        container_id,
        booking_ref,
        'AIR_FREIGHT' AS transport_mode,
        origin_hub,
        dest_hub,
        gross_weight_kg,
        manifest_timestamp
    FROM `aerologix-logistics-prod.raw_manifests.air_cargo_inbound`
    WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
                            AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())

    UNION ALL

    -- Stream 2: Inbound Ocean Freight Feeds
    SELECT 
        container_id,
        booking_ref,
        'OCEAN_FREIGHT' AS transport_mode,
        origin_hub,
        dest_hub,
        gross_weight_kg,
        manifest_timestamp
    FROM `aerologix-logistics-prod.raw_manifests.ocean_freight_inbound`
    WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
                            AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),

customs_clearance_status AS (
    -- Checkpoint Clearance Registry
    SELECT 
        clearance_id,
        container_id,
        clearance_status,
        inspection_officer_id,
        cleared_timestamp
    FROM `aerologix-logistics-prod.compliance.customs_checkpoints`
    WHERE checkpoint_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
)

SELECT 
    s.container_id,
    s.booking_ref,
    s.transport_mode,
    s.origin_hub,
    s.dest_hub,
    s.gross_weight_kg,
    s.manifest_timestamp,
    COALESCE(c.clearance_status, 'UNREGISTERED_PENDING_AUDIT') AS audit_status,
    CASE 
        WHEN c.clearance_id IS NULL THEN 'CRITICAL_DISCREPANCY_NO_RECORD'
        WHEN c.clearance_status = 'HELD' THEN 'CUSTOMS_HOLD_ALERT'
        WHEN c.clearance_status = 'REJECTED' THEN 'CUSTOMS_REJECTED_QUARANTINE'
        ELSE 'STANDARD_CLEARANCE'
    END AS operational_risk_tier
FROM unified_shipment_stream AS s
LEFT JOIN customs_clearance_status AS c
    ON s.container_id = c.container_id
WHERE c.clearance_id IS NULL 
   OR c.clearance_status IN ('HELD', 'REJECTED')
ORDER BY s.manifest_timestamp DESC;
