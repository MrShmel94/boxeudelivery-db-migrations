CREATE TABLE crm.cargo_unit_intake_session
(
    id                       UUID        NOT NULL,
    project_id               UUID        NOT NULL,
    cargo_item_id            UUID        NOT NULL,
    created_by_account_id    UUID        NOT NULL,
    target_type_code         VARCHAR(32) NOT NULL,
    inbound_delivery_id      UUID,
    mini_supplier_intake_id  UUID,
    warehouse_id             UUID,
    status_code              VARCHAR(16) NOT NULL,
    receipt_id               UUID,
    activated_at             TIMESTAMPTZ,
    completed_at             TIMESTAMPTZ,
    cancelled_at             TIMESTAMPTZ,
    expires_at               TIMESTAMPTZ NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                  BIGINT      NOT NULL DEFAULT 0,
    CONSTRAINT pk_cargo_unit_intake_session PRIMARY KEY (id),
    CONSTRAINT fk_cargo_unit_intake_session_item
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_unit_intake_session_creator
        FOREIGN KEY (created_by_account_id)
            REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_unit_intake_session_delivery
        FOREIGN KEY (inbound_delivery_id, project_id)
            REFERENCES crm.inbound_delivery (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_unit_intake_session_mini_intake
        FOREIGN KEY (mini_supplier_intake_id, project_id)
            REFERENCES crm.mini_supplier_intake (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_unit_intake_session_warehouse
        FOREIGN KEY (warehouse_id)
            REFERENCES crm.warehouse (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_unit_intake_session_target CHECK (
        (
            target_type_code = 'INBOUND_DELIVERY'
            AND inbound_delivery_id IS NOT NULL
            AND mini_supplier_intake_id IS NULL
            AND warehouse_id IS NULL
        )
        OR (
            target_type_code = 'MINI_SUPPLIER_INTAKE'
            AND inbound_delivery_id IS NULL
            AND mini_supplier_intake_id IS NOT NULL
            AND warehouse_id IS NOT NULL
        )
    ),
    CONSTRAINT ck_cargo_unit_intake_session_status CHECK (
        status_code IN ('WAITING', 'ACTIVE', 'COMPLETED', 'CANCELLED')
    ),
    CONSTRAINT ck_cargo_unit_intake_session_lifecycle CHECK (
        (
            status_code = 'WAITING'
            AND activated_at IS NULL
            AND completed_at IS NULL
            AND cancelled_at IS NULL
            AND receipt_id IS NULL
        )
        OR (
            status_code = 'ACTIVE'
            AND activated_at IS NOT NULL
            AND completed_at IS NULL
            AND cancelled_at IS NULL
            AND receipt_id IS NULL
        )
        OR (
            status_code = 'COMPLETED'
            AND activated_at IS NOT NULL
            AND completed_at IS NOT NULL
            AND cancelled_at IS NULL
            AND receipt_id IS NOT NULL
        )
        OR (
            status_code = 'CANCELLED'
            AND completed_at IS NULL
            AND cancelled_at IS NOT NULL
            AND receipt_id IS NULL
        )
    ),
    CONSTRAINT ck_cargo_unit_intake_session_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_cargo_unit_intake_session_timestamps CHECK (updated_at >= created_at),
    CONSTRAINT ck_cargo_unit_intake_session_version CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_cargo_unit_intake_session_open_creator_item
    ON crm.cargo_unit_intake_session (project_id, cargo_item_id, created_by_account_id)
    WHERE status_code IN ('WAITING', 'ACTIVE');

CREATE INDEX ix_cargo_unit_intake_session_creator_status_expiry
    ON crm.cargo_unit_intake_session (created_by_account_id, status_code, expires_at, id);

CREATE INDEX ix_cargo_unit_intake_session_item_created
    ON crm.cargo_unit_intake_session (cargo_item_id, created_at DESC, id);

COMMENT ON TABLE crm.cargo_unit_intake_session IS
    'Short-lived same-account handoff that binds one desktop-selected exact unit to phone-only scan, photo, and receipt completion.';

COMMENT ON COLUMN crm.cargo_unit_intake_session.id IS
    'Random routing identity only; possession grants neither authentication nor receipt authorization.';

COMMENT ON COLUMN crm.cargo_unit_intake_session.receipt_id IS
    'Receipt created atomically by the authenticated phone completion command; table depends on target type.';
