CREATE TABLE crm.project_internal_courier
(
    project_member_id  UUID         NOT NULL,
    assigned_by_subject VARCHAR(255) NOT NULL,
    assigned_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_project_internal_courier
        PRIMARY KEY (project_member_id),
    CONSTRAINT fk_project_internal_courier_member
        FOREIGN KEY (project_member_id)
            REFERENCES crm.project_member (id) ON DELETE CASCADE,
    CONSTRAINT ck_project_internal_courier_actor
        CHECK (BTRIM(assigned_by_subject) <> '')
);

COMMENT ON TABLE crm.project_internal_courier IS
    'Project-scoped operational eligibility for an employee project member to perform directly assigned customer deliveries.';

ALTER TABLE crm.outbound_delivery
    ADD COLUMN assigned_courier_source VARCHAR(32),
    ADD COLUMN courier_conversation_id UUID,
    ADD COLUMN courier_compensation_amount NUMERIC(19, 4),
    ADD COLUMN courier_compensation_currency VARCHAR(3);

INSERT INTO crm.conversation (
    id,
    project_id,
    last_message_sequence,
    created_at,
    version,
    kind_code
)
SELECT MD5('outbound-delivery-courier-conversation:' || delivery.id::TEXT)::UUID,
       delivery.project_id,
       0,
       delivery.created_at,
       0,
       'COURIER_INTERNAL'
FROM crm.outbound_delivery delivery
WHERE delivery.method_code = 'COMPANY_COURIER';

UPDATE crm.outbound_delivery delivery
SET assigned_courier_source = 'GLOBAL_COURIER',
    courier_conversation_id = MD5('outbound-delivery-courier-conversation:' || delivery.id::TEXT)::UUID
WHERE delivery.method_code = 'COMPANY_COURIER';

INSERT INTO crm.conversation_participant (
    conversation_id,
    account_id,
    source_code,
    joined_at,
    created_at,
    updated_at
)
SELECT delivery.courier_conversation_id,
       delivery.assigned_courier_account_id,
       'COURIER',
       delivery.created_at,
       delivery.created_at,
       delivery.created_at
FROM crm.outbound_delivery delivery
WHERE delivery.method_code = 'COMPANY_COURIER'
ON CONFLICT (conversation_id, account_id) DO UPDATE
SET revoked_at = NULL,
    source_code = 'COURIER',
    updated_at = EXCLUDED.updated_at;

ALTER TABLE crm.outbound_delivery
    ADD CONSTRAINT uq_outbound_delivery_courier_conversation
        UNIQUE (courier_conversation_id),
    ADD CONSTRAINT fk_outbound_delivery_courier_conversation
        FOREIGN KEY (courier_conversation_id, project_id)
            REFERENCES crm.conversation (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_outbound_delivery_courier_compensation_currency
        FOREIGN KEY (courier_compensation_currency)
            REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_outbound_delivery_courier_source
        CHECK (assigned_courier_source IS NULL OR assigned_courier_source IN (
            'GLOBAL_COURIER',
            'PROJECT_INTERNAL'
        )),
    ADD CONSTRAINT ck_outbound_delivery_courier_assignment
        CHECK (
            (
                method_code = 'COMPANY_COURIER'
                AND assigned_courier_account_id IS NOT NULL
                AND assigned_courier_source IS NOT NULL
                AND courier_conversation_id IS NOT NULL
            )
            OR (
                method_code <> 'COMPANY_COURIER'
                AND assigned_courier_account_id IS NULL
                AND assigned_courier_source IS NULL
                AND courier_conversation_id IS NULL
            )
        ),
    ADD CONSTRAINT ck_outbound_delivery_courier_compensation
        CHECK (
            (courier_compensation_amount IS NULL AND courier_compensation_currency IS NULL)
            OR (
                method_code = 'COMPANY_COURIER'
                AND courier_compensation_amount >= 0
                AND courier_compensation_currency IS NOT NULL
            )
        );

ALTER TABLE crm.outbound_delivery_financial_revision
    ADD COLUMN courier_compensation_amount NUMERIC(19, 4),
    ADD COLUMN courier_compensation_currency VARCHAR(3),
    ADD CONSTRAINT fk_outbound_delivery_fin_rev_courier_comp_currency
        FOREIGN KEY (courier_compensation_currency)
            REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_outbound_delivery_financial_revision_courier_compensation
        CHECK (
            (courier_compensation_amount IS NULL AND courier_compensation_currency IS NULL)
            OR (courier_compensation_amount >= 0 AND courier_compensation_currency IS NOT NULL)
        );

COMMENT ON COLUMN crm.outbound_delivery.assigned_courier_source IS
    'Immutable source of the directly assigned company courier: global routed courier or project-internal employee.';

COMMENT ON COLUMN crm.outbound_delivery.courier_conversation_id IS
    'Separate employee-courier coordination channel for a directly assigned customer delivery.';

COMMENT ON COLUMN crm.outbound_delivery.courier_compensation_amount IS
    'Optional amount earned by the assigned courier; separate from customer charge, supplier deduction, and company actual cost.';

COMMENT ON COLUMN crm.outbound_delivery.courier_compensation_currency IS
    'Currency of the optional assigned-courier compensation.';
