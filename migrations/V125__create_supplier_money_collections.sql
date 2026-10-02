CREATE TABLE crm.settlement_supplier_money_collection
(
    id UUID NOT NULL,
    project_id UUID NOT NULL,
    supplier_id UUID NOT NULL,
    currency_code VARCHAR(3) NOT NULL,
    expected_amount NUMERIC(19, 4) NOT NULL,
    confirmed_amount NUMERIC(19, 4),
    approved_amount NUMERIC(19, 4),
    status_code VARCHAR(24) NOT NULL,
    evidence_message_id UUID,
    receipt_account_id UUID,
    receipt_operation_id UUID,
    correction_operation_id UUID,
    accrual_operation_id UUID,
    correction_reason VARCHAR(500),
    created_by_subject VARCHAR(255) NOT NULL,
    confirmed_by_subject VARCHAR(255),
    approved_by_subject VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL,
    confirmed_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT pk_settlement_supplier_money_collection PRIMARY KEY (id),
    CONSTRAINT uq_settlement_supplier_money_collection_scope UNIQUE (id, project_id),
    CONSTRAINT fk_settlement_supplier_money_collection_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_money_collection_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_money_collection_account
        FOREIGN KEY (receipt_account_id) REFERENCES crm.settlement_financial_account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_money_collection_receipt
        FOREIGN KEY (receipt_operation_id) REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_money_collection_correction
        FOREIGN KEY (correction_operation_id) REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_supplier_money_collection_accrual
        FOREIGN KEY (accrual_operation_id) REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_supplier_money_collection_amounts CHECK (
        expected_amount > 0
        AND (confirmed_amount IS NULL OR confirmed_amount > 0)
        AND (approved_amount IS NULL OR approved_amount > 0)
    ),
    CONSTRAINT ck_settlement_supplier_money_collection_status CHECK (
        (status_code = 'OPEN' AND confirmed_amount IS NULL AND approved_amount IS NULL
            AND evidence_message_id IS NULL AND receipt_account_id IS NULL
            AND receipt_operation_id IS NULL AND correction_operation_id IS NULL
            AND accrual_operation_id IS NULL AND correction_reason IS NULL
            AND confirmed_by_subject IS NULL AND approved_by_subject IS NULL
            AND confirmed_at IS NULL AND approved_at IS NULL)
        OR (status_code = 'PENDING_APPROVAL' AND confirmed_amount IS NOT NULL
            AND approved_amount IS NULL AND evidence_message_id IS NOT NULL
            AND receipt_account_id IS NOT NULL AND receipt_operation_id IS NOT NULL
            AND correction_operation_id IS NULL AND accrual_operation_id IS NULL
            AND correction_reason IS NULL AND confirmed_by_subject IS NOT NULL
            AND approved_by_subject IS NULL AND confirmed_at IS NOT NULL AND approved_at IS NULL)
        OR (status_code = 'APPROVED' AND confirmed_amount IS NOT NULL
            AND approved_amount IS NOT NULL AND evidence_message_id IS NOT NULL
            AND receipt_account_id IS NOT NULL AND receipt_operation_id IS NOT NULL
            AND accrual_operation_id IS NOT NULL AND confirmed_by_subject IS NOT NULL
            AND approved_by_subject IS NOT NULL AND confirmed_at IS NOT NULL AND approved_at IS NOT NULL
            AND ((approved_amount = confirmed_amount AND correction_operation_id IS NULL AND correction_reason IS NULL)
                OR (approved_amount <> confirmed_amount AND correction_operation_id IS NOT NULL
                    AND correction_reason IS NOT NULL AND BTRIM(correction_reason) <> '')))
    )
);

CREATE INDEX ix_settlement_supplier_money_collection_scope
    ON crm.settlement_supplier_money_collection (project_id, supplier_id, status_code, created_at DESC, id);

ALTER TABLE crm.task
    DROP CONSTRAINT ck_task_standalone_managed_shape,
    DROP CONSTRAINT ck_task_deadline_required_shape,
    ADD COLUMN supplier_money_collection_id UUID,
    ADD CONSTRAINT uq_task_supplier_money_collection UNIQUE (supplier_money_collection_id),
    ADD CONSTRAINT fk_task_supplier_money_collection
        FOREIGN KEY (supplier_money_collection_id, project_id)
            REFERENCES crm.settlement_supplier_money_collection (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_task_standalone_managed_shape CHECK (
        NUM_NONNULLS(customer_order_id, warehouse_relocation_id, fulfillment_shipment_id,
            fulfillment_return_id, mini_supplier_intake_id, supplier_money_collection_id) = 0
        OR (NUM_NONNULLS(customer_order_id, warehouse_relocation_id, fulfillment_shipment_id,
            fulfillment_return_id, mini_supplier_intake_id, supplier_money_collection_id) = 1
            AND inbound_delivery_id IS NULL AND courier_trip_id IS NULL AND parent_task_id IS NULL)
    ),
    ADD CONSTRAINT ck_task_deadline_required_shape CHECK (
        deadline_at IS NOT NULL OR customer_order_id IS NOT NULL OR warehouse_relocation_id IS NOT NULL
        OR fulfillment_shipment_id IS NOT NULL OR fulfillment_return_id IS NOT NULL
        OR mini_supplier_intake_id IS NOT NULL OR supplier_money_collection_id IS NOT NULL
    );

CREATE INDEX ix_task_supplier_money_collection
    ON crm.task (supplier_money_collection_id) WHERE supplier_money_collection_id IS NOT NULL;

ALTER TABLE crm.task_subcategory
    DROP CONSTRAINT ck_task_subcategory_system_source,
    ADD CONSTRAINT ck_task_subcategory_system_source CHECK (
        system_source_code IS NULL OR system_source_code IN (
            'INBOUND_DELIVERY', 'COURIER_TRIP', 'CUSTOMER_ORDER',
            'CUSTOMER_ORDER_SHIPMENT', 'CUSTOMER_ORDER_HANDOVER', 'CUSTOMER_ORDER_DELIVERY',
            'WAREHOUSE_RELOCATION', 'FULFILLMENT_SHIPMENT', 'FULFILLMENT_RETURN',
            'SUPPLIER_MONEY_COLLECTION'
        )
    );

INSERT INTO crm.task_subcategory (
    id, category_id, country_code, system_source_code, name, active, sort_order,
    created_by_subject, updated_by_subject, created_at, updated_at, version
) VALUES (
    '00000000-0000-0000-0000-000000005410',
    '00000000-0000-0000-0000-000000005400',
    NULL, 'SUPPLIER_MONEY_COLLECTION', 'Получение денег для поставщика', TRUE, 9,
    'system:migration-v125', 'system:migration-v125', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0
);

ALTER TABLE crm.settlement_supplier_entitlement
    DROP CONSTRAINT ck_settlement_supplier_entitlement_source,
    ADD COLUMN supplier_money_collection_id UUID,
    ADD CONSTRAINT fk_settlement_supplier_entitlement_collection
        FOREIGN KEY (supplier_money_collection_id)
            REFERENCES crm.settlement_supplier_money_collection (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_settlement_supplier_entitlement_source CHECK (
        (customer_order_id IS NOT NULL AND customer_order_line_id IS NOT NULL AND cargo_item_id IS NOT NULL
            AND fulfillment_shipment_id IS NULL AND supplier_money_collection_id IS NULL)
        OR (customer_order_id IS NULL AND customer_order_line_id IS NULL AND cargo_item_id IS NULL
            AND fulfillment_shipment_id IS NOT NULL AND supplier_money_collection_id IS NULL)
        OR (customer_order_id IS NULL AND customer_order_line_id IS NULL AND cargo_item_id IS NULL
            AND fulfillment_shipment_id IS NULL AND supplier_money_collection_id IS NOT NULL)
    );

CREATE UNIQUE INDEX uq_settlement_supplier_entitlement_collection
    ON crm.settlement_supplier_entitlement (supplier_money_collection_id)
    WHERE supplier_money_collection_id IS NOT NULL;
