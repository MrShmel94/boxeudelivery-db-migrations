CREATE TABLE crm.supplier_goods_entry
(
    id                       UUID          NOT NULL,
    project_id               UUID          NOT NULL,
    supplier_account_id      UUID          NOT NULL,
    name                     VARCHAR(150)  NOT NULL,
    description              VARCHAR(2000),
    supplier_sku             VARCHAR(100),
    ean                      VARCHAR(13),
    manufacturer_article     VARCHAR(100),
    created_by_subject       VARCHAR(255)  NOT NULL,
    updated_by_subject       VARCHAR(255)  NOT NULL,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                  BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_supplier_goods_entry
        PRIMARY KEY (id),
    CONSTRAINT uq_supplier_goods_entry_id_project_supplier
        UNIQUE (id, project_id, supplier_account_id),
    CONSTRAINT fk_supplier_goods_entry_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_supplier_goods_entry_supplier
        FOREIGN KEY (supplier_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_supplier_goods_entry_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_supplier_goods_entry_description_not_blank
        CHECK (description IS NULL OR BTRIM(description) <> ''),
    CONSTRAINT ck_supplier_goods_entry_supplier_sku_not_blank
        CHECK (supplier_sku IS NULL OR BTRIM(supplier_sku) <> ''),
    CONSTRAINT ck_supplier_goods_entry_ean
        CHECK (ean IS NULL OR ean ~ '^([0-9]{8}|[0-9]{13})$'),
    CONSTRAINT ck_supplier_goods_entry_manufacturer_article_not_blank
        CHECK (manufacturer_article IS NULL OR BTRIM(manufacturer_article) <> ''),
    CONSTRAINT ck_supplier_goods_entry_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_supplier_goods_entry_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_supplier_goods_entry_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_supplier_goods_entry_version
        CHECK (version >= 0)
);

CREATE INDEX ix_supplier_goods_entry_project_supplier_created
    ON crm.supplier_goods_entry (project_id, supplier_account_id, created_at DESC, id);

CREATE INDEX ix_supplier_goods_entry_search
    ON crm.supplier_goods_entry (project_id, name, supplier_sku, ean, manufacturer_article);

INSERT INTO crm.supplier_goods_entry
(
    id,
    project_id,
    supplier_account_id,
    name,
    description,
    supplier_sku,
    ean,
    manufacturer_article,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at,
    version
)
SELECT line.id,
       delivery.project_id,
       delivery.supplier_account_id,
       line.name,
       line.description,
       line.supplier_sku,
       line.ean,
       line.manufacturer_article,
       line.created_by_subject,
       line.updated_by_subject,
       line.created_at,
       line.updated_at,
       line.version
FROM crm.inbound_delivery_line line
JOIN crm.inbound_delivery delivery ON delivery.id = line.inbound_delivery_id;

ALTER TABLE crm.inbound_delivery
    ADD COLUMN dispatched_at TIMESTAMPTZ,
    ADD CONSTRAINT uq_inbound_delivery_id_project_supplier
        UNIQUE (id, project_id, supplier_account_id),
    DROP CONSTRAINT ck_inbound_delivery_status;

UPDATE crm.inbound_delivery
SET status_code = 'IN_TRANSIT',
    dispatched_at = created_at
WHERE status_code = 'DECLARED';

ALTER TABLE crm.inbound_delivery
    ADD CONSTRAINT ck_inbound_delivery_status
        CHECK (status_code IN ('DRAFT', 'IN_TRANSIT', 'PARTIALLY_RECEIVED', 'COMPLETED', 'CANCELLED')),
    ADD CONSTRAINT ck_inbound_delivery_dispatch_state
        CHECK (
            (status_code IN ('DRAFT', 'CANCELLED') AND dispatched_at IS NULL)
            OR (status_code IN ('IN_TRANSIT', 'PARTIALLY_RECEIVED', 'COMPLETED') AND dispatched_at IS NOT NULL)
        );

ALTER TABLE crm.inbound_delivery_line
    ADD COLUMN supplier_goods_entry_id UUID,
    ADD COLUMN project_id UUID,
    ADD COLUMN supplier_account_id UUID;

UPDATE crm.inbound_delivery_line line
SET supplier_goods_entry_id = line.id,
    project_id = delivery.project_id,
    supplier_account_id = delivery.supplier_account_id
FROM crm.inbound_delivery delivery
WHERE delivery.id = line.inbound_delivery_id;

ALTER TABLE crm.inbound_delivery_line
    ALTER COLUMN supplier_goods_entry_id SET NOT NULL,
    ALTER COLUMN project_id SET NOT NULL,
    ALTER COLUMN supplier_account_id SET NOT NULL,
    ADD CONSTRAINT uq_inbound_delivery_line_id_delivery_project_supplier
        UNIQUE (id, inbound_delivery_id, project_id, supplier_account_id),
    ADD CONSTRAINT fk_inbound_delivery_line_delivery_scope
        FOREIGN KEY (inbound_delivery_id, project_id, supplier_account_id)
            REFERENCES crm.inbound_delivery (id, project_id, supplier_account_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_inbound_delivery_line_supplier_goods
        FOREIGN KEY (supplier_goods_entry_id, project_id, supplier_account_id)
            REFERENCES crm.supplier_goods_entry (id, project_id, supplier_account_id) ON DELETE RESTRICT;

CREATE INDEX ix_inbound_delivery_line_supplier_goods
    ON crm.inbound_delivery_line (supplier_goods_entry_id, inbound_delivery_id, id);

ALTER TABLE crm.cargo_item
    ADD COLUMN supplier_goods_entry_id UUID,
    ADD COLUMN supplier_account_id UUID,
    ADD COLUMN customer_account_id UUID;

UPDATE crm.cargo_item item
SET supplier_goods_entry_id = item.inbound_delivery_line_id,
    supplier_account_id = delivery.supplier_account_id
FROM crm.inbound_delivery delivery
WHERE delivery.id = item.inbound_delivery_id;

ALTER TABLE crm.cargo_item
    DROP CONSTRAINT ck_cargo_item_origin,
    DROP CONSTRAINT ck_cargo_item_status,
    DROP CONSTRAINT ck_cargo_item_availability_state;

UPDATE crm.cargo_item
SET origin_code = 'SUPPLIER'
WHERE origin_code = 'DECLARED';

UPDATE crm.cargo_item
SET status_code = 'IN_TRANSIT'
WHERE status_code = 'DECLARED';

ALTER TABLE crm.cargo_item
    ALTER COLUMN inbound_delivery_id DROP NOT NULL,
    ALTER COLUMN inbound_delivery_line_id DROP NOT NULL,
    ALTER COLUMN supplier_goods_entry_id SET NOT NULL,
    ALTER COLUMN supplier_account_id SET NOT NULL,
    ADD CONSTRAINT fk_cargo_item_supplier_goods
        FOREIGN KEY (supplier_goods_entry_id, project_id, supplier_account_id)
            REFERENCES crm.supplier_goods_entry (id, project_id, supplier_account_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargo_item_supplier
        FOREIGN KEY (supplier_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargo_item_customer
        FOREIGN KEY (customer_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargo_item_delivery_supplier
        FOREIGN KEY (inbound_delivery_id, project_id, supplier_account_id)
            REFERENCES crm.inbound_delivery (id, project_id, supplier_account_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_cargo_item_owner_customer
        CHECK (customer_account_id IS NULL OR customer_account_id <> supplier_account_id),
    ADD CONSTRAINT ck_cargo_item_origin
        CHECK (origin_code IN ('SUPPLIER', 'SURPLUS')),
    ADD CONSTRAINT ck_cargo_item_status
        CHECK (status_code IN (
            'EXPECTED_AT_SUPPLIER',
            'AT_SUPPLIER',
            'RESERVED_FOR_DELIVERY',
            'IN_TRANSIT',
            'AVAILABLE',
            'MISSING',
            'DAMAGED',
            'REJECTED',
            'CANCELLED'
        )),
    ADD CONSTRAINT ck_cargo_item_delivery_assignment
        CHECK (
            (
                status_code IN ('EXPECTED_AT_SUPPLIER', 'AT_SUPPLIER', 'CANCELLED')
                AND inbound_delivery_id IS NULL
                AND inbound_delivery_line_id IS NULL
            )
            OR (
                status_code IN (
                    'RESERVED_FOR_DELIVERY',
                    'IN_TRANSIT',
                    'AVAILABLE',
                    'MISSING',
                    'DAMAGED',
                    'REJECTED'
                )
                AND inbound_delivery_id IS NOT NULL
                AND inbound_delivery_line_id IS NOT NULL
            )
        ),
    ADD CONSTRAINT ck_cargo_item_availability_state
        CHECK (
            (
                status_code = 'AVAILABLE'
                AND label_code IS NOT NULL
                AND current_warehouse_id IS NOT NULL
                AND accepted_by_account_id IS NOT NULL
                AND accepted_at IS NOT NULL
            ) OR (
                status_code <> 'AVAILABLE'
                AND label_code IS NULL
                AND current_warehouse_id IS NULL
                AND accepted_by_account_id IS NULL
                AND accepted_at IS NULL
            )
        );

CREATE INDEX ix_cargo_item_supplier_status_created
    ON crm.cargo_item (project_id, supplier_account_id, status_code, created_at DESC, id);

CREATE INDEX ix_cargo_item_customer_status_created
    ON crm.cargo_item (project_id, customer_account_id, status_code, created_at DESC, id)
    WHERE customer_account_id IS NOT NULL;

CREATE INDEX ix_cargo_item_supplier_goods_status
    ON crm.cargo_item (supplier_goods_entry_id, status_code, created_at, id);

ALTER TABLE crm.cargo_audit_event
    DROP CONSTRAINT ck_cargo_audit_event_aggregate_type,
    ADD CONSTRAINT ck_cargo_audit_event_aggregate_type
        CHECK (aggregate_type IN ('SUPPLIER_GOODS', 'INBOUND_DELIVERY', 'CARGO_ITEM', 'CARGO_PHOTO'));

COMMENT ON TABLE crm.supplier_goods_entry IS
    'Shared supplier-owned description for individually tracked goods before and across inbound deliveries.';

COMMENT ON COLUMN crm.cargo_item.supplier_account_id IS
    'Immutable supplier owner of the physical cargo item.';

COMMENT ON COLUMN crm.cargo_item.customer_account_id IS
    'Optional exact customer assignment granting read visibility without changing supplier ownership.';

COMMENT ON COLUMN crm.inbound_delivery.dispatched_at IS
    'Instant when the immutable draft composition physically left supplier custody for the target warehouse.';
