ALTER TABLE crm.settlement_money_operation
    DROP CONSTRAINT ck_settlement_money_operation_type,
    DROP CONSTRAINT ck_settlement_money_operation_counterparty,
    DROP CONSTRAINT ck_settlement_money_operation_delta,
    DROP CONSTRAINT ck_settlement_money_operation_customer_advance,
    DROP CONSTRAINT ck_settlement_money_operation_adjustment;

ALTER TABLE crm.settlement_money_operation
    ALTER COLUMN project_id DROP NOT NULL,
    ALTER COLUMN supplier_id DROP NOT NULL,
    ALTER COLUMN counterparty_type DROP NOT NULL,
    ALTER COLUMN counterparty_delta DROP NOT NULL,
    ADD COLUMN customer_order_id UUID,
    ADD COLUMN destination_financial_account_id UUID,
    ADD CONSTRAINT fk_settlement_money_operation_customer_order
        FOREIGN KEY (customer_order_id) REFERENCES crm.customer_order (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_settlement_money_operation_destination_account
        FOREIGN KEY (destination_financial_account_id)
            REFERENCES crm.settlement_financial_account (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_settlement_money_operation_type
        CHECK (operation_type IN (
            'CUSTOMER_ADVANCE',
            'CUSTOMER_ORDER_CHARGE',
            'CUSTOMER_REFUND',
            'COUNTERPARTY_ADJUSTMENT',
            'INTERNAL_TRANSFER',
            'INTERNAL_CONVERSION',
            'SUPPLIER_ACCRUAL',
            'SUPPLIER_PAYOUT'
        )),
    ADD CONSTRAINT ck_settlement_money_operation_scope
        CHECK (
            (project_id IS NULL AND supplier_id IS NULL)
            OR
            (project_id IS NOT NULL AND supplier_id IS NOT NULL)
        ),
    ADD CONSTRAINT ck_settlement_money_operation_counterparty
        CHECK (
            (counterparty_type IS NULL AND customer_profile_id IS NULL)
            OR
            (counterparty_type = 'CUSTOMER' AND customer_profile_id IS NOT NULL)
            OR
            (counterparty_type = 'SUPPLIER' AND customer_profile_id IS NULL)
        ),
    ADD CONSTRAINT ck_settlement_money_operation_delta
        CHECK (
            counterparty_delta IS NULL
            OR
            (counterparty_delta <> 0 AND ABS(counterparty_delta) = amount)
        ),
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

CREATE INDEX ix_settlement_money_operation_order
    ON crm.settlement_money_operation (customer_order_id, currency_code, occurred_at, id)
    WHERE customer_order_id IS NOT NULL;

CREATE INDEX ix_settlement_money_operation_type_occurred
    ON crm.settlement_money_operation (operation_type, occurred_at DESC, id DESC);

CREATE TABLE crm.settlement_customer_order_allocation
(
    operation_id       UUID           NOT NULL,
    customer_order_id  UUID           NOT NULL,
    project_id         UUID           NOT NULL,
    supplier_id        UUID           NOT NULL,
    customer_profile_id UUID          NOT NULL,
    amount             NUMERIC(19, 4) NOT NULL,
    currency_code      VARCHAR(3)     NOT NULL,
    occurred_at        TIMESTAMPTZ    NOT NULL,
    CONSTRAINT pk_settlement_customer_order_allocation
        PRIMARY KEY (operation_id),
    CONSTRAINT fk_settlement_customer_order_allocation_operation
        FOREIGN KEY (operation_id) REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_customer_order_allocation_order
        FOREIGN KEY (customer_order_id) REFERENCES crm.customer_order (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_customer_order_allocation_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_customer_order_allocation_customer
        FOREIGN KEY (customer_profile_id, project_id, supplier_id)
            REFERENCES crm.customer_profile (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_customer_order_allocation_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_customer_order_allocation_amount
        CHECK (amount > 0)
);

CREATE INDEX ix_settlement_customer_order_allocation_balance
    ON crm.settlement_customer_order_allocation (
        customer_order_id,
        currency_code,
        occurred_at,
        operation_id
    );

CREATE TABLE crm.settlement_supplier_entitlement
(
    id                       UUID           NOT NULL,
    accrual_operation_id     UUID           NOT NULL,
    project_id               UUID           NOT NULL,
    supplier_id              UUID           NOT NULL,
    customer_order_id        UUID           NOT NULL,
    customer_order_line_id   UUID           NOT NULL,
    cargo_item_id            UUID           NOT NULL,
    item_name_snapshot       VARCHAR(300)   NOT NULL,
    item_label_snapshot      VARCHAR(100),
    amount                   NUMERIC(19, 4) NOT NULL,
    currency_code            VARCHAR(3)     NOT NULL,
    occurred_at              TIMESTAMPTZ    NOT NULL,
    created_at               TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement_supplier_entitlement
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_supplier_entitlement_currency
        UNIQUE (id, currency_code),
    CONSTRAINT uq_settlement_supplier_entitlement_line
        UNIQUE (customer_order_line_id),
    CONSTRAINT uq_settlement_supplier_entitlement_item
        UNIQUE (cargo_item_id),
    CONSTRAINT fk_settlement_supplier_entitlement_operation
        FOREIGN KEY (accrual_operation_id)
            REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_entitlement_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_entitlement_order
        FOREIGN KEY (customer_order_id) REFERENCES crm.customer_order (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_entitlement_line
        FOREIGN KEY (customer_order_line_id) REFERENCES crm.customer_order_line (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_entitlement_item
        FOREIGN KEY (cargo_item_id) REFERENCES crm.cargo_item (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_entitlement_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_entitlement_name
        CHECK (BTRIM(item_name_snapshot) <> ''),
    CONSTRAINT ck_settlement_supplier_entitlement_label
        CHECK (item_label_snapshot IS NULL OR BTRIM(item_label_snapshot) <> ''),
    CONSTRAINT ck_settlement_supplier_entitlement_amount
        CHECK (amount > 0)
);

CREATE INDEX ix_settlement_supplier_entitlement_scope
    ON crm.settlement_supplier_entitlement (
        project_id,
        supplier_id,
        currency_code,
        occurred_at,
        id
    );

CREATE TABLE crm.settlement_supplier_payout_allocation
(
    payout_operation_id UUID           NOT NULL,
    entitlement_id      UUID           NOT NULL,
    amount              NUMERIC(19, 4) NOT NULL,
    currency_code       VARCHAR(3)     NOT NULL,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement_supplier_payout_allocation
        PRIMARY KEY (payout_operation_id, entitlement_id),
    CONSTRAINT fk_settlement_supplier_payout_allocation_operation
        FOREIGN KEY (payout_operation_id)
            REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_payout_allocation_entitlement
        FOREIGN KEY (entitlement_id, currency_code)
            REFERENCES crm.settlement_supplier_entitlement (id, currency_code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_payout_allocation_amount
        CHECK (amount > 0)
);

CREATE INDEX ix_settlement_supplier_payout_allocation_entitlement
    ON crm.settlement_supplier_payout_allocation (entitlement_id, created_at, payout_operation_id);

CREATE TABLE crm.settlement_supplier_payout_acknowledgement
(
    payout_operation_id UUID         NOT NULL,
    decision_code       VARCHAR(16)  NOT NULL,
    supplier_account_id UUID         NOT NULL,
    note                VARCHAR(500),
    occurred_at         TIMESTAMPTZ  NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement_supplier_payout_acknowledgement
        PRIMARY KEY (payout_operation_id),
    CONSTRAINT fk_settlement_supplier_payout_acknowledgement_operation
        FOREIGN KEY (payout_operation_id)
            REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_payout_acknowledgement_account
        FOREIGN KEY (supplier_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_payout_acknowledgement_decision
        CHECK (decision_code IN ('RECEIVED', 'DISPUTED')),
    CONSTRAINT ck_settlement_supplier_payout_acknowledgement_note
        CHECK (note IS NULL OR BTRIM(note) <> '')
);

CREATE TABLE crm.settlement_money_conversion
(
    operation_id                 UUID           NOT NULL,
    source_financial_account_id  UUID           NOT NULL,
    target_financial_account_id  UUID           NOT NULL,
    source_amount                NUMERIC(19, 4) NOT NULL,
    source_currency_code         VARCHAR(3)     NOT NULL,
    target_amount                NUMERIC(19, 4) NOT NULL,
    target_currency_code         VARCHAR(3)     NOT NULL,
    CONSTRAINT pk_settlement_money_conversion
        PRIMARY KEY (operation_id),
    CONSTRAINT fk_settlement_money_conversion_operation
        FOREIGN KEY (operation_id) REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_money_conversion_source
        FOREIGN KEY (source_financial_account_id, source_currency_code)
            REFERENCES crm.settlement_financial_account (id, currency_code) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_money_conversion_target
        FOREIGN KEY (target_financial_account_id, target_currency_code)
            REFERENCES crm.settlement_financial_account (id, currency_code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_money_conversion_accounts
        CHECK (source_financial_account_id <> target_financial_account_id),
    CONSTRAINT ck_settlement_money_conversion_currencies
        CHECK (source_currency_code <> target_currency_code),
    CONSTRAINT ck_settlement_money_conversion_amounts
        CHECK (source_amount > 0 AND target_amount > 0)
);

COMMENT ON TABLE crm.settlement_customer_order_allocation IS
    'Immutable allocation of signed customer balance to one frozen order obligation.';

COMMENT ON TABLE crm.settlement_supplier_entitlement IS
    'Manually confirmed supplier entitlement snapshots for exact fulfilled order items.';

COMMENT ON TABLE crm.settlement_supplier_payout_allocation IS
    'Immutable partial or complete payout allocation against confirmed supplier entitlements.';

COMMENT ON TABLE crm.settlement_supplier_payout_acknowledgement IS
    'Supplier evidence that a recorded payout was received or disputed; it never silently reverses money.';

COMMENT ON TABLE crm.settlement_money_conversion IS
    'Actual source and target amounts for a cross-currency internal movement; the effective rate is derived.';
