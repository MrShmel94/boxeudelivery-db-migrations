CREATE TEMPORARY TABLE mini_order_action_category_target ON COMMIT DROP AS
WITH country_scope AS (
    SELECT DISTINCT supplier.home_country_code AS country_code
    FROM crm.project_supplier assignment
    JOIN crm.supplier supplier
      ON supplier.id = assignment.supplier_id
    WHERE assignment.operating_mode = 'MINI'
      AND supplier.home_country_code IS NOT NULL

    UNION

    SELECT DISTINCT category.country_code
    FROM crm.task_category category
    WHERE category.managed_task_source_code IN (
        'CUSTOMER_ORDER_SHIPMENT',
        'CUSTOMER_ORDER_HANDOVER',
        'CUSTOMER_ORDER_DELIVERY'
    )
      AND category.country_code IS NOT NULL
),
action(action_code, canonical_name, sort_order) AS (
    VALUES
        ('CUSTOMER_ORDER_SHIPMENT'::VARCHAR(32), 'Отправка'::VARCHAR(150), 0),
        ('CUSTOMER_ORDER_HANDOVER'::VARCHAR(32), 'Выдача'::VARCHAR(150), 1),
        ('CUSTOMER_ORDER_DELIVERY'::VARCHAR(32), 'Доставка'::VARCHAR(150), 2)
)
SELECT country_scope.country_code,
       action.action_code,
       action.canonical_name,
       action.sort_order
FROM country_scope
CROSS JOIN action;

UPDATE crm.task_category category
SET name = target.canonical_name || ' · другая · ' || category.id::TEXT,
    updated_by_subject = 'system:migration-v107',
    updated_at = CURRENT_TIMESTAMP,
    version = category.version + 1
FROM mini_order_action_category_target target
WHERE category.country_code = target.country_code
  AND category.managed_task_source_code IS DISTINCT FROM target.action_code
  AND LOWER(BTRIM(category.name)) = LOWER(target.canonical_name);

INSERT INTO crm.task_category (
    id,
    country_code,
    system_code,
    managed_task_source_code,
    name,
    active,
    sort_order,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at,
    version
)
SELECT MD5(
           'v107-mini-order-action:'
           || target.country_code
           || ':'
           || target.action_code
       )::UUID,
       target.country_code,
       NULL,
       target.action_code,
       target.canonical_name,
       TRUE,
       target.sort_order,
       'system:migration-v107',
       'system:migration-v107',
       CURRENT_TIMESTAMP,
       CURRENT_TIMESTAMP,
       0
FROM mini_order_action_category_target target
ON CONFLICT (country_code, managed_task_source_code)
    WHERE managed_task_source_code IS NOT NULL
DO UPDATE SET
    name = EXCLUDED.name,
    active = TRUE,
    sort_order = EXCLUDED.sort_order,
    updated_by_subject = EXCLUDED.updated_by_subject,
    updated_at = EXCLUDED.updated_at,
    version = crm.task_category.version + 1
WHERE crm.task_category.name IS DISTINCT FROM EXCLUDED.name
   OR NOT crm.task_category.active
   OR crm.task_category.sort_order IS DISTINCT FROM EXCLUDED.sort_order;
