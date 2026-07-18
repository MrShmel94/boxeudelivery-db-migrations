ALTER TABLE crm.customer_order
    DROP CONSTRAINT ck_customer_order_status,
    DROP CONSTRAINT ck_customer_order_lifecycle,
    ADD CONSTRAINT ck_customer_order_status
        CHECK (status_code IN ('DRAFT', 'CONFIRMED', 'PICKING', 'PACKED', 'FULFILLED', 'CANCELLED')),
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
                status_code IN ('CONFIRMED', 'PICKING', 'PACKED', 'FULFILLED')
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
        CHECK (status_code IN ('DRAFT', 'CONFIRMED', 'PICKED', 'PACKED', 'DELIVERED', 'REMOVED'));

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
            'DELIVERED_TO_CUSTOMER',
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
                    'DELIVERED_TO_CUSTOMER',
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
            )
            OR (
                status_code = 'DELIVERED_TO_CUSTOMER'
                AND label_code IS NOT NULL
                AND current_warehouse_id IS NULL
                AND accepted_by_account_id IS NOT NULL
                AND accepted_at IS NOT NULL
            )
            OR (
                status_code NOT IN ('AVAILABLE', 'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER', 'DELIVERED_TO_CUSTOMER')
                AND label_code IS NULL
                AND current_warehouse_id IS NULL
                AND accepted_by_account_id IS NULL
                AND accepted_at IS NULL
            )
        );

CREATE TABLE crm.outbound_delivery_number_counter
(
    calendar_year INTEGER NOT NULL,
    last_value    BIGINT  NOT NULL,
    CONSTRAINT pk_outbound_delivery_number_counter
        PRIMARY KEY (calendar_year),
    CONSTRAINT ck_outbound_delivery_number_counter_year
        CHECK (calendar_year BETWEEN 2000 AND 9999),
    CONSTRAINT ck_outbound_delivery_number_counter_value
        CHECK (last_value >= 1)
);

CREATE TABLE crm.outbound_delivery
(
    id                         UUID           NOT NULL,
    client_request_id          UUID           NOT NULL,
    delivery_number            VARCHAR(21)    NOT NULL,
    customer_order_id          UUID           NOT NULL,
    project_id                 UUID           NOT NULL,
    origin_warehouse_id        UUID           NOT NULL,
    method_code                VARCHAR(24)    NOT NULL,
    status_code                VARCHAR(24)    NOT NULL,
    recipient_name             VARCHAR(255)   NOT NULL,
    recipient_phone            VARCHAR(32)    NOT NULL,
    country_code               VARCHAR(2),
    postal_code                VARCHAR(32),
    address_line               VARCHAR(1000),
    delivery_instructions      VARCHAR(1000),
    assigned_courier_account_id UUID,
    external_carrier_name      VARCHAR(255),
    external_service_name      VARCHAR(255),
    tracking_number            VARCHAR(255),
    tracking_url               VARCHAR(1000),
    customer_charge_amount     NUMERIC(19, 4),
    customer_charge_currency   VARCHAR(3),
    actual_cost_amount         NUMERIC(19, 4),
    actual_cost_currency       VARCHAR(3),
    financial_revision_number  INTEGER        NOT NULL DEFAULT 1,
    ready_by_account_id        UUID,
    ready_by_subject           VARCHAR(255),
    ready_at                   TIMESTAMPTZ,
    dispatched_by_account_id   UUID,
    dispatched_by_subject      VARCHAR(255),
    dispatched_at              TIMESTAMPTZ,
    delivered_by_account_id    UUID,
    delivered_by_subject       VARCHAR(255),
    delivered_at               TIMESTAMPTZ,
    cancelled_by_account_id    UUID,
    cancelled_by_subject       VARCHAR(255),
    cancelled_at               TIMESTAMPTZ,
    cancellation_reason        VARCHAR(500),
    created_by_account_id      UUID           NOT NULL,
    created_by_subject         VARCHAR(255)   NOT NULL,
    updated_by_subject         VARCHAR(255)   NOT NULL,
    created_at                 TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                    BIGINT         NOT NULL DEFAULT 0,
    CONSTRAINT pk_outbound_delivery
        PRIMARY KEY (id),
    CONSTRAINT uq_outbound_delivery_number
        UNIQUE (delivery_number),
    CONSTRAINT uq_outbound_delivery_order_request
        UNIQUE (customer_order_id, client_request_id),
    CONSTRAINT uq_outbound_delivery_scope
        UNIQUE (id, customer_order_id, project_id, origin_warehouse_id),
    CONSTRAINT uq_outbound_delivery_order_scope
        UNIQUE (id, customer_order_id, project_id),
    CONSTRAINT fk_outbound_delivery_order_scope
        FOREIGN KEY (customer_order_id, project_id)
            REFERENCES crm.customer_order (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_origin_warehouse
        FOREIGN KEY (project_id, origin_warehouse_id)
            REFERENCES crm.project_warehouse (project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_courier
        FOREIGN KEY (assigned_courier_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_customer_charge_currency
        FOREIGN KEY (customer_charge_currency) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_actual_cost_currency
        FOREIGN KEY (actual_cost_currency) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_ready_account
        FOREIGN KEY (ready_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_dispatched_account
        FOREIGN KEY (dispatched_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_delivered_account
        FOREIGN KEY (delivered_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_cancelled_account
        FOREIGN KEY (cancelled_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_created_account
        FOREIGN KEY (created_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_outbound_delivery_number_format
        CHECK (delivery_number ~ '^DLV-[0-9]{4}-[0-9]{6}$'),
    CONSTRAINT ck_outbound_delivery_method
        CHECK (method_code IN ('WAREHOUSE_PICKUP', 'COMPANY_COURIER', 'EXTERNAL_CARRIER')),
    CONSTRAINT ck_outbound_delivery_status
        CHECK (status_code IN ('DRAFT', 'READY_FOR_HANDOVER', 'READY_FOR_DISPATCH', 'IN_TRANSIT', 'DELIVERED', 'CANCELLED')),
    CONSTRAINT ck_outbound_delivery_recipient_name
        CHECK (BTRIM(recipient_name) <> ''),
    CONSTRAINT ck_outbound_delivery_recipient_phone
        CHECK (recipient_phone ~ '^\+[1-9][0-9]{7,14}$'),
    CONSTRAINT ck_outbound_delivery_country
        CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_outbound_delivery_optional_text
        CHECK (
            (postal_code IS NULL OR BTRIM(postal_code) <> '')
            AND (address_line IS NULL OR BTRIM(address_line) <> '')
            AND (delivery_instructions IS NULL OR BTRIM(delivery_instructions) <> '')
            AND (external_service_name IS NULL OR BTRIM(external_service_name) <> '')
            AND (tracking_number IS NULL OR BTRIM(tracking_number) <> '')
            AND (tracking_url IS NULL OR BTRIM(tracking_url) <> '')
        ),
    CONSTRAINT ck_outbound_delivery_method_details
        CHECK (
            (
                method_code = 'WAREHOUSE_PICKUP'
                AND country_code IS NULL
                AND postal_code IS NULL
                AND address_line IS NULL
                AND assigned_courier_account_id IS NULL
                AND external_carrier_name IS NULL
                AND external_service_name IS NULL
                AND tracking_number IS NULL
                AND tracking_url IS NULL
            )
            OR (
                method_code = 'COMPANY_COURIER'
                AND country_code IS NOT NULL
                AND address_line IS NOT NULL
                AND BTRIM(address_line) <> ''
                AND assigned_courier_account_id IS NOT NULL
                AND external_carrier_name IS NULL
                AND external_service_name IS NULL
                AND tracking_number IS NULL
                AND tracking_url IS NULL
            )
            OR (
                method_code = 'EXTERNAL_CARRIER'
                AND country_code IS NOT NULL
                AND address_line IS NOT NULL
                AND BTRIM(address_line) <> ''
                AND assigned_courier_account_id IS NULL
                AND external_carrier_name IS NOT NULL
                AND BTRIM(external_carrier_name) <> ''
            )
        ),
    CONSTRAINT ck_outbound_delivery_customer_charge
        CHECK (
            (customer_charge_amount IS NULL AND customer_charge_currency IS NULL)
            OR (customer_charge_amount >= 0 AND customer_charge_currency IS NOT NULL)
        ),
    CONSTRAINT ck_outbound_delivery_actual_cost
        CHECK (
            (actual_cost_amount IS NULL AND actual_cost_currency IS NULL)
            OR (actual_cost_amount >= 0 AND actual_cost_currency IS NOT NULL)
        ),
    CONSTRAINT ck_outbound_delivery_financial_revision
        CHECK (financial_revision_number >= 1),
    CONSTRAINT ck_outbound_delivery_lifecycle
        CHECK (
            (
                status_code = 'DRAFT'
                AND ready_by_account_id IS NULL AND ready_by_subject IS NULL AND ready_at IS NULL
                AND dispatched_by_account_id IS NULL AND dispatched_by_subject IS NULL AND dispatched_at IS NULL
                AND delivered_by_account_id IS NULL AND delivered_by_subject IS NULL AND delivered_at IS NULL
                AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code IN ('READY_FOR_HANDOVER', 'READY_FOR_DISPATCH')
                AND ready_by_account_id IS NOT NULL AND ready_by_subject IS NOT NULL AND BTRIM(ready_by_subject) <> '' AND ready_at IS NOT NULL
                AND dispatched_by_account_id IS NULL AND dispatched_by_subject IS NULL AND dispatched_at IS NULL
                AND delivered_by_account_id IS NULL AND delivered_by_subject IS NULL AND delivered_at IS NULL
                AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'IN_TRANSIT'
                AND ready_by_account_id IS NOT NULL AND ready_by_subject IS NOT NULL AND ready_at IS NOT NULL
                AND dispatched_by_account_id IS NOT NULL AND dispatched_by_subject IS NOT NULL AND BTRIM(dispatched_by_subject) <> '' AND dispatched_at IS NOT NULL
                AND delivered_by_account_id IS NULL AND delivered_by_subject IS NULL AND delivered_at IS NULL
                AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'DELIVERED'
                AND ready_by_account_id IS NOT NULL AND ready_by_subject IS NOT NULL AND ready_at IS NOT NULL
                AND (
                    (
                        method_code = 'WAREHOUSE_PICKUP'
                        AND dispatched_by_account_id IS NULL
                        AND dispatched_by_subject IS NULL
                        AND dispatched_at IS NULL
                    )
                    OR (
                        method_code <> 'WAREHOUSE_PICKUP'
                        AND dispatched_by_account_id IS NOT NULL
                        AND dispatched_by_subject IS NOT NULL
                        AND BTRIM(dispatched_by_subject) <> ''
                        AND dispatched_at IS NOT NULL
                    )
                )
                AND delivered_by_account_id IS NOT NULL AND delivered_by_subject IS NOT NULL AND BTRIM(delivered_by_subject) <> '' AND delivered_at IS NOT NULL
                AND cancelled_by_account_id IS NULL AND cancelled_by_subject IS NULL AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'CANCELLED'
                AND dispatched_by_account_id IS NULL AND dispatched_by_subject IS NULL AND dispatched_at IS NULL
                AND delivered_by_account_id IS NULL AND delivered_by_subject IS NULL AND delivered_at IS NULL
                AND cancelled_by_account_id IS NOT NULL AND cancelled_by_subject IS NOT NULL AND BTRIM(cancelled_by_subject) <> '' AND cancelled_at IS NOT NULL
                AND cancellation_reason IS NOT NULL AND BTRIM(cancellation_reason) <> ''
            )
        ),
    CONSTRAINT ck_outbound_delivery_status_method
        CHECK (
            (method_code = 'WAREHOUSE_PICKUP' AND status_code NOT IN ('READY_FOR_DISPATCH', 'IN_TRANSIT'))
            OR (method_code <> 'WAREHOUSE_PICKUP' AND status_code <> 'READY_FOR_HANDOVER')
        ),
    CONSTRAINT ck_outbound_delivery_created_subject
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_outbound_delivery_updated_subject
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_outbound_delivery_timestamps
        CHECK (
            updated_at >= created_at
            AND (ready_at IS NULL OR ready_at >= created_at)
            AND (dispatched_at IS NULL OR (ready_at IS NOT NULL AND dispatched_at >= ready_at))
            AND (delivered_at IS NULL OR (ready_at IS NOT NULL AND delivered_at >= ready_at))
            AND (cancelled_at IS NULL OR cancelled_at >= created_at)
        ),
    CONSTRAINT ck_outbound_delivery_version
        CHECK (version >= 0)
);

CREATE INDEX ix_outbound_delivery_order_status
    ON crm.outbound_delivery (customer_order_id, status_code, created_at, id);

CREATE INDEX ix_outbound_delivery_courier_status
    ON crm.outbound_delivery (assigned_courier_account_id, status_code, updated_at DESC, id)
    WHERE assigned_courier_account_id IS NOT NULL;

ALTER TABLE crm.outbound_package
    ADD CONSTRAINT uq_outbound_package_delivery_scope
        UNIQUE (id, customer_order_id, project_id, warehouse_id);

CREATE TABLE crm.outbound_delivery_package
(
    id                         UUID         NOT NULL,
    outbound_delivery_id       UUID         NOT NULL,
    outbound_package_id        UUID         NOT NULL,
    customer_order_id          UUID         NOT NULL,
    project_id                 UUID         NOT NULL,
    origin_warehouse_id        UUID         NOT NULL,
    status_code                VARCHAR(16)  NOT NULL,
    assigned_by_account_id     UUID         NOT NULL,
    assigned_by_subject        VARCHAR(255) NOT NULL,
    assigned_at                TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    released_by_account_id     UUID,
    released_by_subject        VARCHAR(255),
    released_at                TIMESTAMPTZ,
    release_reason             VARCHAR(500),
    CONSTRAINT pk_outbound_delivery_package
        PRIMARY KEY (id),
    CONSTRAINT uq_outbound_delivery_package_scope
        UNIQUE (id, outbound_delivery_id),
    CONSTRAINT fk_outbound_delivery_package_delivery_scope
        FOREIGN KEY (outbound_delivery_id, customer_order_id, project_id, origin_warehouse_id)
            REFERENCES crm.outbound_delivery (id, customer_order_id, project_id, origin_warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_package_package_scope
        FOREIGN KEY (outbound_package_id, customer_order_id, project_id, origin_warehouse_id)
            REFERENCES crm.outbound_package (id, customer_order_id, project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_package_assigned_account
        FOREIGN KEY (assigned_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_package_released_account
        FOREIGN KEY (released_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_outbound_delivery_package_status
        CHECK (status_code IN ('ACTIVE', 'RELEASED')),
    CONSTRAINT ck_outbound_delivery_package_lifecycle
        CHECK (
            (
                status_code = 'ACTIVE'
                AND released_by_account_id IS NULL
                AND released_by_subject IS NULL
                AND released_at IS NULL
                AND release_reason IS NULL
            )
            OR (
                status_code = 'RELEASED'
                AND released_by_account_id IS NOT NULL
                AND released_by_subject IS NOT NULL
                AND BTRIM(released_by_subject) <> ''
                AND released_at IS NOT NULL
                AND release_reason IS NOT NULL
                AND BTRIM(release_reason) <> ''
            )
        ),
    CONSTRAINT ck_outbound_delivery_package_assigned_subject
        CHECK (BTRIM(assigned_by_subject) <> ''),
    CONSTRAINT ck_outbound_delivery_package_timestamps
        CHECK (released_at IS NULL OR released_at >= assigned_at)
);

CREATE UNIQUE INDEX uq_outbound_delivery_package_active_package
    ON crm.outbound_delivery_package (outbound_package_id)
    WHERE status_code = 'ACTIVE';

CREATE INDEX ix_outbound_delivery_package_delivery_status
    ON crm.outbound_delivery_package (outbound_delivery_id, status_code, assigned_at, id);

CREATE TABLE crm.outbound_delivery_financial_revision
(
    id                        UUID           NOT NULL,
    outbound_delivery_id      UUID           NOT NULL,
    customer_order_id         UUID           NOT NULL,
    project_id                UUID           NOT NULL,
    revision_number           INTEGER        NOT NULL,
    action_code               VARCHAR(16)    NOT NULL,
    customer_charge_amount    NUMERIC(19, 4),
    customer_charge_currency  VARCHAR(3),
    actual_cost_amount        NUMERIC(19, 4),
    actual_cost_currency      VARCHAR(3),
    actor_subject             VARCHAR(255)   NOT NULL,
    reason                    VARCHAR(500),
    occurred_at               TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_outbound_delivery_financial_revision
        PRIMARY KEY (id),
    CONSTRAINT uq_outbound_delivery_financial_revision_number
        UNIQUE (outbound_delivery_id, revision_number),
    CONSTRAINT fk_outbound_delivery_financial_revision_scope
        FOREIGN KEY (outbound_delivery_id, customer_order_id, project_id)
            REFERENCES crm.outbound_delivery (id, customer_order_id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_financial_revision_customer_currency
        FOREIGN KEY (customer_charge_currency) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_outbound_delivery_financial_revision_actual_currency
        FOREIGN KEY (actual_cost_currency) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT ck_outbound_delivery_financial_revision_number
        CHECK (revision_number >= 1),
    CONSTRAINT ck_outbound_delivery_financial_revision_action
        CHECK (action_code IN ('CREATED', 'UPDATED', 'CONFIRMED')),
    CONSTRAINT ck_outbound_delivery_financial_revision_customer_charge
        CHECK (
            (customer_charge_amount IS NULL AND customer_charge_currency IS NULL)
            OR (customer_charge_amount >= 0 AND customer_charge_currency IS NOT NULL)
        ),
    CONSTRAINT ck_outbound_delivery_financial_revision_actual_cost
        CHECK (
            (actual_cost_amount IS NULL AND actual_cost_currency IS NULL)
            OR (actual_cost_amount >= 0 AND actual_cost_currency IS NOT NULL)
        ),
    CONSTRAINT ck_outbound_delivery_financial_revision_actor
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_outbound_delivery_financial_revision_reason
        CHECK (
            (action_code = 'UPDATED' AND reason IS NOT NULL AND BTRIM(reason) <> '')
            OR (action_code <> 'UPDATED' AND reason IS NULL)
        )
);

CREATE INDEX ix_outbound_delivery_financial_revision_delivery
    ON crm.outbound_delivery_financial_revision (outbound_delivery_id, revision_number DESC);

ALTER TABLE crm.inventory_movement
    DROP CONSTRAINT ck_inventory_movement_type,
    DROP CONSTRAINT ck_inventory_movement_warehouses,
    ADD CONSTRAINT ck_inventory_movement_type
        CHECK (movement_type IN ('RECEIVED', 'PICKED_FOR_ORDER', 'DELIVERED_TO_CUSTOMER')),
    ADD CONSTRAINT ck_inventory_movement_warehouses
        CHECK (
            (movement_type = 'RECEIVED' AND from_warehouse_id IS NULL AND to_warehouse_id IS NOT NULL)
            OR (movement_type IN ('PICKED_FOR_ORDER', 'DELIVERED_TO_CUSTOMER') AND from_warehouse_id IS NOT NULL AND to_warehouse_id IS NULL)
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
            'CARGO_USER_DAILY_RATE',
            'CUSTOMER_ORDER',
            'CUSTOMER_ORDER_LINE',
            'PICKING_SESSION',
            'OUTBOUND_PACKAGE',
            'OUTBOUND_DELIVERY'
        ));

COMMENT ON TABLE crm.outbound_delivery IS
    'Customer handover or delivery of one or more sealed outbound packages from one warehouse.';

COMMENT ON TABLE crm.outbound_delivery_package IS
    'Attributable assignment history of sealed outbound packages to customer deliveries.';

COMMENT ON TABLE crm.outbound_delivery_financial_revision IS
    'Immutable snapshots of customer-facing delivery charge and internal actual delivery cost.';
