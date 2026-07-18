CREATE TABLE crm.pickup_point
(
    id                    UUID          NOT NULL,
    name                  VARCHAR(150)  NOT NULL,
    country_code          CHAR(2)       NOT NULL,
    location_description  VARCHAR(1000) NOT NULL,
    instructions          VARCHAR(2000),
    active                BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by_subject    VARCHAR(255)  NOT NULL,
    updated_by_subject    VARCHAR(255)  NOT NULL,
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version               BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_pickup_point
        PRIMARY KEY (id),
    CONSTRAINT ck_pickup_point_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_pickup_point_country_code
        CHECK (country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_pickup_point_location_not_blank
        CHECK (BTRIM(location_description) <> ''),
    CONSTRAINT ck_pickup_point_instructions_not_blank
        CHECK (instructions IS NULL OR BTRIM(instructions) <> ''),
    CONSTRAINT ck_pickup_point_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_pickup_point_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_pickup_point_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_pickup_point_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_pickup_point_name_case_insensitive
    ON crm.pickup_point (LOWER(BTRIM(name)));

CREATE INDEX ix_pickup_point_active_name
    ON crm.pickup_point (active, name, id);

CREATE TABLE crm.project_pickup_point
(
    project_id          UUID         NOT NULL,
    pickup_point_id     UUID         NOT NULL,
    assigned_by_subject VARCHAR(255) NOT NULL,
    assigned_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_project_pickup_point
        PRIMARY KEY (project_id, pickup_point_id),
    CONSTRAINT fk_project_pickup_point_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_project_pickup_point_pickup_point
        FOREIGN KEY (pickup_point_id) REFERENCES crm.pickup_point (id) ON DELETE RESTRICT,
    CONSTRAINT ck_project_pickup_point_assigned_by_subject_not_blank
        CHECK (BTRIM(assigned_by_subject) <> '')
);

CREATE INDEX ix_project_pickup_point_pickup_point_project
    ON crm.project_pickup_point (pickup_point_id, project_id);

CREATE TABLE crm.pickup_point_audit_event
(
    id               UUID         NOT NULL,
    pickup_point_id  UUID         NOT NULL,
    event_type       VARCHAR(64)  NOT NULL,
    actor_subject    VARCHAR(255) NOT NULL,
    details          JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at      TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pickup_point_audit_event
        PRIMARY KEY (id),
    CONSTRAINT ck_pickup_point_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'UPDATED',
            'DELETED',
            'PROJECT_ASSIGNED',
            'PROJECT_REMOVED'
        )),
    CONSTRAINT ck_pickup_point_audit_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_pickup_point_audit_details_object
        CHECK (jsonb_typeof(details) = 'object')
);

CREATE INDEX ix_pickup_point_audit_point_occurred
    ON crm.pickup_point_audit_event (pickup_point_id, occurred_at DESC, id);

ALTER TABLE crm.inbound_delivery
    DROP CONSTRAINT ck_inbound_delivery_status,
    DROP CONSTRAINT ck_inbound_delivery_dispatch_state,
    ADD COLUMN transport_mode VARCHAR(32) NOT NULL DEFAULT 'DIRECT_TO_WAREHOUSE',
    ADD COLUMN pickup_point_id UUID,
    ADD COLUMN carrier_name VARCHAR(100),
    ADD COLUMN tracking_number VARCHAR(150),
    ADD COLUMN ready_for_courier_at TIMESTAMPTZ,
    ADD COLUMN courier_picked_up_at TIMESTAMPTZ;

UPDATE crm.inbound_delivery
SET status_code = 'IN_TRANSIT_TO_WAREHOUSE'
WHERE status_code = 'IN_TRANSIT';

ALTER TABLE crm.inbound_delivery
    ADD CONSTRAINT fk_inbound_delivery_project_pickup_point
        FOREIGN KEY (project_id, pickup_point_id)
            REFERENCES crm.project_pickup_point (project_id, pickup_point_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_inbound_delivery_transport_mode
        CHECK (transport_mode IN ('DIRECT_TO_WAREHOUSE', 'COURIER_VIA_PICKUP_POINT')),
    ADD CONSTRAINT ck_inbound_delivery_carrier_name_not_blank
        CHECK (carrier_name IS NULL OR BTRIM(carrier_name) <> ''),
    ADD CONSTRAINT ck_inbound_delivery_tracking_number_not_blank
        CHECK (tracking_number IS NULL OR BTRIM(tracking_number) <> ''),
    ADD CONSTRAINT ck_inbound_delivery_transport_scope
        CHECK (
            (transport_mode = 'DIRECT_TO_WAREHOUSE' AND pickup_point_id IS NULL)
            OR (transport_mode = 'COURIER_VIA_PICKUP_POINT' AND pickup_point_id IS NOT NULL)
        ),
    ADD CONSTRAINT ck_inbound_delivery_status
        CHECK (status_code IN (
            'DRAFT',
            'IN_TRANSIT_TO_PICKUP_POINT',
            'READY_FOR_COURIER_PICKUP',
            'COURIER_ASSIGNED',
            'IN_TRANSIT_TO_WAREHOUSE',
            'PARTIALLY_RECEIVED',
            'COMPLETED',
            'CANCELLED'
        )),
    ADD CONSTRAINT ck_inbound_delivery_transport_lifecycle
        CHECK (
            (
                status_code IN ('DRAFT', 'CANCELLED')
                AND dispatched_at IS NULL
                AND ready_for_courier_at IS NULL
                AND courier_picked_up_at IS NULL
            )
            OR (
                status_code = 'IN_TRANSIT_TO_PICKUP_POINT'
                AND transport_mode = 'COURIER_VIA_PICKUP_POINT'
                AND dispatched_at IS NOT NULL
                AND ready_for_courier_at IS NULL
                AND courier_picked_up_at IS NULL
            )
            OR (
                status_code IN ('READY_FOR_COURIER_PICKUP', 'COURIER_ASSIGNED')
                AND transport_mode = 'COURIER_VIA_PICKUP_POINT'
                AND dispatched_at IS NOT NULL
                AND ready_for_courier_at IS NOT NULL
                AND courier_picked_up_at IS NULL
            )
            OR (
                status_code IN ('IN_TRANSIT_TO_WAREHOUSE', 'PARTIALLY_RECEIVED', 'COMPLETED')
                AND dispatched_at IS NOT NULL
                AND (
                    (
                        transport_mode = 'DIRECT_TO_WAREHOUSE'
                        AND ready_for_courier_at IS NULL
                        AND courier_picked_up_at IS NULL
                    )
                    OR (
                        transport_mode = 'COURIER_VIA_PICKUP_POINT'
                        AND ready_for_courier_at IS NOT NULL
                        AND courier_picked_up_at IS NOT NULL
                    )
                )
            )
        );

CREATE INDEX ix_inbound_delivery_pickup_status_created
    ON crm.inbound_delivery (pickup_point_id, status_code, created_at DESC, id)
    WHERE pickup_point_id IS NOT NULL;

CREATE TABLE crm.inbound_package
(
    id                  UUID          NOT NULL,
    inbound_delivery_id UUID          NOT NULL,
    project_id          UUID          NOT NULL,
    sequence_number     SMALLINT      NOT NULL,
    package_number      VARCHAR(48)   NOT NULL,
    description         VARCHAR(500),
    weight_grams        INTEGER,
    length_mm           INTEGER,
    width_mm            INTEGER,
    height_mm           INTEGER,
    created_by_subject  VARCHAR(255)  NOT NULL,
    updated_by_subject  VARCHAR(255)  NOT NULL,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version             BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_inbound_package
        PRIMARY KEY (id),
    CONSTRAINT uq_inbound_package_id_delivery_project
        UNIQUE (id, inbound_delivery_id, project_id),
    CONSTRAINT uq_inbound_package_delivery_sequence
        UNIQUE (inbound_delivery_id, sequence_number),
    CONSTRAINT uq_inbound_package_number
        UNIQUE (package_number),
    CONSTRAINT fk_inbound_package_delivery_scope
        FOREIGN KEY (inbound_delivery_id, project_id)
            REFERENCES crm.inbound_delivery (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT ck_inbound_package_sequence
        CHECK (sequence_number BETWEEN 1 AND 100),
    CONSTRAINT ck_inbound_package_number_format
        CHECK (package_number ~ '^IN-[0-9]{4}-[0-9]{6}-P[0-9]{3}$'),
    CONSTRAINT ck_inbound_package_description_not_blank
        CHECK (description IS NULL OR BTRIM(description) <> ''),
    CONSTRAINT ck_inbound_package_weight
        CHECK (weight_grams IS NULL OR weight_grams BETWEEN 1 AND 1000000),
    CONSTRAINT ck_inbound_package_dimensions
        CHECK (
            (length_mm IS NULL AND width_mm IS NULL AND height_mm IS NULL)
            OR (
                length_mm BETWEEN 1 AND 10000
                AND width_mm BETWEEN 1 AND 10000
                AND height_mm BETWEEN 1 AND 10000
            )
        ),
    CONSTRAINT ck_inbound_package_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_inbound_package_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_inbound_package_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_inbound_package_version
        CHECK (version >= 0)
);

CREATE INDEX ix_inbound_package_delivery_sequence
    ON crm.inbound_package (inbound_delivery_id, sequence_number, id);

ALTER TABLE crm.inbound_delivery_line
    ADD COLUMN package_id UUID,
    ADD CONSTRAINT fk_inbound_delivery_line_package_scope
        FOREIGN KEY (package_id, inbound_delivery_id, project_id)
            REFERENCES crm.inbound_package (id, inbound_delivery_id, project_id) ON DELETE RESTRICT;

CREATE INDEX ix_inbound_delivery_line_package_created
    ON crm.inbound_delivery_line (package_id, created_at, id)
    WHERE package_id IS NOT NULL;

ALTER TABLE crm.cargo_item
    DROP CONSTRAINT ck_cargo_item_status,
    DROP CONSTRAINT ck_cargo_item_delivery_assignment;

UPDATE crm.cargo_item
SET status_code = 'IN_TRANSIT_TO_WAREHOUSE'
WHERE status_code = 'IN_TRANSIT';

ALTER TABLE crm.cargo_item
    ADD CONSTRAINT ck_cargo_item_status
        CHECK (status_code IN (
            'EXPECTED_AT_SUPPLIER',
            'AT_SUPPLIER',
            'RESERVED_FOR_DELIVERY',
            'IN_TRANSIT_TO_PICKUP_POINT',
            'READY_FOR_COURIER_PICKUP',
            'IN_TRANSIT_TO_WAREHOUSE',
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
                    'IN_TRANSIT_TO_PICKUP_POINT',
                    'READY_FOR_COURIER_PICKUP',
                    'IN_TRANSIT_TO_WAREHOUSE',
                    'AVAILABLE',
                    'MISSING',
                    'DAMAGED',
                    'REJECTED'
                )
                AND inbound_delivery_id IS NOT NULL
                AND inbound_delivery_line_id IS NOT NULL
            )
        );

CREATE TABLE crm.courier_assignment
(
    id                    UUID         NOT NULL,
    inbound_delivery_id   UUID         NOT NULL,
    project_id            UUID         NOT NULL,
    courier_account_id    UUID         NOT NULL,
    status_code           VARCHAR(32)  NOT NULL,
    claimed_at            TIMESTAMPTZ  NOT NULL,
    picked_up_at          TIMESTAMPTZ,
    released_at           TIMESTAMPTZ,
    completed_at          TIMESTAMPTZ,
    release_reason        VARCHAR(500),
    created_by_subject    VARCHAR(255) NOT NULL,
    updated_by_subject    VARCHAR(255) NOT NULL,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version               BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_courier_assignment
        PRIMARY KEY (id),
    CONSTRAINT uq_courier_assignment_id_delivery
        UNIQUE (id, inbound_delivery_id),
    CONSTRAINT fk_courier_assignment_delivery_scope
        FOREIGN KEY (inbound_delivery_id, project_id)
            REFERENCES crm.inbound_delivery (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_assignment_courier
        FOREIGN KEY (courier_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_courier_assignment_status
        CHECK (status_code IN ('CLAIMED', 'PICKED_UP', 'RELEASED', 'COMPLETED')),
    CONSTRAINT ck_courier_assignment_release_reason_not_blank
        CHECK (release_reason IS NULL OR BTRIM(release_reason) <> ''),
    CONSTRAINT ck_courier_assignment_state
        CHECK (
            (
                status_code = 'CLAIMED'
                AND picked_up_at IS NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND release_reason IS NULL
            )
            OR (
                status_code = 'PICKED_UP'
                AND picked_up_at IS NOT NULL
                AND released_at IS NULL
                AND completed_at IS NULL
                AND release_reason IS NULL
            )
            OR (
                status_code = 'RELEASED'
                AND picked_up_at IS NULL
                AND released_at IS NOT NULL
                AND completed_at IS NULL
                AND release_reason IS NOT NULL
            )
            OR (
                status_code = 'COMPLETED'
                AND picked_up_at IS NOT NULL
                AND released_at IS NULL
                AND completed_at IS NOT NULL
                AND release_reason IS NULL
            )
        ),
    CONSTRAINT ck_courier_assignment_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_courier_assignment_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_courier_assignment_timestamps
        CHECK (
            updated_at >= created_at
            AND claimed_at >= created_at
            AND (picked_up_at IS NULL OR picked_up_at >= claimed_at)
            AND (released_at IS NULL OR released_at >= claimed_at)
            AND (completed_at IS NULL OR completed_at >= picked_up_at)
        ),
    CONSTRAINT ck_courier_assignment_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_courier_assignment_active_delivery
    ON crm.courier_assignment (inbound_delivery_id)
    WHERE status_code IN ('CLAIMED', 'PICKED_UP');

CREATE INDEX ix_courier_assignment_courier_status_claimed
    ON crm.courier_assignment (courier_account_id, status_code, claimed_at DESC, id);

ALTER TABLE crm.cargo_audit_event
    DROP CONSTRAINT ck_cargo_audit_event_aggregate_type,
    ADD CONSTRAINT ck_cargo_audit_event_aggregate_type
        CHECK (aggregate_type IN (
            'SUPPLIER_GOODS',
            'INBOUND_DELIVERY',
            'INBOUND_PACKAGE',
            'COURIER_ASSIGNMENT',
            'CARGO_ITEM',
            'CARGO_PHOTO'
        ));

COMMENT ON TABLE crm.pickup_point IS
    'Global catalogue of courier pickup locations assignable to business projects.';
COMMENT ON TABLE crm.project_pickup_point IS
    'Explicit many-to-many assignment between projects and courier pickup points.';
COMMENT ON TABLE crm.inbound_package IS
    'One physical package inside an inbound delivery; its exact items are linked through package-scoped delivery lines.';
COMMENT ON TABLE crm.courier_assignment IS
    'Append-preserved courier claim lifecycle; a delivery may have only one active assignment.';
COMMENT ON COLUMN crm.inbound_delivery.transport_mode IS
    'Distinguishes legacy direct-to-warehouse deliveries from pickup-point courier transport.';
COMMENT ON COLUMN crm.inbound_delivery.ready_for_courier_at IS
    'Instant when the pickup location made the delivery visible for a courier claim.';
COMMENT ON COLUMN crm.inbound_delivery.courier_picked_up_at IS
    'Instant when the assigned courier confirmed physical pickup for transport to the target warehouse.';
