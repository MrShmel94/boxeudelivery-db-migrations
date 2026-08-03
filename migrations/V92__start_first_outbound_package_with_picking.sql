-- The normal fulfillment flow scans exact items directly into a physical outbound package.
-- Repair already-started picking sessions that predate automatic first-package creation.
WITH missing_sessions AS (
    SELECT session.id AS picking_session_id,
           session.customer_order_id,
           session.project_id,
           session.warehouse_id,
           session.started_by_account_id,
           session.started_by_subject,
           session.started_at,
           customer_order.order_number,
           COALESCE((
               SELECT MAX(existing_package.sequence_number)
               FROM crm.outbound_package existing_package
               WHERE existing_package.customer_order_id = session.customer_order_id
           ), 0)
           + ROW_NUMBER() OVER (
               PARTITION BY session.customer_order_id
               ORDER BY session.warehouse_id, session.id
           ) AS sequence_number
    FROM crm.customer_order_picking_session session
    JOIN crm.customer_order customer_order
      ON customer_order.id = session.customer_order_id
     AND customer_order.project_id = session.project_id
    WHERE customer_order.status_code = 'PICKING'
      AND NOT EXISTS (
          SELECT 1
          FROM crm.outbound_package existing_package
          WHERE existing_package.picking_session_id = session.id
      )
), prepared_packages AS (
    SELECT (
               SUBSTRING(MD5('auto-outbound-package:' || picking_session_id::TEXT), 1, 8)
               || '-' || SUBSTRING(MD5('auto-outbound-package:' || picking_session_id::TEXT), 9, 4)
               || '-' || SUBSTRING(MD5('auto-outbound-package:' || picking_session_id::TEXT), 13, 4)
               || '-' || SUBSTRING(MD5('auto-outbound-package:' || picking_session_id::TEXT), 17, 4)
               || '-' || SUBSTRING(MD5('auto-outbound-package:' || picking_session_id::TEXT), 21, 12)
           )::UUID AS package_id,
           picking_session_id,
           customer_order_id,
           project_id,
           warehouse_id,
           started_by_account_id,
           started_by_subject,
           started_at,
           sequence_number,
           'OUT-' || SUBSTRING(order_number FROM 5)
               || '-P' || LPAD(sequence_number::TEXT, 3, '0') AS package_number
    FROM missing_sessions
), inserted_packages AS (
    INSERT INTO crm.outbound_package (
        id,
        client_request_id,
        customer_order_id,
        picking_session_id,
        project_id,
        warehouse_id,
        sequence_number,
        package_number,
        status_code,
        created_by_account_id,
        created_by_subject,
        created_at,
        updated_at,
        version
    )
    SELECT package_id,
           picking_session_id,
           customer_order_id,
           picking_session_id,
           project_id,
           warehouse_id,
           sequence_number,
           package_number,
           'DRAFT',
           started_by_account_id,
           started_by_subject,
           started_at,
           started_at,
           0
    FROM prepared_packages
    RETURNING id,
              customer_order_id,
              picking_session_id,
              project_id,
              created_by_subject,
              created_at
)
INSERT INTO crm.cargo_audit_event (
    id,
    aggregate_type,
    aggregate_id,
    project_id,
    event_type,
    actor_subject,
    details,
    occurred_at
)
SELECT (
           SUBSTRING(MD5('auto-outbound-package-audit:' || id::TEXT), 1, 8)
           || '-' || SUBSTRING(MD5('auto-outbound-package-audit:' || id::TEXT), 9, 4)
           || '-' || SUBSTRING(MD5('auto-outbound-package-audit:' || id::TEXT), 13, 4)
           || '-' || SUBSTRING(MD5('auto-outbound-package-audit:' || id::TEXT), 17, 4)
           || '-' || SUBSTRING(MD5('auto-outbound-package-audit:' || id::TEXT), 21, 12)
       )::UUID,
       'OUTBOUND_PACKAGE',
       id,
       project_id,
       'CREATED',
       created_by_subject,
       JSONB_BUILD_OBJECT(
           'orderId', customer_order_id::TEXT,
           'pickingSessionId', picking_session_id::TEXT,
           'automatic', TRUE,
           'backfill', 'V92'
       ),
       created_at
FROM inserted_packages;
