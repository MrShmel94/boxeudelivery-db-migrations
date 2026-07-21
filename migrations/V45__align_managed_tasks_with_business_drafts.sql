UPDATE crm.task task
SET status_code = 'PLANNED',
    managed_state_code = NULL,
    priority_code = 'NORMAL',
    completed_at = NULL,
    updated_at = GREATEST(task.updated_at, resource.updated_at),
    version = task.version + 1
FROM (
    SELECT customer_order.id AS resource_id, customer_order.updated_at
    FROM crm.customer_order
    WHERE customer_order.status_code = 'DRAFT'
    UNION ALL
    SELECT relocation.id, relocation.updated_at
    FROM crm.warehouse_relocation relocation
    WHERE relocation.status_code = 'DRAFT'
) resource
WHERE (task.customer_order_id = resource.resource_id
       OR task.warehouse_relocation_id = resource.resource_id)
  AND task.status_code <> 'PLANNED';

UPDATE crm.task task
SET status_code = 'PLANNED',
    managed_state_code = NULL,
    priority_code = 'NORMAL',
    completed_at = NULL,
    updated_at = GREATEST(task.updated_at, delivery.updated_at),
    version = task.version + 1
FROM crm.inbound_delivery delivery
WHERE task.inbound_delivery_id = delivery.id
  AND delivery.status_code = 'DRAFT'
  AND task.status_code <> 'PLANNED';

INSERT INTO crm.task_audit_event (
    id,
    project_id,
    task_id,
    event_type,
    actor_subject,
    details,
    occurred_at
)
SELECT MD5('boxeudelivery:managed-task-planned:v45:' || task.id::TEXT)::UUID,
       task.project_id,
       task.id,
       'STATUS_CHANGED',
       'system:flyway-v45',
       JSONB_BUILD_OBJECT(
           'status', 'PLANNED',
           'reason', 'BUSINESS_RESOURCE_DRAFT',
           'reconciled', TRUE
       ),
       task.updated_at
FROM crm.task task
WHERE task.status_code = 'PLANNED'
  AND (
      EXISTS (
          SELECT 1
          FROM crm.customer_order customer_order
          WHERE customer_order.id = task.customer_order_id
            AND customer_order.status_code = 'DRAFT'
      )
      OR EXISTS (
          SELECT 1
          FROM crm.warehouse_relocation relocation
          WHERE relocation.id = task.warehouse_relocation_id
            AND relocation.status_code = 'DRAFT'
      )
      OR EXISTS (
          SELECT 1
          FROM crm.inbound_delivery delivery
          WHERE delivery.id = task.inbound_delivery_id
            AND delivery.status_code = 'DRAFT'
      )
  )
ON CONFLICT (id) DO NOTHING;

CREATE TEMPORARY TABLE inbound_draft_task_backfill ON COMMIT DROP AS
WITH participant_candidates AS (
    SELECT delivery.id AS inbound_delivery_id,
           delivery.project_id,
           member.id AS project_member_id,
           member.account_id,
           'DELIVERY_SUPPLIER'::VARCHAR(32) AS source_code,
           1 AS source_priority
    FROM crm.inbound_delivery delivery
    JOIN crm.project_supplier_member supplier_member
      ON supplier_member.project_id = delivery.project_id
     AND supplier_member.supplier_id = delivery.supplier_id
     AND supplier_member.status_code = 'ACTIVE'
    JOIN crm.project_member member
      ON member.project_id = supplier_member.project_id
     AND member.account_id = supplier_member.account_id
    JOIN crm.account account
      ON account.id = member.account_id
     AND account.status = 'ACTIVE'
    WHERE delivery.status_code = 'DRAFT'
      AND delivery.delivery_deadline_at IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM crm.task task WHERE task.inbound_delivery_id = delivery.id
      )
    UNION ALL
    SELECT delivery.id,
           delivery.project_id,
           member.id,
           member.account_id,
           'DELIVERY_PROJECT_ROLE',
           2
    FROM crm.inbound_delivery delivery
    JOIN crm.project_member member ON member.project_id = delivery.project_id
    JOIN crm.project_member_role role ON role.project_member_id = member.id
    JOIN crm.account account ON account.id = member.account_id AND account.status = 'ACTIVE'
    WHERE delivery.status_code = 'DRAFT'
      AND delivery.delivery_deadline_at IS NOT NULL
      AND role.role_code IN ('OPERATIONS_MANAGER', 'CUSTOMER_MANAGER')
      AND NOT EXISTS (
          SELECT 1 FROM crm.task task WHERE task.inbound_delivery_id = delivery.id
      )
), selected_participants AS (
    SELECT DISTINCT ON (inbound_delivery_id, project_member_id)
           inbound_delivery_id,
           project_id,
           project_member_id,
           account_id,
           source_code,
           source_priority
    FROM participant_candidates
    ORDER BY inbound_delivery_id, project_member_id, source_priority
), resources AS (
    SELECT delivery.id AS resource_id,
           delivery.project_id,
           delivery.conversation_id,
           delivery.delivery_number,
           delivery.delivery_deadline_at,
           delivery.delivery_deadline_zone_id,
           delivery.created_at,
           delivery.updated_at,
           warehouse.country_code,
           actor.account_id AS actor_account_id
    FROM crm.inbound_delivery delivery
    JOIN crm.warehouse warehouse ON warehouse.id = delivery.target_warehouse_id
    JOIN LATERAL (
        SELECT participant.account_id
        FROM selected_participants participant
        WHERE participant.inbound_delivery_id = delivery.id
        ORDER BY participant.source_priority, participant.account_id
        LIMIT 1
    ) actor ON TRUE
    WHERE delivery.status_code = 'DRAFT'
      AND delivery.delivery_deadline_at IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM crm.task task WHERE task.inbound_delivery_id = delivery.id
      )
), numbered AS (
    SELECT resources.*,
           ROW_NUMBER() OVER (
               PARTITION BY resources.project_id
               ORDER BY resources.created_at, resources.resource_id
           ) AS allocated_offset
    FROM resources
), allocated AS (
    SELECT numbered.*,
           COALESCE(counter.last_value, 0) + numbered.allocated_offset AS sequence_number
    FROM numbered
    LEFT JOIN crm.project_task_counter counter ON counter.project_id = numbered.project_id
)
SELECT MD5('boxeudelivery:inbound-draft-task:' || allocated.resource_id::TEXT)::UUID AS task_id,
       allocated.*,
       classification.subcategory_id
FROM allocated
LEFT JOIN crm.task_system_classification_default classification
  ON classification.country_code = allocated.country_code
 AND classification.source_code = 'INBOUND_DELIVERY';

INSERT INTO crm.project_task_counter (project_id, last_value)
SELECT project_id, MAX(sequence_number)
FROM inbound_draft_task_backfill
GROUP BY project_id
ON CONFLICT (project_id) DO UPDATE
SET last_value = GREATEST(crm.project_task_counter.last_value, EXCLUDED.last_value);

INSERT INTO crm.task (
    id,
    project_id,
    conversation_id,
    parent_task_id,
    task_subcategory_id,
    inbound_delivery_id,
    courier_trip_id,
    customer_order_id,
    warehouse_relocation_id,
    managed_state_code,
    task_key,
    sequence_number,
    title,
    description,
    status_code,
    priority_code,
    deadline_at,
    deadline_zone_id,
    completed_at,
    created_by_account_id,
    updated_by_account_id,
    created_at,
    updated_at,
    version
)
SELECT backfill.task_id,
       backfill.project_id,
       backfill.conversation_id,
       NULL,
       backfill.subcategory_id,
       backfill.resource_id,
       NULL,
       NULL,
       NULL,
       NULL,
       project.task_prefix || '-' || backfill.sequence_number,
       backfill.sequence_number,
       'Приёмка поставки ' || backfill.delivery_number,
       'Поставка должна быть окончательно принята складом.',
       'PLANNED',
       'NORMAL',
       backfill.delivery_deadline_at,
       backfill.delivery_deadline_zone_id,
       NULL,
       backfill.actor_account_id,
       backfill.actor_account_id,
       backfill.created_at,
       backfill.updated_at,
       0
FROM inbound_draft_task_backfill backfill
JOIN crm.project project ON project.id = backfill.project_id;

WITH participant_candidates AS (
    SELECT backfill.task_id,
           backfill.project_id,
           member.id AS project_member_id,
           backfill.actor_account_id,
           backfill.created_at,
           'DELIVERY_SUPPLIER'::VARCHAR(32) AS source_code,
           1 AS source_priority
    FROM inbound_draft_task_backfill backfill
    JOIN crm.inbound_delivery delivery ON delivery.id = backfill.resource_id
    JOIN crm.project_supplier_member supplier_member
      ON supplier_member.project_id = delivery.project_id
     AND supplier_member.supplier_id = delivery.supplier_id
     AND supplier_member.status_code = 'ACTIVE'
    JOIN crm.project_member member
      ON member.project_id = supplier_member.project_id
     AND member.account_id = supplier_member.account_id
    JOIN crm.account account ON account.id = member.account_id AND account.status = 'ACTIVE'
    UNION ALL
    SELECT backfill.task_id,
           backfill.project_id,
           member.id,
           backfill.actor_account_id,
           backfill.created_at,
           'DELIVERY_PROJECT_ROLE',
           2
    FROM inbound_draft_task_backfill backfill
    JOIN crm.project_member member ON member.project_id = backfill.project_id
    JOIN crm.project_member_role role ON role.project_member_id = member.id
    JOIN crm.account account ON account.id = member.account_id AND account.status = 'ACTIVE'
    WHERE role.role_code IN ('OPERATIONS_MANAGER', 'CUSTOMER_MANAGER')
), selected_participants AS (
    SELECT DISTINCT ON (task_id, project_member_id)
           task_id,
           project_id,
           project_member_id,
           actor_account_id,
           created_at,
           source_code
    FROM participant_candidates
    ORDER BY task_id, project_member_id, source_priority
)
INSERT INTO crm.task_participant (
    id,
    project_id,
    task_id,
    project_member_id,
    assigned_by_account_id,
    assigned_at,
    source_code,
    version
)
SELECT MD5('boxeudelivery:inbound-draft-participant:v45:' || task_id::TEXT || ':'
           || project_member_id::TEXT)::UUID,
       project_id,
       task_id,
       project_member_id,
       actor_account_id,
       created_at,
       source_code,
       0
FROM selected_participants;

INSERT INTO crm.task_audit_event (
    id,
    project_id,
    task_id,
    event_type,
    actor_subject,
    details,
    occurred_at
)
SELECT MD5('boxeudelivery:inbound-draft-audit:v45:' || backfill.task_id::TEXT)::UUID,
       backfill.project_id,
       backfill.task_id,
       'CREATED',
       'system:flyway-v45',
       JSONB_BUILD_OBJECT(
           'taskKey', project.task_prefix || '-' || backfill.sequence_number,
           'inboundDeliveryId', backfill.resource_id::TEXT,
           'status', 'PLANNED',
           'backfilled', TRUE
       ),
       backfill.created_at
FROM inbound_draft_task_backfill backfill
JOIN crm.project project ON project.id = backfill.project_id;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM crm.inbound_delivery delivery
        WHERE delivery.status_code = 'DRAFT'
          AND delivery.delivery_deadline_at IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM crm.task task WHERE task.inbound_delivery_id = delivery.id
          )
    ) THEN
        RAISE EXCEPTION
            'Cannot backfill every inbound-delivery draft task: an active supplier or operational participant is missing';
    END IF;
END
$$;

COMMENT ON COLUMN crm.task.status_code IS
    'Business-managed tasks are PLANNED while their owning resource is a draft and activate only through that resource lifecycle.';
