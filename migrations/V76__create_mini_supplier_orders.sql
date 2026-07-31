-- MINI suppliers use the existing customer-order aggregate without inventing a
-- synthetic customer or fake cargo financial entry. The order keeps the same
-- number, item reservation, lifecycle, task and audit history as a full order.

ALTER TABLE crm.customer_order
    ADD COLUMN order_kind_code VARCHAR(16) NOT NULL DEFAULT 'STANDARD',
    ADD COLUMN task_type_code VARCHAR(16) NOT NULL DEFAULT 'STANDARD',
    ADD COLUMN operator_comment VARCHAR(2000),
    ALTER COLUMN customer_profile_id DROP NOT NULL,
    ALTER COLUMN customer_display_name DROP NOT NULL,
    ADD CONSTRAINT ck_customer_order_kind
        CHECK (order_kind_code IN ('STANDARD', 'MINI')),
    ADD CONSTRAINT ck_customer_order_task_type
        CHECK (task_type_code IN ('STANDARD', 'SHIPMENT', 'HANDOVER', 'DELIVERY')),
    ADD CONSTRAINT ck_customer_order_shape
        CHECK (
            (
                order_kind_code = 'STANDARD'
                AND task_type_code = 'STANDARD'
                AND customer_profile_id IS NOT NULL
                AND customer_display_name IS NOT NULL
                AND BTRIM(customer_display_name) <> ''
            )
            OR (
                order_kind_code = 'MINI'
                AND task_type_code IN ('SHIPMENT', 'HANDOVER', 'DELIVERY')
                AND customer_profile_id IS NULL
                AND customer_account_id IS NULL
                AND customer_display_name IS NULL
                AND customer_phone IS NULL
                AND customer_email IS NULL
                AND operator_comment IS NOT NULL
                AND BTRIM(operator_comment) <> ''
            )
        );

ALTER TABLE crm.customer_order
    ALTER COLUMN order_kind_code DROP DEFAULT,
    ALTER COLUMN task_type_code DROP DEFAULT;

CREATE INDEX ix_customer_order_kind_supplier_created
    ON crm.customer_order (order_kind_code, supplier_id, created_at DESC, id);

ALTER TABLE crm.customer_order_line
    DROP CONSTRAINT fk_customer_order_line_price_source,
    DROP CONSTRAINT ck_customer_order_line_price_source_type,
    DROP CONSTRAINT ck_customer_order_line_source_revision,
    ADD COLUMN price_source_code VARCHAR(32) NOT NULL DEFAULT 'ITEM_FINANCIAL_ENTRY',
    ALTER COLUMN source_financial_entry_id DROP NOT NULL,
    ALTER COLUMN source_financial_revision DROP NOT NULL,
    ALTER COLUMN source_financial_entry_type DROP NOT NULL,
    ADD CONSTRAINT ck_customer_order_line_price_source
        CHECK (price_source_code IN ('ITEM_FINANCIAL_ENTRY', 'ORDER_ENTRY')),
    ADD CONSTRAINT ck_customer_order_line_price_source_shape
        CHECK (
            (
                price_source_code = 'ITEM_FINANCIAL_ENTRY'
                AND source_financial_entry_id IS NOT NULL
                AND source_financial_revision IS NOT NULL
                AND source_financial_revision >= 1
                AND source_financial_entry_type = 'CUSTOMER_ITEM_PRICE'
            )
            OR (
                price_source_code = 'ORDER_ENTRY'
                AND source_financial_entry_id IS NULL
                AND source_financial_revision IS NULL
                AND source_financial_entry_type IS NULL
            )
        );

ALTER TABLE crm.customer_order_line
    ALTER COLUMN price_source_code DROP DEFAULT,
    ADD CONSTRAINT fk_customer_order_line_price_source
        FOREIGN KEY (
            source_financial_entry_id,
            source_financial_revision,
            cargo_item_id,
            project_id,
            source_financial_entry_type
        ) REFERENCES crm.cargo_item_financial_revision (
            financial_entry_id,
            revision_number,
            cargo_item_id,
            project_id,
            entry_type
        ) ON DELETE RESTRICT;

ALTER TABLE crm.customer_order_line_revision
    DROP CONSTRAINT fk_customer_order_line_revision_price_source,
    DROP CONSTRAINT ck_customer_order_line_revision_source_type,
    DROP CONSTRAINT ck_customer_order_line_revision_source_revision,
    ADD COLUMN price_source_code VARCHAR(32) NOT NULL DEFAULT 'ITEM_FINANCIAL_ENTRY',
    ALTER COLUMN source_financial_entry_id DROP NOT NULL,
    ALTER COLUMN source_financial_revision DROP NOT NULL,
    ALTER COLUMN source_financial_entry_type DROP NOT NULL,
    ADD CONSTRAINT ck_customer_order_line_revision_price_source
        CHECK (price_source_code IN ('ITEM_FINANCIAL_ENTRY', 'ORDER_ENTRY')),
    ADD CONSTRAINT ck_customer_order_line_revision_price_source_shape
        CHECK (
            (
                price_source_code = 'ITEM_FINANCIAL_ENTRY'
                AND source_financial_entry_id IS NOT NULL
                AND source_financial_revision IS NOT NULL
                AND source_financial_revision >= 1
                AND source_financial_entry_type = 'CUSTOMER_ITEM_PRICE'
            )
            OR (
                price_source_code = 'ORDER_ENTRY'
                AND source_financial_entry_id IS NULL
                AND source_financial_revision IS NULL
                AND source_financial_entry_type IS NULL
            )
        );

ALTER TABLE crm.customer_order_line_revision
    ALTER COLUMN price_source_code DROP DEFAULT,
    ADD CONSTRAINT fk_customer_order_line_revision_price_source
        FOREIGN KEY (
            source_financial_entry_id,
            source_financial_revision,
            cargo_item_id,
            project_id,
            source_financial_entry_type
        ) REFERENCES crm.cargo_item_financial_revision (
            financial_entry_id,
            revision_number,
            cargo_item_id,
            project_id,
            entry_type
        ) ON DELETE RESTRICT;

ALTER TABLE crm.task_subcategory
    DROP CONSTRAINT ck_task_subcategory_system_source,
    ADD CONSTRAINT ck_task_subcategory_system_source
        CHECK (
            system_source_code IS NULL
            OR system_source_code IN (
                'INBOUND_DELIVERY',
                'COURIER_TRIP',
                'CUSTOMER_ORDER',
                'CUSTOMER_ORDER_SHIPMENT',
                'CUSTOMER_ORDER_HANDOVER',
                'CUSTOMER_ORDER_DELIVERY',
                'WAREHOUSE_RELOCATION'
            )
        );

INSERT INTO crm.task_subcategory (
    id,
    category_id,
    country_code,
    system_source_code,
    name,
    active,
    sort_order,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at,
    version
) VALUES
    (
        '00000000-0000-0000-0000-000000005405',
        '00000000-0000-0000-0000-000000005400',
        NULL,
        'CUSTOMER_ORDER_SHIPMENT',
        'Отправка',
        TRUE,
        4,
        'system:migration-v76',
        'system:migration-v76',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        0
    ),
    (
        '00000000-0000-0000-0000-000000005406',
        '00000000-0000-0000-0000-000000005400',
        NULL,
        'CUSTOMER_ORDER_HANDOVER',
        'Выдача',
        TRUE,
        5,
        'system:migration-v76',
        'system:migration-v76',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        0
    ),
    (
        '00000000-0000-0000-0000-000000005407',
        '00000000-0000-0000-0000-000000005400',
        NULL,
        'CUSTOMER_ORDER_DELIVERY',
        'Доставка',
        TRUE,
        6,
        'system:migration-v76',
        'system:migration-v76',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        0
    );

COMMENT ON COLUMN crm.customer_order.order_kind_code IS
    'STANDARD uses a customer profile; MINI is the simplified no-customer supplier workflow.';

COMMENT ON COLUMN crm.customer_order.task_type_code IS
    'Stable business action selected for the managed order task.';

COMMENT ON COLUMN crm.customer_order.operator_comment IS
    'Required operator instruction for a MINI order; copied to its managed task.';

COMMENT ON COLUMN crm.customer_order_line.price_source_code IS
    'ITEM_FINANCIAL_ENTRY snapshots a cargo price; ORDER_ENTRY stores the amount entered for this order.';
