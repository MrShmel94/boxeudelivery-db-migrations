CREATE TABLE crm.inbound_delivery
(
    id                  UUID         NOT NULL,
    project_id          UUID         NOT NULL,
    supplier_account_id UUID         NOT NULL,
    target_warehouse_id UUID         NOT NULL,
    status_code         VARCHAR(32)  NOT NULL,
    created_by_subject  VARCHAR(255) NOT NULL,
    updated_by_subject  VARCHAR(255) NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version             BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_inbound_delivery
        PRIMARY KEY (id),
    CONSTRAINT uq_inbound_delivery_id_project
        UNIQUE (id, project_id),
    CONSTRAINT uq_inbound_delivery_id_project_warehouse
        UNIQUE (id, project_id, target_warehouse_id),
    CONSTRAINT fk_inbound_delivery_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_inbound_delivery_supplier
        FOREIGN KEY (supplier_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_inbound_delivery_project_warehouse
        FOREIGN KEY (project_id, target_warehouse_id)
            REFERENCES crm.project_warehouse (project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT ck_inbound_delivery_status
        CHECK (status_code IN ('DECLARED', 'PARTIALLY_RECEIVED', 'COMPLETED')),
    CONSTRAINT ck_inbound_delivery_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_inbound_delivery_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_inbound_delivery_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_inbound_delivery_version
        CHECK (version >= 0)
);

CREATE INDEX ix_inbound_delivery_project_created
    ON crm.inbound_delivery (project_id, created_at DESC, id);

CREATE INDEX ix_inbound_delivery_supplier_created
    ON crm.inbound_delivery (supplier_account_id, created_at DESC, id);

CREATE TABLE crm.inbound_delivery_line
(
    id                       UUID          NOT NULL,
    inbound_delivery_id      UUID          NOT NULL,
    copied_from_line_id      UUID,
    name                     VARCHAR(150)  NOT NULL,
    description              VARCHAR(2000),
    declared_quantity        INTEGER       NOT NULL,
    supplier_sku             VARCHAR(100),
    ean                      VARCHAR(13),
    manufacturer_article     VARCHAR(100),
    created_by_subject       VARCHAR(255)  NOT NULL,
    updated_by_subject       VARCHAR(255)  NOT NULL,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                  BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_inbound_delivery_line
        PRIMARY KEY (id),
    CONSTRAINT uq_inbound_delivery_line_id_delivery
        UNIQUE (id, inbound_delivery_id),
    CONSTRAINT fk_inbound_delivery_line_delivery
        FOREIGN KEY (inbound_delivery_id) REFERENCES crm.inbound_delivery (id) ON DELETE RESTRICT,
    CONSTRAINT fk_inbound_delivery_line_copied_from
        FOREIGN KEY (copied_from_line_id) REFERENCES crm.inbound_delivery_line (id) ON DELETE RESTRICT,
    CONSTRAINT ck_inbound_delivery_line_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_inbound_delivery_line_description_not_blank
        CHECK (description IS NULL OR BTRIM(description) <> ''),
    CONSTRAINT ck_inbound_delivery_line_quantity
        CHECK (declared_quantity BETWEEN 1 AND 10000),
    CONSTRAINT ck_inbound_delivery_line_supplier_sku_not_blank
        CHECK (supplier_sku IS NULL OR BTRIM(supplier_sku) <> ''),
    CONSTRAINT ck_inbound_delivery_line_ean
        CHECK (ean IS NULL OR ean ~ '^([0-9]{8}|[0-9]{13})$'),
    CONSTRAINT ck_inbound_delivery_line_manufacturer_article_not_blank
        CHECK (manufacturer_article IS NULL OR BTRIM(manufacturer_article) <> ''),
    CONSTRAINT ck_inbound_delivery_line_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_inbound_delivery_line_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_inbound_delivery_line_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_inbound_delivery_line_version
        CHECK (version >= 0)
);

CREATE INDEX ix_inbound_delivery_line_delivery_created
    ON crm.inbound_delivery_line (inbound_delivery_id, created_at, id);

CREATE INDEX ix_inbound_delivery_line_supplier_sku
    ON crm.inbound_delivery_line (supplier_sku)
    WHERE supplier_sku IS NOT NULL;

CREATE INDEX ix_inbound_delivery_line_ean
    ON crm.inbound_delivery_line (ean)
    WHERE ean IS NOT NULL;

CREATE TABLE crm.cargo_item
(
    id                       UUID         NOT NULL,
    project_id               UUID         NOT NULL,
    inbound_delivery_id      UUID         NOT NULL,
    inbound_delivery_line_id UUID         NOT NULL,
    origin_code              VARCHAR(16)  NOT NULL,
    status_code              VARCHAR(32)  NOT NULL,
    serial_number            VARCHAR(150),
    label_code               VARCHAR(64),
    current_warehouse_id     UUID,
    accepted_by_account_id   UUID,
    accepted_at              TIMESTAMPTZ,
    created_by_subject       VARCHAR(255) NOT NULL,
    updated_by_subject       VARCHAR(255) NOT NULL,
    created_at               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                  BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_cargo_item
        PRIMARY KEY (id),
    CONSTRAINT uq_cargo_item_id_delivery
        UNIQUE (id, inbound_delivery_id),
    CONSTRAINT uq_cargo_item_id_project
        UNIQUE (id, project_id),
    CONSTRAINT fk_cargo_item_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_delivery_project
        FOREIGN KEY (inbound_delivery_id, project_id)
            REFERENCES crm.inbound_delivery (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_line_delivery
        FOREIGN KEY (inbound_delivery_line_id, inbound_delivery_id)
            REFERENCES crm.inbound_delivery_line (id, inbound_delivery_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_current_project_warehouse
        FOREIGN KEY (project_id, current_warehouse_id)
            REFERENCES crm.project_warehouse (project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_accepted_by
        FOREIGN KEY (accepted_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_item_origin
        CHECK (origin_code IN ('DECLARED', 'SURPLUS')),
    CONSTRAINT ck_cargo_item_status
        CHECK (status_code IN ('DECLARED', 'AVAILABLE', 'MISSING', 'DAMAGED', 'REJECTED')),
    CONSTRAINT ck_cargo_item_serial_not_blank
        CHECK (serial_number IS NULL OR BTRIM(serial_number) <> ''),
    CONSTRAINT ck_cargo_item_label_not_blank
        CHECK (label_code IS NULL OR BTRIM(label_code) <> ''),
    CONSTRAINT ck_cargo_item_availability_state
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
        ),
    CONSTRAINT ck_cargo_item_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_cargo_item_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_cargo_item_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_cargo_item_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_cargo_item_serial_number_case_insensitive
    ON crm.cargo_item (UPPER(BTRIM(serial_number)))
    WHERE serial_number IS NOT NULL;

CREATE UNIQUE INDEX uq_cargo_item_label_code_case_insensitive
    ON crm.cargo_item (UPPER(BTRIM(label_code)))
    WHERE label_code IS NOT NULL;

CREATE INDEX ix_cargo_item_project_status_created
    ON crm.cargo_item (project_id, status_code, created_at DESC, id);

CREATE INDEX ix_cargo_item_delivery_line_status
    ON crm.cargo_item (inbound_delivery_line_id, status_code, id);

CREATE INDEX ix_cargo_item_warehouse_status
    ON crm.cargo_item (current_warehouse_id, status_code, id)
    WHERE current_warehouse_id IS NOT NULL;

CREATE TABLE crm.warehouse_receipt
(
    id                     UUID         NOT NULL,
    inbound_delivery_id    UUID         NOT NULL,
    project_id             UUID         NOT NULL,
    warehouse_id           UUID         NOT NULL,
    received_by_account_id UUID         NOT NULL,
    completes_delivery     BOOLEAN      NOT NULL,
    received_by_subject    VARCHAR(255) NOT NULL,
    received_at            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_warehouse_receipt
        PRIMARY KEY (id),
    CONSTRAINT uq_warehouse_receipt_id_delivery
        UNIQUE (id, inbound_delivery_id),
    CONSTRAINT fk_warehouse_receipt_delivery_project_warehouse
        FOREIGN KEY (inbound_delivery_id, project_id, warehouse_id)
            REFERENCES crm.inbound_delivery (id, project_id, target_warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_receipt_received_by
        FOREIGN KEY (received_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_warehouse_receipt_subject_not_blank
        CHECK (BTRIM(received_by_subject) <> '')
);

CREATE INDEX ix_warehouse_receipt_delivery_received
    ON crm.warehouse_receipt (inbound_delivery_id, received_at DESC, id);

CREATE TABLE crm.warehouse_receipt_item
(
    warehouse_receipt_id UUID        NOT NULL,
    cargo_item_id        UUID        NOT NULL,
    inbound_delivery_id  UUID        NOT NULL,
    outcome_code         VARCHAR(32) NOT NULL,
    processed_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_warehouse_receipt_item
        PRIMARY KEY (warehouse_receipt_id, cargo_item_id),
    CONSTRAINT uq_warehouse_receipt_item_cargo
        UNIQUE (cargo_item_id),
    CONSTRAINT fk_warehouse_receipt_item_receipt_delivery
        FOREIGN KEY (warehouse_receipt_id, inbound_delivery_id)
            REFERENCES crm.warehouse_receipt (id, inbound_delivery_id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_receipt_item_cargo_delivery
        FOREIGN KEY (cargo_item_id, inbound_delivery_id)
            REFERENCES crm.cargo_item (id, inbound_delivery_id) ON DELETE RESTRICT,
    CONSTRAINT ck_warehouse_receipt_item_outcome
        CHECK (outcome_code IN ('ACCEPTED', 'MISSING', 'DAMAGED', 'REJECTED', 'SURPLUS_ACCEPTED'))
);

CREATE INDEX ix_warehouse_receipt_item_receipt_outcome
    ON crm.warehouse_receipt_item (warehouse_receipt_id, outcome_code, cargo_item_id);

CREATE TABLE crm.inventory_movement
(
    id                       UUID         NOT NULL,
    cargo_item_id            UUID         NOT NULL,
    project_id               UUID         NOT NULL,
    movement_type            VARCHAR(32)  NOT NULL,
    from_warehouse_id        UUID,
    to_warehouse_id          UUID,
    actor_subject            VARCHAR(255) NOT NULL,
    occurred_at              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    details                  JSONB        NOT NULL DEFAULT '{}'::JSONB,
    CONSTRAINT pk_inventory_movement
        PRIMARY KEY (id),
    CONSTRAINT fk_inventory_movement_cargo_project
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_inventory_movement_from_project_warehouse
        FOREIGN KEY (project_id, from_warehouse_id)
            REFERENCES crm.project_warehouse (project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_inventory_movement_to_project_warehouse
        FOREIGN KEY (project_id, to_warehouse_id)
            REFERENCES crm.project_warehouse (project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_movement_type
        CHECK (movement_type IN ('RECEIVED')),
    CONSTRAINT ck_inventory_movement_received_warehouses
        CHECK (movement_type <> 'RECEIVED' OR (from_warehouse_id IS NULL AND to_warehouse_id IS NOT NULL)),
    CONSTRAINT ck_inventory_movement_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_inventory_movement_details_object
        CHECK (jsonb_typeof(details) = 'object')
);

CREATE UNIQUE INDEX uq_inventory_movement_received_cargo
    ON crm.inventory_movement (cargo_item_id)
    WHERE movement_type = 'RECEIVED';

CREATE INDEX ix_inventory_movement_cargo_occurred
    ON crm.inventory_movement (cargo_item_id, occurred_at DESC, id);

CREATE TABLE crm.cargo_item_photo
(
    id                       UUID          NOT NULL,
    cargo_item_id            UUID          NOT NULL,
    uploader_account_id      UUID          NOT NULL,
    status_code              VARCHAR(32)   NOT NULL,
    position                 SMALLINT      NOT NULL,
    original_filename        VARCHAR(255)  NOT NULL,
    declared_content_type    VARCHAR(255)  NOT NULL,
    declared_size_bytes      BIGINT        NOT NULL,
    declared_checksum_sha256 VARCHAR(44)   NOT NULL,
    original_object_key      VARCHAR(1024) NOT NULL,
    upload_expires_at        TIMESTAMPTZ   NOT NULL,
    upload_completed_at      TIMESTAMPTZ,
    ready_at                 TIMESTAMPTZ,
    failure_code             VARCHAR(64),
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                  BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_cargo_item_photo
        PRIMARY KEY (id),
    CONSTRAINT uq_cargo_item_photo_position
        UNIQUE (cargo_item_id, position),
    CONSTRAINT uq_cargo_item_photo_original_object_key
        UNIQUE (original_object_key),
    CONSTRAINT fk_cargo_item_photo_item
        FOREIGN KEY (cargo_item_id) REFERENCES crm.cargo_item (id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_photo_uploader
        FOREIGN KEY (uploader_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_item_photo_status
        CHECK (status_code IN ('PENDING_UPLOAD', 'PROCESSING', 'READY', 'FAILED')),
    CONSTRAINT ck_cargo_item_photo_position
        CHECK (position BETWEEN 0 AND 9),
    CONSTRAINT ck_cargo_item_photo_filename_not_blank
        CHECK (BTRIM(original_filename) <> ''),
    CONSTRAINT ck_cargo_item_photo_content_type
        CHECK (declared_content_type IN ('image/jpeg', 'image/png')),
    CONSTRAINT ck_cargo_item_photo_size
        CHECK (declared_size_bytes BETWEEN 1 AND 15728640),
    CONSTRAINT ck_cargo_item_photo_checksum
        CHECK (LENGTH(declared_checksum_sha256) = 44),
    CONSTRAINT ck_cargo_item_photo_object_key_not_blank
        CHECK (BTRIM(original_object_key) <> ''),
    CONSTRAINT ck_cargo_item_photo_upload_expiry
        CHECK (upload_expires_at > created_at),
    CONSTRAINT ck_cargo_item_photo_completed_at
        CHECK (upload_completed_at IS NULL OR upload_completed_at >= created_at),
    CONSTRAINT ck_cargo_item_photo_ready_at
        CHECK (ready_at IS NULL OR (upload_completed_at IS NOT NULL AND ready_at >= upload_completed_at)),
    CONSTRAINT ck_cargo_item_photo_failure
        CHECK ((status_code = 'FAILED') = (failure_code IS NOT NULL)),
    CONSTRAINT ck_cargo_item_photo_version
        CHECK (version >= 0)
);

CREATE INDEX ix_cargo_item_photo_item_position
    ON crm.cargo_item_photo (cargo_item_id, position, id);

CREATE INDEX ix_cargo_item_photo_pending_expiry
    ON crm.cargo_item_photo (upload_expires_at, id)
    WHERE status_code = 'PENDING_UPLOAD';

CREATE TABLE crm.cargo_item_photo_object
(
    photo_id        UUID          NOT NULL,
    variant_code    VARCHAR(16)   NOT NULL,
    object_key      VARCHAR(1024) NOT NULL,
    content_type    VARCHAR(255)  NOT NULL,
    size_bytes      BIGINT        NOT NULL,
    checksum_sha256 VARCHAR(44),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_cargo_item_photo_object
        PRIMARY KEY (photo_id, variant_code),
    CONSTRAINT uq_cargo_item_photo_object_key
        UNIQUE (object_key),
    CONSTRAINT fk_cargo_item_photo_object_photo
        FOREIGN KEY (photo_id) REFERENCES crm.cargo_item_photo (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_item_photo_object_variant
        CHECK (variant_code IN ('ORIGINAL', 'PREVIEW')),
    CONSTRAINT ck_cargo_item_photo_object_key_not_blank
        CHECK (BTRIM(object_key) <> ''),
    CONSTRAINT ck_cargo_item_photo_object_content_type_not_blank
        CHECK (BTRIM(content_type) <> ''),
    CONSTRAINT ck_cargo_item_photo_object_size
        CHECK (size_bytes > 0),
    CONSTRAINT ck_cargo_item_photo_object_checksum
        CHECK (checksum_sha256 IS NULL OR LENGTH(checksum_sha256) = 44)
);

CREATE TABLE crm.cargo_photo_processing_job
(
    id              UUID        NOT NULL,
    photo_id        UUID        NOT NULL,
    status_code     VARCHAR(16) NOT NULL,
    attempt_count   INTEGER     NOT NULL DEFAULT 0,
    not_before      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    locked_at       TIMESTAMPTZ,
    locked_by       VARCHAR(128),
    last_error_code VARCHAR(64),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_cargo_photo_processing_job
        PRIMARY KEY (id),
    CONSTRAINT uq_cargo_photo_processing_job_photo
        UNIQUE (photo_id),
    CONSTRAINT fk_cargo_photo_processing_job_photo
        FOREIGN KEY (photo_id) REFERENCES crm.cargo_item_photo (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_photo_processing_job_status
        CHECK (status_code IN ('PENDING', 'RUNNING', 'DONE', 'FAILED')),
    CONSTRAINT ck_cargo_photo_processing_job_attempt_count
        CHECK (attempt_count >= 0),
    CONSTRAINT ck_cargo_photo_processing_job_lock
        CHECK (
            (status_code = 'RUNNING' AND locked_at IS NOT NULL AND locked_by IS NOT NULL)
            OR (status_code <> 'RUNNING' AND locked_at IS NULL AND locked_by IS NULL)
        ),
    CONSTRAINT ck_cargo_photo_processing_job_timestamps
        CHECK (updated_at >= created_at)
);

CREATE INDEX ix_cargo_photo_processing_job_claim
    ON crm.cargo_photo_processing_job (not_before, created_at, id)
    WHERE status_code IN ('PENDING', 'RUNNING');

CREATE TABLE crm.cargo_audit_event
(
    id             UUID         NOT NULL,
    aggregate_type VARCHAR(32)  NOT NULL,
    aggregate_id   UUID         NOT NULL,
    project_id     UUID         NOT NULL,
    event_type     VARCHAR(64)  NOT NULL,
    actor_subject  VARCHAR(255) NOT NULL,
    details        JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at    TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_cargo_audit_event
        PRIMARY KEY (id),
    CONSTRAINT fk_cargo_audit_event_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_audit_event_aggregate_type
        CHECK (aggregate_type IN ('INBOUND_DELIVERY', 'CARGO_ITEM', 'CARGO_PHOTO')),
    CONSTRAINT ck_cargo_audit_event_type_not_blank
        CHECK (BTRIM(event_type) <> ''),
    CONSTRAINT ck_cargo_audit_event_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_cargo_audit_event_details_object
        CHECK (jsonb_typeof(details) = 'object')
);

CREATE INDEX ix_cargo_audit_event_aggregate_occurred
    ON crm.cargo_audit_event (aggregate_type, aggregate_id, occurred_at DESC, id);

COMMENT ON TABLE crm.inbound_delivery IS
    'Supplier-declared inbound delivery for one project and one assigned target warehouse.';
COMMENT ON TABLE crm.cargo_item IS
    'One row per individual physical item; label code is generated only for accepted available inventory.';
COMMENT ON TABLE crm.warehouse_receipt_item IS
    'Immutable per-item receipt outcome supporting partial receipt and completion.';
COMMENT ON TABLE crm.inventory_movement IS
    'Append-only warehouse movement ledger; V11 introduces the initial RECEIVED movement.';
COMMENT ON TABLE crm.cargo_item_photo IS
    'Cargo-owned private photo upload lifecycle with at most ten positions per item.';
COMMENT ON TABLE crm.cargo_item_photo_object IS
    'Verified original and backend-generated preview objects stored in private S3-compatible storage.';
