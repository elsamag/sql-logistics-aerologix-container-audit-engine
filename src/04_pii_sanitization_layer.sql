-- =============================================================================
-- Enterprise Practice: Elsamag IT Solutions
-- Author & Lead Technical Consultant: Samuel Chinwendu Agu
-- Repository Target: https://github.com/Elsamag/sql-logistics-aerologix-container-audit-engine
-- File: src/04_pii_sanitization_layer.sql
-- Module: SQL Subqueries and Joins (Rule 124 / Rule 131 Capstone Asset)
-- Technical Standard: Google Cloud BigQuery Standard SQL / SHA-256 Masking
-- Objective: Cryptographically sanitize driver, dispatcher, and officer PII 
--            across multi-modal logistics streams prior to analytics export.
-- =============================================================================

WITH raw_shipment_stream AS (
    -- Air Cargo Feed: Sanitize Dispatcher & Customer Contact Data
    SELECT 
        container_id,
        booking_ref,
        'AIR_FREIGHT' AS transport_mode,
        origin_hub,
        dest_hub,
        gross_weight_kg,
        dispatcher_name,
        contact_email,
        manifest_timestamp
    FROM `aerologix-logistics-prod.raw_manifests.air_cargo_inbound`
    WHERE manifest_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)

    UNION ALL

    -- Ocean Cargo Feed: Sanitize Master & Carrier Contact Data
    SELECT 
        container_id,
        booking_ref,
        'OCEAN_FREIGHT' AS transport_mode,
        origin_hub,
        dest_hub,
        gross_weight_kg,
        dispatcher_name,
        contact_email,
        manifest_timestamp
    FROM `aerologix-logistics-prod.raw_manifests.ocean_freight_inbound`
    WHERE manifest_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
),

raw_clearance_checkpoints AS (
    SELECT 
        clearance_id,
        container_id,
        inspection_officer_id,
        officer_badge_name,
        clearance_status,
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
    
    -- Zero-Trust PII Masking: SHA-256 Hashing on Commercial Dispatcher Entities
    TO_HEX(SHA256(LOWER(TRIM(s.dispatcher_name)))) AS hashed_dispatcher_signature,
    
    -- Domain-Preserved Masked Email: Mask local part, preserve routing domain
    CONCAT(
        SUBSTR(s.contact_email, 1, 2),
        '***@',
        REGEXP_EXTRACT(s.contact_email, r'@(.+)$')
    ) AS masked_routing_email,
    
    -- Zero-Trust PII Masking: Customs Officer Identity Obfuscation
    TO_HEX(SHA256(CONCAT(c.inspection_officer_id, '_', TRIM(c.officer_badge_name)))) AS hashed_officer_token,
    
    COALESCE(c.clearance_status, 'UNREGISTERED_PENDING_AUDIT') AS audit_status,
    CASE 
        WHEN c.clearance_id IS NULL THEN 'CRITICAL_DISCREPANCY_NO_RECORD'
        WHEN c.clearance_status = 'HELD' THEN 'CUSTOMS_HOLD_ALERT'
        ELSE 'STANDARD_CLEARANCE'
    END AS operational_risk_tier

FROM raw_shipment_stream s
LEFT JOIN raw_clearance_checkpoints c
    ON s.container_id = c.container_id
ORDER BY s.manifest_timestamp DESC;
