ALTER TABLE crm.project_supplier
    DROP CONSTRAINT ck_project_supplier_operating_mode,
    ADD CONSTRAINT ck_project_supplier_operating_mode
        CHECK (operating_mode IN ('FULL', 'MINI', 'FULFILLMENT'));

COMMENT ON COLUMN crm.project_supplier.operating_mode IS
    'Project-scoped supplier workflow: FULL uses catalogued goods, MINI uses direct warehouse goods, FULFILLMENT uses customer-scoped opaque parcels and itemized returns.';

CREATE SEQUENCE crm.fulfillment_shipment_number_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE crm.fulfillment_return_number_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE crm.fulfillment_shipment
(
    id                           UUID           NOT NULL,
    project_id                   UUID           NOT NULL,
    supplier_id                  UUID           NOT NULL,
    customer_profile_id          UUID           NOT NULL,
    customer_account_id          UUID,
    shipment_number              VARCHAR(32)    NOT NULL,
    customer_display_name        VARCHAR(200)   NOT NULL,
    customer_phone               VARCHAR(32),
    customer_email               VARCHAR(254),
    status_code                  VARCHAR(32)    NOT NULL DEFAULT 'DRAFT',
    warehouse_id                 UUID           NOT NULL,
    delivery_method_code         VARCHAR(32)    NOT NULL,
    recipient_name               VARCHAR(200),
    recipient_phone              VARCHAR(32),
    delivery_address             VARCHAR(1000),
    delivery_instructions        VARCHAR(2000),
    customer_amount              NUMERIC(19, 4) NOT NULL,
    service_fee_amount           NUMERIC(19, 4) NOT NULL,
    partner_entitlement_amount   NUMERIC(19, 4)
        GENERATED ALWAYS AS (customer_amount - service_fee_amount) STORED,
    currency_code                VARCHAR(3)     NOT NULL,
    operator_description         VARCHAR(10000),
    submitted_at                 TIMESTAMPTZ,
    warehouse_received_at        TIMESTAMPTZ,
    dispatched_at                TIMESTAMPTZ,
    delivered_at                 TIMESTAMPTZ,
    settled_at                   TIMESTAMPTZ,
    cancelled_at                 TIMESTAMPTZ,
    cancellation_reason          VARCHAR(500),
    created_by_account_id        UUID           NOT NULL,
    created_by_subject           VARCHAR(255)   NOT NULL,
    updated_by_subject           VARCHAR(255)   NOT NULL,
    created_at                   TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                   TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                      BIGINT         NOT NULL DEFAULT 0,
    CONSTRAINT pk_fulfillment_shipment PRIMARY KEY (id),
    CONSTRAINT uq_fulfillment_shipment_project UNIQUE (id, project_id),
    CONSTRAINT uq_fulfillment_shipment_scope UNIQUE (id, project_id, supplier_id),
    CONSTRAINT uq_fulfillment_shipment_number UNIQUE (shipment_number),
    CONSTRAINT fk_fulfillment_shipment_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_shipment_customer
        FOREIGN KEY (customer_profile_id, project_id, supplier_id)
            REFERENCES crm.customer_profile (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_shipment_customer_account
        FOREIGN KEY (customer_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_shipment_warehouse
        FOREIGN KEY (warehouse_id) REFERENCES crm.warehouse (id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_shipment_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_shipment_creator
        FOREIGN KEY (created_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_fulfillment_shipment_status
        CHECK (status_code IN (
            'DRAFT', 'EXPECTED_AT_WAREHOUSE', 'AT_WAREHOUSE', 'DISPATCHED',
            'DELIVERED', 'SETTLED', 'CANCELLED'
        )),
    CONSTRAINT ck_fulfillment_shipment_delivery_method
        CHECK (delivery_method_code IN ('WAREHOUSE_HANDOVER', 'INTERNAL_COURIER', 'EXTERNAL_COURIER')),
    CONSTRAINT ck_fulfillment_shipment_customer_name CHECK (BTRIM(customer_display_name) <> ''),
    CONSTRAINT ck_fulfillment_shipment_optional_text CHECK (
        (customer_phone IS NULL OR BTRIM(customer_phone) <> '')
        AND (customer_email IS NULL OR BTRIM(customer_email) <> '')
        AND (recipient_name IS NULL OR BTRIM(recipient_name) <> '')
        AND (recipient_phone IS NULL OR BTRIM(recipient_phone) <> '')
        AND (delivery_address IS NULL OR BTRIM(delivery_address) <> '')
        AND (delivery_instructions IS NULL OR BTRIM(delivery_instructions) <> '')
        AND (operator_description IS NULL OR BTRIM(operator_description) <> '')
    ),
    CONSTRAINT ck_fulfillment_shipment_route CHECK (
        delivery_method_code = 'WAREHOUSE_HANDOVER'
        OR (recipient_name IS NOT NULL AND recipient_phone IS NOT NULL AND delivery_address IS NOT NULL)
    ),
    CONSTRAINT ck_fulfillment_shipment_money CHECK (
        customer_amount > 0
        AND service_fee_amount >= 0
        AND service_fee_amount < customer_amount
        AND partner_entitlement_amount > 0
    ),
    CONSTRAINT ck_fulfillment_shipment_lifecycle CHECK (
        (status_code = 'DRAFT' AND submitted_at IS NULL AND warehouse_received_at IS NULL
            AND dispatched_at IS NULL AND delivered_at IS NULL AND settled_at IS NULL
            AND cancelled_at IS NULL AND cancellation_reason IS NULL)
        OR (status_code = 'EXPECTED_AT_WAREHOUSE' AND submitted_at IS NOT NULL
            AND warehouse_received_at IS NULL AND dispatched_at IS NULL AND delivered_at IS NULL
            AND settled_at IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL)
        OR (status_code = 'AT_WAREHOUSE' AND submitted_at IS NOT NULL
            AND warehouse_received_at IS NOT NULL AND dispatched_at IS NULL AND delivered_at IS NULL
            AND settled_at IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL)
        OR (status_code = 'DISPATCHED' AND submitted_at IS NOT NULL
            AND warehouse_received_at IS NOT NULL AND dispatched_at IS NOT NULL AND delivered_at IS NULL
            AND settled_at IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL)
        OR (status_code = 'DELIVERED' AND submitted_at IS NOT NULL
            AND warehouse_received_at IS NOT NULL AND dispatched_at IS NOT NULL AND delivered_at IS NOT NULL
            AND settled_at IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL)
        OR (status_code = 'SETTLED' AND submitted_at IS NOT NULL
            AND warehouse_received_at IS NOT NULL AND dispatched_at IS NOT NULL AND delivered_at IS NOT NULL
            AND settled_at IS NOT NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL)
        OR (status_code = 'CANCELLED' AND settled_at IS NULL AND cancelled_at IS NOT NULL
            AND cancellation_reason IS NOT NULL AND BTRIM(cancellation_reason) <> '')
    ),
    CONSTRAINT ck_fulfillment_shipment_actor CHECK (
        BTRIM(created_by_subject) <> '' AND BTRIM(updated_by_subject) <> ''
    ),
    CONSTRAINT ck_fulfillment_shipment_timestamps CHECK (updated_at >= created_at),
    CONSTRAINT ck_fulfillment_shipment_version CHECK (version >= 0)
);

CREATE INDEX ix_fulfillment_shipment_scope_status
    ON crm.fulfillment_shipment (project_id, supplier_id, status_code, updated_at DESC, id);
CREATE INDEX ix_fulfillment_shipment_customer
    ON crm.fulfillment_shipment (customer_profile_id, created_at DESC, id);
CREATE INDEX ix_fulfillment_shipment_warehouse
    ON crm.fulfillment_shipment (warehouse_id, status_code, updated_at DESC, id);

CREATE TABLE crm.fulfillment_parcel
(
    id                  UUID          NOT NULL,
    shipment_id         UUID          NOT NULL,
    project_id          UUID          NOT NULL,
    supplier_id         UUID          NOT NULL,
    parcel_number       VARCHAR(48)   NOT NULL,
    label_code          VARCHAR(100)  NOT NULL,
    external_reference  VARCHAR(200),
    description         VARCHAR(2000),
    weight_kg           NUMERIC(12, 3),
    length_cm           NUMERIC(12, 2),
    width_cm            NUMERIC(12, 2),
    height_cm           NUMERIC(12, 2),
    status_code         VARCHAR(24)   NOT NULL DEFAULT 'EXPECTED',
    received_at         TIMESTAMPTZ,
    dispatched_at       TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    created_by_subject  VARCHAR(255)  NOT NULL,
    updated_by_subject  VARCHAR(255)  NOT NULL,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version             BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_fulfillment_parcel PRIMARY KEY (id),
    CONSTRAINT uq_fulfillment_parcel_scope UNIQUE (id, shipment_id, project_id, supplier_id),
    CONSTRAINT uq_fulfillment_parcel_number UNIQUE (parcel_number),
    CONSTRAINT uq_fulfillment_parcel_label UNIQUE (label_code),
    CONSTRAINT fk_fulfillment_parcel_shipment
        FOREIGN KEY (shipment_id, project_id, supplier_id)
            REFERENCES crm.fulfillment_shipment (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT ck_fulfillment_parcel_status
        CHECK (status_code IN ('EXPECTED', 'RECEIVED', 'DISPATCHED', 'DELIVERED', 'CANCELLED')),
    CONSTRAINT ck_fulfillment_parcel_text CHECK (
        BTRIM(parcel_number) <> '' AND BTRIM(label_code) <> ''
        AND (external_reference IS NULL OR BTRIM(external_reference) <> '')
        AND (description IS NULL OR BTRIM(description) <> '')
        AND BTRIM(created_by_subject) <> '' AND BTRIM(updated_by_subject) <> ''
    ),
    CONSTRAINT ck_fulfillment_parcel_measurements CHECK (
        (weight_kg IS NULL OR weight_kg > 0)
        AND (length_cm IS NULL OR length_cm > 0)
        AND (width_cm IS NULL OR width_cm > 0)
        AND (height_cm IS NULL OR height_cm > 0)
    ),
    CONSTRAINT ck_fulfillment_parcel_lifecycle CHECK (
        (status_code = 'EXPECTED' AND received_at IS NULL AND dispatched_at IS NULL AND delivered_at IS NULL)
        OR (status_code = 'RECEIVED' AND received_at IS NOT NULL AND dispatched_at IS NULL AND delivered_at IS NULL)
        OR (status_code = 'DISPATCHED' AND received_at IS NOT NULL AND dispatched_at IS NOT NULL AND delivered_at IS NULL)
        OR (status_code = 'DELIVERED' AND received_at IS NOT NULL AND dispatched_at IS NOT NULL AND delivered_at IS NOT NULL)
        OR (status_code = 'CANCELLED' AND dispatched_at IS NULL AND delivered_at IS NULL)
    ),
    CONSTRAINT ck_fulfillment_parcel_timestamps CHECK (updated_at >= created_at),
    CONSTRAINT ck_fulfillment_parcel_version CHECK (version >= 0)
);

CREATE INDEX ix_fulfillment_parcel_shipment
    ON crm.fulfillment_parcel (shipment_id, created_at, id);

CREATE TABLE crm.fulfillment_return
(
    id                           UUID          NOT NULL,
    project_id                   UUID          NOT NULL,
    supplier_id                  UUID          NOT NULL,
    customer_profile_id          UUID          NOT NULL,
    customer_account_id          UUID,
    original_shipment_id         UUID,
    return_number                VARCHAR(32)   NOT NULL,
    customer_display_name        VARCHAR(200)  NOT NULL,
    customer_phone               VARCHAR(32),
    customer_email               VARCHAR(254),
    warehouse_id                 UUID          NOT NULL,
    status_code                  VARCHAR(32)   NOT NULL DEFAULT 'DRAFT',
    reason                       VARCHAR(2000)  NOT NULL,
    operator_description         VARCHAR(10000),
    expected_unit_count          INTEGER       NOT NULL,
    received_unit_count          INTEGER       NOT NULL DEFAULT 0,
    submitted_at                 TIMESTAMPTZ,
    received_at                  TIMESTAMPTZ,
    closed_at                    TIMESTAMPTZ,
    cancelled_at                 TIMESTAMPTZ,
    cancellation_reason          VARCHAR(500),
    created_by_account_id        UUID          NOT NULL,
    created_by_subject           VARCHAR(255)  NOT NULL,
    updated_by_subject           VARCHAR(255)  NOT NULL,
    created_at                   TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                   TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                      BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_fulfillment_return PRIMARY KEY (id),
    CONSTRAINT uq_fulfillment_return_project UNIQUE (id, project_id),
    CONSTRAINT uq_fulfillment_return_scope UNIQUE (id, project_id, supplier_id),
    CONSTRAINT uq_fulfillment_return_number UNIQUE (return_number),
    CONSTRAINT fk_fulfillment_return_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_return_customer
        FOREIGN KEY (customer_profile_id, project_id, supplier_id)
            REFERENCES crm.customer_profile (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_return_customer_account
        FOREIGN KEY (customer_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_return_original_shipment
        FOREIGN KEY (original_shipment_id, project_id, supplier_id)
            REFERENCES crm.fulfillment_shipment (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_return_warehouse
        FOREIGN KEY (warehouse_id) REFERENCES crm.warehouse (id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_return_creator
        FOREIGN KEY (created_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_fulfillment_return_status
        CHECK (status_code IN (
            'DRAFT', 'EXPECTED_AT_WAREHOUSE', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED', 'CANCELLED'
        )),
    CONSTRAINT ck_fulfillment_return_text CHECK (
        BTRIM(customer_display_name) <> '' AND BTRIM(reason) <> ''
        AND (customer_phone IS NULL OR BTRIM(customer_phone) <> '')
        AND (customer_email IS NULL OR BTRIM(customer_email) <> '')
        AND (operator_description IS NULL OR BTRIM(operator_description) <> '')
        AND BTRIM(created_by_subject) <> '' AND BTRIM(updated_by_subject) <> ''
    ),
    CONSTRAINT ck_fulfillment_return_counts CHECK (
        expected_unit_count > 0
        AND received_unit_count >= 0
        AND received_unit_count <= expected_unit_count
    ),
    CONSTRAINT ck_fulfillment_return_lifecycle CHECK (
        (status_code = 'DRAFT' AND submitted_at IS NULL AND received_at IS NULL AND closed_at IS NULL
            AND cancelled_at IS NULL AND cancellation_reason IS NULL AND received_unit_count = 0)
        OR (status_code = 'EXPECTED_AT_WAREHOUSE' AND submitted_at IS NOT NULL AND received_at IS NULL
            AND closed_at IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL
            AND received_unit_count = 0)
        OR (status_code = 'PARTIALLY_RECEIVED' AND submitted_at IS NOT NULL AND received_at IS NULL
            AND closed_at IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL
            AND received_unit_count > 0 AND received_unit_count < expected_unit_count)
        OR (status_code = 'RECEIVED' AND submitted_at IS NOT NULL AND received_at IS NOT NULL
            AND closed_at IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL
            AND received_unit_count = expected_unit_count)
        OR (status_code = 'CLOSED' AND submitted_at IS NOT NULL AND received_at IS NOT NULL
            AND closed_at IS NOT NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL
            AND received_unit_count = expected_unit_count)
        OR (status_code = 'CANCELLED' AND received_unit_count = 0 AND closed_at IS NULL
            AND cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL
            AND BTRIM(cancellation_reason) <> '')
    ),
    CONSTRAINT ck_fulfillment_return_timestamps CHECK (updated_at >= created_at),
    CONSTRAINT ck_fulfillment_return_version CHECK (version >= 0)
);

CREATE INDEX ix_fulfillment_return_scope_status
    ON crm.fulfillment_return (project_id, supplier_id, status_code, updated_at DESC, id);
CREATE INDEX ix_fulfillment_return_customer
    ON crm.fulfillment_return (customer_profile_id, created_at DESC, id);
CREATE INDEX ix_fulfillment_return_warehouse
    ON crm.fulfillment_return (warehouse_id, status_code, updated_at DESC, id);

CREATE TABLE crm.fulfillment_return_unit
(
    id                    UUID          NOT NULL,
    fulfillment_return_id UUID          NOT NULL,
    project_id            UUID          NOT NULL,
    supplier_id           UUID          NOT NULL,
    original_parcel_id    UUID,
    unit_number           VARCHAR(48)   NOT NULL,
    label_code            VARCHAR(100)  NOT NULL,
    external_reference    VARCHAR(200),
    declared_description  VARCHAR(2000) NOT NULL,
    received_description  VARCHAR(2000),
    condition_code        VARCHAR(24),
    status_code           VARCHAR(24)   NOT NULL DEFAULT 'EXPECTED',
    evidence_message_id   UUID,
    received_by_account_id UUID,
    received_at           TIMESTAMPTZ,
    created_by_subject    VARCHAR(255)  NOT NULL,
    updated_by_subject    VARCHAR(255)  NOT NULL,
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version               BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_fulfillment_return_unit PRIMARY KEY (id),
    CONSTRAINT uq_fulfillment_return_unit_scope
        UNIQUE (id, fulfillment_return_id, project_id, supplier_id),
    CONSTRAINT uq_fulfillment_return_unit_number UNIQUE (unit_number),
    CONSTRAINT uq_fulfillment_return_unit_label UNIQUE (label_code),
    CONSTRAINT fk_fulfillment_return_unit_return
        FOREIGN KEY (fulfillment_return_id, project_id, supplier_id)
            REFERENCES crm.fulfillment_return (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_return_unit_original_parcel
        FOREIGN KEY (original_parcel_id) REFERENCES crm.fulfillment_parcel (id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_return_unit_evidence
        FOREIGN KEY (evidence_message_id) REFERENCES crm.chat_message (id) ON DELETE RESTRICT,
    CONSTRAINT fk_fulfillment_return_unit_receiver
        FOREIGN KEY (received_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_fulfillment_return_unit_status
        CHECK (status_code IN ('EXPECTED', 'RECEIVED', 'RETURNED_TO_PARTNER', 'REASSIGNED', 'CANCELLED')),
    CONSTRAINT ck_fulfillment_return_unit_condition
        CHECK (condition_code IS NULL OR condition_code IN ('NEW', 'OPENED', 'USED', 'DAMAGED', 'UNKNOWN')),
    CONSTRAINT ck_fulfillment_return_unit_text CHECK (
        BTRIM(unit_number) <> '' AND BTRIM(label_code) <> '' AND BTRIM(declared_description) <> ''
        AND (external_reference IS NULL OR BTRIM(external_reference) <> '')
        AND (received_description IS NULL OR BTRIM(received_description) <> '')
        AND BTRIM(created_by_subject) <> '' AND BTRIM(updated_by_subject) <> ''
    ),
    CONSTRAINT ck_fulfillment_return_unit_receipt CHECK (
        (status_code IN ('EXPECTED', 'CANCELLED') AND received_description IS NULL
            AND condition_code IS NULL AND evidence_message_id IS NULL
            AND received_by_account_id IS NULL AND received_at IS NULL)
        OR (status_code IN ('RECEIVED', 'RETURNED_TO_PARTNER', 'REASSIGNED')
            AND received_description IS NOT NULL AND condition_code IS NOT NULL
            AND evidence_message_id IS NOT NULL AND received_by_account_id IS NOT NULL AND received_at IS NOT NULL)
    ),
    CONSTRAINT ck_fulfillment_return_unit_timestamps CHECK (updated_at >= created_at),
    CONSTRAINT ck_fulfillment_return_unit_version CHECK (version >= 0)
);

CREATE INDEX ix_fulfillment_return_unit_return
    ON crm.fulfillment_return_unit (fulfillment_return_id, created_at, id);
CREATE INDEX ix_fulfillment_return_unit_original_parcel
    ON crm.fulfillment_return_unit (original_parcel_id, created_at, id)
    WHERE original_parcel_id IS NOT NULL;

CREATE UNIQUE INDEX uq_fulfillment_return_unit_evidence
    ON crm.fulfillment_return_unit (evidence_message_id)
    WHERE evidence_message_id IS NOT NULL;

CREATE TABLE crm.fulfillment_audit_event
(
    id             UUID         NOT NULL,
    project_id     UUID         NOT NULL,
    supplier_id    UUID         NOT NULL,
    aggregate_type VARCHAR(24)  NOT NULL,
    aggregate_id   UUID         NOT NULL,
    event_type     VARCHAR(64)  NOT NULL,
    actor_subject  VARCHAR(255) NOT NULL,
    details        JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at    TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fulfillment_audit_event PRIMARY KEY (id),
    CONSTRAINT ck_fulfillment_audit_aggregate
        CHECK (aggregate_type IN ('SHIPMENT', 'RETURN', 'RETURN_UNIT')),
    CONSTRAINT ck_fulfillment_audit_text
        CHECK (BTRIM(event_type) <> '' AND BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_fulfillment_audit_details CHECK (JSONB_TYPEOF(details) = 'object')
);

CREATE INDEX ix_fulfillment_audit_aggregate
    ON crm.fulfillment_audit_event (aggregate_type, aggregate_id, occurred_at DESC, id);

ALTER TABLE crm.task
    DROP CONSTRAINT ck_task_standalone_managed_shape,
    DROP CONSTRAINT ck_task_deadline_required_shape,
    ADD COLUMN fulfillment_shipment_id UUID,
    ADD COLUMN fulfillment_return_id UUID,
    ADD CONSTRAINT uq_task_fulfillment_shipment UNIQUE (fulfillment_shipment_id),
    ADD CONSTRAINT uq_task_fulfillment_return UNIQUE (fulfillment_return_id),
    ADD CONSTRAINT fk_task_fulfillment_shipment
        FOREIGN KEY (fulfillment_shipment_id, project_id)
            REFERENCES crm.fulfillment_shipment (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_task_fulfillment_return
        FOREIGN KEY (fulfillment_return_id, project_id)
            REFERENCES crm.fulfillment_return (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_task_standalone_managed_shape CHECK (
        NUM_NONNULLS(
            customer_order_id,
            warehouse_relocation_id,
            fulfillment_shipment_id,
            fulfillment_return_id
        ) = 0
        OR (
            NUM_NONNULLS(
                customer_order_id,
                warehouse_relocation_id,
                fulfillment_shipment_id,
                fulfillment_return_id
            ) = 1
            AND inbound_delivery_id IS NULL
            AND courier_trip_id IS NULL
            AND parent_task_id IS NULL
        )
    ),
    ADD CONSTRAINT ck_task_deadline_required_shape CHECK (
        deadline_at IS NOT NULL
        OR customer_order_id IS NOT NULL
        OR warehouse_relocation_id IS NOT NULL
        OR fulfillment_shipment_id IS NOT NULL
        OR fulfillment_return_id IS NOT NULL
    );

CREATE INDEX ix_task_fulfillment_shipment
    ON crm.task (fulfillment_shipment_id) WHERE fulfillment_shipment_id IS NOT NULL;
CREATE INDEX ix_task_fulfillment_return
    ON crm.task (fulfillment_return_id) WHERE fulfillment_return_id IS NOT NULL;

ALTER TABLE crm.task_participant
    DROP CONSTRAINT ck_task_participant_source,
    ADD CONSTRAINT ck_task_participant_source CHECK (source_code IN (
        'MANUAL',
        'DELIVERY_SUPPLIER', 'DELIVERY_PROJECT_ROLE',
        'COURIER_TRIP_SUPPLIER', 'COURIER_TRIP_PROJECT_ROLE',
        'CUSTOMER_ORDER_SUPPLIER', 'CUSTOMER_ORDER_CUSTOMER', 'CUSTOMER_ORDER_PROJECT_ROLE',
        'RELOCATION_PROJECT_ROLE',
        'FULFILLMENT_SUPPLIER', 'FULFILLMENT_CUSTOMER', 'FULFILLMENT_PROJECT_ROLE',
        'GLOBAL_ADMINISTRATOR'
    ));

ALTER TABLE crm.task_subcategory
    DROP CONSTRAINT ck_task_subcategory_system_source,
    ADD CONSTRAINT ck_task_subcategory_system_source CHECK (
        system_source_code IS NULL
        OR system_source_code IN (
            'INBOUND_DELIVERY', 'COURIER_TRIP', 'CUSTOMER_ORDER',
            'CUSTOMER_ORDER_SHIPMENT', 'CUSTOMER_ORDER_HANDOVER', 'CUSTOMER_ORDER_DELIVERY',
            'WAREHOUSE_RELOCATION', 'FULFILLMENT_SHIPMENT', 'FULFILLMENT_RETURN'
        )
    );

INSERT INTO crm.task_subcategory (
    id, category_id, country_code, system_source_code, name, active, sort_order,
    created_by_subject, updated_by_subject, created_at, updated_at, version
) VALUES
    (
        '00000000-0000-0000-0000-000000005408',
        '00000000-0000-0000-0000-000000005400',
        NULL, 'FULFILLMENT_SHIPMENT', 'Отправление fulfillment-партнёра', TRUE, 7,
        'system:migration-v85', 'system:migration-v85', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0
    ),
    (
        '00000000-0000-0000-0000-000000005409',
        '00000000-0000-0000-0000-000000005400',
        NULL, 'FULFILLMENT_RETURN', 'Возврат клиента fulfillment-партнёра', TRUE, 8,
        'system:migration-v85', 'system:migration-v85', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0
    );

ALTER TABLE crm.settlement_money_operation
    ADD COLUMN fulfillment_shipment_id UUID,
    ADD CONSTRAINT fk_settlement_money_operation_fulfillment_shipment
        FOREIGN KEY (fulfillment_shipment_id) REFERENCES crm.fulfillment_shipment (id) ON DELETE RESTRICT,
    DROP CONSTRAINT ck_settlement_money_operation_shape,
    ADD CONSTRAINT ck_settlement_money_operation_shape CHECK (
        (
            operation_type = 'CUSTOMER_ADVANCE' AND project_id IS NOT NULL
            AND counterparty_type = 'CUSTOMER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND counterparty_delta = amount AND reason IS NULL
        ) OR (
            operation_type = 'CUSTOMER_ORDER_CHARGE' AND project_id IS NOT NULL
            AND counterparty_type = 'CUSTOMER' AND customer_order_id IS NOT NULL
            AND fulfillment_shipment_id IS NULL AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta = -amount AND reason IS NULL
        ) OR (
            operation_type = 'CUSTOMER_ORDER_RECEIPT' AND project_id IS NOT NULL
            AND customer_order_id IS NOT NULL AND fulfillment_shipment_id IS NULL
            AND financial_account_id IS NOT NULL AND destination_financial_account_id IS NULL
            AND payment_method IS NOT NULL AND counterparty_delta IS NULL AND reason IS NULL
            AND ((counterparty_type IS NULL AND customer_profile_id IS NULL)
                OR (counterparty_type = 'CUSTOMER' AND customer_profile_id IS NOT NULL))
        ) OR (
            operation_type = 'CUSTOMER_REFUND' AND project_id IS NOT NULL
            AND counterparty_type = 'CUSTOMER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND counterparty_delta = -amount AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'COUNTERPARTY_ADJUSTMENT' AND project_id IS NOT NULL
            AND counterparty_type IS NOT NULL AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta IS NOT NULL AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type IN ('INTERNAL_TRANSFER', 'INTERNAL_CONVERSION')
            AND project_id IS NULL AND supplier_id IS NULL AND counterparty_type IS NULL
            AND customer_profile_id IS NULL AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NOT NULL
            AND financial_account_id <> destination_financial_account_id
            AND payment_method IS NULL AND counterparty_delta IS NULL
            AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_ACCRUAL' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER'
            AND NUM_NONNULLS(customer_order_id, fulfillment_shipment_id) = 1
            AND financial_account_id IS NULL AND destination_financial_account_id IS NULL
            AND payment_method IS NULL AND counterparty_delta = amount
            AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_ENTITLEMENT_ADJUSTMENT' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER'
            AND NUM_NONNULLS(customer_order_id, fulfillment_shipment_id) = 1
            AND financial_account_id IS NULL AND destination_financial_account_id IS NULL
            AND payment_method IS NULL AND counterparty_delta IS NOT NULL AND counterparty_delta <> 0
            AND amount = ABS(counterparty_delta) AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_DEDUCTION' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta = -amount AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_PAYOUT' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND counterparty_delta = -amount AND reason IS NULL
        )
    );

CREATE INDEX ix_settlement_money_operation_fulfillment_shipment
    ON crm.settlement_money_operation (fulfillment_shipment_id, currency_code, occurred_at, id)
    WHERE fulfillment_shipment_id IS NOT NULL;

ALTER TABLE crm.settlement_supplier_entitlement
    DROP CONSTRAINT uq_settlement_supplier_entitlement_line,
    DROP CONSTRAINT uq_settlement_supplier_entitlement_item,
    ALTER COLUMN customer_order_id DROP NOT NULL,
    ALTER COLUMN customer_order_line_id DROP NOT NULL,
    ALTER COLUMN cargo_item_id DROP NOT NULL,
    ADD COLUMN fulfillment_shipment_id UUID,
    ADD CONSTRAINT fk_settlement_supplier_entitlement_fulfillment_shipment
        FOREIGN KEY (fulfillment_shipment_id) REFERENCES crm.fulfillment_shipment (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_settlement_supplier_entitlement_source CHECK (
        (
            customer_order_id IS NOT NULL
            AND customer_order_line_id IS NOT NULL
            AND cargo_item_id IS NOT NULL
            AND fulfillment_shipment_id IS NULL
        ) OR (
            customer_order_id IS NULL
            AND customer_order_line_id IS NULL
            AND cargo_item_id IS NULL
            AND fulfillment_shipment_id IS NOT NULL
        )
    );

CREATE UNIQUE INDEX uq_settlement_supplier_entitlement_line
    ON crm.settlement_supplier_entitlement (customer_order_line_id)
    WHERE customer_order_line_id IS NOT NULL;
CREATE UNIQUE INDEX uq_settlement_supplier_entitlement_item
    ON crm.settlement_supplier_entitlement (cargo_item_id)
    WHERE cargo_item_id IS NOT NULL;
CREATE UNIQUE INDEX uq_settlement_supplier_entitlement_fulfillment_shipment
    ON crm.settlement_supplier_entitlement (fulfillment_shipment_id)
    WHERE fulfillment_shipment_id IS NOT NULL;

COMMENT ON TABLE crm.fulfillment_shipment IS
    'Customer-scoped opaque-parcel shipment for a FULFILLMENT supplier. It has no product catalogue or per-item sale prices.';
COMMENT ON TABLE crm.fulfillment_parcel IS
    'Operationally tracked opaque parcel. Its contents are intentionally outside the Box EU product model.';
COMMENT ON TABLE crm.fulfillment_return IS
    'Reverse warehouse flow from an exact customer, optionally linked to the original shipment.';
COMMENT ON TABLE crm.fulfillment_return_unit IS
    'One physical returned unit with exact provenance and immutable task-chat receipt evidence.';
COMMENT ON COLUMN crm.fulfillment_return_unit.evidence_message_id IS
    'Task-chat message containing the warehouse receipt description and ready photos for this exact unit.';
COMMENT ON COLUMN crm.settlement_supplier_entitlement.fulfillment_shipment_id IS
    'FULFILLMENT economic source; mutually exclusive with exact customer-order line and cargo-item sources.';
