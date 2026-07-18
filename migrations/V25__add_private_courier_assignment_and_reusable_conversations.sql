ALTER TABLE crm.task_conversation
    RENAME TO conversation;

ALTER TABLE crm.conversation
    ADD COLUMN kind_code VARCHAR(32) NOT NULL DEFAULT 'TASK',
    ADD CONSTRAINT ck_conversation_kind
        CHECK (kind_code IN ('TASK', 'INBOUND_DELIVERY'));

ALTER TABLE crm.conversation
    ALTER COLUMN kind_code DROP DEFAULT;

ALTER INDEX crm.ix_task_conversation_project
    RENAME TO ix_conversation_project;

ALTER TABLE crm.chat_attachment
    DROP CONSTRAINT fk_chat_attachment_message;

ALTER TABLE crm.chat_message
    DROP CONSTRAINT fk_chat_message_context_task,
    DROP CONSTRAINT uq_chat_message_id_context_conversation,
    ALTER COLUMN context_task_id DROP NOT NULL,
    ADD CONSTRAINT fk_chat_message_context_task
        FOREIGN KEY (context_task_id, conversation_id)
            REFERENCES crm.task (id, conversation_id) ON DELETE RESTRICT;

ALTER TABLE crm.chat_attachment
    DROP CONSTRAINT fk_chat_attachment_context_task,
    ALTER COLUMN context_task_id DROP NOT NULL,
    ADD CONSTRAINT fk_chat_attachment_context_task
        FOREIGN KEY (context_task_id, conversation_id)
            REFERENCES crm.task (id, conversation_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_chat_attachment_message
        FOREIGN KEY (message_id, conversation_id)
            REFERENCES crm.chat_message (id, conversation_id) ON DELETE RESTRICT;

ALTER TABLE crm.inbound_delivery
    ADD COLUMN conversation_id UUID,
    ADD COLUMN courier_distribution_mode VARCHAR(32) NOT NULL DEFAULT 'OPEN_POOL',
    ADD COLUMN designated_courier_account_id UUID,
    ADD COLUMN pickup_deadline_at TIMESTAMPTZ,
    ADD COLUMN pickup_deadline_zone_id VARCHAR(64);

INSERT INTO crm.conversation (
    id,
    project_id,
    last_message_sequence,
    created_at,
    version,
    kind_code
)
SELECT
    MD5('inbound-delivery-conversation:' || delivery.id::TEXT)::UUID,
    delivery.project_id,
    0,
    delivery.created_at,
    0,
    'INBOUND_DELIVERY'
FROM crm.inbound_delivery delivery;

UPDATE crm.inbound_delivery delivery
SET conversation_id = MD5('inbound-delivery-conversation:' || delivery.id::TEXT)::UUID;

UPDATE crm.inbound_delivery
SET pickup_deadline_at = COALESCE(ready_for_courier_at, dispatched_at, created_at) + INTERVAL '7 days',
    pickup_deadline_zone_id = 'Europe/Moscow'
WHERE transport_mode = 'COURIER_VIA_PICKUP_POINT';

ALTER TABLE crm.inbound_delivery
    ALTER COLUMN conversation_id SET NOT NULL,
    ALTER COLUMN courier_distribution_mode DROP DEFAULT,
    ADD CONSTRAINT uq_inbound_delivery_conversation
        UNIQUE (conversation_id),
    ADD CONSTRAINT fk_inbound_delivery_conversation
        FOREIGN KEY (conversation_id, project_id)
            REFERENCES crm.conversation (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_inbound_delivery_designated_courier
        FOREIGN KEY (designated_courier_account_id)
            REFERENCES crm.account (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_inbound_delivery_courier_distribution
        CHECK (courier_distribution_mode IN ('OPEN_POOL', 'DIRECT_ASSIGNMENT')),
    ADD CONSTRAINT ck_inbound_delivery_pickup_deadline_pair
        CHECK (
            (pickup_deadline_at IS NULL AND pickup_deadline_zone_id IS NULL)
            OR (pickup_deadline_at IS NOT NULL AND pickup_deadline_zone_id IS NOT NULL)
        ),
    ADD CONSTRAINT ck_inbound_delivery_courier_configuration
        CHECK (
            (
                transport_mode = 'DIRECT_TO_WAREHOUSE'
                AND courier_distribution_mode = 'OPEN_POOL'
                AND designated_courier_account_id IS NULL
                AND pickup_deadline_at IS NULL
                AND pickup_deadline_zone_id IS NULL
            )
            OR (
                transport_mode = 'COURIER_VIA_PICKUP_POINT'
                AND pickup_deadline_at IS NOT NULL
                AND pickup_deadline_zone_id IS NOT NULL
            )
        );

CREATE INDEX ix_inbound_delivery_courier_pool
    ON crm.inbound_delivery (ready_for_courier_at, id)
    WHERE status_code = 'READY_FOR_COURIER_PICKUP'
      AND courier_distribution_mode = 'OPEN_POOL';

CREATE INDEX ix_inbound_delivery_designated_courier
    ON crm.inbound_delivery (designated_courier_account_id, status_code, updated_at DESC, id)
    WHERE designated_courier_account_id IS NOT NULL;

CREATE TABLE crm.conversation_participant
(
    conversation_id UUID        NOT NULL,
    account_id      UUID        NOT NULL,
    source_code     VARCHAR(32) NOT NULL,
    joined_at       TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (conversation_id, account_id),

    CONSTRAINT fk_conversation_participant_conversation
        FOREIGN KEY (conversation_id) REFERENCES crm.conversation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_conversation_participant_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_conversation_participant_source
        CHECK (source_code IN ('SUPPLIER', 'CREATOR', 'COURIER')),
    CONSTRAINT ck_conversation_participant_timestamps
        CHECK (
            updated_at >= created_at
            AND (revoked_at IS NULL OR revoked_at >= joined_at)
        )
);

CREATE INDEX ix_conversation_participant_account_active
    ON crm.conversation_participant (account_id, conversation_id)
    WHERE revoked_at IS NULL;

INSERT INTO crm.conversation_participant (
    conversation_id,
    account_id,
    source_code,
    joined_at,
    created_at,
    updated_at
)
SELECT
    delivery.conversation_id,
    delivery.supplier_account_id,
    'SUPPLIER',
    delivery.created_at,
    delivery.created_at,
    delivery.created_at
FROM crm.inbound_delivery delivery;

INSERT INTO crm.conversation_participant (
    conversation_id,
    account_id,
    source_code,
    joined_at,
    created_at,
    updated_at
)
SELECT
    delivery.conversation_id,
    account.id,
    'CREATOR',
    delivery.created_at,
    delivery.created_at,
    delivery.created_at
FROM crm.inbound_delivery delivery
JOIN crm.account account
  ON delivery.created_by_subject = 'account:' || account.id::TEXT
ON CONFLICT (conversation_id, account_id) DO NOTHING;

INSERT INTO crm.conversation_participant (
    conversation_id,
    account_id,
    source_code,
    joined_at,
    created_at,
    updated_at
)
SELECT
    delivery.conversation_id,
    assignment.courier_account_id,
    'COURIER',
    assignment.claimed_at,
    assignment.created_at,
    assignment.updated_at
FROM crm.courier_assignment assignment
JOIN crm.inbound_delivery delivery ON delivery.id = assignment.inbound_delivery_id
WHERE assignment.status_code IN ('CLAIMED', 'PICKED_UP', 'COMPLETED')
ON CONFLICT (conversation_id, account_id) DO NOTHING;

ALTER TABLE crm.courier_assignment
    DROP CONSTRAINT ck_courier_assignment_status,
    DROP CONSTRAINT ck_courier_assignment_state,
    DROP CONSTRAINT ck_courier_assignment_timestamps,
    ALTER COLUMN claimed_at DROP NOT NULL,
    ADD COLUMN offered_at TIMESTAMPTZ,
    ADD COLUMN courier_planned_pickup_at TIMESTAMPTZ,
    ADD COLUMN response_reason VARCHAR(500);

UPDATE crm.courier_assignment
SET offered_at = claimed_at,
    courier_planned_pickup_at = claimed_at
WHERE offered_at IS NULL;

ALTER TABLE crm.courier_assignment
    ALTER COLUMN offered_at SET NOT NULL,
    ADD CONSTRAINT ck_courier_assignment_status
        CHECK (status_code IN (
            'OFFERED',
            'CLAIMED',
            'DECLINED',
            'WITHDRAWN',
            'PICKED_UP',
            'RELEASED',
            'COMPLETED'
        )),
    ADD CONSTRAINT ck_courier_assignment_response_reason
        CHECK (response_reason IS NULL OR BTRIM(response_reason) <> ''),
    ADD CONSTRAINT ck_courier_assignment_state
        CHECK (
            (
                status_code = 'OFFERED'
                AND claimed_at IS NULL
                AND courier_planned_pickup_at IS NULL
                AND picked_up_at IS NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND response_reason IS NULL
                AND release_reason IS NULL
            )
            OR (
                status_code IN ('DECLINED', 'WITHDRAWN')
                AND claimed_at IS NULL
                AND courier_planned_pickup_at IS NULL
                AND picked_up_at IS NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND response_reason IS NOT NULL
                AND release_reason IS NULL
            )
            OR (
                status_code = 'CLAIMED'
                AND claimed_at IS NOT NULL
                AND courier_planned_pickup_at IS NOT NULL
                AND picked_up_at IS NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND release_reason IS NULL
            )
            OR (
                status_code = 'PICKED_UP'
                AND claimed_at IS NOT NULL
                AND courier_planned_pickup_at IS NOT NULL
                AND picked_up_at IS NOT NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND release_reason IS NULL
            )
            OR (
                status_code = 'RELEASED'
                AND claimed_at IS NOT NULL
                AND courier_planned_pickup_at IS NOT NULL
                AND picked_up_at IS NULL
                AND released_at IS NOT NULL
                AND completed_at IS NULL
                AND release_reason IS NOT NULL
            )
            OR (
                status_code = 'COMPLETED'
                AND claimed_at IS NOT NULL
                AND courier_planned_pickup_at IS NOT NULL
                AND picked_up_at IS NOT NULL
                AND released_at IS NULL
                AND completed_at IS NOT NULL
                AND release_reason IS NULL
            )
        ),
    ADD CONSTRAINT ck_courier_assignment_timestamps
        CHECK (
            updated_at >= created_at
            AND offered_at >= created_at
            AND (claimed_at IS NULL OR claimed_at >= offered_at)
            AND (courier_planned_pickup_at IS NULL OR courier_planned_pickup_at >= claimed_at)
            AND (picked_up_at IS NULL OR picked_up_at >= claimed_at)
            AND (released_at IS NULL OR released_at >= claimed_at)
            AND (completed_at IS NULL OR completed_at >= picked_up_at)
        );

DROP INDEX crm.uq_courier_assignment_active_delivery;

CREATE UNIQUE INDEX uq_courier_assignment_active_delivery
    ON crm.courier_assignment (inbound_delivery_id)
    WHERE status_code IN ('OFFERED', 'CLAIMED', 'PICKED_UP');

COMMENT ON TABLE crm.conversation IS
    'Reusable durable conversation sequence shared by typed business-resource bindings.';
COMMENT ON COLUMN crm.inbound_delivery.courier_distribution_mode IS
    'OPEN_POOL publishes a ready job to eligible couriers; DIRECT_ASSIGNMENT creates a private offer.';
COMMENT ON COLUMN crm.inbound_delivery.pickup_deadline_at IS
    'Exact latest instant when courier pickup may occur; V25 backfilled existing courier routes with a visible seven-day operational deadline.';
COMMENT ON COLUMN crm.courier_assignment.courier_planned_pickup_at IS
    'Exact pickup instant promised by the courier when accepting or claiming the job.';
