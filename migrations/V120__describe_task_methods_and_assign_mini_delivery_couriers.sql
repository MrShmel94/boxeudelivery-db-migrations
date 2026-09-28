ALTER TABLE crm.task_subcategory
    ADD COLUMN description VARCHAR(500),
    ADD CONSTRAINT ck_task_subcategory_description_not_blank
        CHECK (description IS NULL OR BTRIM(description) <> '');

UPDATE crm.task_subcategory
SET description = 'Сотрудник проекта забирает упакованный заказ и доставляет его клиенту. Конкретный курьер выбирается при создании доставки.',
    updated_by_subject = 'system:migration-v120',
    updated_at = CURRENT_TIMESTAMP,
    version = version + 1
WHERE customer_order_method_code = 'PROJECT_INTERNAL_COURIER'
  AND description IS DISTINCT FROM
      'Сотрудник проекта забирает упакованный заказ и доставляет его клиенту. Конкретный курьер выбирается при создании доставки.';

COMMENT ON COLUMN crm.task_subcategory.description IS
    'Optional operator-facing explanation of how the configured task method is performed.';

ALTER TABLE crm.outbound_delivery
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
                AND external_carrier_name IS NULL
                AND external_service_name IS NULL
                AND tracking_number IS NULL
                AND tracking_url IS NULL
                AND (
                    (
                        method_code = 'WAREHOUSE_PICKUP'
                        AND assigned_courier_account_id IS NULL
                        AND assigned_courier_source IS NULL
                        AND courier_conversation_id IS NULL
                    )
                    OR (
                        method_code = 'COMPANY_COURIER'
                        AND (
                            (
                                assigned_courier_account_id IS NULL
                                AND assigned_courier_source IS NULL
                                AND courier_conversation_id IS NULL
                            )
                            OR (
                                assigned_courier_account_id IS NOT NULL
                                AND assigned_courier_source = 'PROJECT_INTERNAL'
                                AND courier_conversation_id IS NOT NULL
                            )
                        )
                    )
                )
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
                details_mode_code = 'COMMENT_ONLY'
                AND method_code = 'COMPANY_COURIER'
                AND (
                    (
                        assigned_courier_account_id IS NULL
                        AND assigned_courier_source IS NULL
                        AND courier_conversation_id IS NULL
                    )
                    OR (
                        assigned_courier_account_id IS NOT NULL
                        AND assigned_courier_source = 'PROJECT_INTERNAL'
                        AND courier_conversation_id IS NOT NULL
                    )
                )
            )
            OR (
                method_code <> 'COMPANY_COURIER'
                AND assigned_courier_account_id IS NULL
                AND assigned_courier_source IS NULL
                AND courier_conversation_id IS NULL
            )
        );

COMMENT ON COLUMN crm.outbound_delivery.assigned_courier_account_id IS
    'Exact courier selected for company delivery; required for new MINI delivery handovers and optional only on legacy rows.';
