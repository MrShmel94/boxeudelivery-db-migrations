CREATE TABLE crm.cargo_photo_capture_session
(
    id                    UUID        NOT NULL,
    project_id            UUID        NOT NULL,
    cargo_item_id          UUID        NOT NULL,
    created_by_account_id UUID        NOT NULL,
    status_code           VARCHAR(16) NOT NULL,
    activated_at          TIMESTAMPTZ,
    completed_at          TIMESTAMPTZ,
    cancelled_at          TIMESTAMPTZ,
    expires_at            TIMESTAMPTZ NOT NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version               BIGINT      NOT NULL DEFAULT 0,
    CONSTRAINT pk_cargo_photo_capture_session
        PRIMARY KEY (id),
    CONSTRAINT fk_cargo_photo_capture_session_item
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_photo_capture_session_creator
        FOREIGN KEY (created_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_photo_capture_session_status
        CHECK (status_code IN ('WAITING', 'ACTIVE', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT ck_cargo_photo_capture_session_lifecycle
        CHECK (
            (
                status_code = 'WAITING'
                AND activated_at IS NULL
                AND completed_at IS NULL
                AND cancelled_at IS NULL
            )
            OR (
                status_code = 'ACTIVE'
                AND activated_at IS NOT NULL
                AND completed_at IS NULL
                AND cancelled_at IS NULL
            )
            OR (
                status_code = 'COMPLETED'
                AND activated_at IS NOT NULL
                AND completed_at IS NOT NULL
                AND cancelled_at IS NULL
            )
            OR (
                status_code = 'CANCELLED'
                AND completed_at IS NULL
                AND cancelled_at IS NOT NULL
            )
        ),
    CONSTRAINT ck_cargo_photo_capture_session_expiry
        CHECK (expires_at > created_at),
    CONSTRAINT ck_cargo_photo_capture_session_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_cargo_photo_capture_session_version
        CHECK (version >= 0)
);

CREATE INDEX ix_cargo_photo_capture_session_creator_status_expiry
    ON crm.cargo_photo_capture_session (created_by_account_id, status_code, expires_at, id);

CREATE INDEX ix_cargo_photo_capture_session_item_created
    ON crm.cargo_photo_capture_session (cargo_item_id, created_at DESC, id);

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
            'CARGO_PHOTO_CAPTURE_SESSION',
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

COMMENT ON TABLE crm.cargo_photo_capture_session IS
    'Short-lived authenticated handoff from a desktop cargo gallery to the same account on a camera-capable device.';

COMMENT ON COLUMN crm.cargo_photo_capture_session.id IS
    'Random routing identifier only. Possession never grants authentication or cargo access.';
