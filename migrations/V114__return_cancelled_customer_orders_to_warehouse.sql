ALTER TABLE crm.warehouse_relocation
    ADD COLUMN kind_code VARCHAR(32) NOT NULL DEFAULT 'STANDARD',
    ADD COLUMN customer_order_id UUID,
    ADD CONSTRAINT fk_warehouse_relocation_customer_order
        FOREIGN KEY (customer_order_id, project_id)
            REFERENCES crm.customer_order (id, project_id) ON DELETE RESTRICT,
    DROP CONSTRAINT ck_warehouse_relocation_distinct_warehouses,
    ADD CONSTRAINT ck_warehouse_relocation_kind CHECK (
        (
            kind_code = 'STANDARD'
            AND customer_order_id IS NULL
            AND source_warehouse_id <> destination_warehouse_id
        )
        OR (
            kind_code = 'CUSTOMER_ORDER_RETURN'
            AND customer_order_id IS NOT NULL
            AND status_code IN ('IN_TRANSIT', 'PARTIALLY_RECEIVED', 'COMPLETED')
            AND service_fee_amount IS NULL
            AND service_fee_currency IS NULL
            AND service_fee_charged_party IS NULL
            AND service_fee_charged_account_id IS NULL
            AND service_fee_charged_supplier_id IS NULL
        )
    );

CREATE UNIQUE INDEX uq_warehouse_relocation_customer_order_return_source
    ON crm.warehouse_relocation (customer_order_id, source_warehouse_id)
    WHERE kind_code = 'CUSTOMER_ORDER_RETURN';

ALTER TABLE crm.outbound_delivery
    DROP CONSTRAINT ck_outbound_delivery_lifecycle,
    ADD CONSTRAINT ck_outbound_delivery_lifecycle CHECK (
        (
            status_code = 'DRAFT'
            AND ready_by_account_id IS NULL AND ready_by_subject IS NULL AND ready_at IS NULL
            AND dispatched_by_account_id IS NULL AND dispatched_by_subject IS NULL AND dispatched_at IS NULL
            AND delivered_by_account_id IS NULL AND delivered_by_subject IS NULL AND delivered_at IS NULL
            AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
            AND cancellation_reason IS NULL
        )
        OR (
            status_code IN ('READY_FOR_HANDOVER', 'READY_FOR_DISPATCH')
            AND ready_by_account_id IS NOT NULL AND ready_by_subject IS NOT NULL
            AND BTRIM(ready_by_subject) <> '' AND ready_at IS NOT NULL
            AND dispatched_by_account_id IS NULL AND dispatched_by_subject IS NULL AND dispatched_at IS NULL
            AND delivered_by_account_id IS NULL AND delivered_by_subject IS NULL AND delivered_at IS NULL
            AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
            AND cancellation_reason IS NULL
        )
        OR (
            status_code = 'IN_TRANSIT'
            AND ready_by_account_id IS NOT NULL AND ready_by_subject IS NOT NULL AND ready_at IS NOT NULL
            AND dispatched_by_account_id IS NOT NULL AND dispatched_by_subject IS NOT NULL
            AND BTRIM(dispatched_by_subject) <> '' AND dispatched_at IS NOT NULL
            AND delivered_by_account_id IS NULL AND delivered_by_subject IS NULL AND delivered_at IS NULL
            AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
            AND cancellation_reason IS NULL
        )
        OR (
            status_code = 'DELIVERED'
            AND ready_by_account_id IS NOT NULL AND ready_by_subject IS NOT NULL AND ready_at IS NOT NULL
            AND (
                (
                    method_code = 'WAREHOUSE_PICKUP'
                    AND dispatched_by_account_id IS NULL
                    AND dispatched_by_subject IS NULL
                    AND dispatched_at IS NULL
                )
                OR (
                    method_code <> 'WAREHOUSE_PICKUP'
                    AND dispatched_by_account_id IS NOT NULL
                    AND dispatched_by_subject IS NOT NULL
                    AND BTRIM(dispatched_by_subject) <> ''
                    AND dispatched_at IS NOT NULL
                )
            )
            AND delivered_by_account_id IS NOT NULL AND delivered_by_subject IS NOT NULL
            AND BTRIM(delivered_by_subject) <> '' AND delivered_at IS NOT NULL
            AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
            AND cancellation_reason IS NULL
        )
        OR (
            status_code = 'CANCELLED'
            AND delivered_by_account_id IS NULL AND delivered_by_subject IS NULL AND delivered_at IS NULL
            AND cancelled_by_account_id IS NOT NULL AND cancelled_by_subject IS NOT NULL
            AND BTRIM(cancelled_by_subject) <> '' AND cancelled_at IS NOT NULL
            AND cancellation_reason IS NOT NULL AND BTRIM(cancellation_reason) <> ''
            AND (
                (
                    ready_by_account_id IS NULL AND ready_by_subject IS NULL AND ready_at IS NULL
                    AND dispatched_by_account_id IS NULL
                    AND dispatched_by_subject IS NULL
                    AND dispatched_at IS NULL
                )
                OR (
                    ready_by_account_id IS NOT NULL
                    AND ready_by_subject IS NOT NULL
                    AND BTRIM(ready_by_subject) <> ''
                    AND ready_at IS NOT NULL
                    AND (
                        (
                            dispatched_by_account_id IS NULL
                            AND dispatched_by_subject IS NULL
                            AND dispatched_at IS NULL
                        )
                        OR (
                            dispatched_by_account_id IS NOT NULL
                            AND dispatched_by_subject IS NOT NULL
                            AND BTRIM(dispatched_by_subject) <> ''
                            AND dispatched_at IS NOT NULL
                        )
                    )
                )
            )
        )
    );

COMMENT ON COLUMN crm.warehouse_relocation.kind_code IS
    'STANDARD for an ordinary warehouse movement; CUSTOMER_ORDER_RETURN for exact units from an undelivered cancelled order.';

COMMENT ON COLUMN crm.warehouse_relocation.customer_order_id IS
    'Source customer order when this relocation is a scan-controlled warehouse return.';
