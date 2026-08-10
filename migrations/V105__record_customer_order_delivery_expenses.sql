ALTER TABLE crm.settlement_money_operation
    ADD COLUMN outbound_delivery_id UUID,
    ADD CONSTRAINT fk_settlement_money_operation_outbound_delivery
        FOREIGN KEY (outbound_delivery_id) REFERENCES crm.outbound_delivery (id) ON DELETE RESTRICT,
    DROP CONSTRAINT ck_settlement_money_operation_type,
    DROP CONSTRAINT ck_settlement_money_operation_shape,
    ADD CONSTRAINT ck_settlement_money_operation_type
        CHECK (operation_type IN (
            'CUSTOMER_ADVANCE',
            'CUSTOMER_ORDER_CHARGE',
            'CUSTOMER_ORDER_RECEIPT',
            'CUSTOMER_ORDER_DELIVERY_EXPENSE',
            'CUSTOMER_REFUND',
            'COUNTERPARTY_ADJUSTMENT',
            'INTERNAL_TRANSFER',
            'INTERNAL_CONVERSION',
            'SUPPLIER_ACCRUAL',
            'SUPPLIER_ENTITLEMENT_ADJUSTMENT',
            'SUPPLIER_DEDUCTION',
            'SUPPLIER_PAYOUT'
        )),
    ADD CONSTRAINT ck_settlement_money_operation_shape CHECK (
        (
            operation_type = 'CUSTOMER_ADVANCE' AND project_id IS NOT NULL
            AND counterparty_type = 'CUSTOMER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND counterparty_delta = amount AND reason IS NULL
        ) OR (
            operation_type = 'CUSTOMER_ORDER_CHARGE' AND project_id IS NOT NULL
            AND counterparty_type = 'CUSTOMER' AND customer_order_id IS NOT NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta = -amount AND reason IS NULL
        ) OR (
            operation_type = 'CUSTOMER_ORDER_RECEIPT' AND project_id IS NOT NULL
            AND customer_order_id IS NOT NULL AND fulfillment_shipment_id IS NULL
            AND outbound_delivery_id IS NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL
            AND payment_method IS NOT NULL AND counterparty_delta IS NULL AND reason IS NULL
            AND ((counterparty_type IS NULL AND customer_profile_id IS NULL)
                OR (counterparty_type = 'CUSTOMER' AND customer_profile_id IS NOT NULL))
        ) OR (
            operation_type = 'CUSTOMER_ORDER_DELIVERY_EXPENSE'
            AND project_id IS NOT NULL AND supplier_id IS NOT NULL
            AND counterparty_type IS NULL AND customer_profile_id IS NULL
            AND customer_order_id IS NOT NULL AND fulfillment_shipment_id IS NULL
            AND outbound_delivery_id IS NOT NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta IS NULL AND reason IS NULL
        ) OR (
            operation_type = 'CUSTOMER_REFUND' AND project_id IS NOT NULL
            AND counterparty_type = 'CUSTOMER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND counterparty_delta = -amount AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'COUNTERPARTY_ADJUSTMENT' AND project_id IS NOT NULL
            AND counterparty_type IS NOT NULL AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta IS NOT NULL AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type IN ('INTERNAL_TRANSFER', 'INTERNAL_CONVERSION')
            AND project_id IS NULL AND supplier_id IS NULL AND counterparty_type IS NULL
            AND customer_profile_id IS NULL AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NOT NULL
            AND financial_account_id <> destination_financial_account_id
            AND payment_method IS NULL AND counterparty_delta IS NULL
            AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_ACCRUAL' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER'
            AND NUM_NONNULLS(customer_order_id, fulfillment_shipment_id) = 1
            AND outbound_delivery_id IS NULL AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL
            AND payment_method IS NULL AND counterparty_delta = amount
            AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_ENTITLEMENT_ADJUSTMENT' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER'
            AND NUM_NONNULLS(customer_order_id, fulfillment_shipment_id) = 1
            AND outbound_delivery_id IS NULL AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL
            AND payment_method IS NULL AND counterparty_delta IS NOT NULL AND counterparty_delta <> 0
            AND amount = ABS(counterparty_delta) AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_DEDUCTION' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta = -amount AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_PAYOUT' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND (counterparty_delta IS NULL OR counterparty_delta = -amount) AND reason IS NULL
        )
    );

CREATE UNIQUE INDEX uq_settlement_money_operation_delivery_expense
    ON crm.settlement_money_operation (outbound_delivery_id)
    WHERE operation_type = 'CUSTOMER_ORDER_DELIVERY_EXPENSE';

CREATE INDEX ix_settlement_money_operation_outbound_delivery
    ON crm.settlement_money_operation (outbound_delivery_id, occurred_at DESC, id DESC)
    WHERE outbound_delivery_id IS NOT NULL;

COMMENT ON COLUMN crm.settlement_money_operation.outbound_delivery_id IS
    'Source delivery for an immutable actual delivery expense posted during controlled order payment confirmation.';
