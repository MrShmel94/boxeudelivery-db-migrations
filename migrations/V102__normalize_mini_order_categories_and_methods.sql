DO $$
DECLARE
    category_record RECORD;
    canonical_name VARCHAR(150);
BEGIN
    FOR category_record IN
        SELECT id,
               country_code,
               name,
               active,
               managed_task_source_code
        FROM crm.task_category
        WHERE managed_task_source_code IN (
            'CUSTOMER_ORDER_SHIPMENT',
            'CUSTOMER_ORDER_HANDOVER',
            'CUSTOMER_ORDER_DELIVERY'
        )
        ORDER BY country_code, id
    LOOP
        canonical_name := CASE category_record.managed_task_source_code
            WHEN 'CUSTOMER_ORDER_SHIPMENT' THEN 'Отправка'
            WHEN 'CUSTOMER_ORDER_HANDOVER' THEN 'Выдача'
            WHEN 'CUSTOMER_ORDER_DELIVERY' THEN 'Доставка'
        END;

        IF LOWER(BTRIM(category_record.name)) NOT IN (
            LOWER(canonical_name),
            LOWER(canonical_name || ' заказа')
        ) THEN
            INSERT INTO crm.task_subcategory (
                id,
                category_id,
                country_code,
                system_source_code,
                customer_order_action_code,
                name,
                active,
                sort_order,
                created_by_subject,
                updated_by_subject,
                created_at,
                updated_at,
                version
            ) VALUES (
                MD5('v102-mini-method:' || category_record.id::TEXT)::UUID,
                category_record.id,
                category_record.country_code,
                NULL,
                category_record.managed_task_source_code,
                BTRIM(category_record.name),
                category_record.active,
                0,
                'system:migration-v102',
                'system:migration-v102',
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP,
                0
            )
            ON CONFLICT DO NOTHING;
        END IF;

        UPDATE crm.task_category
        SET name = canonical_name || ' · обычная · ' || LEFT(id::TEXT, 8),
            updated_by_subject = 'system:migration-v102',
            updated_at = CURRENT_TIMESTAMP,
            version = version + 1
        WHERE id <> category_record.id
          AND country_code = category_record.country_code
          AND managed_task_source_code IS NULL
          AND LOWER(BTRIM(name)) = LOWER(canonical_name);

        UPDATE crm.task_category
        SET name = canonical_name,
            updated_by_subject = 'system:migration-v102',
            updated_at = CURRENT_TIMESTAMP,
            version = version + 1
        WHERE id = category_record.id
          AND name <> canonical_name;
    END LOOP;
END;
$$;

WITH resolved_category AS (
    SELECT customer_order.id AS order_id,
           category.id       AS category_id
    FROM crm.customer_order customer_order
    JOIN crm.supplier supplier
      ON supplier.id = customer_order.supplier_id
    JOIN crm.task_category current_category
      ON current_category.id = customer_order.mini_task_category_id
    JOIN crm.task_category category
      ON category.country_code = supplier.home_country_code
     AND category.active
     AND category.managed_task_source_code = CASE customer_order.task_type_code
         WHEN 'SHIPMENT' THEN 'CUSTOMER_ORDER_SHIPMENT'
         WHEN 'HANDOVER' THEN 'CUSTOMER_ORDER_HANDOVER'
         WHEN 'DELIVERY' THEN 'CUSTOMER_ORDER_DELIVERY'
     END
    WHERE customer_order.order_kind_code = 'MINI'
      AND current_category.system_code IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM crm.project_country project_country
          WHERE project_country.project_id = customer_order.project_id
            AND project_country.country_code = supplier.home_country_code
      )
)
UPDATE crm.customer_order customer_order
SET mini_task_category_id = resolved_category.category_id,
    mini_task_subcategory_id = NULL,
    updated_by_subject = 'system:migration-v102',
    updated_at = CURRENT_TIMESTAMP,
    version = customer_order.version + 1
FROM resolved_category
WHERE customer_order.id = resolved_category.order_id;

WITH resolved_category AS (
    SELECT customer_order.id                    AS order_id,
           customer_order.mini_task_category_id AS category_id,
           customer_order.mini_task_subcategory_id AS subcategory_id
    FROM crm.customer_order customer_order
    WHERE customer_order.order_kind_code = 'MINI'
      AND customer_order.mini_task_category_id IS NOT NULL
)
UPDATE crm.task task
SET task_category_id = resolved_category.category_id,
    task_subcategory_id = resolved_category.subcategory_id,
    updated_at = CURRENT_TIMESTAMP,
    version = task.version + 1
FROM resolved_category
WHERE task.customer_order_id = resolved_category.order_id
  AND (
      task.task_category_id IS DISTINCT FROM resolved_category.category_id
      OR task.task_subcategory_id IS DISTINCT FROM resolved_category.subcategory_id
  );

COMMENT ON COLUMN crm.task_category.managed_task_source_code IS
    'Optional stable managed-process binding. MINI customer-order actions own fixed category names; their administrator-defined carriers and handover methods are child subcategories.';

COMMENT ON COLUMN crm.customer_order.mini_task_subcategory_id IS
    'Optional internal MINI execution method within mini_task_category_id; null means the supplier-selected category itself is sufficient.';
