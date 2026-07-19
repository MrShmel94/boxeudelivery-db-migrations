INSERT INTO crm.supplier_goods_variant
(
    id,
    supplier_goods_entry_id,
    project_id,
    supplier_account_id,
    value_text,
    unit_code,
    created_by_subject,
    created_at
)
SELECT MD5(entry.id::TEXT || ':unspecified')::UUID,
       entry.id,
       entry.project_id,
       entry.supplier_account_id,
       NULL,
       'UNSPECIFIED',
       piece.created_by_subject,
       piece.created_at
FROM crm.supplier_goods_entry entry
JOIN LATERAL
(
    SELECT variant.created_by_subject,
           variant.created_at
    FROM crm.supplier_goods_variant variant
    WHERE variant.supplier_goods_entry_id = entry.id
      AND variant.unit_code = 'PIECE'
    ORDER BY variant.created_at, variant.id
    LIMIT 1
) piece ON TRUE
WHERE NOT EXISTS
(
    SELECT 1
    FROM crm.supplier_goods_variant variant
    WHERE variant.supplier_goods_entry_id = entry.id
      AND variant.unit_code = 'UNSPECIFIED'
);

UPDATE crm.cargo_item item
SET supplier_goods_variant_id = unspecified.id
FROM crm.supplier_goods_variant piece,
     crm.supplier_goods_variant unspecified
WHERE item.supplier_goods_variant_id = piece.id
  AND piece.unit_code = 'PIECE'
  AND unspecified.supplier_goods_entry_id = piece.supplier_goods_entry_id
  AND unspecified.unit_code = 'UNSPECIFIED';

UPDATE crm.inbound_delivery_line line
SET supplier_goods_variant_id = unspecified.id,
    variant_value_text = NULL,
    variant_unit_code = 'UNSPECIFIED'
FROM crm.supplier_goods_variant piece,
     crm.supplier_goods_variant unspecified
WHERE line.supplier_goods_variant_id = piece.id
  AND piece.unit_code = 'PIECE'
  AND unspecified.supplier_goods_entry_id = piece.supplier_goods_entry_id
  AND unspecified.unit_code = 'UNSPECIFIED';

DELETE FROM crm.supplier_goods_variant
WHERE unit_code = 'PIECE';

ALTER TABLE crm.supplier_goods_variant
    DROP CONSTRAINT ck_supplier_goods_variant_unit,
    ADD CONSTRAINT ck_supplier_goods_variant_unit
        CHECK (unit_code IN (
            'UNSPECIFIED', 'SIZE', 'MILLILITER', 'LITER',
            'GRAM', 'KILOGRAM', 'MILLIMETER', 'CENTIMETER', 'METER'
        ));

ALTER TABLE crm.inbound_delivery_line
    DROP CONSTRAINT ck_inbound_delivery_line_variant_unit,
    ADD CONSTRAINT ck_inbound_delivery_line_variant_unit
        CHECK (variant_unit_code IN (
            'UNSPECIFIED', 'SIZE', 'MILLILITER', 'LITER',
            'GRAM', 'KILOGRAM', 'MILLIMETER', 'CENTIMETER', 'METER'
        ));

COMMENT ON COLUMN crm.supplier_goods_variant.unit_code IS
    'Operational characteristic unit. Piece count belongs to cargo item quantity; UNSPECIFIED means no characteristic.';

COMMENT ON COLUMN crm.inbound_delivery_line.variant_unit_code IS
    'Immutable operational characteristic snapshot. Piece count is represented by delivery line quantity.';
