ALTER TABLE crm.task
    DROP CONSTRAINT fk_task_inbound_delivery,
    DROP CONSTRAINT ck_task_inbound_delivery_root,
    ADD COLUMN courier_trip_id UUID,
    ADD COLUMN managed_state_code VARCHAR(32),
    ADD CONSTRAINT fk_task_inbound_delivery
        FOREIGN KEY (inbound_delivery_id, project_id)
            REFERENCES crm.inbound_delivery (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_task_courier_trip_conversation
        FOREIGN KEY (courier_trip_id, project_id, conversation_id)
            REFERENCES crm.courier_trip (id, project_id, conversation_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_task_managed_business_shape
        CHECK (
            (
                inbound_delivery_id IS NULL
                OR parent_task_id IS NULL
                OR courier_trip_id IS NOT NULL
            )
            AND (
                courier_trip_id IS NULL
                OR (inbound_delivery_id IS NULL AND parent_task_id IS NULL)
                OR (inbound_delivery_id IS NOT NULL AND parent_task_id IS NOT NULL)
            )
        ),
    ADD CONSTRAINT ck_task_managed_state
        CHECK (managed_state_code IS NULL OR managed_state_code = 'PRICE_MODERATION'),
    ADD CONSTRAINT ck_task_managed_state_shape
        CHECK (
            managed_state_code IS NULL
            OR (
                inbound_delivery_id IS NOT NULL
                AND status_code = 'BLOCKED'
                AND priority_code = 'URGENT'
            )
        );

CREATE UNIQUE INDEX uq_task_courier_trip_root
    ON crm.task (courier_trip_id)
    WHERE courier_trip_id IS NOT NULL AND inbound_delivery_id IS NULL;

CREATE INDEX ix_task_courier_trip
    ON crm.task (courier_trip_id, parent_task_id, id)
    WHERE courier_trip_id IS NOT NULL;

ALTER TABLE crm.task_participant
    DROP CONSTRAINT ck_task_participant_source,
    ADD CONSTRAINT ck_task_participant_source
        CHECK (source_code IN (
            'MANUAL',
            'DELIVERY_SUPPLIER',
            'DELIVERY_PROJECT_ROLE',
            'COURIER_TRIP_SUPPLIER',
            'COURIER_TRIP_PROJECT_ROLE'
        ));

COMMENT ON COLUMN crm.task.courier_trip_id IS
    'Grouped courier trip whose active conversation and managed lifecycle are projected by this task tree.';
COMMENT ON COLUMN crm.task.managed_state_code IS
    'Cargo-owned non-terminal task state that ordinary task commands cannot override.';
COMMENT ON COLUMN crm.task.inbound_delivery_id IS
    'One-to-one inbound-delivery binding. A grouped delivery task becomes a child in the courier-trip conversation.';
