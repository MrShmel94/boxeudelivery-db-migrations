ALTER TABLE crm.cargo_item
    ADD CONSTRAINT uq_cargo_item_id_project_supplier
        UNIQUE (id, project_id, supplier_id);

CREATE TABLE crm.mini_supplier_warehouse_receipt
(
    id                        UUID         NOT NULL,
    project_id                UUID         NOT NULL,
    supplier_id               UUID         NOT NULL,
    supplier_goods_entry_id   UUID         NOT NULL,
    supplier_goods_variant_id UUID         NOT NULL,
    warehouse_id              UUID         NOT NULL,
    received_by_account_id    UUID         NOT NULL,
    received_by_subject       VARCHAR(255) NOT NULL,
    received_at               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_mini_supplier_warehouse_receipt
        PRIMARY KEY (id),
    CONSTRAINT uq_mini_supplier_warehouse_receipt_scope
        UNIQUE (id, project_id, supplier_id),
    CONSTRAINT fk_mini_supplier_warehouse_receipt_entry
        FOREIGN KEY (supplier_goods_entry_id, project_id, supplier_id)
            REFERENCES crm.supplier_goods_entry (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mini_supplier_warehouse_receipt_variant
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
    CONSTRAINT fk_mini_supplier_warehouse_receipt_warehouse
        FOREIGN KEY (warehouse_id) REFERENCES crm.warehouse (id) ON DELETE RESTRICT,
    CONSTRAINT fk_mini_supplier_warehouse_receipt_received_by
        FOREIGN KEY (received_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_mini_supplier_warehouse_receipt_subject_not_blank
        CHECK (BTRIM(received_by_subject) <> '')
);

CREATE INDEX ix_mini_supplier_warehouse_receipt_entry_received
    ON crm.mini_supplier_warehouse_receipt (supplier_goods_entry_id, received_at DESC, id DESC);

CREATE TABLE crm.mini_supplier_warehouse_receipt_item
(
    warehouse_receipt_id UUID        NOT NULL,
    cargo_item_id        UUID        NOT NULL,
    project_id           UUID        NOT NULL,
    supplier_id          UUID        NOT NULL,
    processed_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_mini_supplier_warehouse_receipt_item
        PRIMARY KEY (warehouse_receipt_id, cargo_item_id),
    CONSTRAINT uq_mini_supplier_warehouse_receipt_item_cargo
        UNIQUE (cargo_item_id),
    CONSTRAINT fk_mini_supplier_warehouse_receipt_item_receipt
        FOREIGN KEY (warehouse_receipt_id, project_id, supplier_id)
            REFERENCES crm.mini_supplier_warehouse_receipt (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mini_supplier_warehouse_receipt_item_cargo
        FOREIGN KEY (cargo_item_id, project_id, supplier_id)
            REFERENCES crm.cargo_item (id, project_id, supplier_id) ON DELETE RESTRICT
);

CREATE INDEX ix_mini_supplier_warehouse_receipt_item_receipt
    ON crm.mini_supplier_warehouse_receipt_item (warehouse_receipt_id, processed_at, cargo_item_id);

COMMENT ON TABLE crm.mini_supplier_warehouse_receipt IS
    'Durable batch created when MINI supplier goods are accepted directly at a project warehouse.';

COMMENT ON TABLE crm.mini_supplier_warehouse_receipt_item IS
    'Exact accepted items belonging to one direct MINI warehouse receipt and its repeatable label print batch.';
