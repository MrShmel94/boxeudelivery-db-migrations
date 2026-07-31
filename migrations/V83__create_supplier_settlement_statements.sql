ALTER TABLE crm.settlement_money_operation
    DROP CONSTRAINT ck_settlement_money_operation_type,
    DROP CONSTRAINT ck_settlement_money_operation_shape,
    ADD CONSTRAINT ck_settlement_money_operation_type
        CHECK (operation_type IN (
            'CUSTOMER_ADVANCE',
            'CUSTOMER_ORDER_CHARGE',
            'CUSTOMER_ORDER_RECEIPT',
            'CUSTOMER_REFUND',
            'COUNTERPARTY_ADJUSTMENT',
            'INTERNAL_TRANSFER',
            'INTERNAL_CONVERSION',
            'SUPPLIER_ACCRUAL',
            'SUPPLIER_DEDUCTION',
            'SUPPLIER_PAYOUT'
        )),
    ADD CONSTRAINT ck_settlement_money_operation_shape
        CHECK (
            (
                operation_type = 'CUSTOMER_ADVANCE'
                AND project_id IS NOT NULL
                AND counterparty_type = 'CUSTOMER'
                AND customer_order_id IS NULL
                AND financial_account_id IS NOT NULL
                AND destination_financial_account_id IS NULL
                AND payment_method IS NOT NULL
                AND counterparty_delta = amount
                AND reason IS NULL
            )
            OR
            (
                operation_type = 'CUSTOMER_ORDER_CHARGE'
                AND project_id IS NOT NULL
                AND counterparty_type = 'CUSTOMER'
                AND customer_order_id IS NOT NULL
                AND financial_account_id IS NULL
                AND destination_financial_account_id IS NULL
                AND payment_method IS NULL
                AND counterparty_delta = -amount
                AND reason IS NULL
            )
            OR
            (
                operation_type = 'CUSTOMER_ORDER_RECEIPT'
                AND project_id IS NOT NULL
                AND customer_order_id IS NOT NULL
                AND financial_account_id IS NOT NULL
                AND destination_financial_account_id IS NULL
                AND payment_method IS NOT NULL
                AND counterparty_delta IS NULL
                AND reason IS NULL
                AND (
                    (counterparty_type IS NULL AND customer_profile_id IS NULL)
                    OR
                    (counterparty_type = 'CUSTOMER' AND customer_profile_id IS NOT NULL)
                )
            )
            OR
            (
                operation_type = 'CUSTOMER_REFUND'
                AND project_id IS NOT NULL
                AND counterparty_type = 'CUSTOMER'
                AND customer_order_id IS NULL
                AND financial_account_id IS NOT NULL
                AND destination_financial_account_id IS NULL
                AND payment_method IS NOT NULL
                AND counterparty_delta = -amount
                AND reason IS NOT NULL
                AND BTRIM(reason) <> ''
            )
            OR
            (
                operation_type = 'COUNTERPARTY_ADJUSTMENT'
                AND project_id IS NOT NULL
                AND counterparty_type IS NOT NULL
                AND customer_order_id IS NULL
                AND financial_account_id IS NULL
                AND destination_financial_account_id IS NULL
                AND payment_method IS NULL
                AND counterparty_delta IS NOT NULL
                AND reason IS NOT NULL
                AND BTRIM(reason) <> ''
            )
            OR
            (
                operation_type IN ('INTERNAL_TRANSFER', 'INTERNAL_CONVERSION')
                AND project_id IS NULL
                AND supplier_id IS NULL
                AND counterparty_type IS NULL
                AND customer_profile_id IS NULL
                AND customer_order_id IS NULL
                AND financial_account_id IS NOT NULL
                AND destination_financial_account_id IS NOT NULL
                AND financial_account_id <> destination_financial_account_id
                AND payment_method IS NULL
                AND counterparty_delta IS NULL
                AND reason IS NOT NULL
                AND BTRIM(reason) <> ''
            )
            OR
            (
                operation_type = 'SUPPLIER_ACCRUAL'
                AND project_id IS NOT NULL
                AND counterparty_type = 'SUPPLIER'
                AND customer_order_id IS NOT NULL
                AND financial_account_id IS NULL
                AND destination_financial_account_id IS NULL
                AND payment_method IS NULL
                AND counterparty_delta = amount
                AND reason IS NOT NULL
                AND BTRIM(reason) <> ''
            )
            OR
            (
                operation_type = 'SUPPLIER_DEDUCTION'
                AND project_id IS NOT NULL
                AND counterparty_type = 'SUPPLIER'
                AND customer_order_id IS NULL
                AND financial_account_id IS NULL
                AND destination_financial_account_id IS NULL
                AND payment_method IS NULL
                AND counterparty_delta = -amount
                AND reason IS NOT NULL
                AND BTRIM(reason) <> ''
            )
            OR
            (
                operation_type = 'SUPPLIER_PAYOUT'
                AND project_id IS NOT NULL
                AND counterparty_type = 'SUPPLIER'
                AND customer_order_id IS NULL
                AND financial_account_id IS NOT NULL
                AND destination_financial_account_id IS NULL
                AND payment_method IS NOT NULL
                AND counterparty_delta = -amount
                AND reason IS NULL
            )
        );

CREATE SEQUENCE crm.supplier_settlement_statement_number_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE crm.settlement_supplier_statement
(
    id                     UUID           NOT NULL,
    client_operation_id    UUID           NOT NULL,
    request_fingerprint    VARCHAR(64)    NOT NULL,
    statement_number       VARCHAR(32)    NOT NULL,
    project_id             UUID           NOT NULL,
    supplier_id            UUID           NOT NULL,
    currency_code          VARCHAR(3)     NOT NULL,
    gross_amount           NUMERIC(19, 4) NOT NULL,
    deduction_amount       NUMERIC(19, 4) NOT NULL,
    net_amount             NUMERIC(19, 4) NOT NULL,
    deduction_operation_id UUID,
    note                   VARCHAR(500),
    occurred_at            TIMESTAMPTZ    NOT NULL,
    created_by_subject     VARCHAR(255)   NOT NULL,
    created_at             TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement_supplier_statement
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_supplier_statement_client
        UNIQUE (client_operation_id),
    CONSTRAINT uq_settlement_supplier_statement_number
        UNIQUE (statement_number),
    CONSTRAINT uq_settlement_supplier_statement_deduction_operation
        UNIQUE (deduction_operation_id),
    CONSTRAINT fk_settlement_supplier_statement_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_statement_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_statement_deduction_operation
        FOREIGN KEY (deduction_operation_id)
            REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_statement_fingerprint
        CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_settlement_supplier_statement_number
        CHECK (BTRIM(statement_number) <> ''),
    CONSTRAINT ck_settlement_supplier_statement_amounts
        CHECK (
            gross_amount > 0
            AND deduction_amount >= 0
            AND net_amount >= 0
            AND net_amount = gross_amount - deduction_amount
        ),
    CONSTRAINT ck_settlement_supplier_statement_deduction_operation
        CHECK (
            (deduction_amount = 0 AND deduction_operation_id IS NULL)
            OR (deduction_amount > 0 AND deduction_operation_id IS NOT NULL)
        ),
    CONSTRAINT ck_settlement_supplier_statement_note
        CHECK (note IS NULL OR BTRIM(note) <> ''),
    CONSTRAINT ck_settlement_supplier_statement_actor
        CHECK (BTRIM(created_by_subject) <> '')
);

CREATE INDEX ix_settlement_supplier_statement_scope_occurred
    ON crm.settlement_supplier_statement (
        project_id,
        supplier_id,
        occurred_at DESC,
        id DESC
    );

CREATE TABLE crm.settlement_supplier_statement_entitlement
(
    statement_id       UUID           NOT NULL,
    entitlement_id     UUID           NOT NULL,
    gross_amount       NUMERIC(19, 4) NOT NULL,
    paid_before_amount NUMERIC(19, 4) NOT NULL,
    deduction_amount   NUMERIC(19, 4) NOT NULL,
    CONSTRAINT pk_settlement_supplier_statement_entitlement
        PRIMARY KEY (statement_id, entitlement_id),
    CONSTRAINT uq_settlement_supplier_statement_entitlement
        UNIQUE (entitlement_id),
    CONSTRAINT fk_settlement_supplier_statement_entitlement_statement
        FOREIGN KEY (statement_id)
            REFERENCES crm.settlement_supplier_statement (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_statement_entitlement_entitlement
        FOREIGN KEY (entitlement_id)
            REFERENCES crm.settlement_supplier_entitlement (id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_statement_entitlement_amounts
        CHECK (
            gross_amount > 0
            AND paid_before_amount >= 0
            AND deduction_amount >= 0
            AND deduction_amount <= gross_amount
        )
);

CREATE INDEX ix_settlement_supplier_statement_entitlement_statement
    ON crm.settlement_supplier_statement_entitlement (statement_id, entitlement_id);

CREATE TABLE crm.settlement_supplier_statement_deduction
(
    id                UUID           NOT NULL,
    statement_id      UUID           NOT NULL,
    customer_order_id UUID,
    description       VARCHAR(300)   NOT NULL,
    amount            NUMERIC(19, 4) NOT NULL,
    sort_order        INTEGER        NOT NULL,
    CONSTRAINT pk_settlement_supplier_statement_deduction
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_supplier_statement_deduction_order
        UNIQUE (statement_id, sort_order),
    CONSTRAINT fk_settlement_supplier_statement_deduction_statement
        FOREIGN KEY (statement_id)
            REFERENCES crm.settlement_supplier_statement (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_statement_deduction_order
        FOREIGN KEY (customer_order_id)
            REFERENCES crm.customer_order (id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_statement_deduction_description
        CHECK (BTRIM(description) <> ''),
    CONSTRAINT ck_settlement_supplier_statement_deduction_amount
        CHECK (amount > 0),
    CONSTRAINT ck_settlement_supplier_statement_deduction_sort
        CHECK (sort_order >= 0)
);

CREATE INDEX ix_settlement_supplier_statement_deduction_statement
    ON crm.settlement_supplier_statement_deduction (statement_id, sort_order, id);

COMMENT ON TABLE crm.settlement_supplier_statement IS
    'Immutable supplier-visible calculation combining confirmed entitlements and explicit deductions in one currency.';
COMMENT ON TABLE crm.settlement_supplier_statement_entitlement IS
    'Exact outstanding supplier entitlements included in one calculation, with the deduction allocation snapshot.';
COMMENT ON TABLE crm.settlement_supplier_statement_deduction IS
    'Supplier-visible deduction lines; an optional order link attributes the expense without hiding general deductions.';
