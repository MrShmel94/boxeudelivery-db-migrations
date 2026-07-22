-- Replace country-specific managed-task defaults with one protected global catalogue.
-- V54 introduces the managed-task catalogue before the independent supplier product-card migration.
DROP TABLE crm.task_system_classification_default;

ALTER TABLE crm.task_category
    ADD COLUMN system_code VARCHAR(32),
    ALTER COLUMN country_code DROP NOT NULL,
    ADD CONSTRAINT ck_task_category_scope
        CHECK (
            (country_code IS NOT NULL AND system_code IS NULL)
            OR (country_code IS NULL AND system_code IS NOT NULL)
        ),
    ADD CONSTRAINT ck_task_category_system_code
        CHECK (system_code IS NULL OR system_code = 'BUSINESS_PROCESS');

DROP INDEX crm.uq_task_category_country_name;

CREATE UNIQUE INDEX uq_task_category_country_name
    ON crm.task_category (country_code, LOWER(BTRIM(name)))
    WHERE country_code IS NOT NULL;

CREATE UNIQUE INDEX uq_task_category_system_code
    ON crm.task_category (system_code)
    WHERE system_code IS NOT NULL;

ALTER TABLE crm.task_subcategory
    DROP CONSTRAINT fk_task_subcategory_category_country,
    ADD COLUMN system_source_code VARCHAR(32),
    ALTER COLUMN country_code DROP NOT NULL,
    ADD CONSTRAINT fk_task_subcategory_category
        FOREIGN KEY (category_id) REFERENCES crm.task_category (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_task_subcategory_scope
        CHECK (
            (country_code IS NOT NULL AND system_source_code IS NULL)
            OR (country_code IS NULL AND system_source_code IS NOT NULL)
        ),
    ADD CONSTRAINT ck_task_subcategory_system_source
        CHECK (
            system_source_code IS NULL
            OR system_source_code IN (
                'INBOUND_DELIVERY',
                'COURIER_TRIP',
                'CUSTOMER_ORDER',
                'WAREHOUSE_RELOCATION'
            )
        );

CREATE UNIQUE INDEX uq_task_subcategory_system_source
    ON crm.task_subcategory (system_source_code)
    WHERE system_source_code IS NOT NULL;

ALTER TABLE crm.task
    ADD COLUMN operator_description VARCHAR(10000),
    ADD CONSTRAINT ck_task_operator_description_not_blank
        CHECK (operator_description IS NULL OR BTRIM(operator_description) <> '');

INSERT INTO crm.task_category (
    id,
    country_code,
    system_code,
    name,
    active,
    sort_order,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at,
    version
) VALUES (
    '00000000-0000-0000-0000-000000005400',
    NULL,
    'BUSINESS_PROCESS',
    'Системные процессы',
    TRUE,
    0,
    'system:migration-v54',
    'system:migration-v54',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    0
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
        '00000000-0000-0000-0000-000000005401',
        '00000000-0000-0000-0000-000000005400',
        NULL,
        'INBOUND_DELIVERY',
        'Поставка на склад',
        TRUE,
        0,
        'system:migration-v54',
        'system:migration-v54',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        0
    ),
    (
        '00000000-0000-0000-0000-000000005402',
        '00000000-0000-0000-0000-000000005400',
        NULL,
        'COURIER_TRIP',
        'Курьерский рейс',
        TRUE,
        1,
        'system:migration-v54',
        'system:migration-v54',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        0
    ),
    (
        '00000000-0000-0000-0000-000000005403',
        '00000000-0000-0000-0000-000000005400',
        NULL,
        'CUSTOMER_ORDER',
        'Заказ клиента',
        TRUE,
        2,
        'system:migration-v54',
        'system:migration-v54',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        0
    ),
    (
        '00000000-0000-0000-0000-000000005404',
        '00000000-0000-0000-0000-000000005400',
        NULL,
        'WAREHOUSE_RELOCATION',
        'Релокация склада',
        TRUE,
        3,
        'system:migration-v54',
        'system:migration-v54',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        0
    );

UPDATE crm.task
SET task_subcategory_id = CASE
    WHEN inbound_delivery_id IS NOT NULL THEN '00000000-0000-0000-0000-000000005401'::UUID
    WHEN courier_trip_id IS NOT NULL THEN '00000000-0000-0000-0000-000000005402'::UUID
    WHEN customer_order_id IS NOT NULL THEN '00000000-0000-0000-0000-000000005403'::UUID
    WHEN warehouse_relocation_id IS NOT NULL THEN '00000000-0000-0000-0000-000000005404'::UUID
    ELSE task_subcategory_id
END
WHERE inbound_delivery_id IS NOT NULL
   OR courier_trip_id IS NOT NULL
   OR customer_order_id IS NOT NULL
   OR warehouse_relocation_id IS NOT NULL;

COMMENT ON COLUMN crm.task_category.system_code IS
    'Stable code for a protected global category owned by CRM business processes; null for administrator-managed country categories.';

COMMENT ON COLUMN crm.task_subcategory.system_source_code IS
    'Stable managed-task source assigned automatically by CRM; null for administrator-managed subcategories.';

COMMENT ON COLUMN crm.task.operator_description IS
    'Optional operator-authored description for a business-managed task. Generated task description remains immutable.';
