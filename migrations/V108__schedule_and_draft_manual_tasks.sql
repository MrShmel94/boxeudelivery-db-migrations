ALTER TABLE crm.task
    DROP CONSTRAINT ck_task_status,
    ADD COLUMN scheduled_execution_at TIMESTAMPTZ,
    ADD COLUMN scheduled_execution_zone_id VARCHAR(64),
    ADD CONSTRAINT ck_task_status
        CHECK (status_code IN ('DRAFT', 'PLANNED', 'IN_PROGRESS', 'BLOCKED', 'COMPLETED', 'CANCELLED')),
    ADD CONSTRAINT ck_task_draft_native_only
        CHECK (
            status_code <> 'DRAFT'
            OR NUM_NONNULLS(
                inbound_delivery_id,
                mini_supplier_intake_id,
                courier_trip_id,
                customer_order_id,
                warehouse_relocation_id,
                fulfillment_shipment_id,
                fulfillment_return_id
            ) = 0
        ),
    ADD CONSTRAINT ck_task_scheduled_execution_shape
        CHECK (
            (
                scheduled_execution_at IS NULL
                AND scheduled_execution_zone_id IS NULL
            )
            OR (
                scheduled_execution_at IS NOT NULL
                AND scheduled_execution_zone_id IS NOT NULL
                AND BTRIM(scheduled_execution_zone_id) <> ''
                AND deadline_at IS NOT NULL
                AND scheduled_execution_at <= deadline_at
                AND NUM_NONNULLS(
                    inbound_delivery_id,
                    mini_supplier_intake_id,
                    courier_trip_id,
                    customer_order_id,
                    warehouse_relocation_id,
                    fulfillment_shipment_id,
                    fulfillment_return_id
                ) = 0
            )
        );

CREATE INDEX ix_task_dashboard_schedule
    ON crm.task (status_code, scheduled_execution_at, deadline_at, updated_at DESC, id);

ALTER TABLE crm.task_audit_event
    DROP CONSTRAINT ck_task_audit_event_type,
    ADD CONSTRAINT ck_task_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'UPDATED',
            'DEADLINE_CHANGED',
            'SCHEDULE_CHANGED',
            'STATUS_CHANGED',
            'DELETED',
            'PARTICIPANT_ADDED',
            'PARTICIPANT_REMOVED',
            'ASSIGNEE_ADDED',
            'ASSIGNEE_REMOVED',
            'ATTACHMENT_CANCELLED'
        ));

COMMENT ON COLUMN crm.task.scheduled_execution_at IS
    'Optional exact execution moment for a manually managed task. It is distinct from the completion deadline.';
COMMENT ON COLUMN crm.task.scheduled_execution_zone_id IS
    'Business time-zone snapshot used to classify and display the optional execution moment.';
