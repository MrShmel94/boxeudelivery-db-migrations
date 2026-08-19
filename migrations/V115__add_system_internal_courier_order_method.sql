ALTER TABLE crm.task_subcategory
    ADD COLUMN customer_order_method_code VARCHAR(32),
    ADD CONSTRAINT ck_task_subcategory_customer_order_method
        CHECK (
            customer_order_method_code IS NULL
            OR customer_order_method_code = 'PROJECT_INTERNAL_COURIER'
        );

UPDATE crm.task_subcategory subcategory
SET customer_order_method_code = 'PROJECT_INTERNAL_COURIER',
    customer_order_action_code = 'CUSTOMER_ORDER_DELIVERY',
    name = 'Наш курьер',
    active = TRUE,
    sort_order = 0,
    updated_by_subject = 'system:migration-v115',
    updated_at = CURRENT_TIMESTAMP,
    version = subcategory.version + 1
FROM crm.task_category category
WHERE category.id = subcategory.category_id
  AND category.managed_task_source_code = 'CUSTOMER_ORDER_DELIVERY'
  AND LOWER(BTRIM(subcategory.name)) = LOWER('Наш курьер');

INSERT INTO crm.task_subcategory (
    id,
    category_id,
    country_code,
    system_source_code,
    customer_order_action_code,
    customer_order_method_code,
    name,
    active,
    sort_order,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at,
    version
)
SELECT MD5('v115-project-internal-courier:' || category.id::TEXT)::UUID,
       category.id,
       category.country_code,
       NULL,
       'CUSTOMER_ORDER_DELIVERY',
       'PROJECT_INTERNAL_COURIER',
       'Наш курьер',
       TRUE,
       0,
       'system:migration-v115',
       'system:migration-v115',
       CURRENT_TIMESTAMP,
       CURRENT_TIMESTAMP,
       0
FROM crm.task_category category
WHERE category.managed_task_source_code = 'CUSTOMER_ORDER_DELIVERY'
  AND NOT EXISTS (
      SELECT 1
      FROM crm.task_subcategory subcategory
      WHERE subcategory.category_id = category.id
        AND subcategory.customer_order_method_code = 'PROJECT_INTERNAL_COURIER'
  );

CREATE UNIQUE INDEX uq_task_subcategory_customer_order_method
    ON crm.task_subcategory (category_id, customer_order_method_code)
    WHERE customer_order_method_code IS NOT NULL;

COMMENT ON COLUMN crm.task_subcategory.customer_order_method_code IS
    'Stable system-owned behavior of a MINI customer-order execution method; null means an administrator-managed method.';

ALTER TABLE crm.customer_order
    ADD COLUMN internal_courier_account_id UUID,
    ADD CONSTRAINT fk_customer_order_internal_courier_account
        FOREIGN KEY (internal_courier_account_id)
            REFERENCES crm.account (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_customer_order_internal_courier_scope
        CHECK (
            internal_courier_account_id IS NULL
            OR (order_kind_code = 'MINI' AND task_type_code = 'DELIVERY')
        );

CREATE INDEX ix_customer_order_internal_courier
    ON crm.customer_order (internal_courier_account_id, status_code, created_at DESC, id)
    WHERE internal_courier_account_id IS NOT NULL;

COMMENT ON COLUMN crm.customer_order.internal_courier_account_id IS
    'Selected active project-internal courier for the system MINI delivery method.';

ALTER TABLE crm.task_assignee
    ADD COLUMN source_code VARCHAR(40) NOT NULL DEFAULT 'MANUAL',
    ADD CONSTRAINT ck_task_assignee_source
        CHECK (source_code IN ('MANUAL', 'CUSTOMER_ORDER_INTERNAL_COURIER'));

ALTER TABLE crm.task_assignee
    ALTER COLUMN source_code DROP DEFAULT;

CREATE UNIQUE INDEX uq_task_assignee_customer_order_internal_courier
    ON crm.task_assignee (task_id)
    WHERE source_code = 'CUSTOMER_ORDER_INTERNAL_COURIER';

COMMENT ON COLUMN crm.task_assignee.source_code IS
    'Authoritative origin of the task execution assignment; the internal-courier source is synchronized by the owning customer order.';

ALTER TABLE crm.task_participant
    DROP CONSTRAINT ck_task_participant_source,
    ADD CONSTRAINT ck_task_participant_source CHECK (source_code IN (
        'MANUAL',
        'DELIVERY_SUPPLIER', 'DELIVERY_PROJECT_ROLE',
        'COURIER_TRIP_SUPPLIER', 'COURIER_TRIP_PROJECT_ROLE',
        'CUSTOMER_ORDER_SUPPLIER', 'CUSTOMER_ORDER_CUSTOMER', 'CUSTOMER_ORDER_PROJECT_ROLE',
        'CUSTOMER_ORDER_INTERNAL_COURIER',
        'RELOCATION_PROJECT_ROLE',
        'FULFILLMENT_SUPPLIER', 'FULFILLMENT_CUSTOMER', 'FULFILLMENT_PROJECT_ROLE',
        'GLOBAL_ADMINISTRATOR'
    ));
