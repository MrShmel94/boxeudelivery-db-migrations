CREATE TABLE crm.warehouse_relocation_number_counter
(
    calendar_year INTEGER NOT NULL,
    last_value    BIGINT  NOT NULL,
    CONSTRAINT pk_warehouse_relocation_number_counter PRIMARY KEY (calendar_year),
    CONSTRAINT ck_warehouse_relocation_number_counter_year CHECK (calendar_year BETWEEN 2000 AND 9999),
    CONSTRAINT ck_warehouse_relocation_number_counter_value CHECK (last_value >= 1)
);

CREATE TABLE crm.warehouse_relocation
(
    id                         UUID          NOT NULL,
    client_request_id          UUID          NOT NULL,
    relocation_number          VARCHAR(21)   NOT NULL,
    project_id                 UUID          NOT NULL,
    source_warehouse_id        UUID          NOT NULL,
    destination_warehouse_id   UUID          NOT NULL,
    status_code                VARCHAR(24)   NOT NULL,
    service_fee_amount         NUMERIC(19, 4),
    service_fee_currency       VARCHAR(3),
    service_fee_charged_party  VARCHAR(16),
    service_fee_charged_account_id UUID,
    service_fee_charged_supplier_id UUID,
    dispatched_by_account_id   UUID,
    dispatched_by_subject      VARCHAR(255),
    dispatched_at              TIMESTAMPTZ,
    completed_by_account_id    UUID,
    completed_by_subject       VARCHAR(255),
    completed_at               TIMESTAMPTZ,
    cancelled_by_account_id    UUID,
    cancelled_by_subject       VARCHAR(255),
    cancelled_at               TIMESTAMPTZ,
    cancellation_reason        VARCHAR(500),
    created_by_account_id      UUID          NOT NULL,
    created_by_subject         VARCHAR(255)  NOT NULL,
    updated_by_subject         VARCHAR(255)  NOT NULL,
    created_at                 TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                    BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_warehouse_relocation PRIMARY KEY (id),
    CONSTRAINT uq_warehouse_relocation_number UNIQUE (relocation_number),
    CONSTRAINT uq_warehouse_relocation_request UNIQUE (project_id, client_request_id),
    CONSTRAINT uq_warehouse_relocation_project_scope UNIQUE (id, project_id),
    CONSTRAINT uq_warehouse_relocation_scope UNIQUE (id, project_id, source_warehouse_id, destination_warehouse_id),
    CONSTRAINT fk_warehouse_relocation_project FOREIGN KEY (project_id)
        REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_source FOREIGN KEY (project_id, source_warehouse_id)
        REFERENCES crm.project_warehouse (project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_destination FOREIGN KEY (project_id, destination_warehouse_id)
        REFERENCES crm.project_warehouse (project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_fee_currency FOREIGN KEY (service_fee_currency)
        REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_fee_account FOREIGN KEY (service_fee_charged_account_id)
        REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_fee_supplier FOREIGN KEY (project_id, service_fee_charged_supplier_id)
        REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_dispatched_account FOREIGN KEY (dispatched_by_account_id)
        REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_completed_account FOREIGN KEY (completed_by_account_id)
        REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_cancelled_account FOREIGN KEY (cancelled_by_account_id)
        REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_created_account FOREIGN KEY (created_by_account_id)
        REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_warehouse_relocation_number CHECK (relocation_number ~ '^REL-[0-9]{4}-[0-9]{6}$'),
    CONSTRAINT ck_warehouse_relocation_distinct_warehouses CHECK (source_warehouse_id <> destination_warehouse_id),
    CONSTRAINT ck_warehouse_relocation_status CHECK (
        status_code IN ('DRAFT', 'IN_TRANSIT', 'PARTIALLY_RECEIVED', 'COMPLETED', 'CANCELLED')
    ),
    CONSTRAINT ck_warehouse_relocation_service_fee CHECK (
        (
            service_fee_amount IS NULL
            AND service_fee_currency IS NULL
            AND service_fee_charged_party IS NULL
            AND service_fee_charged_account_id IS NULL
            AND service_fee_charged_supplier_id IS NULL
        )
        OR (
            service_fee_amount > 0
            AND service_fee_currency IS NOT NULL
            AND (
                (service_fee_charged_party = 'CUSTOMER'
                    AND service_fee_charged_account_id IS NOT NULL
                    AND service_fee_charged_supplier_id IS NULL)
                OR (service_fee_charged_party = 'SUPPLIER'
                    AND service_fee_charged_account_id IS NULL
                    AND service_fee_charged_supplier_id IS NOT NULL)
            )
        )
    ),
    CONSTRAINT ck_warehouse_relocation_lifecycle CHECK (
        (
            status_code = 'DRAFT'
            AND dispatched_by_account_id IS NULL AND dispatched_by_subject IS NULL AND dispatched_at IS NULL
            AND completed_by_account_id IS NULL AND completed_by_subject IS NULL AND completed_at IS NULL
            AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
            AND cancellation_reason IS NULL
        )
        OR (
            status_code IN ('IN_TRANSIT', 'PARTIALLY_RECEIVED')
            AND dispatched_by_account_id IS NOT NULL AND dispatched_by_subject IS NOT NULL AND dispatched_at IS NOT NULL
            AND completed_by_account_id IS NULL AND completed_by_subject IS NULL AND completed_at IS NULL
            AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
            AND cancellation_reason IS NULL
        )
        OR (
            status_code = 'COMPLETED'
            AND dispatched_by_account_id IS NOT NULL AND dispatched_by_subject IS NOT NULL AND dispatched_at IS NOT NULL
            AND completed_by_account_id IS NOT NULL AND completed_by_subject IS NOT NULL AND completed_at IS NOT NULL
            AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
            AND cancellation_reason IS NULL
        )
        OR (
            status_code = 'CANCELLED'
            AND dispatched_by_account_id IS NULL AND dispatched_by_subject IS NULL AND dispatched_at IS NULL
            AND completed_by_account_id IS NULL AND completed_by_subject IS NULL AND completed_at IS NULL
            AND cancelled_by_account_id IS NOT NULL AND cancelled_by_subject IS NOT NULL AND cancelled_at IS NOT NULL
            AND cancellation_reason IS NOT NULL AND BTRIM(cancellation_reason) <> ''
        )
    ),
    CONSTRAINT ck_warehouse_relocation_subjects CHECK (
        BTRIM(created_by_subject) <> ''
        AND BTRIM(updated_by_subject) <> ''
        AND (dispatched_by_subject IS NULL OR BTRIM(dispatched_by_subject) <> '')
        AND (completed_by_subject IS NULL OR BTRIM(completed_by_subject) <> '')
        AND (cancelled_by_subject IS NULL OR BTRIM(cancelled_by_subject) <> '')
    ),
    CONSTRAINT ck_warehouse_relocation_timestamps CHECK (
        updated_at >= created_at
        AND (dispatched_at IS NULL OR dispatched_at >= created_at)
        AND (completed_at IS NULL OR (dispatched_at IS NOT NULL AND completed_at >= dispatched_at))
        AND (cancelled_at IS NULL OR cancelled_at >= created_at)
    ),
    CONSTRAINT ck_warehouse_relocation_version CHECK (version >= 0)
);

CREATE TABLE crm.warehouse_relocation_item
(
    relocation_id              UUID         NOT NULL,
    cargo_item_id              UUID         NOT NULL,
    project_id                 UUID         NOT NULL,
    source_warehouse_id        UUID         NOT NULL,
    destination_warehouse_id   UUID         NOT NULL,
    label_code_snapshot        VARCHAR(64)  NOT NULL,
    sequence_number            INTEGER      NOT NULL,
    received_by_account_id     UUID,
    received_by_subject        VARCHAR(255),
    received_at                TIMESTAMPTZ,
    CONSTRAINT pk_warehouse_relocation_item PRIMARY KEY (relocation_id, cargo_item_id),
    CONSTRAINT uq_warehouse_relocation_item_sequence UNIQUE (relocation_id, sequence_number),
    CONSTRAINT fk_warehouse_relocation_item_relocation FOREIGN KEY (
        relocation_id, project_id, source_warehouse_id, destination_warehouse_id
    ) REFERENCES crm.warehouse_relocation (
        id, project_id, source_warehouse_id, destination_warehouse_id
    ) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_item_cargo FOREIGN KEY (cargo_item_id, project_id)
        REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_relocation_item_receiver FOREIGN KEY (received_by_account_id)
        REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_warehouse_relocation_item_label CHECK (BTRIM(label_code_snapshot) <> ''),
    CONSTRAINT ck_warehouse_relocation_item_sequence CHECK (sequence_number >= 1),
    CONSTRAINT ck_warehouse_relocation_item_receipt CHECK (
        (received_by_account_id IS NULL AND received_by_subject IS NULL AND received_at IS NULL)
        OR (received_by_account_id IS NOT NULL AND received_by_subject IS NOT NULL
            AND BTRIM(received_by_subject) <> '' AND received_at IS NOT NULL)
    )
);

CREATE INDEX ix_warehouse_relocation_project_status
    ON crm.warehouse_relocation (project_id, status_code, created_at DESC, id);

CREATE INDEX ix_warehouse_relocation_route_status
    ON crm.warehouse_relocation (source_warehouse_id, destination_warehouse_id, status_code, created_at DESC, id);

CREATE INDEX ix_warehouse_relocation_item_cargo
    ON crm.warehouse_relocation_item (cargo_item_id, received_at DESC, relocation_id);

ALTER TABLE crm.cargo_item
    DROP CONSTRAINT ck_cargo_item_status,
    DROP CONSTRAINT ck_cargo_item_delivery_assignment,
    DROP CONSTRAINT ck_cargo_item_availability_state,
    ADD CONSTRAINT ck_cargo_item_status CHECK (status_code IN (
        'EXPECTED_AT_SUPPLIER', 'AT_SUPPLIER', 'RESERVED_FOR_DELIVERY',
        'IN_TRANSIT_TO_PICKUP_POINT', 'READY_FOR_COURIER_PICKUP', 'IN_TRANSIT_TO_WAREHOUSE',
        'AVAILABLE', 'IN_RELOCATION', 'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER',
        'DELIVERED_TO_CUSTOMER', 'MISSING', 'DAMAGED', 'REJECTED', 'CANCELLED'
    )),
    ADD CONSTRAINT ck_cargo_item_delivery_assignment CHECK (
        (
            status_code IN ('EXPECTED_AT_SUPPLIER', 'AT_SUPPLIER', 'CANCELLED')
            AND inbound_delivery_id IS NULL
            AND inbound_delivery_line_id IS NULL
        )
        OR (
            status_code IN (
                'RESERVED_FOR_DELIVERY', 'IN_TRANSIT_TO_PICKUP_POINT',
                'READY_FOR_COURIER_PICKUP', 'IN_TRANSIT_TO_WAREHOUSE',
                'AVAILABLE', 'IN_RELOCATION', 'PICKED_FOR_ORDER',
                'PACKED_FOR_CUSTOMER', 'DELIVERED_TO_CUSTOMER',
                'MISSING', 'DAMAGED', 'REJECTED'
            )
            AND inbound_delivery_id IS NOT NULL
            AND inbound_delivery_line_id IS NOT NULL
        )
    ),
    ADD CONSTRAINT ck_cargo_item_availability_state CHECK (
        (
            status_code IN ('AVAILABLE', 'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER')
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

ALTER TABLE crm.inventory_movement
    ADD COLUMN relocation_id UUID,
    ADD CONSTRAINT fk_inventory_movement_relocation
        FOREIGN KEY (relocation_id, project_id)
            REFERENCES crm.warehouse_relocation (id, project_id) ON DELETE RESTRICT,
    DROP CONSTRAINT ck_inventory_movement_type,
    DROP CONSTRAINT ck_inventory_movement_warehouses,
    ADD CONSTRAINT ck_inventory_movement_type CHECK (movement_type IN (
        'RECEIVED', 'PICKED_FOR_ORDER', 'DELIVERED_TO_CUSTOMER',
        'RELOCATION_DISPATCHED', 'RELOCATION_RECEIVED'
    )),
    ADD CONSTRAINT ck_inventory_movement_warehouses CHECK (
        (movement_type = 'RECEIVED' AND from_warehouse_id IS NULL AND to_warehouse_id IS NOT NULL AND relocation_id IS NULL)
        OR (movement_type IN ('PICKED_FOR_ORDER', 'DELIVERED_TO_CUSTOMER')
            AND from_warehouse_id IS NOT NULL AND to_warehouse_id IS NULL AND relocation_id IS NULL)
        OR (movement_type IN ('RELOCATION_DISPATCHED', 'RELOCATION_RECEIVED')
            AND from_warehouse_id IS NOT NULL AND to_warehouse_id IS NOT NULL
            AND from_warehouse_id <> to_warehouse_id AND relocation_id IS NOT NULL)
    );

CREATE UNIQUE INDEX uq_inventory_movement_relocation_item_type
    ON crm.inventory_movement (relocation_id, cargo_item_id, movement_type)
    WHERE relocation_id IS NOT NULL;

ALTER TABLE crm.cargo_audit_event
    DROP CONSTRAINT ck_cargo_audit_event_aggregate_type,
    ADD CONSTRAINT ck_cargo_audit_event_aggregate_type CHECK (aggregate_type IN (
        'SUPPLIER_GOODS', 'INBOUND_DELIVERY', 'INBOUND_PACKAGE', 'COURIER_ASSIGNMENT',
        'CARGO_ITEM', 'CARGO_PHOTO', 'CARGO_FINANCIAL_ENTRY', 'CARGO_PURCHASE_RATE',
        'CARGO_USER_DAILY_RATE', 'CUSTOMER_ORDER', 'CUSTOMER_ORDER_LINE', 'PICKING_SESSION',
        'OUTBOUND_PACKAGE', 'OUTBOUND_DELIVERY', 'WAREHOUSE_RELOCATION'
    ));

COMMENT ON TABLE crm.warehouse_relocation IS
    'Auditable movement of already labelled exact cargo items between two project warehouses.';

COMMENT ON TABLE crm.warehouse_relocation_item IS
    'Immutable relocation composition and per-item receipt attribution using the original cargo label.';
