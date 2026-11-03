ALTER TABLE crm.settlement_money_operation DROP CONSTRAINT ck_settlement_money_operation_type,
    DROP CONSTRAINT ck_settlement_money_operation_scope,
    DROP CONSTRAINT ck_settlement_money_operation_shape;
ALTER TABLE crm.settlement_money_operation ADD CONSTRAINT ck_settlement_money_operation_type
    CHECK (operation_type IN ('CUSTOMER_ADVANCE','CUSTOMER_ORDER_CHARGE','CUSTOMER_ORDER_RECEIPT',
        'CUSTOMER_ORDER_DELIVERY_EXPENSE','CUSTOMER_REFUND','COUNTERPARTY_ADJUSTMENT','INTERNAL_TRANSFER',
        'INTERNAL_CONVERSION','COMPANY_MONEY_IN','COMPANY_MONEY_OUT','SUPPLIER_ACCRUAL',
        'SUPPLIER_ENTITLEMENT_ADJUSTMENT','SUPPLIER_DEDUCTION','SUPPLIER_PAYOUT','SALES_ADVANCE','SALES_REFUND','SALES_PREPAYMENT_RETAINED')),
    ADD CONSTRAINT ck_settlement_money_operation_scope CHECK (
        (sales_request_id IS NULL AND ((project_id IS NULL AND supplier_id IS NULL) OR (project_id IS NOT NULL AND supplier_id IS NOT NULL)))
        OR (sales_request_id IS NOT NULL AND project_id IS NOT NULL AND supplier_id IS NULL)
    ),
    ADD CONSTRAINT ck_settlement_money_operation_shape CHECK (
        (sales_request_id IS NULL AND (

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
        OR (
            operation_type IN ('COMPANY_MONEY_IN', 'COMPANY_MONEY_OUT')
            AND project_id IS NULL AND supplier_id IS NULL
            AND counterparty_type IS NULL AND customer_profile_id IS NULL
            AND customer_order_id IS NULL AND fulfillment_shipment_id IS NULL
            AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL
            AND payment_method IS NULL AND counterparty_delta IS NULL
            AND reason IS NOT NULL AND BTRIM(reason) <> ''
        )
            )) OR (
            operation_type IN ('SALES_ADVANCE','SALES_REFUND') AND sales_request_id IS NOT NULL
            AND project_id IS NOT NULL AND supplier_id IS NULL AND customer_profile_id IS NULL
            AND counterparty_type IS NULL AND customer_order_id IS NULL AND fulfillment_shipment_id IS NULL
            AND outbound_delivery_id IS NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND counterparty_delta IS NULL
            AND (operation_type <> 'SALES_REFUND' OR (reason IS NOT NULL AND length(btrim(reason)) > 0))
        )
        OR (
            operation_type = 'SALES_PREPAYMENT_RETAINED'
            AND sales_request_id IS NOT NULL AND project_id IS NOT NULL
            AND supplier_id IS NULL AND customer_profile_id IS NULL AND counterparty_type IS NULL
            AND customer_order_id IS NULL AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NULL AND destination_financial_account_id IS NULL
            AND payment_method IS NULL AND counterparty_delta IS NULL
            AND reason IS NOT NULL AND length(btrim(reason)) > 0
        )
    );

CREATE UNIQUE INDEX uq_sales_prepayment_retention_currency
    ON crm.settlement_money_operation(sales_request_id,currency_code)
    WHERE operation_type='SALES_PREPAYMENT_RETAINED';

CREATE FUNCTION crm.enforce_sales_prepayment_retention() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    request_state TEXT;
    confirmed_at TIMESTAMPTZ;
    available_amount NUMERIC;
    funded_amount NUMERIC;
BEGIN
    SELECT status_code,payment_confirmed_at INTO request_state,confirmed_at
        FROM crm.sales_request
        WHERE id=NEW.sales_request_id AND project_id=NEW.project_id
        FOR UPDATE;
    IF request_state IS DISTINCT FROM 'CANCELLED' OR confirmed_at IS NULL THEN
        RAISE EXCEPTION 'Prepayment retention requires a cancelled paid sales request'
            USING ERRCODE='23514',CONSTRAINT='ck_sales_prepayment_retention';
    END IF;
    SELECT COALESCE(SUM(CASE operation_type
        WHEN 'SALES_ADVANCE' THEN amount
        WHEN 'SALES_REFUND' THEN -amount
        WHEN 'SALES_PREPAYMENT_RETAINED' THEN -amount
        ELSE 0 END),0) INTO available_amount
        FROM crm.settlement_money_operation
        WHERE sales_request_id=NEW.sales_request_id AND currency_code=NEW.currency_code;
    SELECT COALESCE(SUM(amount),0) INTO funded_amount
        FROM crm.settlement_sales_order_funding
        WHERE sales_request_id=NEW.sales_request_id AND currency_code=NEW.currency_code
            AND released_at IS NULL;
    IF NEW.amount > available_amount-funded_amount THEN
        RAISE EXCEPTION 'Prepayment retention exceeds unallocated customer funds'
            USING ERRCODE='23514',CONSTRAINT='ck_sales_prepayment_retention';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER sales_prepayment_retention
    BEFORE INSERT ON crm.settlement_money_operation
    FOR EACH ROW WHEN (NEW.operation_type='SALES_PREPAYMENT_RETAINED')
    EXECUTE FUNCTION crm.enforce_sales_prepayment_retention();
