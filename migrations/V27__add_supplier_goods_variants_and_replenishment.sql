CREATE TABLE crm.supplier_goods_variant
(
    id                       UUID         NOT NULL,
    supplier_goods_entry_id UUID         NOT NULL,
    project_id               UUID         NOT NULL,
    supplier_account_id      UUID         NOT NULL,
    value_text               VARCHAR(50),
    unit_code                VARCHAR(32)  NOT NULL,
    created_by_subject       VARCHAR(255) NOT NULL,
    created_at               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_supplier_goods_variant
        PRIMARY KEY (id),
    CONSTRAINT uq_supplier_goods_variant_scope
        UNIQUE (id, supplier_goods_entry_id, project_id, supplier_account_id),
    CONSTRAINT fk_supplier_goods_variant_entry
        FOREIGN KEY (supplier_goods_entry_id, project_id, supplier_account_id)
            REFERENCES crm.supplier_goods_entry (id, project_id, supplier_account_id) ON DELETE RESTRICT,
    CONSTRAINT ck_supplier_goods_variant_unit
        CHECK (unit_code IN (
            'UNSPECIFIED', 'SIZE', 'PIECE', 'MILLILITER', 'LITER',
            'GRAM', 'KILOGRAM', 'MILLIMETER', 'CENTIMETER', 'METER'
        )),
    CONSTRAINT ck_supplier_goods_variant_value
        CHECK (
            (unit_code = 'UNSPECIFIED' AND value_text IS NULL)
            OR (unit_code <> 'UNSPECIFIED' AND value_text IS NOT NULL AND BTRIM(value_text) <> '')
        ),
    CONSTRAINT ck_supplier_goods_variant_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> '')
);

CREATE UNIQUE INDEX uq_supplier_goods_variant_business_key
    ON crm.supplier_goods_variant (
        supplier_goods_entry_id,
        unit_code,
        LOWER(COALESCE(value_text, ''))
    );

CREATE INDEX ix_supplier_goods_variant_entry_created
    ON crm.supplier_goods_variant (supplier_goods_entry_id, created_at, id);

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
       entry.created_by_subject,
       entry.created_at
FROM crm.supplier_goods_entry entry;

ALTER TABLE crm.cargo_item
    ADD COLUMN supplier_goods_variant_id UUID;

UPDATE crm.cargo_item item
SET supplier_goods_variant_id = MD5(item.supplier_goods_entry_id::TEXT || ':unspecified')::UUID;

ALTER TABLE crm.cargo_item
    ALTER COLUMN supplier_goods_variant_id SET NOT NULL,
    ADD CONSTRAINT fk_cargo_item_supplier_goods_variant
        FOREIGN KEY (
            supplier_goods_variant_id,
            supplier_goods_entry_id,
            project_id,
            supplier_account_id
        ) REFERENCES crm.supplier_goods_variant (
            id,
            supplier_goods_entry_id,
            project_id,
            supplier_account_id
        ) ON DELETE RESTRICT;

CREATE INDEX ix_cargo_item_variant_status_created
    ON crm.cargo_item (supplier_goods_variant_id, status_code, created_at, id);

ALTER TABLE crm.inbound_delivery_line
    ADD COLUMN supplier_goods_variant_id UUID,
    ADD COLUMN variant_value_text VARCHAR(50),
    ADD COLUMN variant_unit_code VARCHAR(32);

UPDATE crm.inbound_delivery_line line
SET supplier_goods_variant_id = MD5(line.supplier_goods_entry_id::TEXT || ':unspecified')::UUID,
    variant_unit_code = 'UNSPECIFIED';

ALTER TABLE crm.inbound_delivery_line
    ALTER COLUMN supplier_goods_variant_id SET NOT NULL,
    ALTER COLUMN variant_unit_code SET NOT NULL,
    ADD CONSTRAINT fk_inbound_delivery_line_supplier_goods_variant
        FOREIGN KEY (
            supplier_goods_variant_id,
            supplier_goods_entry_id,
            project_id,
            supplier_account_id
        ) REFERENCES crm.supplier_goods_variant (
            id,
            supplier_goods_entry_id,
            project_id,
            supplier_account_id
        ) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_inbound_delivery_line_variant_unit
        CHECK (variant_unit_code IN (
            'UNSPECIFIED', 'SIZE', 'PIECE', 'MILLILITER', 'LITER',
            'GRAM', 'KILOGRAM', 'MILLIMETER', 'CENTIMETER', 'METER'
        )),
    ADD CONSTRAINT ck_inbound_delivery_line_variant_value
        CHECK (
            (variant_unit_code = 'UNSPECIFIED' AND variant_value_text IS NULL)
            OR (
                variant_unit_code <> 'UNSPECIFIED'
                AND variant_value_text IS NOT NULL
                AND BTRIM(variant_value_text) <> ''
            )
        );

CREATE INDEX ix_inbound_delivery_line_variant
    ON crm.inbound_delivery_line (supplier_goods_variant_id, inbound_delivery_id, id);
