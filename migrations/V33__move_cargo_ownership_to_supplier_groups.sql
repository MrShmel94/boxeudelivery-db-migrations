DROP INDEX IF EXISTS crm.ix_inbound_delivery_supplier_created;
DROP INDEX IF EXISTS crm.ix_inbound_delivery_project_supplier_created;
DROP INDEX IF EXISTS crm.ix_supplier_goods_entry_project_supplier_created;
DROP INDEX IF EXISTS crm.ix_cargo_item_supplier_status_created;
DROP INDEX IF EXISTS crm.ix_customer_order_supplier_status;

ALTER TABLE crm.cargo_item
    DROP CONSTRAINT fk_cargo_item_supplier_goods_variant,
    DROP CONSTRAINT fk_cargo_item_supplier_goods,
    DROP CONSTRAINT fk_cargo_item_supplier,
    DROP CONSTRAINT fk_cargo_item_delivery_supplier,
    DROP CONSTRAINT ck_cargo_item_owner_customer;

ALTER TABLE crm.inbound_delivery_line
    DROP CONSTRAINT fk_inbound_delivery_line_supplier_goods_variant,
    DROP CONSTRAINT fk_inbound_delivery_line_delivery_scope,
    DROP CONSTRAINT fk_inbound_delivery_line_supplier_goods,
    DROP CONSTRAINT uq_inbound_delivery_line_id_delivery_project_supplier;

ALTER TABLE crm.supplier_goods_variant
    DROP CONSTRAINT fk_supplier_goods_variant_entry,
    DROP CONSTRAINT uq_supplier_goods_variant_scope;

ALTER TABLE crm.supplier_goods_entry
    DROP CONSTRAINT fk_supplier_goods_entry_supplier,
    DROP CONSTRAINT uq_supplier_goods_entry_id_project_supplier;

ALTER TABLE crm.inbound_delivery
    DROP CONSTRAINT fk_inbound_delivery_supplier,
    DROP CONSTRAINT uq_inbound_delivery_id_project_supplier;

ALTER TABLE crm.customer_order
    DROP CONSTRAINT fk_customer_order_supplier,
    DROP CONSTRAINT ck_customer_order_distinct_parties;

ALTER TABLE crm.supplier_goods_entry
    RENAME COLUMN supplier_account_id TO supplier_id;

ALTER TABLE crm.supplier_goods_variant
    RENAME COLUMN supplier_account_id TO supplier_id;

ALTER TABLE crm.inbound_delivery
    RENAME COLUMN supplier_account_id TO supplier_id;

ALTER TABLE crm.inbound_delivery_line
    RENAME COLUMN supplier_account_id TO supplier_id;

ALTER TABLE crm.cargo_item
    RENAME COLUMN supplier_account_id TO supplier_id;

ALTER TABLE crm.customer_order
    RENAME COLUMN supplier_account_id TO supplier_id;

UPDATE crm.supplier_goods_entry
SET supplier_id = MD5('boxeudelivery:supplier:' || supplier_id::TEXT)::UUID;

UPDATE crm.supplier_goods_variant
SET supplier_id = MD5('boxeudelivery:supplier:' || supplier_id::TEXT)::UUID;

UPDATE crm.inbound_delivery
SET supplier_id = MD5('boxeudelivery:supplier:' || supplier_id::TEXT)::UUID;

UPDATE crm.inbound_delivery_line
SET supplier_id = MD5('boxeudelivery:supplier:' || supplier_id::TEXT)::UUID;

UPDATE crm.cargo_item
SET supplier_id = MD5('boxeudelivery:supplier:' || supplier_id::TEXT)::UUID;

UPDATE crm.customer_order
SET supplier_id = MD5('boxeudelivery:supplier:' || supplier_id::TEXT)::UUID;

ALTER TABLE crm.supplier_goods_entry
    ADD CONSTRAINT uq_supplier_goods_entry_id_project_supplier
        UNIQUE (id, project_id, supplier_id),
    ADD CONSTRAINT fk_supplier_goods_entry_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT;

ALTER TABLE crm.supplier_goods_variant
    ADD CONSTRAINT uq_supplier_goods_variant_scope
        UNIQUE (id, supplier_goods_entry_id, project_id, supplier_id),
    ADD CONSTRAINT fk_supplier_goods_variant_entry
        FOREIGN KEY (supplier_goods_entry_id, project_id, supplier_id)
            REFERENCES crm.supplier_goods_entry (id, project_id, supplier_id) ON DELETE RESTRICT;

ALTER TABLE crm.inbound_delivery
    ADD CONSTRAINT uq_inbound_delivery_id_project_supplier
        UNIQUE (id, project_id, supplier_id),
    ADD CONSTRAINT fk_inbound_delivery_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT;

ALTER TABLE crm.inbound_delivery_line
    ADD CONSTRAINT uq_inbound_delivery_line_id_delivery_project_supplier
        UNIQUE (id, inbound_delivery_id, project_id, supplier_id),
    ADD CONSTRAINT fk_inbound_delivery_line_delivery_scope
        FOREIGN KEY (inbound_delivery_id, project_id, supplier_id)
            REFERENCES crm.inbound_delivery (id, project_id, supplier_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_inbound_delivery_line_supplier_goods
        FOREIGN KEY (supplier_goods_entry_id, project_id, supplier_id)
            REFERENCES crm.supplier_goods_entry (id, project_id, supplier_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_inbound_delivery_line_supplier_goods_variant
        FOREIGN KEY (
            supplier_goods_variant_id,
            supplier_goods_entry_id,
            project_id,
            supplier_id
        ) REFERENCES crm.supplier_goods_variant (
            id,
            supplier_goods_entry_id,
            project_id,
            supplier_id
        ) ON DELETE RESTRICT;

ALTER TABLE crm.cargo_item
    ADD CONSTRAINT fk_cargo_item_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargo_item_supplier_goods
        FOREIGN KEY (supplier_goods_entry_id, project_id, supplier_id)
            REFERENCES crm.supplier_goods_entry (id, project_id, supplier_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargo_item_supplier_goods_variant
        FOREIGN KEY (
            supplier_goods_variant_id,
            supplier_goods_entry_id,
            project_id,
            supplier_id
        ) REFERENCES crm.supplier_goods_variant (
            id,
            supplier_goods_entry_id,
            project_id,
            supplier_id
        ) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargo_item_delivery_supplier
        FOREIGN KEY (inbound_delivery_id, project_id, supplier_id)
            REFERENCES crm.inbound_delivery (id, project_id, supplier_id) ON DELETE RESTRICT;

ALTER TABLE crm.customer_order
    ADD CONSTRAINT fk_customer_order_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT;

CREATE INDEX ix_inbound_delivery_supplier_created
    ON crm.inbound_delivery (supplier_id, created_at DESC, id);

CREATE INDEX ix_inbound_delivery_project_supplier_created
    ON crm.inbound_delivery (project_id, supplier_id, created_at DESC, id);

CREATE INDEX ix_supplier_goods_entry_project_supplier_created
    ON crm.supplier_goods_entry (project_id, supplier_id, created_at DESC, id);

CREATE INDEX ix_cargo_item_supplier_status_created
    ON crm.cargo_item (project_id, supplier_id, status_code, created_at DESC, id);

CREATE INDEX ix_customer_order_supplier_status
    ON crm.customer_order (supplier_id, status_code, created_at DESC, id);

ALTER TABLE crm.cargo_item_financial_entry
    ADD COLUMN charged_supplier_id UUID;

ALTER TABLE crm.cargo_item_financial_revision
    ADD COLUMN charged_supplier_id UUID;

UPDATE crm.cargo_item_financial_entry entry
SET charged_supplier_id = item.supplier_id,
    charged_account_id = NULL
FROM crm.cargo_item item
WHERE item.id = entry.cargo_item_id
  AND entry.entry_type = 'COMPANY_SERVICE_FEE'
  AND entry.charged_party = 'SUPPLIER';

UPDATE crm.cargo_item_financial_revision revision
SET charged_supplier_id = item.supplier_id,
    charged_account_id = NULL
FROM crm.cargo_item item
WHERE item.id = revision.cargo_item_id
  AND revision.entry_type = 'COMPANY_SERVICE_FEE'
  AND revision.charged_party = 'SUPPLIER';

ALTER TABLE crm.cargo_item_financial_entry
    DROP CONSTRAINT ck_cargo_item_financial_entry_charge,
    ADD CONSTRAINT fk_cargo_item_financial_entry_charged_supplier
        FOREIGN KEY (project_id, charged_supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_cargo_item_financial_entry_charge
        CHECK (
            (
                entry_type = 'COMPANY_SERVICE_FEE'
                AND charged_party = 'CUSTOMER'
                AND charged_account_id IS NOT NULL
                AND charged_supplier_id IS NULL
            )
            OR (
                entry_type = 'COMPANY_SERVICE_FEE'
                AND charged_party = 'SUPPLIER'
                AND charged_account_id IS NULL
                AND charged_supplier_id IS NOT NULL
            )
            OR (
                entry_type <> 'COMPANY_SERVICE_FEE'
                AND charged_party IS NULL
                AND charged_account_id IS NULL
                AND charged_supplier_id IS NULL
            )
        );

ALTER TABLE crm.cargo_item_financial_revision
    DROP CONSTRAINT ck_cargo_item_financial_revision_charge,
    ADD CONSTRAINT fk_cargo_item_financial_revision_charged_supplier
        FOREIGN KEY (project_id, charged_supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_cargo_item_financial_revision_charge
        CHECK (
            (
                entry_type = 'COMPANY_SERVICE_FEE'
                AND charged_party = 'CUSTOMER'
                AND charged_account_id IS NOT NULL
                AND charged_supplier_id IS NULL
            )
            OR (
                entry_type = 'COMPANY_SERVICE_FEE'
                AND charged_party = 'SUPPLIER'
                AND charged_account_id IS NULL
                AND charged_supplier_id IS NOT NULL
            )
            OR (
                entry_type <> 'COMPANY_SERVICE_FEE'
                AND charged_party IS NULL
                AND charged_account_id IS NULL
                AND charged_supplier_id IS NULL
            )
        );

CREATE INDEX ix_cargo_item_financial_entry_charged_supplier
    ON crm.cargo_item_financial_entry (project_id, charged_supplier_id, updated_at DESC, id)
    WHERE charged_supplier_id IS NOT NULL;

CREATE INDEX ix_cargo_item_financial_revision_charged_supplier
    ON crm.cargo_item_financial_revision (project_id, charged_supplier_id, occurred_at DESC, id)
    WHERE charged_supplier_id IS NOT NULL;

COMMENT ON COLUMN crm.cargo_item.supplier_id IS
    'Immutable supplier-group owner of the physical cargo item inside the project.';

COMMENT ON COLUMN crm.cargo_item_financial_entry.charged_supplier_id IS
    'Exact project supplier charged when a company service fee targets the supplier party.';
