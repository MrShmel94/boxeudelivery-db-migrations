ALTER TABLE crm.cargo_item
    ALTER COLUMN label_code TYPE VARCHAR(128),
    ADD COLUMN label_source_code VARCHAR(32),
    ADD COLUMN label_symbology_code VARCHAR(32),
    DROP CONSTRAINT ck_cargo_item_availability_state;

ALTER TABLE crm.customer_order_pick
    ALTER COLUMN scanned_label_code TYPE VARCHAR(128);

ALTER TABLE crm.outbound_package_item
    ALTER COLUMN scanned_label_code TYPE VARCHAR(128);

ALTER TABLE crm.warehouse_relocation_item
    ALTER COLUMN label_code_snapshot TYPE VARCHAR(128);

UPDATE crm.cargo_item
SET label_source_code = 'LEGACY_INTERNAL'
WHERE label_code IS NOT NULL;

ALTER TABLE crm.cargo_item
    ADD CONSTRAINT ck_cargo_item_label_source CHECK (
        (label_code IS NULL AND label_source_code IS NULL AND label_symbology_code IS NULL)
        OR (
            label_code IS NOT NULL
            AND label_source_code = 'LEGACY_INTERNAL'
            AND label_symbology_code IS NULL
        )
        OR (
            label_code IS NOT NULL
            AND label_source_code = 'EXTERNAL_SCAN'
            AND label_symbology_code IN ('QR_CODE', 'CODE_128')
        )
    ),
    ADD CONSTRAINT ck_cargo_item_availability_state CHECK (
        (
            status_code IN ('AVAILABLE', 'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER', 'DAMAGED', 'REJECTED')
            AND label_code IS NOT NULL AND current_warehouse_id IS NOT NULL
            AND accepted_by_account_id IS NOT NULL AND accepted_at IS NOT NULL
        )
        OR (
            status_code IN ('IN_RELOCATION', 'DELIVERED_TO_CUSTOMER')
            AND label_code IS NOT NULL AND current_warehouse_id IS NULL
            AND accepted_by_account_id IS NOT NULL AND accepted_at IS NOT NULL
        )
        OR (
            status_code NOT IN (
                'AVAILABLE', 'IN_RELOCATION', 'PICKED_FOR_ORDER',
                'PACKED_FOR_CUSTOMER', 'DELIVERED_TO_CUSTOMER'
            )
            AND label_code IS NULL AND current_warehouse_id IS NULL
            AND accepted_by_account_id IS NULL AND accepted_at IS NULL
        )
    );

ALTER TABLE crm.cargo_item_photo
    ADD COLUMN gallery_scope_code VARCHAR(32) NOT NULL DEFAULT 'SUPPLIER_GOODS',
    DROP CONSTRAINT uq_cargo_item_photo_goods_position,
    ADD CONSTRAINT ck_cargo_item_photo_gallery_scope
        CHECK (gallery_scope_code IN ('SUPPLIER_GOODS', 'CARGO_ITEM')),
    DROP CONSTRAINT ck_cargo_item_photo_shared_position,
    ADD CONSTRAINT ck_cargo_item_photo_position
        CHECK (position BETWEEN 0 AND 9);

CREATE UNIQUE INDEX uq_cargo_item_photo_goods_position
    ON crm.cargo_item_photo (supplier_goods_entry_id, position)
    WHERE gallery_scope_code = 'SUPPLIER_GOODS';

CREATE UNIQUE INDEX uq_cargo_item_photo_unit_position
    ON crm.cargo_item_photo (cargo_item_id, position)
    WHERE gallery_scope_code = 'CARGO_ITEM';

CREATE INDEX ix_cargo_item_photo_unit_position
    ON crm.cargo_item_photo (cargo_item_id, position, id)
    WHERE gallery_scope_code = 'CARGO_ITEM';

ALTER TABLE crm.warehouse_receipt_item
    ADD COLUMN problem_description VARCHAR(1000);

UPDATE crm.warehouse_receipt_item
SET problem_description = 'Причина не была зафиксирована в историческом сценарии приёмки.'
WHERE outcome_code = 'MISSING';

ALTER TABLE crm.warehouse_receipt_item
    ADD CONSTRAINT ck_warehouse_receipt_item_problem_description CHECK (
        (
            outcome_code = 'MISSING'
            AND problem_description IS NOT NULL
            AND BTRIM(problem_description) <> ''
        )
        OR (
            outcome_code <> 'MISSING'
            AND (problem_description IS NULL OR BTRIM(problem_description) <> '')
        )
    );

ALTER TABLE crm.mini_supplier_warehouse_receipt_item
    ADD COLUMN outcome_code VARCHAR(32) NOT NULL DEFAULT 'ACCEPTED',
    ADD COLUMN problem_description VARCHAR(1000),
    ADD CONSTRAINT ck_mini_supplier_warehouse_receipt_item_outcome
        CHECK (outcome_code IN ('ACCEPTED', 'MISSING', 'DAMAGED', 'REJECTED')),
    ADD CONSTRAINT ck_mini_supplier_warehouse_receipt_item_problem_description CHECK (
        (
            outcome_code = 'MISSING'
            AND problem_description IS NOT NULL
            AND BTRIM(problem_description) <> ''
        )
        OR (
            outcome_code <> 'MISSING'
            AND (problem_description IS NULL OR BTRIM(problem_description) <> '')
        )
    );

COMMENT ON COLUMN crm.cargo_item.label_source_code IS
    'LEGACY_INTERNAL for historical system-generated labels; EXTERNAL_SCAN for purchased labels scanned during mobile intake.';

COMMENT ON COLUMN crm.cargo_item.label_symbology_code IS
    'Detected external label symbology. New intake supports QR_CODE and CODE_128.';

COMMENT ON COLUMN crm.cargo_item_photo.gallery_scope_code IS
    'SUPPLIER_GOODS is the shared product-card gallery; CARGO_ITEM is evidence attached to one exact physical unit.';

COMMENT ON COLUMN crm.warehouse_receipt_item.problem_description IS
    'Required operator explanation for an exact unit marked missing.';

COMMENT ON TABLE crm.mini_supplier_warehouse_receipt_item IS
    'Exact MINI intake outcomes. Physically present units require an external scanned label and exact-unit photo; missing units require a written explanation.';
