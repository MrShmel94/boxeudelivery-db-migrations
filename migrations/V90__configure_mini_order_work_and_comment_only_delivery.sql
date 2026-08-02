ALTER TABLE crm.task_subcategory
    ADD COLUMN customer_order_action_code VARCHAR(32),
    ADD CONSTRAINT ck_task_subcategory_customer_order_action
        CHECK (
            customer_order_action_code IS NULL
            OR customer_order_action_code IN (
                'CUSTOMER_ORDER_SHIPMENT',
                'CUSTOMER_ORDER_HANDOVER',
                'CUSTOMER_ORDER_DELIVERY'
            )
        );

UPDATE crm.task_subcategory
SET customer_order_action_code = system_source_code
WHERE system_source_code IN (
    'CUSTOMER_ORDER_SHIPMENT',
    'CUSTOMER_ORDER_HANDOVER',
    'CUSTOMER_ORDER_DELIVERY'
);

COMMENT ON COLUMN crm.task_subcategory.customer_order_action_code IS
    'Optional MINI customer-order action supplied by this configured task subcategory.';

ALTER TABLE crm.customer_order
    ADD COLUMN mini_task_subcategory_id UUID;

UPDATE crm.customer_order customer_order
SET mini_task_subcategory_id = COALESCE(
    task.task_subcategory_id,
    CASE customer_order.task_type_code
        WHEN 'SHIPMENT' THEN '00000000-0000-0000-0000-000000005405'::UUID
        WHEN 'HANDOVER' THEN '00000000-0000-0000-0000-000000005406'::UUID
        WHEN 'DELIVERY' THEN '00000000-0000-0000-0000-000000005407'::UUID
        ELSE NULL
    END
)
FROM crm.task task
WHERE task.customer_order_id = customer_order.id
  AND customer_order.order_kind_code = 'MINI';

UPDATE crm.customer_order
SET mini_task_subcategory_id = CASE task_type_code
    WHEN 'SHIPMENT' THEN '00000000-0000-0000-0000-000000005405'::UUID
    WHEN 'HANDOVER' THEN '00000000-0000-0000-0000-000000005406'::UUID
    WHEN 'DELIVERY' THEN '00000000-0000-0000-0000-000000005407'::UUID
    ELSE NULL
END
WHERE order_kind_code = 'MINI'
  AND mini_task_subcategory_id IS NULL;

ALTER TABLE crm.customer_order
    ADD CONSTRAINT fk_customer_order_mini_task_subcategory
        FOREIGN KEY (mini_task_subcategory_id)
            REFERENCES crm.task_subcategory (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_customer_order_mini_task_subcategory
        CHECK (
            (order_kind_code = 'MINI' AND mini_task_subcategory_id IS NOT NULL)
            OR (order_kind_code = 'STANDARD' AND mini_task_subcategory_id IS NULL)
        );

CREATE INDEX ix_customer_order_mini_task_subcategory
    ON crm.customer_order (mini_task_subcategory_id, created_at DESC, id)
    WHERE mini_task_subcategory_id IS NOT NULL;

COMMENT ON COLUMN crm.customer_order.mini_task_subcategory_id IS
    'Configured task subcategory selected for a MINI order; its action code determines the delivery lifecycle.';

ALTER TABLE crm.outbound_delivery
    ALTER COLUMN delivery_instructions TYPE VARCHAR(2000),
    ADD COLUMN details_mode_code VARCHAR(16) NOT NULL DEFAULT 'STRUCTURED',
    ADD CONSTRAINT ck_outbound_delivery_details_mode
        CHECK (details_mode_code IN ('STRUCTURED', 'COMMENT_ONLY')),
    DROP CONSTRAINT ck_outbound_delivery_method_details,
    DROP CONSTRAINT ck_outbound_delivery_courier_assignment;

ALTER TABLE crm.outbound_delivery
    ADD CONSTRAINT ck_outbound_delivery_method_details
        CHECK (
            (
                details_mode_code = 'COMMENT_ONLY'
                AND recipient_name IS NULL
                AND recipient_phone IS NULL
                AND country_code IS NULL
                AND postal_code IS NULL
                AND address_line IS NULL
                AND delivery_instructions IS NOT NULL
                AND BTRIM(delivery_instructions) <> ''
                AND assigned_courier_account_id IS NULL
                AND assigned_courier_source IS NULL
                AND courier_conversation_id IS NULL
                AND external_carrier_name IS NULL
                AND external_service_name IS NULL
                AND tracking_number IS NULL
                AND tracking_url IS NULL
            )
            OR (
                details_mode_code = 'STRUCTURED'
                AND (
                    (
                        method_code = 'WAREHOUSE_PICKUP'
                        AND country_code IS NULL
                        AND postal_code IS NULL
                        AND address_line IS NULL
                        AND assigned_courier_account_id IS NULL
                        AND external_carrier_name IS NULL
                        AND external_service_name IS NULL
                        AND tracking_number IS NULL
                        AND tracking_url IS NULL
                    )
                    OR (
                        method_code = 'COMPANY_COURIER'
                        AND country_code IS NOT NULL
                        AND address_line IS NOT NULL
                        AND BTRIM(address_line) <> ''
                        AND assigned_courier_account_id IS NOT NULL
                        AND external_carrier_name IS NULL
                        AND external_service_name IS NULL
                        AND tracking_number IS NULL
                        AND tracking_url IS NULL
                    )
                    OR (
                        method_code = 'EXTERNAL_CARRIER'
                        AND country_code IS NOT NULL
                        AND address_line IS NOT NULL
                        AND BTRIM(address_line) <> ''
                        AND assigned_courier_account_id IS NULL
                        AND external_carrier_name IS NOT NULL
                        AND BTRIM(external_carrier_name) <> ''
                    )
                )
            )
        ),
    ADD CONSTRAINT ck_outbound_delivery_courier_assignment
        CHECK (
            (
                details_mode_code = 'STRUCTURED'
                AND method_code = 'COMPANY_COURIER'
                AND assigned_courier_account_id IS NOT NULL
                AND assigned_courier_source IS NOT NULL
                AND courier_conversation_id IS NOT NULL
            )
            OR (
                (details_mode_code = 'COMMENT_ONLY' OR method_code <> 'COMPANY_COURIER')
                AND assigned_courier_account_id IS NULL
                AND assigned_courier_source IS NULL
                AND courier_conversation_id IS NULL
            )
        );

ALTER TABLE crm.outbound_delivery
    ALTER COLUMN details_mode_code DROP DEFAULT;

COMMENT ON COLUMN crm.outbound_delivery.details_mode_code IS
    'STRUCTURED keeps recipient and route fields; COMMENT_ONLY stores all MINI handover instructions in one comment.';
