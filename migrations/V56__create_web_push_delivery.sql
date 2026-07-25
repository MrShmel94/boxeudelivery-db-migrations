CREATE TABLE crm.web_push_subscription
(
    id                         UUID         PRIMARY KEY,
    account_id                 UUID         NOT NULL,
    endpoint_fingerprint       VARCHAR(64)  NOT NULL,
    encrypted_subscription     BYTEA        NOT NULL,
    encryption_key_version     INTEGER      NOT NULL,
    active                     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at                 TIMESTAMPTZ  NOT NULL,
    updated_at                 TIMESTAMPTZ  NOT NULL,
    last_success_at            TIMESTAMPTZ,
    deactivated_at             TIMESTAMPTZ,
    deactivation_reason        VARCHAR(64),
    version                    BIGINT       NOT NULL DEFAULT 0,

    CONSTRAINT uk_web_push_subscription_endpoint
        UNIQUE (endpoint_fingerprint),
    CONSTRAINT fk_web_push_subscription_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_web_push_subscription_fingerprint
        CHECK (endpoint_fingerprint ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_web_push_subscription_key_version
        CHECK (encryption_key_version > 0),
    CONSTRAINT ck_web_push_subscription_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_web_push_subscription_deactivation
        CHECK (
            (active = TRUE AND deactivated_at IS NULL AND deactivation_reason IS NULL)
            OR
            (active = FALSE AND deactivated_at IS NOT NULL AND deactivation_reason IS NOT NULL)
        )
);

CREATE INDEX ix_web_push_subscription_account_active
    ON crm.web_push_subscription (account_id, updated_at DESC)
    WHERE active = TRUE;

CREATE INDEX ix_web_push_subscription_inactive_updated
    ON crm.web_push_subscription (updated_at, id)
    WHERE active = FALSE;

CREATE TABLE crm.web_push_delivery
(
    id                  UUID         PRIMARY KEY,
    outbox_event_id     UUID         NOT NULL,
    subscription_id     UUID         NOT NULL,
    account_id          UUID         NOT NULL,
    aggregate_id        UUID         NOT NULL,
    event_type          VARCHAR(128) NOT NULL,
    status_code         VARCHAR(32)  NOT NULL,
    attempt_count       INTEGER      NOT NULL DEFAULT 0,
    next_attempt_at     TIMESTAMPTZ  NOT NULL,
    processing_started_at TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL,
    delivered_at        TIMESTAMPTZ,
    last_error          VARCHAR(128),

    CONSTRAINT uk_web_push_delivery_event_subscription
        UNIQUE (outbox_event_id, subscription_id),
    CONSTRAINT fk_web_push_delivery_subscription
        FOREIGN KEY (subscription_id) REFERENCES crm.web_push_subscription (id) ON DELETE RESTRICT,
    CONSTRAINT fk_web_push_delivery_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_web_push_delivery_status
        CHECK (status_code IN ('PENDING', 'PROCESSING', 'DELIVERED', 'ABANDONED')),
    CONSTRAINT ck_web_push_delivery_attempt_count
        CHECK (attempt_count >= 0),
    CONSTRAINT ck_web_push_delivery_state
        CHECK (
            (status_code = 'PENDING' AND processing_started_at IS NULL AND delivered_at IS NULL)
            OR
            (status_code = 'PROCESSING' AND processing_started_at IS NOT NULL AND delivered_at IS NULL)
            OR
            (status_code = 'DELIVERED' AND processing_started_at IS NULL AND delivered_at IS NOT NULL)
            OR
            (status_code = 'ABANDONED' AND processing_started_at IS NULL AND delivered_at IS NULL)
        )
);

CREATE INDEX ix_web_push_delivery_pending
    ON crm.web_push_delivery (next_attempt_at, created_at, id)
    WHERE status_code = 'PENDING';

CREATE INDEX ix_web_push_delivery_processing
    ON crm.web_push_delivery (processing_started_at, id)
    WHERE status_code = 'PROCESSING';

CREATE INDEX ix_web_push_delivery_subscription_open
    ON crm.web_push_delivery (subscription_id, status_code)
    WHERE status_code IN ('PENDING', 'PROCESSING');

COMMENT ON TABLE crm.web_push_subscription IS
    'Per-account browser push endpoints. Endpoint and Push API keys are encrypted by the backend; the SHA-256 fingerprint supports ownership-safe lookup.';

COMMENT ON TABLE crm.web_push_delivery IS
    'Durable, idempotent Web Push delivery queue projected from business outbox events. PostgreSQL remains authoritative and network delivery is retried independently.';
