CREATE TABLE crm.courier_trip_number_counter
(
    calendar_year INTEGER NOT NULL PRIMARY KEY,
    last_value    BIGINT  NOT NULL,
    CONSTRAINT ck_courier_trip_number_counter_year CHECK (calendar_year BETWEEN 2000 AND 9999),
    CONSTRAINT ck_courier_trip_number_counter_value CHECK (last_value > 0)
);

ALTER TABLE crm.conversation
    DROP CONSTRAINT ck_conversation_kind,
    ADD CONSTRAINT ck_conversation_kind
        CHECK (kind_code IN ('TASK', 'INBOUND_DELIVERY', 'COURIER_TRIP'));

CREATE TABLE crm.courier_trip
(
    id                              UUID         NOT NULL,
    trip_number                     VARCHAR(32)  NOT NULL,
    project_id                      UUID         NOT NULL,
    supplier_id                     UUID         NOT NULL,
    pickup_point_id                 UUID         NOT NULL,
    target_warehouse_id             UUID         NOT NULL,
    conversation_id                 UUID         NOT NULL,
    courier_distribution_mode       VARCHAR(32)  NOT NULL,
    designated_courier_account_id   UUID,
    pickup_deadline_at              TIMESTAMPTZ  NOT NULL,
    pickup_deadline_zone_id         VARCHAR(64)  NOT NULL,
    status_code                     VARCHAR(32)  NOT NULL,
    ready_for_courier_at            TIMESTAMPTZ  NOT NULL,
    courier_picked_up_at            TIMESTAMPTZ,
    completed_at                    TIMESTAMPTZ,
    created_by_subject              VARCHAR(255) NOT NULL,
    updated_by_subject              VARCHAR(255) NOT NULL,
    created_at                      TIMESTAMPTZ  NOT NULL,
    updated_at                      TIMESTAMPTZ  NOT NULL,
    version                         BIGINT       NOT NULL DEFAULT 0,

    CONSTRAINT pk_courier_trip PRIMARY KEY (id),
    CONSTRAINT uq_courier_trip_number UNIQUE (trip_number),
    CONSTRAINT uq_courier_trip_conversation UNIQUE (conversation_id),
    CONSTRAINT uq_courier_trip_project UNIQUE (id, project_id),
    CONSTRAINT uq_courier_trip_scope UNIQUE (id, project_id, supplier_id),
    CONSTRAINT uq_courier_trip_project_conversation UNIQUE (id, project_id, conversation_id),
    CONSTRAINT fk_courier_trip_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_trip_project_pickup_point
        FOREIGN KEY (project_id, pickup_point_id)
            REFERENCES crm.project_pickup_point (project_id, pickup_point_id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_trip_project_warehouse
        FOREIGN KEY (project_id, target_warehouse_id)
            REFERENCES crm.project_warehouse (project_id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_trip_conversation
        FOREIGN KEY (conversation_id, project_id)
            REFERENCES crm.conversation (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_trip_designated_courier
        FOREIGN KEY (designated_courier_account_id)
            REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_courier_trip_distribution
        CHECK (courier_distribution_mode IN ('OPEN_POOL', 'DIRECT_ASSIGNMENT')),
    CONSTRAINT ck_courier_trip_designation
        CHECK (
            (courier_distribution_mode = 'OPEN_POOL' AND designated_courier_account_id IS NULL)
            OR
            courier_distribution_mode = 'DIRECT_ASSIGNMENT'
        ),
    CONSTRAINT ck_courier_trip_status
        CHECK (status_code IN (
            'READY_FOR_COURIER_PICKUP',
            'COURIER_ASSIGNED',
            'IN_TRANSIT_TO_WAREHOUSE',
            'COMPLETED'
        )),
    CONSTRAINT ck_courier_trip_state
        CHECK (
            (status_code IN ('READY_FOR_COURIER_PICKUP', 'COURIER_ASSIGNED')
                AND courier_picked_up_at IS NULL AND completed_at IS NULL)
            OR
            (status_code = 'IN_TRANSIT_TO_WAREHOUSE'
                AND courier_picked_up_at IS NOT NULL AND completed_at IS NULL)
            OR
            (status_code = 'COMPLETED'
                AND courier_picked_up_at IS NOT NULL AND completed_at IS NOT NULL)
        ),
    CONSTRAINT ck_courier_trip_deadline_zone_not_blank
        CHECK (BTRIM(pickup_deadline_zone_id) <> ''),
    CONSTRAINT ck_courier_trip_actor_not_blank
        CHECK (BTRIM(created_by_subject) <> '' AND BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_courier_trip_timestamps
        CHECK (
            updated_at >= created_at
            AND ready_for_courier_at >= created_at
            AND (courier_picked_up_at IS NULL OR courier_picked_up_at >= ready_for_courier_at)
            AND (completed_at IS NULL OR completed_at >= courier_picked_up_at)
        ),
    CONSTRAINT ck_courier_trip_version CHECK (version >= 0)
);

CREATE TABLE crm.courier_trip_delivery
(
    courier_trip_id     UUID         NOT NULL,
    inbound_delivery_id UUID         NOT NULL,
    project_id          UUID         NOT NULL,
    supplier_id         UUID         NOT NULL,
    sequence_number     INTEGER      NOT NULL,
    added_by_subject    VARCHAR(255) NOT NULL,
    added_at            TIMESTAMPTZ  NOT NULL,

    CONSTRAINT pk_courier_trip_delivery PRIMARY KEY (courier_trip_id, inbound_delivery_id),
    CONSTRAINT uq_courier_trip_delivery UNIQUE (inbound_delivery_id),
    CONSTRAINT uq_courier_trip_delivery_sequence UNIQUE (courier_trip_id, sequence_number),
    CONSTRAINT fk_courier_trip_delivery_trip
        FOREIGN KEY (courier_trip_id, project_id, supplier_id)
            REFERENCES crm.courier_trip (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_trip_delivery_delivery
        FOREIGN KEY (inbound_delivery_id, project_id, supplier_id)
            REFERENCES crm.inbound_delivery (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT ck_courier_trip_delivery_sequence CHECK (sequence_number > 0),
    CONSTRAINT ck_courier_trip_delivery_actor_not_blank CHECK (BTRIM(added_by_subject) <> '')
);

CREATE TABLE crm.courier_trip_compensation
(
    courier_trip_id UUID          NOT NULL,
    currency_code   VARCHAR(3)    NOT NULL,
    amount          NUMERIC(19,4) NOT NULL,

    CONSTRAINT pk_courier_trip_compensation PRIMARY KEY (courier_trip_id, currency_code),
    CONSTRAINT fk_courier_trip_compensation_trip
        FOREIGN KEY (courier_trip_id) REFERENCES crm.courier_trip (id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_trip_compensation_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT ck_courier_trip_compensation_amount CHECK (amount >= 0)
);

ALTER TABLE crm.courier_assignment
    DROP CONSTRAINT fk_courier_assignment_delivery_scope,
    DROP CONSTRAINT uq_courier_assignment_id_delivery,
    DROP CONSTRAINT ck_courier_assignment_state,
    ALTER COLUMN inbound_delivery_id DROP NOT NULL,
    ADD COLUMN courier_trip_id UUID,
    ADD CONSTRAINT fk_courier_assignment_delivery_scope
        FOREIGN KEY (inbound_delivery_id, project_id)
            REFERENCES crm.inbound_delivery (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_courier_assignment_trip_scope
        FOREIGN KEY (courier_trip_id, project_id)
            REFERENCES crm.courier_trip (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_courier_assignment_target
        CHECK ((inbound_delivery_id IS NULL) <> (courier_trip_id IS NULL)),
    ADD CONSTRAINT ck_courier_assignment_state
        CHECK (
            (
                status_code = 'OFFERED'
                AND claimed_at IS NULL
                AND courier_planned_pickup_at IS NULL
                AND picked_up_at IS NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND response_reason IS NULL
                AND release_reason IS NULL
            )
            OR (
                status_code IN ('DECLINED', 'WITHDRAWN')
                AND claimed_at IS NULL
                AND courier_planned_pickup_at IS NULL
                AND picked_up_at IS NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND response_reason IS NOT NULL
                AND release_reason IS NULL
            )
            OR (
                status_code = 'CLAIMED'
                AND claimed_at IS NOT NULL
                AND courier_planned_pickup_at IS NOT NULL
                AND picked_up_at IS NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND release_reason IS NULL
            )
            OR (
                status_code = 'PICKED_UP'
                AND claimed_at IS NOT NULL
                AND courier_planned_pickup_at IS NOT NULL
                AND picked_up_at IS NOT NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND release_reason IS NULL
            )
            OR (
                status_code = 'RELEASED'
                AND claimed_at IS NOT NULL
                AND courier_planned_pickup_at IS NOT NULL
                AND picked_up_at IS NULL
                AND released_at IS NOT NULL
                AND completed_at IS NULL
                AND release_reason IS NOT NULL
            )
            OR (
                status_code = 'COMPLETED'
                AND claimed_at IS NOT NULL
                AND courier_planned_pickup_at IS NOT NULL
                AND picked_up_at IS NOT NULL
                AND released_at IS NULL
                AND completed_at IS NOT NULL
                AND release_reason IS NULL
            )
        );

DROP INDEX crm.uq_courier_assignment_active_delivery;

CREATE UNIQUE INDEX uq_courier_assignment_active_delivery
    ON crm.courier_assignment (inbound_delivery_id)
    WHERE inbound_delivery_id IS NOT NULL
      AND status_code IN ('OFFERED', 'CLAIMED', 'PICKED_UP');

CREATE UNIQUE INDEX uq_courier_assignment_active_trip
    ON crm.courier_assignment (courier_trip_id)
    WHERE courier_trip_id IS NOT NULL
      AND status_code IN ('OFFERED', 'CLAIMED', 'PICKED_UP');

CREATE INDEX ix_courier_trip_available
    ON crm.courier_trip (ready_for_courier_at, id)
    WHERE status_code = 'READY_FOR_COURIER_PICKUP'
      AND courier_distribution_mode = 'OPEN_POOL';

CREATE INDEX ix_courier_trip_delivery_trip_sequence
    ON crm.courier_trip_delivery (courier_trip_id, sequence_number);

ALTER TABLE crm.cargo_audit_event
    DROP CONSTRAINT ck_cargo_audit_event_aggregate_type,
    ADD CONSTRAINT ck_cargo_audit_event_aggregate_type
        CHECK (aggregate_type IN (
            'SUPPLIER_GOODS',
            'INBOUND_DELIVERY',
            'INBOUND_PACKAGE',
            'COURIER_TRIP',
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
            'OUTBOUND_DELIVERY',
            'WAREHOUSE_RELOCATION'
        ));

COMMENT ON TABLE crm.courier_trip IS
    'One indivisible courier pickup operation containing two or more compatible inbound deliveries.';
COMMENT ON TABLE crm.courier_trip_delivery IS
    'Immutable ordered membership of physical inbound parcels in one grouped courier trip.';
COMMENT ON TABLE crm.courier_trip_compensation IS
    'Currency-separated courier compensation snapshot frozen when the grouped trip is created.';
COMMENT ON COLUMN crm.courier_assignment.courier_trip_id IS
    'Grouped courier-trip target. Exactly one of inbound_delivery_id and courier_trip_id is populated.';
