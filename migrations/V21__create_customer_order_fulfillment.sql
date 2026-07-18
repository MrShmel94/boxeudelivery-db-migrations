ALTER TABLE crm.customer_order
    DROP CONSTRAINT ck_customer_order_status,
    DROP CONSTRAINT ck_customer_order_lifecycle,
    ADD CONSTRAINT ck_customer_order_status
        CHECK (status_code IN ('DRAFT', 'CONFIRMED', 'PICKING', 'PACKED', 'CANCELLED')),
    ADD CONSTRAINT ck_customer_order_lifecycle
        CHECK (
            (
                status_code = 'DRAFT'
                AND confirmed_by_subject IS NULL
                AND confirmed_at IS NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code IN ('CONFIRMED', 'PICKING', 'PACKED')
                AND confirmed_by_subject IS NOT NULL
                AND BTRIM(confirmed_by_subject) <> ''
                AND confirmed_at IS NOT NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'CANCELLED'
                AND confirmed_by_subject IS NULL
                AND confirmed_at IS NULL
                AND cancelled_by_subject IS NOT NULL
                AND BTRIM(cancelled_by_subject) <> ''
                AND cancelled_at IS NOT NULL
                AND cancellation_reason IS NOT NULL
                AND BTRIM(cancellation_reason) <> ''
            )
        );

ALTER TABLE crm.customer_order_line
    DROP CONSTRAINT ck_customer_order_line_status,
    ADD CONSTRAINT ck_customer_order_line_status
        CHECK (status_code IN ('DRAFT', 'CONFIRMED', 'PICKED', 'PACKED', 'REMOVED'));

ALTER TABLE crm.cargo_item
    DROP CONSTRAINT ck_cargo_item_status,
    DROP CONSTRAINT ck_cargo_item_delivery_assignment,
    DROP CONSTRAINT ck_cargo_item_availability_state,
    ADD CONSTRAINT ck_cargo_item_status
        CHECK (status_code IN (
            'EXPECTED_AT_SUPPLIER',
            'AT_SUPPLIER',
            'RESERVED_FOR_DELIVERY',
            'IN_TRANSIT_TO_PICKUP_POINT',
            'READY_FOR_COURIER_PICKUP',
            'IN_TRANSIT_TO_WAREHOUSE',
            'AVAILABLE',
            'PICKED_FOR_ORDER',
            'PACKED_FOR_CUSTOMER',
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
                    'IN_TRANSIT_TO_PICKUP_POINT',
                    'READY_FOR_COURIER_PICKUP',
                    'IN_TRANSIT_TO_WAREHOUSE',
                    'AVAILABLE',
                    'PICKED_FOR_ORDER',
                    'PACKED_FOR_CUSTOMER',
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
                status_code IN ('AVAILABLE', 'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER')
                AND label_code IS NOT NULL
                AND current_warehouse_id IS NOT NULL
                AND accepted_by_account_id IS NOT NULL
                AND accepted_at IS NOT NULL
            ) OR (
                status_code NOT IN ('AVAILABLE', 'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER')
                AND label_code IS NULL
                AND current_warehouse_id IS NULL
                AND accepted_by_account_id IS NULL
                AND accepted_at IS NULL
            )
        );

CREATE TABLE crm.customer_order_picking_session
(
    id                       UUID         NOT NULL,
    customer_order_id        UUID         NOT NULL,
    project_id               UUID         NOT NULL,
    warehouse_id             UUID         NOT NULL,
    status_code              VARCHAR(16)  NOT NULL,
    started_by_account_id    UUID         NOT NULL,
    started_by_subject       VARCHAR(255) NOT NULL,
    started_at               TIMESTAMPTZ  NOT NULL,
    completed_by_account_id  UUID,
    completed_by_subject     VARCHAR(255),
    completed_at             TIMESTAMPTZ,
    created_at               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                  BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_customer_order_picking_session
        PRIMARY KEY (id),
    CONSTRAINT uq_customer_order_picking_session_scope
        UNIQUE (id, customer_order_id, project_id),
    CONSTRAINT uq_customer_order_picking_session_warehouse_scope
        UNIQUE (id, customer_order_id, project_id, warehouse_id),
    CONSTRAINT uq_customer_order_picking_session_order_warehouse
        UNIQUE (customer_order_id, warehouse_id),
    CONSTRAINT fk_customer_order_picking_session_order
        FOREIGN KEY (customer_order_id, project_id)
            REFERENCES crm.customer_order (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_picking_session_warehouse
        FOREIGN KEY (project_id, warehouse_id)
            REFERENCES crm.project_warehouse (project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_picking_session_started_account
        FOREIGN KEY (started_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_picking_session_completed_account
        FOREIGN KEY (completed_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_customer_order_picking_session_status
        CHECK (status_code IN ('IN_PROGRESS', 'COMPLETED')),
    CONSTRAINT ck_customer_order_picking_session_lifecycle
        CHECK (
            (
                status_code = 'IN_PROGRESS'
                AND completed_by_account_id IS NULL
                AND completed_by_subject IS NULL
                AND completed_at IS NULL
            )
            OR (
                status_code = 'COMPLETED'
                AND completed_by_account_id IS NOT NULL
                AND completed_by_subject IS NOT NULL
                AND BTRIM(completed_by_subject) <> ''
                AND completed_at IS NOT NULL
            )
        ),
    CONSTRAINT ck_customer_order_picking_session_started_subject
        CHECK (BTRIM(started_by_subject) <> ''),
    CONSTRAINT ck_customer_order_picking_session_timestamps
        CHECK (updated_at >= created_at AND started_at >= created_at AND (completed_at IS NULL OR completed_at >= started_at)),
    CONSTRAINT ck_customer_order_picking_session_version
        CHECK (version >= 0)
);

CREATE INDEX ix_customer_order_picking_session_order_status
    ON crm.customer_order_picking_session (customer_order_id, status_code, warehouse_id, id);

ALTER TABLE crm.customer_order_line
    ADD COLUMN picking_session_id UUID,
    ADD CONSTRAINT uq_customer_order_line_picking_scope
        UNIQUE (id, customer_order_id, project_id, picking_session_id),
    ADD CONSTRAINT fk_customer_order_line_picking_session
        FOREIGN KEY (picking_session_id, customer_order_id, project_id)
            REFERENCES crm.customer_order_picking_session (id, customer_order_id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_customer_order_line_picking_assignment
        CHECK (status_code NOT IN ('PICKED', 'PACKED') OR picking_session_id IS NOT NULL);

CREATE INDEX ix_customer_order_line_picking_status
    ON crm.customer_order_line (picking_session_id, status_code, sequence_number, id)
    WHERE picking_session_id IS NOT NULL;

CREATE TABLE crm.customer_order_pick
(
    id                       UUID         NOT NULL,
    picking_session_id       UUID         NOT NULL,
    customer_order_id        UUID         NOT NULL,
    customer_order_line_id   UUID         NOT NULL,
    project_id               UUID         NOT NULL,
    cargo_item_id            UUID         NOT NULL,
    warehouse_id             UUID         NOT NULL,
    scanned_label_code       VARCHAR(64)  NOT NULL,
    picked_by_account_id     UUID         NOT NULL,
    picked_by_subject        VARCHAR(255) NOT NULL,
    picked_at                TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_customer_order_pick
        PRIMARY KEY (id),
    CONSTRAINT uq_customer_order_pick_line
        UNIQUE (customer_order_line_id),
    CONSTRAINT uq_customer_order_pick_item
        UNIQUE (cargo_item_id),
    CONSTRAINT fk_customer_order_pick_session_scope
        FOREIGN KEY (picking_session_id, customer_order_id, project_id, warehouse_id)
            REFERENCES crm.customer_order_picking_session (id, customer_order_id, project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_pick_line_scope
        FOREIGN KEY (customer_order_line_id, customer_order_id, project_id, picking_session_id)
            REFERENCES crm.customer_order_line (id, customer_order_id, project_id, picking_session_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_pick_item_scope
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_pick_account
        FOREIGN KEY (picked_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_customer_order_pick_label_not_blank
        CHECK (BTRIM(scanned_label_code) <> ''),
    CONSTRAINT ck_customer_order_pick_subject_not_blank
        CHECK (BTRIM(picked_by_subject) <> '')
);

CREATE INDEX ix_customer_order_pick_session_time
    ON crm.customer_order_pick (picking_session_id, picked_at, id);

CREATE TABLE crm.outbound_package
(
    id                       UUID          NOT NULL,
    client_request_id        UUID          NOT NULL,
    customer_order_id        UUID          NOT NULL,
    picking_session_id       UUID          NOT NULL,
    project_id               UUID          NOT NULL,
    warehouse_id             UUID          NOT NULL,
    sequence_number          SMALLINT      NOT NULL,
    package_number           VARCHAR(48)   NOT NULL,
    status_code              VARCHAR(16)   NOT NULL,
    description              VARCHAR(500),
    weight_grams             INTEGER,
    length_mm                INTEGER,
    width_mm                 INTEGER,
    height_mm                INTEGER,
    sealed_by_account_id     UUID,
    sealed_by_subject        VARCHAR(255),
    sealed_at                TIMESTAMPTZ,
    cancelled_by_account_id  UUID,
    cancelled_by_subject     VARCHAR(255),
    cancelled_at             TIMESTAMPTZ,
    cancellation_reason      VARCHAR(500),
    created_by_account_id    UUID          NOT NULL,
    created_by_subject       VARCHAR(255)  NOT NULL,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                  BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_outbound_package
        PRIMARY KEY (id),
    CONSTRAINT uq_outbound_package_scope
        UNIQUE (id, customer_order_id, project_id, picking_session_id),
    CONSTRAINT uq_outbound_package_number
        UNIQUE (package_number),
    CONSTRAINT uq_outbound_package_order_sequence
        UNIQUE (customer_order_id, sequence_number),
    CONSTRAINT uq_outbound_package_order_client_request
        UNIQUE (customer_order_id, client_request_id),
    CONSTRAINT fk_outbound_package_session_scope
        FOREIGN KEY (picking_session_id, customer_order_id, project_id, warehouse_id)
            REFERENCES crm.customer_order_picking_session (id, customer_order_id, project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_package_sealed_account
        FOREIGN KEY (sealed_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_package_cancelled_account
        FOREIGN KEY (cancelled_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_package_created_account
        FOREIGN KEY (created_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_outbound_package_sequence
        CHECK (sequence_number BETWEEN 1 AND 999),
    CONSTRAINT ck_outbound_package_number_format
        CHECK (package_number ~ '^OUT-[0-9]{4}-[0-9]{6}-P[0-9]{3}$'),
    CONSTRAINT ck_outbound_package_status
        CHECK (status_code IN ('DRAFT', 'SEALED', 'CANCELLED')),
    CONSTRAINT ck_outbound_package_description
        CHECK (description IS NULL OR BTRIM(description) <> ''),
    CONSTRAINT ck_outbound_package_weight
        CHECK (weight_grams IS NULL OR weight_grams BETWEEN 1 AND 1000000),
    CONSTRAINT ck_outbound_package_dimensions
        CHECK (
            (length_mm IS NULL AND width_mm IS NULL AND height_mm IS NULL)
            OR (
                length_mm BETWEEN 1 AND 10000
                AND width_mm BETWEEN 1 AND 10000
                AND height_mm BETWEEN 1 AND 10000
            )
        ),
    CONSTRAINT ck_outbound_package_lifecycle
        CHECK (
            (
                status_code = 'DRAFT'
                AND sealed_by_account_id IS NULL
                AND sealed_by_subject IS NULL
                AND sealed_at IS NULL
                AND cancelled_by_account_id IS NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'SEALED'
                AND sealed_by_account_id IS NOT NULL
                AND sealed_by_subject IS NOT NULL
                AND BTRIM(sealed_by_subject) <> ''
                AND sealed_at IS NOT NULL
                AND cancelled_by_account_id IS NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'CANCELLED'
                AND sealed_by_account_id IS NULL
                AND sealed_by_subject IS NULL
                AND sealed_at IS NULL
                AND cancelled_by_account_id IS NOT NULL
                AND cancelled_by_subject IS NOT NULL
                AND BTRIM(cancelled_by_subject) <> ''
                AND cancelled_at IS NOT NULL
                AND cancellation_reason IS NOT NULL
                AND BTRIM(cancellation_reason) <> ''
            )
        ),
    CONSTRAINT ck_outbound_package_created_subject
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_outbound_package_timestamps
        CHECK (
            updated_at >= created_at
            AND (sealed_at IS NULL OR sealed_at >= created_at)
            AND (cancelled_at IS NULL OR cancelled_at >= created_at)
        ),
    CONSTRAINT ck_outbound_package_version
        CHECK (version >= 0)
);

CREATE INDEX ix_outbound_package_order_status_sequence
    ON crm.outbound_package (customer_order_id, status_code, sequence_number, id);

CREATE TABLE crm.outbound_package_item
(
    id                       UUID         NOT NULL,
    outbound_package_id      UUID         NOT NULL,
    customer_order_id        UUID         NOT NULL,
    picking_session_id       UUID         NOT NULL,
    customer_order_line_id   UUID         NOT NULL,
    project_id               UUID         NOT NULL,
    cargo_item_id            UUID         NOT NULL,
    status_code              VARCHAR(16)  NOT NULL,
    scanned_label_code       VARCHAR(64)  NOT NULL,
    added_by_account_id      UUID         NOT NULL,
    added_by_subject         VARCHAR(255) NOT NULL,
    added_at                 TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    removed_by_account_id    UUID,
    removed_by_subject       VARCHAR(255),
    removed_at               TIMESTAMPTZ,
    removal_reason           VARCHAR(500),
    version                  BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_outbound_package_item
        PRIMARY KEY (id),
    CONSTRAINT uq_outbound_package_item_scope
        UNIQUE (id, outbound_package_id),
    CONSTRAINT fk_outbound_package_item_package_scope
        FOREIGN KEY (outbound_package_id, customer_order_id, project_id, picking_session_id)
            REFERENCES crm.outbound_package (id, customer_order_id, project_id, picking_session_id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_package_item_line_scope
        FOREIGN KEY (customer_order_line_id, customer_order_id, project_id, picking_session_id)
            REFERENCES crm.customer_order_line (id, customer_order_id, project_id, picking_session_id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_package_item_cargo_scope
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_package_item_added_account
        FOREIGN KEY (added_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_package_item_removed_account
        FOREIGN KEY (removed_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_outbound_package_item_status
        CHECK (status_code IN ('ACTIVE', 'REMOVED')),
    CONSTRAINT ck_outbound_package_item_label
        CHECK (BTRIM(scanned_label_code) <> ''),
    CONSTRAINT ck_outbound_package_item_added_subject
        CHECK (BTRIM(added_by_subject) <> ''),
    CONSTRAINT ck_outbound_package_item_lifecycle
        CHECK (
            (
                status_code = 'ACTIVE'
                AND removed_by_account_id IS NULL
                AND removed_by_subject IS NULL
                AND removed_at IS NULL
                AND removal_reason IS NULL
            )
            OR (
                status_code = 'REMOVED'
                AND removed_by_account_id IS NOT NULL
                AND removed_by_subject IS NOT NULL
                AND BTRIM(removed_by_subject) <> ''
                AND removed_at IS NOT NULL
                AND removal_reason IS NOT NULL
                AND BTRIM(removal_reason) <> ''
            )
        ),
    CONSTRAINT ck_outbound_package_item_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_outbound_package_item_active_line
    ON crm.outbound_package_item (customer_order_line_id)
    WHERE status_code = 'ACTIVE';

CREATE UNIQUE INDEX uq_outbound_package_item_active_cargo
    ON crm.outbound_package_item (cargo_item_id)
    WHERE status_code = 'ACTIVE';

CREATE INDEX ix_outbound_package_item_package_status
    ON crm.outbound_package_item (outbound_package_id, status_code, added_at, id);

ALTER TABLE crm.inventory_movement
    DROP CONSTRAINT ck_inventory_movement_type,
    DROP CONSTRAINT ck_inventory_movement_received_warehouses,
    ADD CONSTRAINT ck_inventory_movement_type
        CHECK (movement_type IN ('RECEIVED', 'PICKED_FOR_ORDER')),
    ADD CONSTRAINT ck_inventory_movement_warehouses
        CHECK (
            (movement_type = 'RECEIVED' AND from_warehouse_id IS NULL AND to_warehouse_id IS NOT NULL)
            OR (movement_type = 'PICKED_FOR_ORDER' AND from_warehouse_id IS NOT NULL AND to_warehouse_id IS NULL)
        );

ALTER TABLE crm.cargo_audit_event
    DROP CONSTRAINT ck_cargo_audit_event_aggregate_type,
    ADD CONSTRAINT ck_cargo_audit_event_aggregate_type
        CHECK (aggregate_type IN (
            'SUPPLIER_GOODS',
            'INBOUND_DELIVERY',
            'INBOUND_PACKAGE',
            'COURIER_ASSIGNMENT',
            'CARGO_ITEM',
            'CARGO_PHOTO',
            'CARGO_FINANCIAL_ENTRY',
            'CARGO_PURCHASE_RATE',
            'CUSTOMER_ORDER',
            'CUSTOMER_ORDER_LINE',
            'PICKING_SESSION',
            'OUTBOUND_PACKAGE'
        ));

COMMENT ON TABLE crm.customer_order_picking_session IS
    'Warehouse-specific exact-item picking execution for one confirmed customer order.';

COMMENT ON TABLE crm.customer_order_pick IS
    'Immutable successful label scan that removed one exact item from available warehouse stock.';

COMMENT ON TABLE crm.outbound_package IS
    'New customer-facing physical package assembled after warehouse receipt and order confirmation.';

COMMENT ON TABLE crm.outbound_package_item IS
    'Attributable draft or sealed package grouping for one picked exact order item.';
