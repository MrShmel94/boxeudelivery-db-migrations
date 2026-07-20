ALTER TABLE crm.inbound_delivery
    ADD COLUMN delivery_deadline_at TIMESTAMPTZ,
    ADD COLUMN delivery_deadline_zone_id VARCHAR(64),
    ADD CONSTRAINT ck_inbound_delivery_deadline_pair
        CHECK (
            (delivery_deadline_at IS NULL AND delivery_deadline_zone_id IS NULL)
            OR (delivery_deadline_at IS NOT NULL AND delivery_deadline_zone_id IS NOT NULL)
        ),
    ADD CONSTRAINT ck_inbound_delivery_deadline_zone_not_blank
        CHECK (delivery_deadline_zone_id IS NULL OR BTRIM(delivery_deadline_zone_id) <> ''),
    ADD CONSTRAINT uq_inbound_delivery_id_project_conversation
        UNIQUE (id, project_id, conversation_id);

ALTER TABLE crm.task
    ADD COLUMN inbound_delivery_id UUID,
    ADD CONSTRAINT uq_task_inbound_delivery
        UNIQUE (inbound_delivery_id),
    ADD CONSTRAINT fk_task_inbound_delivery
        FOREIGN KEY (inbound_delivery_id, project_id, conversation_id)
            REFERENCES crm.inbound_delivery (id, project_id, conversation_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_task_inbound_delivery_root
        CHECK (inbound_delivery_id IS NULL OR parent_task_id IS NULL);

ALTER TABLE crm.task_participant
    ADD COLUMN source_code VARCHAR(32) NOT NULL DEFAULT 'MANUAL',
    ADD CONSTRAINT ck_task_participant_source
        CHECK (source_code IN ('MANUAL', 'DELIVERY_SUPPLIER', 'DELIVERY_PROJECT_ROLE'));

ALTER TABLE crm.task_participant
    ALTER COLUMN source_code DROP DEFAULT;

CREATE INDEX ix_task_inbound_delivery
    ON crm.task (inbound_delivery_id)
    WHERE inbound_delivery_id IS NOT NULL;

COMMENT ON COLUMN crm.inbound_delivery.delivery_deadline_at IS
    'Supplier-owned latest warehouse-arrival instant. Distinct from the courier pickup deadline.';
COMMENT ON COLUMN crm.task.inbound_delivery_id IS
    'Optional one-to-one binding for an operational task projected from an inbound delivery. The task reuses the delivery conversation.';
COMMENT ON COLUMN crm.task_participant.source_code IS
    'Manual assignment or mandatory delivery audience captured when the operational task is created.';
