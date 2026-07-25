CREATE OR REPLACE FUNCTION crm.legacy_supplier_goods_attributes(
    value_text VARCHAR,
    unit_code VARCHAR
)
RETURNS JSONB
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN unit_code = 'SIZE' THEN JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
            'type', 'SIZE',
            'value', value_text,
            'unit', NULL
        ))
        WHEN unit_code IN ('MILLILITER', 'LITER') THEN JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
            'type', 'VOLUME',
            'value', value_text,
            'unit', unit_code
        ))
        WHEN unit_code IN ('GRAM', 'KILOGRAM') THEN JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
            'type', 'WEIGHT',
            'value', value_text,
            'unit', unit_code
        ))
        WHEN unit_code IN ('MILLIMETER', 'CENTIMETER', 'METER') THEN JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
            'type', 'LENGTH',
            'value', value_text,
            'unit', unit_code
        ))
        ELSE '[]'::JSONB
    END
$$;

CREATE OR REPLACE FUNCTION crm.legacy_supplier_goods_attribute_signature(
    value_text VARCHAR,
    unit_code VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN unit_code = 'SIZE'
            THEN 'SIZE|' || REPLACE(
                ENCODE(CONVERT_TO(LOWER(BTRIM(value_text)), 'UTF8'), 'base64'),
                E'\n',
                ''
            ) || '|'
        WHEN unit_code IN ('MILLILITER', 'LITER')
            THEN 'VOLUME|' || REPLACE(
                ENCODE(CONVERT_TO(LOWER(BTRIM(value_text)), 'UTF8'), 'base64'),
                E'\n',
                ''
            ) || '|' || unit_code
        WHEN unit_code IN ('GRAM', 'KILOGRAM')
            THEN 'WEIGHT|' || REPLACE(
                ENCODE(CONVERT_TO(LOWER(BTRIM(value_text)), 'UTF8'), 'base64'),
                E'\n',
                ''
            ) || '|' || unit_code
        WHEN unit_code IN ('MILLIMETER', 'CENTIMETER', 'METER')
            THEN 'LENGTH|' || REPLACE(
                ENCODE(CONVERT_TO(LOWER(BTRIM(value_text)), 'UTF8'), 'base64'),
                E'\n',
                ''
            ) || '|' || unit_code
        ELSE ''
    END
$$;

ALTER TABLE crm.supplier_goods_variant
    ADD COLUMN attributes JSONB NOT NULL DEFAULT '[]'::JSONB,
    ADD COLUMN attribute_signature VARCHAR(1024);

UPDATE crm.supplier_goods_variant
SET attributes = crm.legacy_supplier_goods_attributes(value_text, unit_code),
    attribute_signature = crm.legacy_supplier_goods_attribute_signature(value_text, unit_code);

CREATE OR REPLACE FUNCTION crm.populate_legacy_supplier_goods_variant_attributes()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
    IF NEW.attributes = '[]'::JSONB AND NEW.unit_code <> 'UNSPECIFIED' THEN
        NEW.attributes := crm.legacy_supplier_goods_attributes(NEW.value_text, NEW.unit_code);
    END IF;
    IF NEW.attribute_signature IS NULL THEN
        NEW.attribute_signature := crm.legacy_supplier_goods_attribute_signature(
            NEW.value_text,
            NEW.unit_code
        );
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER trg_supplier_goods_variant_legacy_attributes
    BEFORE INSERT ON crm.supplier_goods_variant
    FOR EACH ROW
    EXECUTE FUNCTION crm.populate_legacy_supplier_goods_variant_attributes();

ALTER TABLE crm.supplier_goods_variant
    ALTER COLUMN attribute_signature SET NOT NULL,
    ADD CONSTRAINT ck_supplier_goods_variant_attributes
        CHECK (
            JSONB_TYPEOF(attributes) = 'array'
            AND JSONB_ARRAY_LENGTH(attributes) <= 8
        ),
    ADD CONSTRAINT ck_supplier_goods_variant_attribute_signature_not_blank
        CHECK (
            (attributes = '[]'::JSONB AND attribute_signature = '')
            OR (
                attributes <> '[]'::JSONB
                AND BTRIM(attribute_signature) <> ''
            )
        );

DROP INDEX crm.uq_supplier_goods_variant_business_key;

CREATE UNIQUE INDEX uq_supplier_goods_variant_attribute_signature
    ON crm.supplier_goods_variant (
        supplier_goods_entry_id,
        attribute_signature
    );

ALTER TABLE crm.inbound_delivery_line
    ADD COLUMN variant_attributes JSONB NOT NULL DEFAULT '[]'::JSONB;

UPDATE crm.inbound_delivery_line
SET variant_attributes = crm.legacy_supplier_goods_attributes(
    variant_value_text,
    variant_unit_code
);

CREATE OR REPLACE FUNCTION crm.populate_legacy_inbound_delivery_line_attributes()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
    IF NEW.variant_attributes = '[]'::JSONB
       AND NEW.variant_unit_code <> 'UNSPECIFIED' THEN
        NEW.variant_attributes := crm.legacy_supplier_goods_attributes(
            NEW.variant_value_text,
            NEW.variant_unit_code
        );
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER trg_inbound_delivery_line_legacy_attributes
    BEFORE INSERT ON crm.inbound_delivery_line
    FOR EACH ROW
    EXECUTE FUNCTION crm.populate_legacy_inbound_delivery_line_attributes();

ALTER TABLE crm.inbound_delivery_line
    ADD CONSTRAINT ck_inbound_delivery_line_variant_attributes
        CHECK (
            JSONB_TYPEOF(variant_attributes) = 'array'
            AND JSONB_ARRAY_LENGTH(variant_attributes) <= 8
        );

COMMENT ON COLUMN crm.supplier_goods_variant.attributes IS
    'Ordered immutable characteristic combination for one operational goods variant.';

COMMENT ON COLUMN crm.supplier_goods_variant.attribute_signature IS
    'Canonical case-insensitive business key of the complete characteristic combination.';

COMMENT ON COLUMN crm.inbound_delivery_line.variant_attributes IS
    'Immutable snapshot of the complete goods-variant characteristic combination.';
