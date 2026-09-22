ALTER TABLE crm.border_tariff_subcategory
    ADD COLUMN deleted_by_subject VARCHAR(255),
    ADD COLUMN deleted_at TIMESTAMPTZ,
    DROP CONSTRAINT uq_border_tariff_subcategory_code,
    DROP CONSTRAINT uq_border_tariff_subcategory_name,
    ADD CONSTRAINT ck_border_tariff_subcategory_deletion CHECK (
        (deleted_by_subject IS NULL AND deleted_at IS NULL)
        OR (
            deleted_by_subject IS NOT NULL
            AND BTRIM(deleted_by_subject) <> ''
            AND deleted_at IS NOT NULL
            AND deleted_at >= created_at
            AND NOT active
        )
    );

CREATE UNIQUE INDEX uq_border_tariff_subcategory_code
    ON crm.border_tariff_subcategory (code)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_border_tariff_subcategory_name
    ON crm.border_tariff_subcategory (category_id, display_name)
    WHERE deleted_at IS NULL;

DROP INDEX crm.ix_border_tariff_subcategory_category;

CREATE INDEX ix_border_tariff_subcategory_category
    ON crm.border_tariff_subcategory (category_id, active, display_order, display_name, id)
    WHERE deleted_at IS NULL;

COMMENT ON COLUMN crm.border_tariff_subcategory.deleted_at IS
    'Logical deletion time for an unused tariff subcategory; historical published policy rows remain immutable.';
