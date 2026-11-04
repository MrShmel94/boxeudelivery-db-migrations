CREATE VIEW crm.supplier_goods_website_catalog_variant AS
SELECT variant.id AS variant_id, variant.supplier_goods_entry_id, variant.project_id, variant.created_at,
       first_value(variant.id) OVER (
           PARTITION BY variant.supplier_goods_entry_id ORDER BY variant.created_at, variant.id
       ) AS canonical_variant_id,
       coalesce(stock.quantity, 0)::integer AS available_quantity
FROM crm.supplier_goods_variant variant
LEFT JOIN (
    SELECT item.supplier_goods_variant_id, count(*) AS quantity
    FROM crm.cargo_item item
    WHERE item.status_code = 'AVAILABLE'
      AND item.current_warehouse_id IS NOT NULL AND item.accepted_at IS NOT NULL
      AND item.sales_request_line_id IS NULL
      AND item.customer_profile_id IS NULL AND item.customer_account_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM crm.customer_order_line line
          WHERE line.cargo_item_id = item.id AND line.status_code <> 'REMOVED')
      AND NOT EXISTS (SELECT 1 FROM crm.warehouse_relocation_item link
          JOIN crm.warehouse_relocation relocation ON relocation.id = link.relocation_id
          WHERE link.cargo_item_id = item.id AND relocation.status_code NOT IN ('COMPLETED', 'CANCELLED'))
      AND NOT EXISTS (SELECT 1 FROM crm.mini_supplier_intake_item link
          JOIN crm.mini_supplier_intake intake ON intake.id = link.intake_id
          WHERE link.cargo_item_id = item.id AND intake.completed_at IS NULL)
      AND NOT EXISTS (SELECT 1 FROM crm.inbound_delivery delivery
          WHERE delivery.id = item.inbound_delivery_id AND delivery.status_code NOT IN ('COMPLETED', 'CANCELLED'))
    GROUP BY item.supplier_goods_variant_id
) stock ON stock.supplier_goods_variant_id = variant.id;

CREATE OR REPLACE VIEW crm.supplier_goods_website_readiness AS
SELECT supplier_goods_entry_id, category_ready, brand_ready,
       category_ready AND brand_ready AND price_ready AND delivery_ready AS ready,
       price_ready, delivery_ready
FROM (
    SELECT goods.id AS supplier_goods_entry_id,
           coalesce(subcategory.active AND subcategory.deleted_at IS NULL AND category.active
                    AND (subcategory.group_id IS NULL OR category_group.active), false) AS category_ready,
           goods.brand_id IS NOT NULL AS brand_ready,
           goods.online_store_amount IS NOT NULL AND goods.online_store_currency_code IS NOT NULL
               AND NOT goods.online_store_price_needs_review AS price_ready,
           goods.website_delivery_days IS NOT NULL OR EXISTS (
               SELECT 1 FROM crm.supplier_goods_website_catalog_variant stock
               WHERE stock.supplier_goods_entry_id = goods.id AND stock.available_quantity > 0
           ) AS delivery_ready
    FROM crm.supplier_goods_entry goods
    LEFT JOIN crm.border_tariff_subcategory subcategory ON subcategory.id = goods.border_tariff_subcategory_id
    LEFT JOIN crm.border_tariff_category category ON category.id = subcategory.category_id
    LEFT JOIN crm.border_tariff_category_group category_group
        ON category_group.id = subcategory.group_id AND category_group.category_id = category.id
    WHERE goods.deleted_at IS NULL
) readiness;
