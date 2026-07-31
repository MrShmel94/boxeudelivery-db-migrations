CREATE TABLE crm.courier_compensation_proposal
(
    id                           UUID          NOT NULL,
    project_id                   UUID          NOT NULL,
    inbound_delivery_id          UUID,
    courier_trip_id              UUID,
    courier_account_id           UUID          NOT NULL,
    target_type                  VARCHAR(24)   NOT NULL,
    status_code                  VARCHAR(24)   NOT NULL,
    currency_code                VARCHAR(3)    NOT NULL,
    base_amount                  NUMERIC(19,4) NOT NULL,
    proposed_amount              NUMERIC(19,4) NOT NULL,
    base_allocation_fingerprint  VARCHAR(64)   NOT NULL,
    courier_planned_pickup_at    TIMESTAMPTZ   NOT NULL,
    resolution_reason            VARCHAR(500),
    resolved_assignment_id       UUID,
    submitted_by_subject         VARCHAR(255)  NOT NULL,
    decided_by_subject           VARCHAR(255),
    submitted_at                 TIMESTAMPTZ   NOT NULL,
    decided_at                   TIMESTAMPTZ,
    version                      BIGINT        NOT NULL DEFAULT 0,

    CONSTRAINT pk_courier_compensation_proposal PRIMARY KEY (id),
    CONSTRAINT fk_courier_compensation_proposal_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_compensation_proposal_delivery
        FOREIGN KEY (inbound_delivery_id, project_id)
            REFERENCES crm.inbound_delivery (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_compensation_proposal_trip
        FOREIGN KEY (courier_trip_id, project_id)
            REFERENCES crm.courier_trip (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_compensation_proposal_courier
        FOREIGN KEY (courier_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_compensation_proposal_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_courier_compensation_proposal_assignment
        FOREIGN KEY (resolved_assignment_id) REFERENCES crm.courier_assignment (id) ON DELETE RESTRICT,
    CONSTRAINT ck_courier_compensation_proposal_target_type
        CHECK (target_type IN ('INBOUND_DELIVERY', 'COURIER_TRIP')),
    CONSTRAINT ck_courier_compensation_proposal_target
        CHECK (
            (
                target_type = 'INBOUND_DELIVERY'
                AND inbound_delivery_id IS NOT NULL
                AND courier_trip_id IS NULL
            )
            OR (
                target_type = 'COURIER_TRIP'
                AND inbound_delivery_id IS NULL
                AND courier_trip_id IS NOT NULL
            )
        ),
    CONSTRAINT ck_courier_compensation_proposal_status
        CHECK (status_code IN ('PENDING', 'APPROVED', 'REJECTED', 'SUPERSEDED')),
    CONSTRAINT ck_courier_compensation_proposal_currency
        CHECK (currency_code = 'USD'),
    CONSTRAINT ck_courier_compensation_proposal_amounts
        CHECK (
            base_amount > 0
            AND proposed_amount > 0
            AND proposed_amount <> base_amount
        ),
    CONSTRAINT ck_courier_compensation_proposal_fingerprint
        CHECK (base_allocation_fingerprint ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_courier_compensation_proposal_reason
        CHECK (resolution_reason IS NULL OR BTRIM(resolution_reason) <> ''),
    CONSTRAINT ck_courier_compensation_proposal_actors
        CHECK (
            BTRIM(submitted_by_subject) <> ''
            AND (decided_by_subject IS NULL OR BTRIM(decided_by_subject) <> '')
        ),
    CONSTRAINT ck_courier_compensation_proposal_resolution
        CHECK (
            (
                status_code = 'PENDING'
                AND decided_by_subject IS NULL
                AND decided_at IS NULL
                AND resolution_reason IS NULL
                AND resolved_assignment_id IS NULL
            )
            OR (
                status_code = 'APPROVED'
                AND decided_by_subject IS NOT NULL
                AND decided_at IS NOT NULL
                AND resolved_assignment_id IS NOT NULL
            )
            OR (
                status_code IN ('REJECTED', 'SUPERSEDED')
                AND decided_by_subject IS NOT NULL
                AND decided_at IS NOT NULL
                AND resolution_reason IS NOT NULL
                AND resolved_assignment_id IS NULL
            )
        ),
    CONSTRAINT ck_courier_compensation_proposal_timestamps
        CHECK (
            courier_planned_pickup_at > submitted_at
            AND (decided_at IS NULL OR decided_at >= submitted_at)
        ),
    CONSTRAINT ck_courier_compensation_proposal_version CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_courier_compensation_proposal_pending_delivery_courier
    ON crm.courier_compensation_proposal (inbound_delivery_id, courier_account_id)
    WHERE status_code = 'PENDING';

CREATE UNIQUE INDEX uq_courier_compensation_proposal_pending_trip_courier
    ON crm.courier_compensation_proposal (courier_trip_id, courier_account_id)
    WHERE status_code = 'PENDING';

CREATE INDEX ix_courier_compensation_proposal_delivery_history
    ON crm.courier_compensation_proposal (inbound_delivery_id, submitted_at DESC, id)
    WHERE inbound_delivery_id IS NOT NULL;

CREATE INDEX ix_courier_compensation_proposal_trip_history
    ON crm.courier_compensation_proposal (courier_trip_id, submitted_at DESC, id)
    WHERE courier_trip_id IS NOT NULL;

CREATE INDEX ix_courier_compensation_proposal_moderation
    ON crm.courier_compensation_proposal (project_id, status_code, submitted_at, id);

ALTER TABLE crm.cargo_audit_event
    DROP CONSTRAINT ck_cargo_audit_event_aggregate_type,
    ADD CONSTRAINT ck_cargo_audit_event_aggregate_type
        CHECK (aggregate_type IN (
            'SUPPLIER_GOODS',
            'INBOUND_DELIVERY',
            'INBOUND_PACKAGE',
            'COURIER_TRIP',
            'COURIER_ASSIGNMENT',
            'COURIER_COMPENSATION_PROPOSAL',
            'CARGO_ITEM',
            'CARGO_PHOTO',
            'CARGO_PHOTO_CAPTURE_SESSION',
            'CARGO_FINANCIAL_ENTRY',
            'CARGO_PURCHASE_RATE',
            'CARGO_CUSTOMER_FX_QUOTE',
            'CARGO_USER_DAILY_RATE',
            'CUSTOMER_ORDER',
            'CUSTOMER_ORDER_LINE',
            'PICKING_SESSION',
            'OUTBOUND_PACKAGE',
            'OUTBOUND_DELIVERY',
            'WAREHOUSE_RELOCATION'
        ));

COMMENT ON TABLE crm.courier_compensation_proposal IS
    'Immutable-price negotiation request submitted by an eligible courier before custody is assigned.';
COMMENT ON COLUMN crm.courier_compensation_proposal.base_allocation_fingerprint IS
    'SHA-256 fingerprint of the exact item-level actual-cost revisions used when the courier submitted the proposal.';
COMMENT ON COLUMN crm.courier_compensation_proposal.resolved_assignment_id IS
    'Assignment created or accepted atomically with approval of the negotiated compensation.';
