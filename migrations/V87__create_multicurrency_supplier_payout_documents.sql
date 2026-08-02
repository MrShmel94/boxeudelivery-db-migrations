ALTER TABLE crm.settlement_money_operation
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
            AND (counterparty_delta IS NULL OR counterparty_delta = -amount) AND reason IS NULL
        )
    );

CREATE SEQUENCE crm.supplier_payout_document_number_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE crm.settlement_supplier_payout_document
(
    id                  UUID         NOT NULL,
    client_operation_id UUID         NOT NULL,
    request_fingerprint VARCHAR(64)  NOT NULL,
    document_number     VARCHAR(32)  NOT NULL,
    project_id          UUID         NOT NULL,
    supplier_id         UUID         NOT NULL,
    note                VARCHAR(500),
    occurred_at         TIMESTAMPTZ  NOT NULL,
    created_by_subject  VARCHAR(255) NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement_supplier_payout_document
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_supplier_payout_document_client
        UNIQUE (client_operation_id),
    CONSTRAINT uq_settlement_supplier_payout_document_number
        UNIQUE (document_number),
    CONSTRAINT fk_settlement_supplier_payout_document_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_payout_document_fingerprint
        CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_settlement_supplier_payout_document_number
        CHECK (BTRIM(document_number) <> ''),
    CONSTRAINT ck_settlement_supplier_payout_document_note
        CHECK (note IS NULL OR BTRIM(note) <> ''),
    CONSTRAINT ck_settlement_supplier_payout_document_actor
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_settlement_supplier_payout_document_times
        CHECK (created_at >= occurred_at)
);

CREATE INDEX ix_settlement_supplier_payout_document_scope_occurred
    ON crm.settlement_supplier_payout_document (
        project_id,
        supplier_id,
        occurred_at DESC,
        id DESC
    );

CREATE TABLE crm.settlement_supplier_payout_leg
(
    id                       UUID           NOT NULL,
    payout_document_id       UUID           NOT NULL,
    payout_operation_id      UUID           NOT NULL,
    settlement_amount        NUMERIC(19, 4) NOT NULL,
    settlement_currency_code VARCHAR(3)     NOT NULL,
    payout_amount            NUMERIC(19, 4) NOT NULL,
    payout_currency_code     VARCHAR(3)     NOT NULL,
    sort_order               INTEGER        NOT NULL,
    CONSTRAINT pk_settlement_supplier_payout_leg
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_supplier_payout_leg_operation
        UNIQUE (payout_operation_id),
    CONSTRAINT uq_settlement_supplier_payout_leg_order
        UNIQUE (payout_document_id, sort_order),
    CONSTRAINT fk_settlement_supplier_payout_leg_document
        FOREIGN KEY (payout_document_id)
            REFERENCES crm.settlement_supplier_payout_document (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_payout_leg_operation
        FOREIGN KEY (payout_operation_id)
            REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_payout_leg_settlement_currency
        FOREIGN KEY (settlement_currency_code)
            REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_payout_leg_payout_currency
        FOREIGN KEY (payout_currency_code)
            REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_payout_leg_amounts
        CHECK (settlement_amount > 0 AND payout_amount > 0),
    CONSTRAINT ck_settlement_supplier_payout_leg_sort
        CHECK (sort_order >= 0)
);

CREATE INDEX ix_settlement_supplier_payout_leg_document
    ON crm.settlement_supplier_payout_leg (payout_document_id, sort_order, id);

CREATE TABLE crm.settlement_supplier_payout_document_acknowledgement
(
    payout_document_id  UUID         NOT NULL,
    decision_code       VARCHAR(16)  NOT NULL,
    supplier_account_id UUID         NOT NULL,
    note                VARCHAR(500),
    occurred_at         TIMESTAMPTZ  NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement_supplier_payout_document_acknowledgement
        PRIMARY KEY (payout_document_id),
    CONSTRAINT fk_settlement_supplier_payout_document_acknowledgement_document
        FOREIGN KEY (payout_document_id)
            REFERENCES crm.settlement_supplier_payout_document (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_payout_document_acknowledgement_account
        FOREIGN KEY (supplier_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_payout_document_acknowledgement_decision
        CHECK (decision_code IN ('RECEIVED', 'DISPUTED')),
    CONSTRAINT ck_settlement_supplier_payout_document_acknowledgement_note
        CHECK (note IS NULL OR BTRIM(note) <> '')
);

INSERT INTO crm.settlement_supplier_payout_document (
    id,
    client_operation_id,
    request_fingerprint,
    document_number,
    project_id,
    supplier_id,
    note,
    occurred_at,
    created_by_subject,
    created_at
)
SELECT operation.id,
       operation.client_operation_id,
       MD5(operation.id::TEXT) || MD5(operation.client_operation_id::TEXT),
       'PAY-' || LPAD(NEXTVAL('crm.supplier_payout_document_number_seq')::TEXT, 8, '0'),
       operation.project_id,
       operation.supplier_id,
       operation.note,
       operation.occurred_at,
       operation.created_by_subject,
       operation.created_at
FROM crm.settlement_money_operation operation
WHERE operation.operation_type = 'SUPPLIER_PAYOUT'
ORDER BY operation.occurred_at, operation.id;

INSERT INTO crm.settlement_supplier_payout_leg (
    id,
    payout_document_id,
    payout_operation_id,
    settlement_amount,
    settlement_currency_code,
    payout_amount,
    payout_currency_code,
    sort_order
)
SELECT operation.id,
       operation.id,
       operation.id,
       operation.amount,
       operation.currency_code,
       operation.amount,
       operation.currency_code,
       0
FROM crm.settlement_money_operation operation
WHERE operation.operation_type = 'SUPPLIER_PAYOUT';

INSERT INTO crm.settlement_supplier_payout_document_acknowledgement (
    payout_document_id,
    decision_code,
    supplier_account_id,
    note,
    occurred_at,
    created_at
)
SELECT acknowledgement.payout_operation_id,
       acknowledgement.decision_code,
       acknowledgement.supplier_account_id,
       acknowledgement.note,
       acknowledgement.occurred_at,
       acknowledgement.created_at
FROM crm.settlement_supplier_payout_acknowledgement acknowledgement;

COMMENT ON TABLE crm.settlement_supplier_payout_document IS
    'One supplier-visible payout document containing one or more actual money legs and one acknowledgement.';
COMMENT ON TABLE crm.settlement_supplier_payout_leg IS
    'Maps the supplier liability amount being settled to the actual amount and currency issued by the company.';
COMMENT ON TABLE crm.settlement_supplier_payout_document_acknowledgement IS
    'Supplier evidence for the complete payout document; it never silently reverses its immutable money legs.';
