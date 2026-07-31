UPDATE crm.supplier_goods_entry AS goods
SET border_tariff_subcategory_id = NULL
FROM crm.project_supplier AS supplier_assignment
WHERE supplier_assignment.project_id = goods.project_id
  AND supplier_assignment.supplier_id = goods.supplier_id
  AND supplier_assignment.operating_mode = 'MINI'
  AND goods.border_tariff_subcategory_id IS NOT NULL;

COMMENT ON COLUMN crm.supplier_goods_entry.border_tariff_subcategory_id IS
    'Cross-border tariff classification required for FULL supplier goods and absent for MINI direct-warehouse goods.';
