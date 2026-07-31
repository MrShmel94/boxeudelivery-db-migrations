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
            'SUPPLIER_ENTITLEMENT_ADJUSTMENT',
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
                operation_type = 'SUPPLIER_ENTITLEMENT_ADJUSTMENT'
                AND project_id IS NOT NULL
                AND counterparty_type = 'SUPPLIER'
                AND customer_order_id IS NOT NULL
                AND financial_account_id IS NULL
                AND destination_financial_account_id IS NULL
                AND payment_method IS NULL
                AND counterparty_delta IS NOT NULL
                AND counterparty_delta <> 0
                AND amount = ABS(counterparty_delta)
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

ALTER TABLE crm.settlement_supplier_entitlement
    ADD COLUMN original_amount NUMERIC(19, 4),
    ADD COLUMN version BIGINT NOT NULL DEFAULT 0;

UPDATE crm.settlement_supplier_entitlement
SET original_amount = amount;

ALTER TABLE crm.settlement_supplier_entitlement
    ALTER COLUMN original_amount SET NOT NULL,
    ADD CONSTRAINT ck_settlement_supplier_entitlement_original_amount
        CHECK (original_amount > 0);

CREATE TABLE crm.settlement_supplier_entitlement_adjustment
(
    id                        UUID           NOT NULL,
    adjustment_operation_id   UUID           NOT NULL,
    entitlement_id            UUID           NOT NULL,
    previous_amount           NUMERIC(19, 4) NOT NULL,
    amount_delta              NUMERIC(19, 4) NOT NULL,
    resulting_amount          NUMERIC(19, 4) NOT NULL,
    reason                    VARCHAR(500)   NOT NULL,
    actor_subject             VARCHAR(255)   NOT NULL,
    occurred_at               TIMESTAMPTZ    NOT NULL,
    created_at                TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement_supplier_entitlement_adjustment
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_supplier_entitlement_adjustment_operation
        UNIQUE (adjustment_operation_id),
    CONSTRAINT fk_settlement_supplier_entitlement_adjustment_operation
        FOREIGN KEY (adjustment_operation_id)
            REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_entitlement_adjustment_entitlement
        FOREIGN KEY (entitlement_id)
            REFERENCES crm.settlement_supplier_entitlement (id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_entitlement_adjustment_amounts
        CHECK (
            previous_amount > 0
            AND amount_delta <> 0
            AND resulting_amount > 0
            AND resulting_amount = previous_amount + amount_delta
        ),
    CONSTRAINT ck_settlement_supplier_entitlement_adjustment_reason
        CHECK (BTRIM(reason) <> ''),
    CONSTRAINT ck_settlement_supplier_entitlement_adjustment_actor
        CHECK (BTRIM(actor_subject) <> '')
);

CREATE INDEX ix_settlement_supplier_entitlement_adjustment_history
    ON crm.settlement_supplier_entitlement_adjustment (
        entitlement_id,
        occurred_at DESC,
        created_at DESC,
        id DESC
    );

COMMENT ON COLUMN crm.settlement_supplier_entitlement.original_amount IS
    'Immutable first confirmed supplier amount; amount is the current projection after attributable adjustments.';

COMMENT ON TABLE crm.settlement_supplier_entitlement_adjustment IS
    'Append-only history of supplier entitlement amount corrections made before settlement calculation.';
