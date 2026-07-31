ALTER TABLE crm.customer_order
    DROP CONSTRAINT ck_customer_order_status,
    DROP CONSTRAINT ck_customer_order_lifecycle,
    ADD COLUMN payment_confirmation_request_id UUID,
    ADD COLUMN payment_evidence_message_id UUID,
    ADD COLUMN payment_confirmed_by_account_id UUID,
    ADD COLUMN payment_confirmed_by_subject VARCHAR(255),
    ADD COLUMN payment_confirmed_at TIMESTAMPTZ,
    ADD CONSTRAINT fk_customer_order_payment_evidence
        FOREIGN KEY (payment_evidence_message_id) REFERENCES crm.chat_message (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_customer_order_payment_confirmer
        FOREIGN KEY (payment_confirmed_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_customer_order_status
        CHECK (status_code IN (
            'DRAFT',
            'CONFIRMED',
            'PICKING',
            'PACKED',
            'PAYMENT_PENDING',
            'FULFILLED',
            'CANCELLED'
        )),
    ADD CONSTRAINT ck_customer_order_lifecycle
        CHECK (
            (
                status_code = 'DRAFT'
                AND confirmed_by_subject IS NULL
                AND confirmed_at IS NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code IN ('CONFIRMED', 'PICKING', 'PACKED', 'PAYMENT_PENDING', 'FULFILLED')
                AND confirmed_by_subject IS NOT NULL
                AND BTRIM(confirmed_by_subject) <> ''
                AND confirmed_at IS NOT NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'CANCELLED'
                AND confirmed_by_subject IS NULL
                AND confirmed_at IS NULL
                AND cancelled_by_subject IS NOT NULL
                AND BTRIM(cancelled_by_subject) <> ''
                AND cancelled_at IS NOT NULL
                AND cancellation_reason IS NOT NULL
                AND BTRIM(cancellation_reason) <> ''
            )
        ),
    ADD CONSTRAINT ck_customer_order_payment_confirmation_shape
        CHECK (
            (
                payment_confirmation_request_id IS NULL
                AND payment_evidence_message_id IS NULL
                AND payment_confirmed_by_account_id IS NULL
                AND payment_confirmed_by_subject IS NULL
                AND payment_confirmed_at IS NULL
            )
            OR (
                status_code = 'FULFILLED'
                AND payment_confirmation_request_id IS NOT NULL
                AND payment_evidence_message_id IS NOT NULL
                AND payment_confirmed_by_account_id IS NOT NULL
                AND payment_confirmed_by_subject IS NOT NULL
                AND BTRIM(payment_confirmed_by_subject) <> ''
                AND payment_confirmed_at IS NOT NULL
            )
        );

CREATE UNIQUE INDEX uq_customer_order_payment_confirmation_request
    ON crm.customer_order (payment_confirmation_request_id)
    WHERE payment_confirmation_request_id IS NOT NULL;

CREATE INDEX ix_customer_order_payment_pending
    ON crm.customer_order (project_id, updated_at DESC, id)
    WHERE status_code = 'PAYMENT_PENDING';

ALTER TABLE crm.task
    DROP CONSTRAINT ck_task_managed_state,
    DROP CONSTRAINT ck_task_managed_state_shape,
    ADD CONSTRAINT ck_task_managed_state
        CHECK (managed_state_code IS NULL OR managed_state_code IN (
            'PRICE_MODERATION',
            'PAYMENT_CONFIRMATION'
        )),
    ADD CONSTRAINT ck_task_managed_state_shape
        CHECK (
            managed_state_code IS NULL
            OR (
                managed_state_code = 'PRICE_MODERATION'
                AND inbound_delivery_id IS NOT NULL
                AND status_code = 'BLOCKED'
                AND priority_code = 'URGENT'
            )
            OR (
                managed_state_code = 'PAYMENT_CONFIRMATION'
                AND customer_order_id IS NOT NULL
                AND status_code = 'BLOCKED'
                AND priority_code = 'URGENT'
            )
        );

ALTER TABLE crm.settlement_customer_order_allocation
    ALTER COLUMN customer_profile_id DROP NOT NULL;

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
            OR (
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
            OR (
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
            OR (
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
            OR (
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
            OR (
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
            OR (
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
            OR (
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

COMMENT ON COLUMN crm.customer_order.payment_evidence_message_id IS
    'Immutable task-chat message containing the payment comment and ready photo evidence.';
COMMENT ON COLUMN crm.customer_order.payment_confirmation_request_id IS
    'Idempotency key of the atomic payment-confirmation command.';
COMMENT ON COLUMN crm.task.managed_state_code IS
    'Business-owned blocking state. PAYMENT_CONFIRMATION can be resolved only by the order payment command.';
COMMENT ON COLUMN crm.settlement_customer_order_allocation.customer_profile_id IS
    'Customer profile when the order has one; NULL for customerless MINI orders.';
