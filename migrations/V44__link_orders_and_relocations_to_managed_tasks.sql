ALTER TABLE crm.task
    ADD COLUMN customer_order_id UUID,
    ADD COLUMN warehouse_relocation_id UUID,
    ALTER COLUMN deadline_at DROP NOT NULL,
    ADD CONSTRAINT uq_task_customer_order UNIQUE (customer_order_id),
    ADD CONSTRAINT uq_task_warehouse_relocation UNIQUE (warehouse_relocation_id),
    ADD CONSTRAINT fk_task_customer_order
        FOREIGN KEY (customer_order_id, project_id)
            REFERENCES crm.customer_order (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_task_warehouse_relocation
        FOREIGN KEY (warehouse_relocation_id, project_id)
            REFERENCES crm.warehouse_relocation (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_task_standalone_managed_shape
        CHECK (
            (
                customer_order_id IS NULL
                OR (
                    warehouse_relocation_id IS NULL
                    AND inbound_delivery_id IS NULL
                    AND courier_trip_id IS NULL
                    AND parent_task_id IS NULL
                )
            )
            AND (
                warehouse_relocation_id IS NULL
                OR (
                    customer_order_id IS NULL
                    AND inbound_delivery_id IS NULL
                    AND courier_trip_id IS NULL
                    AND parent_task_id IS NULL
                )
            )
        ),
    ADD CONSTRAINT ck_task_deadline_required_shape
        CHECK (
            deadline_at IS NOT NULL
            OR customer_order_id IS NOT NULL
            OR warehouse_relocation_id IS NOT NULL
        );

CREATE INDEX ix_task_customer_order
    ON crm.task (customer_order_id)
    WHERE customer_order_id IS NOT NULL;

CREATE INDEX ix_task_warehouse_relocation
    ON crm.task (warehouse_relocation_id)
    WHERE warehouse_relocation_id IS NOT NULL;

ALTER TABLE crm.task_participant
    DROP CONSTRAINT ck_task_participant_source,
    ADD CONSTRAINT ck_task_participant_source
        CHECK (source_code IN (
            'MANUAL',
            'DELIVERY_SUPPLIER',
            'DELIVERY_PROJECT_ROLE',
            'COURIER_TRIP_SUPPLIER',
            'COURIER_TRIP_PROJECT_ROLE',
            'CUSTOMER_ORDER_SUPPLIER',
            'CUSTOMER_ORDER_CUSTOMER',
            'CUSTOMER_ORDER_PROJECT_ROLE',
            'RELOCATION_PROJECT_ROLE',
            'GLOBAL_ADMINISTRATOR'
        ));

COMMENT ON COLUMN crm.task.customer_order_id IS
    'One-to-one customer-order binding. The customer-order lifecycle is the only terminal-state authority.';
COMMENT ON COLUMN crm.task.warehouse_relocation_id IS
    'One-to-one warehouse-relocation binding. The relocation lifecycle is the only terminal-state authority.';
COMMENT ON COLUMN crm.task.deadline_at IS
    'Required for manually managed, inbound-delivery, and courier-trip tasks. Standalone order and relocation tasks inherit lifecycle completion without an invented deadline.';

CREATE TEMPORARY TABLE managed_task_backfill ON COMMIT DROP AS
WITH resources AS (
    SELECT customer_order.project_id,
           customer_order.id AS resource_id,
           'CUSTOMER_ORDER'::VARCHAR(32) AS resource_type,
           customer_order.order_number AS resource_number,
           customer_order.customer_account_id AS actor_account_id,
           customer_order.created_by_subject AS actor_subject,
           customer_order.created_at,
           customer_order.updated_at,
           customer_order.status_code,
           CASE WHEN customer_order.status_code = 'FULFILLED'
               THEN customer_order.updated_at
               ELSE NULL
           END AS completed_at
    FROM crm.customer_order
    UNION ALL
    SELECT relocation.project_id,
           relocation.id,
           'WAREHOUSE_RELOCATION'::VARCHAR(32),
           relocation.relocation_number,
           relocation.created_by_account_id,
           relocation.created_by_subject,
           relocation.created_at,
           relocation.updated_at,
           relocation.status_code,
           relocation.completed_at
    FROM crm.warehouse_relocation relocation
), numbered AS (
    SELECT resources.*,
           ROW_NUMBER() OVER (
               PARTITION BY resources.project_id
               ORDER BY resources.created_at, resources.resource_type, resources.resource_id
           ) AS allocated_offset
    FROM resources
), allocated AS (
    SELECT numbered.*,
           COALESCE(counter.last_value, 0) + numbered.allocated_offset AS sequence_number
    FROM numbered
    LEFT JOIN crm.project_task_counter counter ON counter.project_id = numbered.project_id
)
SELECT MD5('boxeudelivery:managed-task:' || allocated.resource_type || ':' || allocated.resource_id::TEXT)::UUID
           AS task_id,
       MD5('boxeudelivery:managed-task-conversation:' || allocated.resource_type || ':'
           || allocated.resource_id::TEXT)::UUID AS conversation_id,
       allocated.*
FROM allocated;

INSERT INTO crm.project_task_counter (project_id, last_value)
SELECT project_id, MAX(sequence_number)
FROM managed_task_backfill
GROUP BY project_id
ON CONFLICT (project_id) DO UPDATE
SET last_value = GREATEST(crm.project_task_counter.last_value, EXCLUDED.last_value);

INSERT INTO crm.conversation (
    id,
    project_id,
    kind_code,
    last_message_sequence,
    created_at,
    version
)
SELECT conversation_id,
       project_id,
       'TASK',
       0,
       created_at,
       0
FROM managed_task_backfill;

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
       NULL,
       NULL,
       NULL,
       CASE WHEN backfill.resource_type = 'CUSTOMER_ORDER' THEN backfill.resource_id ELSE NULL END,
       CASE WHEN backfill.resource_type = 'WAREHOUSE_RELOCATION' THEN backfill.resource_id ELSE NULL END,
       NULL,
       project.task_prefix || '-' || backfill.sequence_number,
       backfill.sequence_number,
       CASE
           WHEN backfill.resource_type = 'CUSTOMER_ORDER'
               THEN 'Выполнение заказа ' || backfill.resource_number
           ELSE 'Перемещение ' || backfill.resource_number
       END,
       CASE
           WHEN backfill.resource_type = 'CUSTOMER_ORDER'
               THEN 'Заказ должен быть укомплектован и полностью передан клиенту.'
           ELSE 'Все товары должны быть приняты на складе назначения.'
       END,
       CASE
           WHEN backfill.status_code = 'CANCELLED' THEN 'CANCELLED'
           WHEN backfill.status_code IN ('FULFILLED', 'COMPLETED') THEN 'COMPLETED'
           ELSE 'IN_PROGRESS'
       END,
       'NORMAL',
       NULL,
       project.time_zone_id,
       backfill.completed_at,
       backfill.actor_account_id,
       backfill.actor_account_id,
       backfill.created_at,
       backfill.updated_at,
       0
FROM managed_task_backfill backfill
JOIN crm.project project ON project.id = backfill.project_id;

WITH participant_candidates AS (
    SELECT backfill.task_id,
           backfill.project_id,
           member.id AS project_member_id,
           backfill.actor_account_id,
           backfill.created_at,
           'CUSTOMER_ORDER_CUSTOMER'::VARCHAR(32) AS source_code,
           1 AS source_priority
    FROM managed_task_backfill backfill
    JOIN crm.customer_order customer_order
      ON backfill.resource_type = 'CUSTOMER_ORDER'
     AND customer_order.id = backfill.resource_id
    JOIN crm.project_member member
      ON member.project_id = customer_order.project_id
     AND member.account_id = customer_order.customer_account_id
    UNION ALL
    SELECT backfill.task_id,
           backfill.project_id,
           member.id,
           backfill.actor_account_id,
           backfill.created_at,
           'CUSTOMER_ORDER_SUPPLIER',
           2
    FROM managed_task_backfill backfill
    JOIN crm.customer_order customer_order
      ON backfill.resource_type = 'CUSTOMER_ORDER'
     AND customer_order.id = backfill.resource_id
    JOIN crm.project_supplier_member supplier_member
      ON supplier_member.project_id = customer_order.project_id
     AND supplier_member.supplier_id = customer_order.supplier_id
     AND supplier_member.status_code = 'ACTIVE'
    JOIN crm.project_member member
      ON member.project_id = supplier_member.project_id
     AND member.account_id = supplier_member.account_id
    JOIN crm.account account
      ON account.id = member.account_id
     AND account.status = 'ACTIVE'
    UNION ALL
    SELECT backfill.task_id,
           backfill.project_id,
           member.id,
           backfill.actor_account_id,
           backfill.created_at,
           'CUSTOMER_ORDER_PROJECT_ROLE',
           3
    FROM managed_task_backfill backfill
    JOIN crm.project_member member ON member.project_id = backfill.project_id
    JOIN crm.project_member_role role ON role.project_member_id = member.id
    JOIN crm.account account ON account.id = member.account_id AND account.status = 'ACTIVE'
    WHERE backfill.resource_type = 'CUSTOMER_ORDER'
      AND role.role_code IN ('OPERATIONS_MANAGER', 'CUSTOMER_MANAGER', 'WAREHOUSE_OPERATOR')
    UNION ALL
    SELECT backfill.task_id,
           backfill.project_id,
           member.id,
           backfill.actor_account_id,
           backfill.created_at,
           'RELOCATION_PROJECT_ROLE',
           1
    FROM managed_task_backfill backfill
    JOIN crm.project_member member ON member.project_id = backfill.project_id
    JOIN crm.project_member_role role ON role.project_member_id = member.id
    JOIN crm.account account ON account.id = member.account_id AND account.status = 'ACTIVE'
    WHERE backfill.resource_type = 'WAREHOUSE_RELOCATION'
      AND role.role_code IN (
          'OPERATIONS_MANAGER',
          'LOGISTICS_SPECIALIST',
          'WAREHOUSE_OPERATOR',
          'ACCOUNTANT',
          'FINANCIAL_CONTROLLER'
      )
    UNION ALL
    SELECT backfill.task_id,
           backfill.project_id,
           member.id,
           backfill.actor_account_id,
           backfill.created_at,
           'RELOCATION_PROJECT_ROLE',
           2
    FROM managed_task_backfill backfill
    JOIN crm.project_member member
      ON member.project_id = backfill.project_id
     AND member.account_id = backfill.actor_account_id
    WHERE backfill.resource_type = 'WAREHOUSE_RELOCATION'
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
SELECT MD5('boxeudelivery:managed-task-participant:' || task_id::TEXT || ':'
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
SELECT MD5('boxeudelivery:managed-task-audit:' || managed_task_backfill.task_id::TEXT)::UUID,
       managed_task_backfill.project_id,
       managed_task_backfill.task_id,
       'CREATED',
       'system:flyway-v44',
       JSONB_BUILD_OBJECT(
           'taskKey', project.task_prefix || '-' || managed_task_backfill.sequence_number,
           'resourceType', managed_task_backfill.resource_type,
           'resourceId', managed_task_backfill.resource_id::TEXT,
           'backfilled', TRUE
       ),
       managed_task_backfill.created_at
FROM managed_task_backfill
JOIN crm.project project ON project.id = managed_task_backfill.project_id;
