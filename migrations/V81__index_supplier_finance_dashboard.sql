CREATE INDEX ix_customer_order_mini_supplier_finance_created
    ON crm.customer_order (project_id, supplier_id, created_at DESC, id DESC)
    WHERE order_kind_code = 'MINI';

CREATE INDEX ix_customer_order_mini_supplier_finance_fulfilled
    ON crm.customer_order (project_id, supplier_id, updated_at DESC, id DESC)
    WHERE order_kind_code = 'MINI' AND status_code = 'FULFILLED';

CREATE INDEX ix_outbound_delivery_supplier_charge_delivered
    ON crm.outbound_delivery (customer_order_id, delivered_at DESC)
    WHERE status_code = 'DELIVERED' AND supplier_charge_amount IS NOT NULL;
